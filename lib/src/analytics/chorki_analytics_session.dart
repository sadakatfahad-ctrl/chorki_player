import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../core/clock.dart';
import '../core/diagnostics.dart';
import '../core/guard.dart';
import '../core/ids.dart';
import '../errors/chorki_player_error.dart';
import 'chorki_analytics_config.dart';
import 'chorki_analytics_event.dart';
import 'chorki_analytics_schema.dart';
import 'chorki_media_metadata.dart';
import 'watch_tracker.dart';

part 'session/session_playback.dart';
part 'session/session_view.dart';

typedef _K = ChorkiAnalyticsKeys;

const Duration _oneSecond = Duration(seconds: 1);

/// Positions this close to the start / end count as "at" it for loop
/// detection; seeks this recent rule a loop out.
const Duration _nearWindow = Duration(milliseconds: 1500);

/// Shorter videos never count as looping (a seek to 0 looks the same).
const Duration _minLoopDuration = Duration(seconds: 3);

/// Longest position step between two ticks counted as playback (at 1x).
const Duration _maxTick = Duration(seconds: 3);

/// A pause this close to the end is the video ending, not the viewer.
const Duration _endWindow = Duration(milliseconds: 300);

/// Tracks one player's views and turns `video_player` values and the
/// player's UI actions into [ChorkiAnalyticsEvent]s.
///
/// [ChorkiPlayer] owns one per widget (never per [ChorkiPlayerController],
/// which a feed shares). It is only reporting while [isActive]: a feed page
/// that is preloading off screen reports nothing.
///
/// Lifecycle:
/// * [activate] when the item is on screen. A new [sessionId] is made.
/// * [bind] the loaded video. With both, an `impression` is sent.
/// * [deactivate] when it leaves the screen (or the player is disposed):
///   a last `heartbeat` and `sessionEnd` with the totals.
///
/// While [ChorkiAnalyticsConfig.isActive] is false (no consent, disabled)
/// nothing is tracked or counted. Turning it on starts a fresh view;
/// turning it off ends the current one silently.
class ChorkiAnalyticsSession {
  /// Creates a session; [clock] and [idGenerator] default to
  /// [ChorkiAnalyticsConfig.clock] / [ChorkiAnalyticsConfig.idGenerator].
  ChorkiAnalyticsSession({
    required this._config,
    required this._metadata,
    ChorkiClock? clock,
    ChorkiIdGenerator? idGenerator,
  }) : _clock = clock ?? _config.clock,
       _newId = idGenerator ?? _config.idGenerator,
       _watch = WatchTracker(_config.segmentLength) {
    _listenToLifecycle();
  }

  ChorkiAnalyticsConfig _config;
  final ChorkiMediaMetadata Function() _metadata;
  final ChorkiClock _clock;
  final ChorkiIdGenerator _newId;
  final WatchTracker _watch;
  AppLifecycleListener? _lifecycle;

  /// Values set by the ad layer's caller (campaign id / title), added to every
  /// ad event.
  Map<String, Object?> adContext = const {};

  /// Where and how events are reported. Changing it applies at once:
  /// consent or [ChorkiAnalyticsConfig.enabled] turning off ends the view
  /// silently (and tells the sinks when consent was revoked); turning on
  /// starts a new one.
  ChorkiAnalyticsConfig get config => _config;
  set config(ChorkiAnalyticsConfig value) {
    final old = _config;
    _config = value;
    _watch.segmentLength = value.segmentLength;
    if (old.isActive && !value.isActive) {
      _stopHeartbeat();
      _discardSession();
      if (old.consentGranted && !value.consentGranted) {
        for (final sink in old.sinks) {
          fireAndReport(sink.onConsentRevoked, 'analytics.onConsentRevoked');
        }
      }
    } else if (!old.isActive && value.isActive && _active) {
      _beginView();
    } else if (value.heartbeatInterval != old.heartbeatInterval &&
        _heartbeat != null) {
      _stopHeartbeat();
      _startHeartbeat();
    }
  }

  // ------------------------------------------------------------------ state

  ValueListenable<VideoPlayerValue>? _video;
  bool _active = false;
  String? _id;
  bool _impressionSent = false;
  bool _disposed = false;

  DateTime? _activatedAt;
  DateTime? _impressionAt;
  DateTime? _loadStartAt;
  DateTime? _loadRunningAt;
  DateTime? _loadedAt;
  DateTime? _firstFrameAt;
  Duration? _timeToPlay;

  Duration _lastPos = Duration.zero;
  Duration _maxPos = Duration.zero;
  bool _wasPlaying = false;
  bool _wasBuffering = false;
  bool _playedOnce = false;
  bool _paused = false;
  bool _completed = false;
  DateTime? _bufferStartAt;
  DateTime? _lastSeekAt;
  double? _volume;

