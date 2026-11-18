import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/clock.dart';
import '../../core/diagnostics.dart';
import '../../core/ids.dart';
import '../chorki_analytics_event.dart';
import '../chorki_analytics_sink.dart';
import 'analytics_storage.dart';
import 'matomo_config.dart';
import 'matomo_request_builder.dart';

/// Sends a batch of Matomo requests (query strings starting with `?`).
abstract class MatomoTransport {
  /// Returns true when the server accepted [requests]. Should return false
  /// rather than throw on network errors; a throw is treated the same way.
  Future<bool> send(Uri endpoint, List<String> requests);
}

/// Bulk tracking: one `POST matomo.php` with `{"requests": [...]}`.
class DioMatomoTransport implements MatomoTransport {
  /// Posts with [dio], or a client with [timeout].
  DioMatomoTransport({Dio? dio, Duration timeout = const Duration(seconds: 10)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: timeout,
              sendTimeout: timeout,
              receiveTimeout: timeout,
            ),
          );

  final Dio _dio;

  @override
  Future<bool> send(Uri endpoint, List<String> requests) async {
    try {
      final response = await _dio.postUri<Object?>(
        endpoint,
        data: jsonEncode({'requests': requests}),
        options: Options(
          contentType: 'application/json',
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
      final code = response.statusCode ?? 0;
      return code >= 200 && code < 300;
    } on DioException {
      // Offline or unreachable: the sink retries with backoff.
      return false;
    }
  }
}

/// Reports player analytics to Matomo.
///
/// * Media Analytics (`ma_*`): an impression when an item is shown and a
///   heartbeat every [ChorkiAnalyticsConfig.heartbeatInterval] (and on
///   pause, seek, complete and session end) with the watched time, position,
///   length, size and newly watched segments. Feeds the Media reports
///   (plays, impressions, finish rate, watch time, segments).
/// * Matomo Events for everything else: playback actions, QoE (startup time,
///   rebuffering, errors, quality), ads and player UI.
///
/// Requests are queued, sent in bulk every [MatomoConfig.flushInterval] (or
/// when [MatomoConfig.batchSize] are waiting), retried with backoff when
/// offline, and flushed when the app goes to the background.
///
/// Create one for the app and pass it to every player:
/// ```dart
/// final matomo = MatomoAnalyticsSink(MatomoConfig(
///   url: 'https://analytics.example.com',
///   siteId: 3,
///   dimensionIds: {'contentId': 1, 'category': 2},
/// ));
/// ChorkiPlayer(route: r, analytics: ChorkiAnalyticsConfig(sinks: [matomo]));
/// ```
class MatomoAnalyticsSink extends ChorkiAnalyticsSink {
  /// Reports to the Matomo described by [config].
  MatomoAnalyticsSink(
    this.config, {
    MatomoTransport? transport,
    this.userId,
    Map<String, String> userProperties = const {},
    @visibleForTesting this._clock = systemClock,
  }) : _transport =
           transport ?? DioMatomoTransport(timeout: config.requestTimeout),
       _builder = MatomoRequestBuilder(config),
       _storage = config.storage ?? InMemoryAnalyticsStorage(),
       _userProperties = Map.of(userProperties) {
    _ready = _restore();
    _listenToLifecycle();
  }

  /// Where and what to report.
  final MatomoConfig config;
  final MatomoTransport _transport;
  final MatomoRequestBuilder _builder;
  final ChorkiAnalyticsStorage _storage;
  final ChorkiClock _clock;

  /// Storage key of the visitor id.
  static const String visitorIdKey = 'chorki_matomo.visitor_id';

  /// Storage key of the unsent requests.
  static const String queueKey = 'chorki_matomo.queue';

  /// Matomo only accepts back-dated requests (`cdt`) within this window
  /// without an auth token.
  static const Duration maxRequestAge = Duration(hours: 23);

  /// Matomo User ID (`uid`): set it when the viewer signs in, null on sign
  /// out. Applies to later events.
  String? userId;
  final Map<String, String> _userProperties;
  String _visitorId = secureHex(8);
  final List<_Queued> _queue = [];
  late final Future<void> _ready;
  Timer? _flushTimer;
  Future<void>? _sending;
  int _failures = 0;
  DateTime? _retryAfter;
  AppLifecycleListener? _lifecycle;
  bool _disposed = false;

  /// Viewer values that can be mapped to custom dimensions, e.g.
  /// `{'subscriptionTier': 'premium'}`. Applies to later events.
  Map<String, String> get userProperties => Map.unmodifiable(_userProperties);

  /// Sets (or with null removes) one of [userProperties].
  void setUserProperty(String key, String? value) {
    if (value == null) {
      _userProperties.remove(key);
    } else {
      _userProperties[key] = value;
    }
  }

  /// The visitor id (`_id`, 16 hex characters) requests are sent with:
  /// [MatomoConfig.visitorIdProvider]'s when valid, else the sink's own.
  Future<String> get visitorId async {
    await _ready;
    return _effectiveVisitorId;
  }

  /// Requests not yet accepted by the server.
  @visibleForTesting
  int get pendingCount => _queue.length;

  @override
  void onEvent(ChorkiAnalyticsEvent event) {
    if (_disposed) return;
    final requests = _builder.build(
      event,
      userId: userId,
      userProperties: _userProperties,
      resolution: _resolution(),
      language: _language(),
      viewport: config.mediaSize == MatomoMediaSize.viewport
          ? _viewport()
          : null,
    );
    if (requests.isEmpty) return;
    for (final r in requests) {
      _queue.add(_Queued(r, event.timestamp));
    }
    final overflow = _queue.length - config.maxQueueLength;
    if (overflow > 0) _queue.removeRange(0, overflow);

    if (_queue.length >= config.batchSize) {
      unawaited(flush());
    } else {
      _flushTimer ??= Timer(config.flushInterval, () {
        _flushTimer = null;
        unawaited(flush());
      });
    }
  }

  /// Sends everything queued (in batches). Safe to call any time.
  @override
  Future<void> flush() {
    final running = _sending;
    if (running != null) return running;
    final future = _flushAll().whenComplete(() => _sending = null);
    _sending = future;
    return future;
  }

  Future<void> _flushAll() async {
    await _ready;
    _flushTimer?.cancel();
    _flushTimer = null;
    final wait = _retryAfter;
    if (wait != null && _clock().isBefore(wait)) {
      _scheduleRetry(wait.difference(_clock()));
      return;
    }

    final oldest = _clock().subtract(maxRequestAge);
    _queue.removeWhere((q) => q.at.isBefore(oldest));

    while (_queue.isNotEmpty) {
      final batch = _queue.take(config.batchSize).toList();
      bool ok;
      try {
        ok = await _transport.send(config.endpoint, [
          for (final q in batch) _encode(q.params),
        ]);
      } catch (e, st) {
        ChorkiDiagnostics.report(e, st, 'matomo.send');
        ok = false;
      }
      if (!ok) {
        _failures++;
        final delay = Duration(
          seconds: min(300, 5 * pow(2, _failures - 1).toInt()),
        );
        _retryAfter = _clock().add(delay);
        _scheduleRetry(delay);
        break;
      }
      _failures = 0;
      _retryAfter = null;
      // By identity: the queue may have been trimmed while sending.
      final sent = batch.toSet();
      _queue.removeWhere(sent.contains);
    }
    await _persist();
  }

  void _scheduleRetry(Duration delay) {
    if (_disposed) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(delay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  static final RegExp _validVisitorId = RegExp(r'^[0-9a-f]{16}$');

  /// The app's shared visitor id when it has a valid one, else ours.
  String get _effectiveVisitorId {
    try {
      final shared = config.visitorIdProvider?.call();
      if (shared != null && _validVisitorId.hasMatch(shared)) return shared;
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'matomo.visitorIdProvider');
    }
    return _visitorId;
  }

  String _encode(Map<String, String> params) {
    final all = {
      ...params,
      '_id': _effectiveVisitorId,
      'rand': '${randomInt(1 << 30)}',
    };
    return '?${Uri(queryParameters: all).query}';
  }

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(visitorIdKey);
      if (saved != null && _validVisitorId.hasMatch(saved)) {
        _visitorId = saved;
      } else {
        await _storage.write(visitorIdKey, _visitorId);
      }
      final raw = await _storage.read(queueKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        final restored = <_Queued>[
          if (decoded is List)
            for (final item in decoded)
              // One damaged entry must not cost the others.
              if (item case {
                'p': final Map<Object?, Object?> p,
                't': final int t,
              })
                _Queued(
                  p.map((k, v) => MapEntry('$k', '$v')),
                  DateTime.fromMillisecondsSinceEpoch(t),
                ),
        ];
        // Saved ones are older: they go first, then the cap applies.
        _queue.insertAll(0, restored);
        final overflow = _queue.length - config.maxQueueLength;
        if (overflow > 0) _queue.removeRange(0, overflow);
      }
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'matomo.restore');
    }
  }

