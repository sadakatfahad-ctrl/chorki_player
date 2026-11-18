import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../analytics/chorki_analytics_event.dart';
import '../../analytics/chorki_analytics_scope.dart';
import '../../analytics/chorki_analytics_session.dart';
import '../../core/guard.dart';
import '../../helpers/time_format.dart';
import '../../theme/chorki_player_theme.dart';
import 'gesture_feedback.dart';
import 'scrub_session.dart';

/// The shorts gestures over a video: tap to play/pause, double-tap a side
/// to seek, drag horizontally to scrub, long-press for a speed boost. Each
/// reports to the analytics session in scope.
class ChorkiGestureOverlay extends StatefulWidget {
  /// Gestures over [controller].
  const ChorkiGestureOverlay({
    super.key,
    required this.controller,
    required this.onTogglePlayPause,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.doubleTapWindow = const Duration(milliseconds: 800),
    this.longPressSpeed = 2.0,
    this.fullScreenDragSeconds = 90,
    this.hapticTickInterval = const Duration(seconds: 5),
    this.seekThrottle = const Duration(milliseconds: 150),
    this.onGesturesActiveChanged,
    this.theme = const ChorkiPlayerTheme(),
    this.icons = const ChorkiPlayerIcons(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
  });

  /// The video the gestures control.
  final VideoPlayerController controller;

  /// A single tap.
  final VoidCallback onTogglePlayPause;

  /// How far a double tap jumps.
  final Duration doubleTapSeek;

  /// Taps within this window add up (three double taps jump three times).
  final Duration doubleTapWindow;

  /// Playback speed while long-pressing.
  final double longPressSpeed;

  /// Seconds a drag across the full width moves.
  final double fullScreenDragSeconds;

  /// A haptic tick each time a scrub crosses a multiple of this.
  final Duration hapticTickInterval;

  /// How often the video follows a scrub.
  final Duration seekThrottle;

  /// A scrub or speed hold started (true) or ended (false), e.g. to hide
  /// other controls meanwhile.
  final ValueChanged<bool>? onGesturesActiveChanged;

  /// Colors and text styles of the feedback.
  final ChorkiPlayerTheme theme;

  /// Feedback icons.
  final ChorkiPlayerIcons icons;

  /// Feedback labels.
  final ChorkiPlayerStrings strings;

  /// May replace the gesture feedback.
  final ChorkiPlayerBuilders builders;

  @override
  State<ChorkiGestureOverlay> createState() => _ChorkiGestureOverlayState();
}

class _ChorkiGestureOverlayState extends State<ChorkiGestureOverlay>
    with SingleTickerProviderStateMixin {
  bool _doubleTapForward = false;
  int _doubleTapFeedbackId = 0;
  Duration? _pendingDoubleTapTarget;
  Timer? _doubleTapTargetReset;

  late final ScrubSession _scrub = ScrubSession(
    controller: () => widget.controller,
    analytics: () => _analytics,
    source: ChorkiSeekSource.scrub,
    context: 'gestures',
    tickInterval: widget.hapticTickInterval,
    throttle: widget.seekThrottle,
  );
  bool get _scrubbing => _scrub.active;
  bool _scrubForward = true;
  double _scrubStartDx = 0;
  double _pointerDownDx = 0;
  double _scrubWidth = 1;

  bool _speedHoldActive = false;
  double _speedBeforeHold = 1.0;
  bool _disposed = false;

  VideoPlayerController get _controller => widget.controller;

  ChorkiAnalyticsSession? get _analytics =>
      mounted ? ChorkiAnalyticsScope.maybeOf(context) : null;

  bool get _canControl => _controller.value.isInitialized;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerValue);
  }

  @override
  void didUpdateWidget(covariant ChorkiGestureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerValue);
      _restoreSpeed(oldWidget.controller);
      _resetGestureState();
      widget.controller.addListener(_onControllerValue);
      _notifyGesturesActive(false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onControllerValue);
    // Must run before the reset, which clears the hold flag.
    _restoreSpeed(_controller);
    _resetGestureState();
    super.dispose();
  }

  /// Undoes a long-press speed hold when the overlay goes away mid-press (ad
  /// break, controller swap). A scrub's pause is deliberately not undone: the
  /// ad layer pauses content right before removing the overlay, and a swapped
  /// controller is off screen.
  void _restoreSpeed(VideoPlayerController controller) {
    if (_speedHoldActive) {
      _safe(() => controller.setPlaybackSpeed(_speedBeforeHold));
    }
  }

  void _onControllerValue() {
    if (!_controller.value.isInitialized && _scrubbing) {
      _resetGestureState();
      setState(() {});
      _notifyGesturesActive(false);
    }
  }

  void _notifyGesturesActive(bool active) {
    if (widget.onGesturesActiveChanged == null || _disposed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      widget.onGesturesActiveChanged?.call(active);
    });
  }

  // ------------------------------------------------------------- double tap

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapForward = details.localPosition.dx >= _scrubWidth / 2;
  }

  void _onDoubleTap() {
    if (!_canControl) return;
    unawaited(HapticFeedback.selectionClick());

    final value = _controller.value;
    final base = _pendingDoubleTapTarget ?? value.position;
    var target = _doubleTapForward
        ? base + widget.doubleTapSeek
        : base - widget.doubleTapSeek;
    target = _scrub.clamp(target);

    _analytics?.recordSeek(base, target, ChorkiSeekSource.doubleTap);
    _pendingDoubleTapTarget = target;
    _doubleTapTargetReset?.cancel();
    _doubleTapTargetReset = Timer(widget.doubleTapWindow, () {
      _pendingDoubleTapTarget = null;
    });

    unawaited(_scrub.seek(target));
    setState(() => _doubleTapFeedbackId++);
  }

  // ------------------------------------------------------- horizontal scrub

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canControl) return;
    _scrubStartDx = _pointerDownDx;
    _scrubForward = true;
    _scrub.begin(_controller.value.position);
    setState(() {});
    _notifyGesturesActive(true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_scrubbing) return;
    final pixelsPerSecond = _scrubWidth / widget.fullScreenDragSeconds;
    final deltaSeconds =
        (details.localPosition.dx - _scrubStartDx) / pixelsPerSecond;
    final delta = Duration(
      microseconds: (deltaSeconds * Duration.microsecondsPerSecond).round(),
    );
    setState(() {
      _scrub.update(_scrub.start + delta);
      _scrubForward = !delta.isNegative;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) => _finishScrub();

  void _onHorizontalDragCancel() => _finishScrub();

  void _finishScrub() {
    if (_scrub.finish() == null) return;
    setState(() {});
    _notifyGesturesActive(false);
  }

  void _resetGestureState() {
    _doubleTapTargetReset?.cancel();
    _pendingDoubleTapTarget = null;
    _scrub.abandon();
    _speedHoldActive = false;
  }

  // ------------------------------------------------------- long-press speed

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_canControl) return;
    unawaited(HapticFeedback.mediumImpact());
    _speedBeforeHold = _controller.value.playbackSpeed;
    _safe(() => _controller.setPlaybackSpeed(widget.longPressSpeed));
    _analytics?.recordSpeedBoostStart(widget.longPressSpeed);
    setState(() => _speedHoldActive = true);
    _notifyGesturesActive(true);
  }

  void _onLongPressEnd(LongPressEndDetails details) => _cancelSpeedHold();

  void _onLongPressCancel() => _cancelSpeedHold();

  void _cancelSpeedHold() {
    if (!_speedHoldActive) return;
    _safe(() => _controller.setPlaybackSpeed(_speedBeforeHold));
    _speedHoldActive = false;
    if (mounted) {
      _analytics?.recordSpeedBoostEnd();
      setState(() {});
    }
    _notifyGesturesActive(false);
  }

  void _safe(Future<void> Function() action) =>
      fireAndReport(action, 'gestures');

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final feedbackBuilder = widget.builders.gestureFeedbackBuilder;
    final seekSeconds = widget.doubleTapSeek.inSeconds;

    return LayoutBuilder(
      builder: (context, constraints) {
        _scrubWidth = constraints.maxWidth;
        return Listener(
          onPointerDown: (event) => _pointerDownDx = event.localPosition.dx,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTogglePlayPause,
            onDoubleTapDown: _onDoubleTapDown,
            onDoubleTap: _onDoubleTap,
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onLongPressCancel: _onLongPressCancel,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            onHorizontalDragCancel: _onHorizontalDragCancel,
            child: Stack(
              children: [
                if (_doubleTapFeedbackId > 0)
                  Align(
                    alignment: _doubleTapForward
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: feedbackBuilder != null
                          ? KeyedSubtree(
                              key: ValueKey(_doubleTapFeedbackId),
                              child: feedbackBuilder(
                                context,
                                ChorkiGestureFeedback(
                                  kind: _doubleTapForward
                                      ? ChorkiGestureKind.seekForward
                                      : ChorkiGestureKind.seekBackward,
                                  label: formatDelta(
                                    Duration(
                                      seconds: _doubleTapForward
                                          ? seekSeconds
                                          : -seekSeconds,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : GestureSeekFeedback(
                              key: ValueKey(_doubleTapFeedbackId),
                              forward: _doubleTapForward,
                              label: '$seekSeconds ${widget.strings.seconds}',
                              theme: widget.theme,
                              icons: widget.icons,
                            ),
                    ),
                  ),

                // Scrub HUD.
                if (_scrubbing)
                  Center(
                    child: GestureScrubHud(
                      forward: _scrubForward,
                      delta: _scrub.target - _scrub.start,
                      target: _scrub.target,
                      theme: widget.theme,
                      icons: widget.icons,
                    ),
                  ),

                if (_speedHoldActive)
                  Center(
                    child: feedbackBuilder != null
                        ? feedbackBuilder(
                            context,
                            ChorkiGestureFeedback(
                              kind: ChorkiGestureKind.speed,
                              label:
                                  '${widget.longPressSpeed.toStringAsFixed(1)}x',
                            ),
                          )
                        : GestureSpeedBadge(
                            speed: widget.longPressSpeed,
                            theme: widget.theme,
                            icons: widget.icons,
                            strings: widget.strings,
                          ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