  int _loopCount = 0;
  int _pauseCount = 0;
  int _seekCount = 0;
  int _rebufferCount = 0;
  int _errorCount = 0;
  Duration _rebufferTime = Duration.zero;

  bool _inAd = false;
  bool _scrubbing = false;
  int _adBreakIndex = 0;
  DateTime? _adBreakStartAt;
  DateTime? _boostStartAt;

  Timer? _heartbeat;

  /// Id of the current view (`ma_id`), null while inactive.
  String? get sessionId => _id;

  /// Whether the item is on screen ([activate]d and not deactivated).
  bool get isActive => _active;

  /// Media time played in this session.
  Duration get watchedTime => _watch.watched;

  /// Whether periodic heartbeats are scheduled (a view is playing).
  @visibleForTesting
  bool get isHeartbeatRunning => _heartbeat != null;

  // -------------------------------------------------------------- lifecycle

  /// The item is on screen. Starts a new session.
  void activate() {
    if (_active || _disposed) return;
    _active = true;
    if (_config.isActive) _beginView();
  }

  /// The item left the screen, its source changed, or it is going away.
  void deactivate(ChorkiSessionEndReason reason) {
    if (!_active) return;
    _endSession(reason);
    _active = false;
    _activatedAt = null;
  }

  /// Follows [video] (a `VideoPlayerController`, or any listenable value in
  /// tests). Keeps the session: a reload after an error continues it.
  void bind(ValueListenable<VideoPlayerValue> video) {
    if (_disposed) return;
    if (identical(video, _video)) return;
    unbind();
    _video = video;
    _lastPos = video.value.position;
    _wasPlaying = false;
    _wasBuffering = false;
    _volume = null;
    video.addListener(_onValue);
    _onValue();
  }

  /// Stops following the video (the session itself continues).
  void unbind() {
    _video?.removeListener(_onValue);
    _video = null;
    _wasPlaying = false;
    _wasBuffering = false;
    _stopHeartbeat();
  }

  /// Ends the session (`disposed`) and stops listening. Final.
  void dispose() {
    if (_disposed) return;
    deactivate(ChorkiSessionEndReason.disposed);
    unbind();
    _lifecycle?.dispose();
    _lifecycle = null;
    _disposed = true;
  }

  // ---------------------------------------------------------- value updates

  /// Listener for the bound video. Kept on the class: an instance-method
  /// tear-off is stable, so `removeListener` finds it.
  void _onValue() => _handleValue();

  // ------------------------------------------------------------- heartbeats

  /// Sends a `heartbeat` now (also used by tests instead of waiting).
  void heartbeat() => _flush('interval');

  // ------------------------------------------------- actions from the player

  /// The video load started (it may still wait for a free slot).
  void recordLoadStart() {
    _loadStartAt = _clock();
    _loadRunningAt = null;
    _loadedAt = null;
    _firstFrameAt = null;
    _emit(ChorkiAnalyticsEventType.loadStart);
  }

  /// The load got its slot in [ChorkiVideoLoadScheduler] and began initializing.
  void recordLoadRunning() => _loadRunningAt = _clock();

  /// The video initialized.
  void recordLoaded() => _loadedAt = _clock();

  /// A route, load or playback failure; [willRetry] when a silent retry
  /// follows.
  void recordError(ChorkiPlayerError error, {required bool willRetry}) {
    if (_id != null) _errorCount++;
    _emit(ChorkiAnalyticsEventType.error, {
      _K.code: error.code.name,
      _K.stage: error.stage.name,
      _K.transient: error.isTransient,
      _K.willRetry: willRetry,
      _K.statusCode: ?error.statusCode,
      _K.detail: ?error.detail,
    });
  }

  /// A reload; [auto] when it was not the viewer's.
  void recordRetry({required int attempt, required bool auto}) {
    _emit(ChorkiAnalyticsEventType.retry, {_K.attempt: attempt, _K.auto: auto});
  }

  /// A drag-to-seek began; the pause it causes is not reported.
  void recordScrubStart() => _scrubbing = true;

  /// A drag ended without moving.
  void recordScrubCancel() => _scrubbing = false;

  /// A seek the viewer (or the app) asked for.
  void recordSeek(Duration from, Duration to, ChorkiSeekSource source) {
    _scrubbing = false;
    if (!_impressionSent || from == to) return;
    _flush('seek');
    _seekCount++;
    _lastSeekAt = _clock();
    _emit(ChorkiAnalyticsEventType.seek, {
      _K.fromMs: from.inMilliseconds,
      _K.toMs: to.inMilliseconds,
      _K.source: source.name,
    });
    _lastPos = to;
    // Replaying from (near) the start after the end: quartiles count again.
    if (_completed && to < _oneSecond) _watch.resetQuartiles();
    _completed = false;
  }

  /// The viewer picked another playback speed.
  void recordSpeedChange(double from, double to) {
    if (from == to) return;
    _emit(ChorkiAnalyticsEventType.speedChange, {_K.from: from, _K.to: to});
  }

