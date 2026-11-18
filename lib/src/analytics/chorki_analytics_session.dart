import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'chorki_analytics_config.dart';
import 'chorki_analytics_event.dart';
import 'chorki_media_metadata.dart';

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
class ChorkiAnalyticsSession {
  ChorkiAnalyticsSession({
    required this._config,
    required this._metadata,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : _clock = clock ?? DateTime.now,
       _newId = idGenerator ?? _randomId;

  ChorkiAnalyticsConfig _config;
  final ChorkiMediaMetadata Function() _metadata;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// Values set by the ad layer's caller (campaign id / title), added to every
  /// ad event.
  Map<String, Object?> adContext = const {};

  ChorkiAnalyticsConfig get config => _config;
  set config(ChorkiAnalyticsConfig value) {
    final restart = value.heartbeatInterval != _config.heartbeatInterval;
    _config = value;
    if (restart && _heartbeat != null) {
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

  Duration _watched = Duration.zero;
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

  final Set<int> _segments = {};
  final Set<int> _pendingSegments = {};
  final Set<int> _quartiles = {};

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

  bool get isActive => _active;

  /// Media time played in this session.
  Duration get watchedTime => _watched;

  @visibleForTesting
  bool get isHeartbeatRunning => _heartbeat != null;

  // -------------------------------------------------------------- lifecycle

  /// The item is on screen. Starts a new session.
  void activate() {
    if (_active || _disposed) return;
    _active = true;
    _activatedAt = _clock();
    _startSession();
    final v = _video?.value;
    if (v != null) {
      _lastPos = v.position;
      _wasPlaying = false;
    }
    _onValue();
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

  void unbind() {
    _video?.removeListener(_onValue);
    _video = null;
    _wasPlaying = false;
    _wasBuffering = false;
    _stopHeartbeat();
  }

  void dispose() {
    if (_disposed) return;
    deactivate(ChorkiSessionEndReason.disposed);
    unbind();
    _disposed = true;
  }

  void _startSession() {
    _id = _newId();
    _impressionSent = false;
    _impressionAt = null;
    _timeToPlay = null;
    _watched = Duration.zero;
    _maxPos = Duration.zero;
    _playedOnce = false;
    _paused = false;
    _completed = false;
    _bufferStartAt = null;
    _segments.clear();
    _pendingSegments.clear();
    _quartiles.clear();
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
        'waitedMs': now.difference(_activatedAt ?? now).inMilliseconds,
        'reason': reason.name,
        'stage': _impressionSent ? 'ready' : 'loading',
        'errorCount': _errorCount,
      });
    }
    if (_impressionSent) {
      final now = _clock();
      final buffering = _bufferStartAt;
      if (buffering != null) {
        _rebufferTime += now.difference(buffering);
        _emit(ChorkiAnalyticsEventType.bufferEnd, {
          'durationMs': now.difference(buffering).inMilliseconds,
        });
        _bufferStartAt = null;
      }
      if (_boostStartAt != null) recordSpeedBoostEnd();
      // Swiped away mid-break: the ad layer is gone and will not end it.
      if (_inAd) {
        final start = _adBreakStartAt;
        _emit(ChorkiAnalyticsEventType.adBreakEnd, {
          'breakIndex': _adBreakIndex,
          'durationMs': start == null
              ? 0
              : now.difference(start).inMilliseconds,
          'interrupted': true,
          ...adContext,
        });
        _inAd = false;
        _adBreakStartAt = null;
      }
      _flush('end');
      final duration = _video?.value.duration ?? Duration.zero;
      _emit(ChorkiAnalyticsEventType.sessionEnd, {
        'reason': reason.name,
        'dwellMs': now.difference(_impressionAt ?? now).inMilliseconds,
        'watchedPercent': duration > Duration.zero
            ? (_segments.length *
                      _config.segmentLength.inMilliseconds /
                      duration.inMilliseconds *
                      100)
                  .clamp(0, 100)
                  .round()
            : 0,
        'maxPositionMs': _maxPos.inMilliseconds,
        'rebufferCount': _rebufferCount,
        'rebufferMs': _rebufferTime.inMilliseconds,
        'pauseCount': _pauseCount,
        'seekCount': _seekCount,
        'loopCount': _loopCount,
        'errorCount': _errorCount,
      });
    }
    _id = null;
    _impressionSent = false;
  }

  // ---------------------------------------------------------- value updates

  void _onValue() {
    final video = _video;
    if (video == null || !_active || _disposed) return;
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
        _lastSeekAt != null &&
        now.difference(_lastSeekAt!) < const Duration(milliseconds: 1500);
    if (_wasPlaying &&
        !recentSeek &&
        dur > const Duration(seconds: 3) &&
        _lastPos >= dur - const Duration(milliseconds: 1500) &&
        pos < const Duration(milliseconds: 1500)) {
      _onLooped(pos);
    }

    // Watched time and segments: only real playback between two ticks.
    if (_wasPlaying && playing && !v.isBuffering) {
      final delta = pos - _lastPos;
      final maxTick = Duration(
        milliseconds: (3000 * max(1.0, v.playbackSpeed)).round(),
      );
      if (delta > Duration.zero && delta <= maxTick) {
        _watched += delta;
        _markSegments(_lastPos, pos);
      }
    }
    if (pos > _maxPos) _maxPos = pos;

    // First frame / play / resume.
    if (playing && !_wasPlaying) {
      if (!_playedOnce) {
        _playedOnce = true;
        _timeToPlay = now.difference(_impressionAt ?? now);
        _emit(ChorkiAnalyticsEventType.play, {
          'timeToPlayMs': _timeToPlay!.inMilliseconds,
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
      _emit(ChorkiAnalyticsEventType.firstFrame, {
        'startupMs': now.difference(from).inMilliseconds,
        if (loadStart != null && _loadRunningAt != null)
          'queueWaitMs': _loadRunningAt!.difference(loadStart).inMilliseconds,
        if (_loadRunningAt != null && _loadedAt != null)
          'initMs': _loadedAt!.difference(_loadRunningAt!).inMilliseconds,
        'preloaded': loadStart != null && loadStart.isBefore(activated),
      });
    }

    // Pause (an ad pausing the content is not the viewer pausing).
    final atEnd =
        v.isCompleted ||
        (dur > Duration.zero && pos >= dur - const Duration(milliseconds: 300));
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
      _emit(ChorkiAnalyticsEventType.bufferStart, {'afterSeek': recentSeek});
    } else if (!v.isBuffering && _bufferStartAt != null) {
      final took = now.difference(_bufferStartAt!);
      _rebufferTime += took;
      _bufferStartAt = null;
      _emit(ChorkiAnalyticsEventType.bufferEnd, {
        'durationMs': took.inMilliseconds,
      });
    }

    // Quartiles and completion.
    if (dur > Duration.zero && (playing || _wasPlaying)) {
      final pct = pos.inMilliseconds / dur.inMilliseconds * 100;
      for (final q in const [25, 50, 75]) {
        if (pct >= q && _quartiles.add(q)) {
          _emit(ChorkiAnalyticsEventType.quartile, {'percent': q});
        }
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
        'from': _volume,
        'to': vol,
        'muted': vol == 0,
      });
    }
    _volume = vol;

    _wasPlaying = playing;
    _wasBuffering = v.isBuffering;
    _lastPos = pos;
  }

  static const Duration _oneSecond = Duration(seconds: 1);

  void _onCompleted() {
    _flush('complete');
    if (_quartiles.add(100)) {
      _emit(ChorkiAnalyticsEventType.quartile, {'percent': 100});
    }
    _emit(ChorkiAnalyticsEventType.complete);
  }

  void _onLooped(Duration pos) {
    // The tail between the last tick and the end was played too.
    final dur = _video?.value.duration ?? Duration.zero;
    if (dur > _lastPos) {
      _watched += dur - _lastPos;
      _markSegments(_lastPos, dur);
    }
    _onCompleted();
    _loopCount++;
    _emit(ChorkiAnalyticsEventType.loop, {'loopCount': _loopCount});
    if (_config.newSessionOnLoop) {
      final loops = _loopCount;
      _endSession(ChorkiSessionEndReason.looped);
      _startSession();
      _loopCount = loops;
      _impressionSent = true;
      _impressionAt = _clock();
      _emit(ChorkiAnalyticsEventType.impression, {'loopCount': loops});
      _playedOnce = true;
      _timeToPlay = Duration.zero;
      _emit(ChorkiAnalyticsEventType.play, {
        'timeToPlayMs': 0,
        'loopCount': loops,
      });
      _startHeartbeat();
    } else {
      _quartiles.clear();
      _completed = false;
    }
    // The regular tick step counts 0 → pos.
    _lastPos = Duration.zero;
  }

  void _markSegments(Duration from, Duration to) {
    final len = _config.segmentLength.inMilliseconds;
    final first = from.inMilliseconds ~/ len;
    final last = to.inMilliseconds ~/ len;
    for (var b = first; b <= last; b++) {
      if (_segments.add(b)) _pendingSegments.add(b);
    }
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

  void _flush(String reason) {
    if (!_impressionSent || _id == null) return;
    final len = _config.segmentLength.inSeconds;
    final segments = (_pendingSegments.toList()..sort())
        .map((b) => (b + 1) * len)
        .toList();
    _pendingSegments.clear();
    _emit(ChorkiAnalyticsEventType.heartbeat, {
      'reason': reason,
      'newSegments': segments,
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

  /// The load got its slot in [VideoLoadScheduler] and began initializing.
  void recordLoadRunning() => _loadRunningAt = _clock();

  /// The video initialized.
  void recordLoaded() => _loadedAt = _clock();

  void recordError(
    String message, {
    required String stage,
    required bool willRetry,
  }) {
    if (_active) _errorCount++;
    _emit(ChorkiAnalyticsEventType.error, {
      'message': message,
      'stage': stage,
      'willRetry': willRetry,
    });
  }

  void recordRetry({required int attempt, required bool auto}) {
    _emit(ChorkiAnalyticsEventType.retry, {'attempt': attempt, 'auto': auto});
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
      'fromMs': from.inMilliseconds,
      'toMs': to.inMilliseconds,
      'source': source.name,
    });
    _lastPos = to;
    _completed = false;
  }

  void recordSpeedChange(double from, double to) {
    if (from == to) return;
    _emit(ChorkiAnalyticsEventType.speedChange, {'from': from, 'to': to});
  }

  void recordSpeedBoostStart(double speed) {
    _boostStartAt = _clock();
    _emit(ChorkiAnalyticsEventType.speedBoostStart, {'speed': speed});
  }

  void recordSpeedBoostEnd() {
    final start = _boostStartAt;
    if (start == null) return;
    _boostStartAt = null;
    _emit(ChorkiAnalyticsEventType.speedBoostEnd, {
      'durationMs': _clock().difference(start).inMilliseconds,
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
      'fromHeight': fromHeight,
      'toHeight': toHeight,
      'bitrate': bitrate,
      'label': label,
      'auto': toHeight == null,
    });
  }

  void recordAudioTrackChange(String? from, String to) {
    if (from == to) return;
    _emit(ChorkiAnalyticsEventType.audioTrackChange, {'from': from, 'to': to});
  }

  void recordFitChange(String fit) =>
      _emit(ChorkiAnalyticsEventType.fitChange, {'fit': fit});

  void recordPipChange(String status) =>
      _emit(ChorkiAnalyticsEventType.pipChange, {'status': status});

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
      'breakIndex': _adBreakIndex,
      'breakKind': kind,
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
      'breakIndex': _adBreakIndex,
      'durationMs': start == null
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
    _emit(type, {'breakIndex': _adBreakIndex, ...adContext, ...?data});
  }

  // ----------------------------------------------------------------- output

  void _emit(ChorkiAnalyticsEventType type, [Map<String, Object?>? data]) {
    final id = _id;
    if (id == null || !_active || _disposed || !_config.isActive) return;
    final v = _video?.value;
    final event = ChorkiAnalyticsEvent(
      type: type,
      sessionId: id,
      timestamp: _clock(),
      metadata: _safeMetadata(),
      position: v?.position ?? Duration.zero,
      duration: v?.duration ?? Duration.zero,
      watchedTime: _watched,
      videoSize: v?.size ?? Size.zero,
      timeToPlay: _timeToPlay,
      data: data ?? const {},
    );
    for (final sink in _config.sinks) {
      try {
        sink.onEvent(event);
      } catch (_) {}
    }
  }

  ChorkiMediaMetadata _safeMetadata() {
    try {
      return _metadata();
    } catch (_) {
      return const ChorkiMediaMetadata();
    }
  }

  static final Random _random = Random();
  static const String _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  static String _randomId() =>
      List.generate(12, (_) => _chars[_random.nextInt(_chars.length)]).join();
}
