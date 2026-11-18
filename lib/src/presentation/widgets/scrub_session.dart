import 'dart:async';

import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../analytics/chorki_analytics_event.dart';
import '../../analytics/chorki_analytics_session.dart';
import '../../core/diagnostics.dart';
import '../../core/guard.dart';

/// One drag-to-seek gesture, shared by the gesture overlay's horizontal
/// scrub and the seek bar's drag.
///
/// [begin] pauses a playing video and starts seeking to [target] every
/// [throttle]; [update] moves the target (with a haptic tick every
/// [tickInterval]); [finish] seeks to the final target, reports a seek (or a
/// cancelled scrub when it ends where it began) and resumes playback.
/// [abandon] stops without seeking or resuming, for a controller swap or a
/// disposal mid-drag.
class ScrubSession {
  /// A scrub of [controller], reported to [analytics] as [source].
  ScrubSession({
    required this.controller,
    required this.analytics,
    required this.source,
    required this.context,
    required this.tickInterval,
    required this.throttle,
    this.skipSeekToCurrent = false,
  });

  /// The video, read at each call (a widget's controller can change).
  final VideoPlayerController Function() controller;

  /// The analytics session in scope, if any.
  final ChorkiAnalyticsSession? Function() analytics;

  /// How the seek is reported.
  final ChorkiSeekSource source;

  /// Diagnostics context, e.g. `gestures` or `seekBar`.
  final String context;

  /// A haptic tick each time the target crosses a multiple of this.
  final Duration tickInterval;

  /// How often the video follows the target during the drag.
  final Duration throttle;

  /// [seek] does nothing when the video is already at the target. The
  /// overlay seeks anyway (a double tap at 0:00 still re-seeks to 0:00).
  final bool skipSeekToCurrent;

  bool _active = false;
  bool _resume = false;
  int _lastTick = 0;
  Timer? _timer;

  /// A drag is in progress.
  bool get active => _active;

  /// The position when the drag began.
  Duration get start => _start;
  Duration _start = Duration.zero;

  /// Where the drag currently points, within the video.
  Duration get target => _target;
  Duration _target = Duration.zero;

  /// Starts a drag pointing at [initialTarget].
  void begin(Duration initialTarget) {
    final value = controller().value;
    unawaited(HapticFeedback.lightImpact());
    _active = true;
    _start = value.position;
    _target = clamp(initialTarget);
    _resume = value.isPlaying;
    _lastTick = _tick(_target);
    analytics()?.recordScrubStart();
    if (value.isPlaying) fireAndReport(controller().pause, context);
    _timer?.cancel();
    _timer = Timer.periodic(throttle, (_) {
      if (_active) unawaited(seek(_target));
    });
  }

  /// Moves the target; returns the clamped one.
  Duration update(Duration target) {
    _target = clamp(target);
    final tick = _tick(_target);
    if (tick != _lastTick) {
      _lastTick = tick;
      unawaited(HapticFeedback.selectionClick());
    }
    return _target;
  }

  /// Ends the drag: seeks, reports and resumes. Returns the final target, or
  /// null when no drag was active.
  Duration? finish() {
    if (!_active) return null;
    _timer?.cancel();
    _timer = null;
    unawaited(HapticFeedback.lightImpact());
    final target = _target;
    final session = analytics();
    if (target == _start) {
      session?.recordScrubCancel();
    } else {
      session?.recordSeek(_start, target, source);
    }
    unawaited(seek(target));
    _active = false;
    if (_resume) {
      _resume = false;
      fireAndReport(controller().play, context);
    }
    return target;
  }

  /// Stops without seeking or resuming. [reportCancel] reports a cancelled
  /// scrub if one was active.
  void abandon({bool reportCancel = false}) {
    _timer?.cancel();
    _timer = null;
    if (_active && reportCancel) analytics()?.recordScrubCancel();
    _active = false;
    _resume = false;
  }

  /// [target] within 0 and the video's duration.
  Duration clamp(Duration target) {
    final duration = controller().value.duration;
    if (target < Duration.zero) return Duration.zero;
    if (target > duration) return duration;
    return target;
  }

  /// Seeks to [target] (clamped), unless [skipSeekToCurrent] and the video is
  /// already there.
  Future<void> seek(Duration target) async {
    final c = controller();
    final value = c.value;
    if (!value.isInitialized) return;
    final clamped = clamp(target);
    if (skipSeekToCurrent && value.position == clamped) return;
    try {
      await c.seekTo(clamped);
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, '$context.seek');
    }
  }

  int _tick(Duration position) {
    final interval = tickInterval.inMilliseconds;
    if (interval <= 0) return 0;
    return position.inMilliseconds ~/ interval;
  }
}