  /// A long-press speed boost began.
  void recordSpeedBoostStart(double speed) {
    _boostStartAt = _clock();
    _emit(ChorkiAnalyticsEventType.speedBoostStart, {_K.speed: speed});
  }

  /// The long-press speed boost ended.
  void recordSpeedBoostEnd() {
    final start = _boostStartAt;
    if (start == null) return;
    _boostStartAt = null;
    _emit(ChorkiAnalyticsEventType.speedBoostEnd, {
      _K.durationMs: _clock().difference(start).inMilliseconds,
    });
  }

  /// Track heights / bitrates; null means Auto.
  void recordQualityChange({
    int? fromHeight,
    int? toHeight,
    int? bitrate,
    String? label,
  }) {
    _emit(ChorkiAnalyticsEventType.qualityChange, {
      _K.fromHeight: ?fromHeight,
      _K.toHeight: ?toHeight,
      _K.bitrate: ?bitrate,
      _K.label: ?label,
      _K.auto: toHeight == null,
    });
  }

  /// The viewer picked another audio track.
  void recordAudioTrackChange(String? from, String to) {
    if (from == to) return;
    _emit(ChorkiAnalyticsEventType.audioTrackChange, {
      _K.fromTrack: ?from,
      _K.toTrack: to,
    });
  }

  /// The video fit changed (`fit` / `fill`).
  void recordFitChange(String fit) =>
      _emit(ChorkiAnalyticsEventType.fitChange, {_K.fit: fit});

  /// The PiP status changed.
  void recordPipChange(String status) =>
      _emit(ChorkiAnalyticsEventType.pipChange, {_K.status: status});

  /// The settings sheet opened.
  void recordSettingsOpen() => _emit(ChorkiAnalyticsEventType.settingsOpen);

  // -------------------------------------------------------------------- ads

  /// An ad break paused the content.
  void recordAdBreakStart() {
    if (_inAd) return;
    _flush('ad');
    _inAd = true;
    _adBreakStartAt = _clock();
    final v = _video?.value;
    final pos = v?.position ?? Duration.zero;
    final dur = v?.duration ?? Duration.zero;
    final kind = pos < _oneSecond
        ? 'preRoll'
        : (dur > Duration.zero && pos >= dur - _oneSecond)
        ? 'postRoll'
        : 'midRoll';
    _emit(ChorkiAnalyticsEventType.adBreakStart, {
      _K.breakIndex: _adBreakIndex,
      _K.breakKind: kind,
      ...adContext,
    });
  }

  /// The content resumed after a break.
  void recordAdBreakEnd() {
    if (!_inAd) return;
    _inAd = false;
    final start = _adBreakStartAt;
    _adBreakStartAt = null;
    _emit(ChorkiAnalyticsEventType.adBreakEnd, {
      _K.breakIndex: _adBreakIndex,
      _K.durationMs: start == null
          ? 0
          : _clock().difference(start).inMilliseconds,
      ...adContext,
    });
    _adBreakIndex++;
    // Re-sync so the jump over the break is not counted as watched.
    final v = _video?.value;
    if (v != null) _lastPos = v.position;
    _wasPlaying = false;
  }

  /// Any other ad event ([ChorkiAnalyticsCategory.ad]).
  void recordAd(ChorkiAnalyticsEventType type, [Map<String, Object?>? data]) {
    assert(type.category == ChorkiAnalyticsCategory.ad);
    _emit(type, {_K.breakIndex: _adBreakIndex, ...adContext, ...?data});
  }

  // ----------------------------------------------------------------- output

  void _emit(ChorkiAnalyticsEventType type, [Map<String, Object?>? data]) {
    final id = _id;
    if (id == null || !_active || _disposed || !_config.isActive) return;
    final payload = Map<String, Object?>.unmodifiable(data ?? const {});
    assert(() {
      final problems = ChorkiAnalyticsSchema.validate(type, payload);
      if (problems.isNotEmpty) {
        throw StateError('Analytics payload breaks the schema: $problems');
      }
      return true;
    }());
    final v = _video?.value;
    final event = ChorkiAnalyticsEvent(
      type: type,
      sessionId: id,
      timestamp: _clock(),
      metadata: _safeMetadata(),
      position: v?.position ?? Duration.zero,
      duration: v?.duration ?? Duration.zero,
      watchedTime: _watch.watched,
      videoSize: v?.size ?? Size.zero,
      timeToPlay: _timeToPlay,
      data: payload,
    );
    for (final sink in _config.sinks) {
      try {
        sink.onEvent(event);
      } catch (e, st) {
        // A broken sink must never break playback (or the other sinks).
        ChorkiDiagnostics.report(e, st, 'analytics.sink');
      }
    }
  }

  ChorkiMediaMetadata _safeMetadata() {
    try {
      return _metadata();
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'analytics.metadata');
      return const ChorkiMediaMetadata();
    }
  }
}
