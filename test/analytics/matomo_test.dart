import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chorki_player/chorki_player.dart';
import 'package:dio/dio.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_test/flutter_test.dart';

class _FakeTransport implements MatomoTransport {
  final List<List<String>> batches = [];
  bool online = true;

  @override
  Future<bool> send(Uri endpoint, List<String> requests) async {
    if (!online) return false;
    batches.add(requests);
    return true;
  }

  List<Map<String, String>> get sent => [
    for (final b in batches)
      for (final r in b) Uri.splitQueryString(r.substring(1)),
  ];
}

final _at = DateTime.utc(2026, 11, 17, 12);

ChorkiAnalyticsEvent _event(
  ChorkiAnalyticsEventType type, {
  Map<String, Object?> data = const {},
  Duration watched = const Duration(seconds: 42),
}) => ChorkiAnalyticsEvent(
  type: type,
  sessionId: 'abc123',
  timestamp: _at,
  metadata: const ChorkiMediaMetadata(
    contentId: 'ep-9',
    title: 'Episode 9',
    mediaUrl: 'https://cdn.test/ep9.m3u8',
    category: 'drama',
  ),
  position: const Duration(seconds: 50),
  duration: const Duration(seconds: 600),
  watchedTime: watched,
  videoSize: const Size(1920, 1080),
  timeToPlay: const Duration(seconds: 3),
  data: data,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const config = MatomoConfig(
    url: 'https://analytics.test/',
    siteId: 7,
    dimensionIds: {'contentId': 1, 'category': 2, 'subscriptionTier': 3},
  );

  group('MatomoRequestBuilder', () {
    const builder = MatomoRequestBuilder(config);

    test('endpoint', () {
      expect(config.endpoint.toString(), 'https://analytics.test/matomo.php');
      expect(
        const MatomoConfig(
          url: 'https://a.test/m.php',
          siteId: 1,
        ).endpoint.toString(),
        'https://a.test/m.php',
      );
    });

    test('a heartbeat is a Media Analytics request', () {
      final requests = builder.build(
        _event(
          ChorkiAnalyticsEventType.heartbeat,
          data: {
            'newSegments': [45, 50],
          },
        ),
        userId: 'user-1',
        userProperties: {'subscriptionTier': 'premium'},
      );
      expect(requests, hasLength(1));
      expect(requests.single, {
        'idsite': '7',
        'rec': '1',
        'apiv': '1',
        'ca': '1',
        'url': 'app://chorki/video/ep-9',
        'cdt': '${_at.millisecondsSinceEpoch ~/ 1000}',
        'uid': 'user-1',
        'dimension1': 'ep-9',
        'dimension2': 'drama',
        'dimension3': 'premium',
        'ma_id': 'abc123',
        'ma_ti': 'Episode 9',
        'ma_re': 'https://cdn.test/ep9.m3u8',
        'ma_mt': 'video',
        'ma_pn': 'chorki_player',
        'ma_st': '42',
        'ma_ps': '50',
        'ma_le': '600',
        'ma_ttp': '3',
        'ma_w': '1920',
        'ma_h': '1080',
        'ma_se': '45,50',
      });
    });

    test('an impression has ma_st=0 and no event duplicate', () {
      final requests = builder.build(
        _event(ChorkiAnalyticsEventType.impression),
      );
      expect(requests, hasLength(1));
      expect(requests.single['ma_st'], '0');
      expect(requests.single.containsKey('ma_ttp'), isFalse);
      expect(requests.single.containsKey('e_c'), isFalse);
    });

    test('other events become Matomo Events', () {
      final seek = builder
          .build(
            _event(
              ChorkiAnalyticsEventType.seek,
              data: {'fromMs': 10000, 'toMs': 40000, 'source': 'doubleTap'},
            ),
          )
          .single;
      expect(seek['e_c'], 'Video');
      expect(seek['e_a'], 'seek (doubleTap)');
      expect(seek['e_n'], 'Episode 9');
      expect(seek['e_v'], '30');
      expect(seek.keys.where((k) => k.startsWith('ma_')), isEmpty);

      final rebuffer = builder
          .build(
            _event(
              ChorkiAnalyticsEventType.bufferEnd,
              data: {'durationMs': 1500},
            ),
          )
          .single;
      expect(rebuffer['e_c'], 'Video QoE');
      expect(rebuffer['e_v'], '1.500');

      final ad = builder
          .build(
            _event(
              ChorkiAnalyticsEventType.adBreakStart,
              data: {
                'breakKind': 'preRoll',
                'breakIndex': 0,
                'adCampaignId': 'c-1',
                'adCampaignTitle': 'Winter',
              },
            ),
          )
          .single;
      expect(ad['e_c'], 'Video Ads');
      expect(ad['e_a'], 'break start (preRoll)');
      expect(ad['e_n'], 'Winter');
    });

    test('every event type has a description', () {
      for (final type in ChorkiAnalyticsEventType.values) {
        final (c, a, _, _) = MatomoRequestBuilder.describe(_event(type));
        expect(c, isNotEmpty);
        expect(a, isNotEmpty);
      }
    });

    test('excluded events and switches', () {
      expect(
        builder.build(_event(ChorkiAnalyticsEventType.bufferStart)),
        isEmpty,
      );
      const eventsOnly = MatomoConfig(
        url: 'https://a.test',
        siteId: 1,
        mediaAnalytics: false,
      );
      final r = const MatomoRequestBuilder(
        eventsOnly,
      ).build(_event(ChorkiAnalyticsEventType.impression)).single;
      expect(r['e_a'], 'impression');
    });
  });

  group('Chorki app compatibility', () {
    test('legacy naming matches the app: MediaVideo play/pause/finished with '
        'the position as value', () {
      const legacy = MatomoRequestBuilder(
        MatomoConfig(
          url: 'https://a.test',
          siteId: 1,
          naming: MatomoNaming.chorkiLegacy,
          playerName: 'ShortsPlayer',
        ),
      );
      Map<String, String> ev(ChorkiAnalyticsEventType t) =>
          legacy.build(_event(t)).single;

      expect(
        ev(ChorkiAnalyticsEventType.play),
        containsPair('e_c', 'MediaVideo'),
      );
      expect(ev(ChorkiAnalyticsEventType.play)['e_a'], 'play');
      expect(ev(ChorkiAnalyticsEventType.resume)['e_a'], 'play');
      expect(ev(ChorkiAnalyticsEventType.pause)['e_a'], 'pause');
      expect(ev(ChorkiAnalyticsEventType.complete)['e_a'], 'finished');
      expect(ev(ChorkiAnalyticsEventType.complete)['e_v'], '50');
      expect(ev(ChorkiAnalyticsEventType.play)['e_n'], 'Episode 9');
      // Other groups keep their richer names.
      expect(ev(ChorkiAnalyticsEventType.bufferEnd)['e_c'], 'Video QoE');
      final ping = legacy
          .build(_event(ChorkiAnalyticsEventType.heartbeat))
          .single;
      expect(ping['ma_pn'], 'ShortsPlayer');
    });

    test('app dimensions and page URLs', () {
      const builder = MatomoRequestBuilder(
        MatomoConfig(
          url: 'https://a.test',
          siteId: 1,
          dimensionIds: MatomoConfig.chorkiAppDimensions,
        ),
      );
      final event = ChorkiAnalyticsEvent(
        type: ChorkiAnalyticsEventType.play,
        sessionId: 's',
        timestamp: _at,
        metadata: const ChorkiMediaMetadata(
          contentId: 'b1',
          pageUrl: 'https://www.chorki.com/bytes/b1',
          referrerUrl: 'https://www.chorki.com/',
        ),
        position: Duration.zero,
        duration: Duration.zero,
        watchedTime: Duration.zero,
      );
      final r = builder
          .build(
            event,
            userProperties: {
              'userId': 'user-9',
              'subscription': 'Subscribed',
              'appVersion': '2.0.0',
            },
          )
          .single;
      expect(r['dimension1'], 'user-9');
      expect(r['dimension2'], 'Subscribed');
      expect(r['dimension3'], '2.0.0');
      expect(r['url'], 'https://www.chorki.com/bytes/b1');
      expect(r['urlref'], 'https://www.chorki.com/');
    });

    test('viewport size mode reports the screen, in whole pixels', () {
      const builder = MatomoRequestBuilder(
        MatomoConfig(
          url: 'https://a.test',
          siteId: 1,
          mediaSize: MatomoMediaSize.viewport,
        ),
      );
      final r = builder
          .build(
            _event(ChorkiAnalyticsEventType.heartbeat),
            viewport: const Size(390.4, 844.6),
          )
          .single;
      expect(r['ma_w'], '390');
      expect(r['ma_h'], '845');
    });
  });

  group('MatomoAnalyticsSink', () {
    late _FakeTransport transport;
    late InMemoryAnalyticsStorage storage;
    late DateTime now;

    MatomoAnalyticsSink create({int batchSize = 20}) => MatomoAnalyticsSink(
      MatomoConfig(
        url: 'https://analytics.test',
        siteId: 7,
        batchSize: batchSize,
        storage: storage,
      ),
      transport: transport,
      clock: () => now,
    );

    setUp(() {
      transport = _FakeTransport();
      storage = InMemoryAnalyticsStorage();
      now = _at;
    });

    test('batches, adds a persistent visitor id, and sends in bulk', () async {
      final sink = create();
      sink.onEvent(_event(ChorkiAnalyticsEventType.impression));
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      expect(transport.batches, isEmpty);
      await sink.flush();

      expect(transport.batches, hasLength(1));
      final sent = transport.sent;
      expect(sent, hasLength(2));
      final id = sent.first['_id']!;
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(sent.every((r) => r['_id'] == id), isTrue);
      expect(storage.values[MatomoAnalyticsSink.visitorIdKey], id);

      // A new sink on the same storage keeps the visitor.
      final again = create();
      expect(await again.visitorId, id);
      await sink.dispose();
      await again.dispose();
    });

    test('keeps requests while offline and sends them later', () async {
      final sink = create();
      transport.online = false;
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      await sink.flush();
      expect(sink.pendingCount, 1);
      expect(storage.values[MatomoAnalyticsSink.queueKey], isNotNull);

      // Survives a restart.
      final restarted = create();
      transport.online = true;
      now = now.add(const Duration(minutes: 5));
      await restarted.flush();
      expect(transport.sent.single['e_a'], 'play');
      expect(restarted.pendingCount, 0);
      await sink.dispose();
      await restarted.dispose();
    });

    test('drops requests too old for Matomo to back-date', () async {
      final sink = create();
      transport.online = false;
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      await sink.flush();
      transport.online = true;
      now = now.add(const Duration(days: 2));
      final later = create();
      await later.flush();
      expect(transport.batches, isEmpty);
      await sink.dispose();
      await later.dispose();
    });

    test('flushes on its own when a batch is full', () async {
      final sink = create(batchSize: 2);
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      sink.onEvent(_event(ChorkiAnalyticsEventType.pause));
      await pumpEventQueue();
      expect(transport.sent, hasLength(2));
      await sink.dispose();
    });

    test(
      'uses the app tracker\'s visitor id when it has a valid one',
      () async {
        String? shared;
        final sink = MatomoAnalyticsSink(
          MatomoConfig(
            url: 'https://a.test',
            siteId: 1,
            storage: storage,
            visitorIdProvider: () => shared,
          ),
          transport: transport,
          clock: () => now,
        );
        final own =
            storage.values[MatomoAnalyticsSink.visitorIdKey] ??
            await sink.visitorId;

        sink.onEvent(_event(ChorkiAnalyticsEventType.play));
        await sink.flush();
        expect(transport.sent.last['_id'], own, reason: 'tracker not ready');

        shared = 'not-hex';
        sink.onEvent(_event(ChorkiAnalyticsEventType.pause));
        await sink.flush();
        expect(transport.sent.last['_id'], own, reason: 'invalid id ignored');

        shared = 'abcdef0123456789';
        sink.onEvent(_event(ChorkiAnalyticsEventType.resume));
        await sink.flush();
        expect(transport.sent.last['_id'], 'abcdef0123456789');
        expect(await sink.visitorId, 'abcdef0123456789');
        await sink.dispose();
      },
    );

    test('user id and properties apply to later events', () async {
      final sink = MatomoAnalyticsSink(
        const MatomoConfig(
          url: 'https://a.test',
          siteId: 1,
          dimensionIds: {'subscriptionTier': 4},
        ),
        transport: transport,
        clock: () => now,
      );
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      sink.userId = 'u-9';
      sink.setUserProperty('subscriptionTier', 'free');
      sink.onEvent(_event(ChorkiAnalyticsEventType.pause));
      await sink.flush();
      expect(transport.sent[0].containsKey('uid'), isFalse);
      expect(transport.sent[1]['uid'], 'u-9');
      expect(transport.sent[1]['dimension4'], 'free');
      await sink.dispose();
    });

    test('a transport that throws is reported and backed off, not stuck '
        '(bug: the exception escaped flush and skipped the retry)', () async {
      final reported = <String>[];
      ChorkiDiagnostics.onError = (e, st, c) => reported.add(c);
      addTearDown(() => ChorkiDiagnostics.onError = null);
      final throwing = _ThrowingTransport();
      final sink = MatomoAnalyticsSink(
        MatomoConfig(url: 'https://a.test', siteId: 1, storage: storage),
        transport: throwing,
        clock: () => now,
      );
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      await sink.flush();
      expect(reported, ['matomo.send']);
      expect(sink.pendingCount, 1, reason: 'kept for a retry');
      expect(storage.values[MatomoAnalyticsSink.queueKey], isNotNull);

      // Backing off: an immediate flush does not hammer the server.
      await sink.flush();
      expect(throwing.calls, 1);
      throwing.fail = false;
      now = now.add(const Duration(seconds: 6));
      await sink.flush();
      expect(sink.pendingCount, 0);
      await sink.dispose();
    });

    test(
      'revoking consent drops queued requests, in memory and storage',
      () async {
        final sink = create();
        transport.online = false;
        sink.onEvent(_event(ChorkiAnalyticsEventType.play));
        await sink.flush();
        expect(sink.pendingCount, 1);

        await sink.onConsentRevoked();
        expect(sink.pendingCount, 0);
        expect(storage.values[MatomoAnalyticsSink.queueKey], isNull);
        transport.online = true;
        await sink.flush();
        expect(transport.batches, isEmpty);
        await sink.dispose();
      },
    );

    test('a damaged saved queue keeps its good entries and the cap '
        '(bug: one bad entry dropped them all)', () async {
      storage.values[MatomoAnalyticsSink.queueKey] = jsonEncode([
        {'p': 'not a map', 't': 1},
        for (var i = 0; i < 5; i++)
          {
            'p': {'idsite': '1', 'n': '$i'},
            't': now.millisecondsSinceEpoch,
          },
        42,
      ]);
      final sink = MatomoAnalyticsSink(
        MatomoConfig(
          url: 'https://a.test',
          siteId: 1,
          storage: storage,
          maxQueueLength: 3,
        ),
        transport: transport,
        clock: () => now,
      );
      await sink.flush();
      expect(transport.sent.map((r) => r['n']), ['2', '3', '4']);
      await sink.dispose();
    });

    test('an unreadable saved queue is reported, not fatal', () async {
      final reported = <String>[];
      ChorkiDiagnostics.onError = (e, st, c) => reported.add(c);
      addTearDown(() => ChorkiDiagnostics.onError = null);
      storage.values[MatomoAnalyticsSink.queueKey] = '{not json';
      final sink = create();
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      await sink.flush();
      expect(reported, ['matomo.restore']);
      expect(transport.sent, hasLength(1));
      await sink.dispose();
    });

    test('a throwing visitorIdProvider falls back to the own id', () async {
      final reported = <String>[];
      ChorkiDiagnostics.onError = (e, st, c) => reported.add(c);
      addTearDown(() => ChorkiDiagnostics.onError = null);
      final sink = MatomoAnalyticsSink(
        MatomoConfig(
          url: 'https://a.test',
          siteId: 1,
          visitorIdProvider: () => throw StateError('not ready'),
        ),
        transport: transport,
        clock: () => now,
      );
      expect(await sink.visitorId, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(reported, ['matomo.visitorIdProvider']);
      await sink.dispose();
    });

    test('DioMatomoTransport: 2xx is accepted, others and network errors '
        'are not', () async {
      final adapter = _StatusAdapter();
      final transport = DioMatomoTransport(
        dio: Dio()..httpClientAdapter = adapter,
      );
      final endpoint = Uri.parse('https://a.test/matomo.php');
      adapter.status = 204;
      expect(await transport.send(endpoint, ['?a=1']), isTrue);
      expect(jsonDecode(adapter.bodies.single), {
        'requests': ['?a=1'],
      });
      adapter.status = 500;
      expect(await transport.send(endpoint, ['?a=1']), isFalse);
      adapter.fail = true;
      expect(await transport.send(endpoint, ['?a=1']), isFalse);
      expect(DioMatomoTransport(), isA<MatomoTransport>());
    });

    test(
      'the viewport media size reports the screen in logical pixels',
      () async {
        final sink = MatomoAnalyticsSink(
          const MatomoConfig(
            url: 'https://a.test',
            siteId: 1,
            mediaSize: MatomoMediaSize.viewport,
          ),
          transport: transport,
          clock: () => now,
        );
        sink.onEvent(_event(ChorkiAnalyticsEventType.impression));
        await sink.flush();
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final logical = view.physicalSize / view.devicePixelRatio;
        expect(transport.sent.single['ma_w'], '${logical.width.round()}');
        await sink.dispose();
      },
    );

    test('going to the background flushes what is queued, once '
        '(bug: a hide before the saved queue was restored sent every '
        'request twice)', () async {
      final sink = create();
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      expect(transport.batches, isEmpty);
      WidgetsBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await pumpEventQueue();
      expect(transport.sent, hasLength(1));
      WidgetsBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await sink.dispose();
    });

    test('user properties can be removed', () {
      final sink = create()
        ..setUserProperty('tier', 'gold')
        ..setUserProperty('tier', null);
      expect(sink.userProperties, isEmpty);
      unawaited(sink.dispose());
    });

    test('the bulk body is Matomo JSON', () async {
      String? body;
      final sink = MatomoAnalyticsSink(
        const MatomoConfig(url: 'https://a.test', siteId: 1),
        transport: _CapturingTransport((b) => body = b),
        clock: () => now,
      );
      sink.onEvent(_event(ChorkiAnalyticsEventType.play));
      await sink.flush();
      final decoded = jsonDecode(body!) as Map<String, Object?>;
      expect(decoded['requests'], isA<List<Object?>>());
      expect((decoded['requests']! as List).single, startsWith('?'));
      await sink.dispose();
    });
  });
}

class _CapturingTransport implements MatomoTransport {
  _CapturingTransport(this.onBody);
  final void Function(String body) onBody;

  @override
  Future<bool> send(Uri endpoint, List<String> requests) async {
    onBody(jsonEncode({'requests': requests}));
    return true;
  }
}

class _ThrowingTransport implements MatomoTransport {
  bool fail = true;
  int calls = 0;

  @override
  Future<bool> send(Uri endpoint, List<String> requests) async {
    calls++;
    if (fail) throw StateError('socket closed');
    return true;
  }
}

class _StatusAdapter implements HttpClientAdapter {
  int status = 200;
  bool fail = false;
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (fail) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final chunks = await requestStream?.toList() ?? [];
    bodies.add(utf8.decode([for (final c in chunks) ...c]));
    return ResponseBody.fromString('', status);
  }

  @override
  void close({bool force = false}) {}
}