  Future<void> _persist() async {
    // Never write before the saved queue was read back: the restore would
    // then load the current requests again and send them twice.
    await _ready;
    try {
      await _storage.write(
        queueKey,
        _queue.isEmpty
            ? null
            : jsonEncode([
                for (final q in _queue)
                  {'p': q.params, 't': q.at.millisecondsSinceEpoch},
              ]),
      );
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'matomo.persist');
    }
  }

  /// Drops every unsent request, in memory and in storage.
  @override
  Future<void> onConsentRevoked() async {
    await _ready;
    _queue.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    await _persist();
  }

  void _listenToLifecycle() {
    try {
      _lifecycle = AppLifecycleListener(
        onHide: () => unawaited(_flushOrPersist()),
        onDetach: () => unawaited(_flushOrPersist()),
      );
    } on FlutterError {
      // No binding (pure Dart tests): flushing still works on the timer.
    }
  }

  /// The app is going away: try to send, keep the rest for next launch.
  Future<void> _flushOrPersist() async {
    await _persist();
    await flush();
  }

  String? _resolution() {
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isEmpty) return null;
      final size = views.first.physicalSize;
      if (size.isEmpty) return null;
      return '${size.width.round()}x${size.height.round()}';
    } on StateError {
      return null;
    }
  }

  Size? _viewport() {
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isEmpty) return null;
      final view = views.first;
      return view.physicalSize / view.devicePixelRatio;
    } on StateError {
      return null;
    }
  }

  String? _language() {
    try {
      return PlatformDispatcher.instance.locale.toLanguageTag();
    } on StateError {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _lifecycle?.dispose();
    _lifecycle = null;
    await _flushOrPersist();
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
  }
}

class _Queued {
  _Queued(this.params, this.at);

  final Map<String, String> params;
  final DateTime at;
}
