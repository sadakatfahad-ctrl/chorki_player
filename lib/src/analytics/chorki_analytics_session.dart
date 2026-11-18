import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../core/clock.dart';
import '../core/diagnostics.dart';
import '../core/ids.dart';
import '../errors/chorki_player_error.dart';
import 'chorki_analytics_config.dart';
import 'chorki_analytics_event.dart';
import 'chorki_analytics_schema.dart';
import 'chorki_media_metadata.dart';
import 'watch_tracker.dart';

typedef _K = ChorkiAnalyticsKeys;

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
          _guard(sink.onConsentRevoked, 'analytics.onConsentRevoked');
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

  @visibleForTesting
  bool get isHeartbeatRunning => _heartbeat != null;

  // -------------------------------------------------------------- lifecycle

  /// The item is on screen. Starts a new session.
  void activate() {
    if (_active || _disposed) return;
    _active = true;
    if (_config.isActive) _beginView();
  }

  void _beginView() {
    _activatedAt = _clock();
    _startSession();
    final v = _video?.value;
    if (v != null) {
      _lastPos = v.position;
      _wasPlaying = false;
      _volume = null;
    }
    _onValue();
  }

  /// Ends the view without reporting it (consent revoked, disabled).
  void _discardSession() {
    _id = null;
    _impressionSent = false;
    _activatedAt = null;
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

  void _listenToLifecycle() {
    try {
      _lifecycle = AppLifecycleListener(onHide: _onAppHidden);
    } on FlutterError {
      // No binding (pure Dart use): nothing to listen to.
    }
  }

  /// The app went to the background: report progress so far and ask the
  /// sinks to send it, before the OS may kill the app.
  void _onAppHidden() {
    if (!_active || !_impressionSent) return;
    _flush('background');
    for (final sink in _config.sinks) {
      _guard(sink.flush, 'analytics.flush');
    }
  }

  void _startSession() {
    _id = _newId();
    _impressionSent = false;
    _impressionAt = null;
    _timeToPlay = null;
    _watch.reset();
    _maxPos = Duration.zero;
    _playedOnce = false;
    _paused = false;
    _completed = false;
    _bufferStartAt = null;
    _firstFrameAt = null;
    _lastSeekAt = null;
    _loopCount = 0;
    _pauseCount = 0;
    _seekCount = 0;
    _rebufferCount = 0;
    _errorCount = 0;
    _rebufferTime = Duration.zero;
    _adBreakIndex = 0;
    _boostStartAt = null;
    // A break or drag cut off by the previous session must not leak in.
    _inAd = false;
    _adBreakStartAt = null;
    _scrubbing = false;
  }

  void _endSession(ChorkiSessionEndReason reason) {
    _stopHeartbeat();
    if (!_playedOnce && _id != null) {
      // Left before the first frame: exit before video start.
      final now = _clock();
      _emit(ChorkiAnalyticsEventType.abandon, {
        _K.waitedMs: now.difference(_activatedAt ?? now).inMilliseconds,
        _K.reason: reason.name,
        _K.abandonStage: _impressionSent ? 'ready' : 'loading',
        _K.errorCount: _errorCount,
      });
    }
    if (_impressionSent) {
      final now = _clock();
      final buffering = _bufferStartAt;
      if (buffering != null) {
        _rebufferTime += now.difference(buffering);
        _emit(ChorkiAnalyticsEventType.bufferEnd, {
          _K.durationMs: now.difference(buffering).inMilliseconds,
        });
        _bufferStartAt = null;
      }
      if (_boostStartAt != null) recordSpeedBoostEnd();
      // Swiped away mid-break: the ad layer is gone and will not end it.
      if (_inAd) {
        final start = _adBreakStartAt;
        _emit(ChorkiAnalyticsEventType.adBreakEnd, {
          _K.breakIndex: _adBreakIndex,
          _K.durationMs: start == null
              ? 0
              : now.difference(start).inMilliseconds,
          _K.interrupted: true,
          ...adContext,
        });
        _inAd = false;
        _adBreakStartAt = null;
      }
      _flush('end');
      final duration = _video?.value.duration ?? Duration.zero;
      _emit(ChorkiAnalyticsEventType.sessionEnd, {
        _K.reason: reason.name,
        _K.dwellMs: now.difference(_impressionAt ?? now).inMilliseconds,
        _K.watchedPercent: _watch.watchedPercent(duration),
        _K.maxPositionMs: _maxPos.inMilliseconds,
        _K.rebufferCount: _rebufferCount,
        _K.rebufferMs: _rebufferTime.inMilliseconds,
        _K.pauseCount: _pauseCount,
        _K.seekCount: _seekCount,
        _K.loopCount: _loopCount,
        _K.errorCount: _errorCount,
      });
    }
    _id = null;
    _impressionSent = false;
  }

  // ---------------------------------------------------------- value updates

  void _onValue() {
    final video = _video;
    if (video == null || !_active || _disposed || _id == null) return;
    final v = video.value;
    if (!v.isInitialized || v.hasError) return;

    if (!_impressionSent) {
      _impressionSent = true;
      _impressionAt = _clock();
      _emit(ChorkiAnalyticsEventType.impression);
    }

    final now = _clock();
    final pos = v.position;
    final dur = v.duration;
    final playing = v.isPlaying && !_inAd;

    // A looping video wraps from the end back to the start without ever
    // reporting completion.
    final recentSeek =
        _lastSeekAt != null && now.difference(_lastSeekAt!) < _nearWindow;
    if (_wasPlaying &&
        !recentSeek &&
        dur > _minLoopDuration &&
        _lastPos >= dur - _nearWindow &&
        pos < _nearWindow) {
      _onLooped(pos);
    }

    // Watched time and segments: only real playback between two ticks.
    if (_wasPlaying && playing && !v.isBuffering) {
      final delta = pos - _lastPos;
      final maxTick = _maxTick * max(1.0, v.playbackSpeed);
      if (delta > Duration.zero && delta <= maxTick) {
        _watch.played(_lastPos, pos);
      }
    }
    if (pos > _maxPos) _maxPos = pos;

    // First frame / play / resume.
    if (playing && !_wasPlaying) {
      if (!_playedOnce) {
        _playedOnce = true;
        _timeToPlay = now.difference(_impressionAt ?? now);
        _emit(ChorkiAnalyticsEventType.play, {
          _K.timeToPlayMs: _timeToPlay!.inMilliseconds,
        });
      } else if (_paused) {
        _emit(ChorkiAnalyticsEventType.resume);
      }
      _paused = false;
      _startHeartbeat();
    }
    if (_firstFrameAt == null && v.isPlaying && pos > Duration.zero) {
      _firstFrameAt = now;
      final activated = _activatedAt ?? now;
      final loadStart = _loadStartAt;
      final from = loadStart != null && loadStart.isAfter(activated)
          ? loadStart
          : activated;
      final preloaded = loadStart != null && loadStart.isBefore(activated);
      _emit(ChorkiAnalyticsEventType.firstFrame, {
        _K.startupMs: now.difference(from).inMilliseconds,
        // Load timings belong to the view that waited for them.
        if (!preloaded && loadStart != null && _loadRunningAt != null)
          _K.queueWaitMs: _loadRunningAt!.difference(loadStart).inMilliseconds,
        if (!preloaded && _loadRunningAt != null && _loadedAt != null)
          _K.initMs: _loadedAt!.difference(_loadRunningAt!).inMilliseconds,
        _K.preloaded: preloaded,
      });
    }

    // Pause (an ad pausing the content is not the viewer pausing).
    final atEnd =
        v.isCompleted || (dur > Duration.zero && pos >= dur - _endWindow);
    if (!playing && _wasPlaying) {
      _stopHeartbeat();
      // A scrub pauses while dragging: that is a seek, not a pause.
      if (!_inAd && !atEnd && !_scrubbing) {
        _flush('pause');
        _pauseCount++;
        _paused = true;
        _emit(ChorkiAnalyticsEventType.pause);
      }
    }

    // Rebuffering, after the first frame and outside ads.
    if (v.isBuffering && !_wasBuffering && _firstFrameAt != null && !_inAd) {
      _bufferStartAt = now;
      _rebufferCount++;
      _emit(ChorkiAnalyticsEventType.bufferStart, {_K.afterSeek: recentSeek});
    } else if (!v.isBuffering && _bufferStartAt != null) {
      final took = now.difference(_bufferStartAt!);
      _rebufferTime += took;
      _bufferStartAt = null;
      _emit(ChorkiAnalyticsEventType.bufferEnd, {
        _K.durationMs: took.inMilliseconds,
      });
    }

    // Quartiles and completion.
    if (playing || _wasPlaying) {
      for (final q in _watch.reachedQuartiles(pos, dur)) {
        _emit(ChorkiAnalyticsEventType.quartile, {_K.percent: q});
      }
    }
    if (v.isCompleted && !_completed) {
      _completed = true;
      _onCompleted();
    } else if (_completed && dur > Duration.zero && pos < dur - _oneSecond) {
      _completed = false;
    }

    // Volume / mute.
    final vol = v.volume;
    if (_volume != null && (vol - _volume!).abs() > 0.001) {
      _emit(ChorkiAnalyticsEventType.volumeChange, {
        _K.from: _volume,
        _K.to: vol,
        _K.muted: vol == 0,
      });
    }
    _volume = vol;

    _wasPlaying = playing;
    _wasBuffering = v.isBuffering;
    _lastPos = pos;
  }

  static const Duration _oneSecond = Duration(seconds: 1);

  /// Positions this close to the start / end count as "at" it for loop
  /// detection; seeks this recent rule a loop out.
  static const Duration _nearWindow = Duration(milliseconds: 1500);

  /// Shorter videos never count as looping (a seek to 0 looks the same).
  static const Duration _minLoopDuration = Duration(seconds: 3);

  /// Longest position step between two ticks counted as playback (at 1x).
  static const Duration _maxTick = Duration(seconds: 3);

  /// A pause this close to the end is the video ending, not the viewer.
  static const Duration _endWindow = Duration(milliseconds: 300);

  void _onCompleted() {
    _flush('complete');
    if (_watch.reachedEnd()) {
      _emit(ChorkiAnalyticsEventType.quartile, {_K.percent: 100});
    }
    _emit(ChorkiAnalyticsEventType.complete);
  }

  void _onLooped(Duration pos) {
    // The tail between the last tick and the end was played too.
    final dur = _video?.value.duration ?? Duration.zero;
    _watch.played(_lastPos, dur);
    _onCompleted();
    _loopCount++;
    _emit(ChorkiAnalyticsEventType.loop, {_K.loopCount: _loopCount});
    if (_config.newSessionOnLoop) {
      final loops = _loopCount;
      _endSession(ChorkiSessionEndReason.looped);
      _startSession();
      _loopCount = loops;
      _impressionSent = true;
      _impressionAt = _clock();
      // Startup was measured on the first view; a loop starts instantly.
      _firstFrameAt = _impressionAt;
      _emit(ChorkiAnalyticsEventType.impression, {_K.loopCount: loops});
      _playedOnce = true;
      _timeToPlay = Duration.zero;
      _emit(ChorkiAnalyticsEventType.play, {
        _K.timeToPlayMs: 0,
        _K.loopCount: loops,
      });
      _startHeartbeat();
    } else {
      _watch.resetQuartiles();
      _completed = false;
    }
    // The regular tick step counts 0 → pos.
    _lastPos = Duration.zero;
  }

  // ------------------------------------------------------------- heartbeats

  void _startHeartbeat() {
    if (_heartbeat != null || !_config.isActive) return;
    _heartbeat = Timer.periodic(_config.heartbeatInterval, (_) {
      _flush('interval');
    });
  }

  void _stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// Sends a `heartbeat` now (also used by tests instead of waiting).
  void heartbeat() => _flush('interval');

  void _flush(String trigger) {
    if (!_impressionSent || _id == null) return;
    _emit(ChorkiAnalyticsEventType.heartbeat, {
      _K.trigger: trigger,
      _K.newSegments: _watch.takeNewSegments(),
    });
  }

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

  static void _guard(Future<void> Function() action, String context) {
    unawaited(
      Future.sync(action).catchError((Object e, StackTrace st) {
        ChorkiDiagnostics.report(e, st, context);
      }),
    );
  }
}
