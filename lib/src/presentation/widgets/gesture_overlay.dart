import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../helpers/time_format.dart';
import '../../theme/chorki_player_theme.dart';

class PlayerGestureOverlay extends StatefulWidget {
  const PlayerGestureOverlay({
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

  final VideoPlayerController controller;
  final VoidCallback onTogglePlayPause;

  final Duration doubleTapSeek;

  final Duration doubleTapWindow;

  final double longPressSpeed;

  final double fullScreenDragSeconds;

  final Duration hapticTickInterval;

  final Duration seekThrottle;

  final ValueChanged<bool>? onGesturesActiveChanged;

  final ChorkiPlayerTheme theme;

  final ChorkiPlayerIcons icons;

  final ChorkiPlayerStrings strings;

  final ChorkiPlayerBuilders builders;

  @override
  State<PlayerGestureOverlay> createState() => _PlayerGestureOverlayState();
}

enum _DragDirection { backward, forward }

class _PlayerGestureOverlayState extends State<PlayerGestureOverlay>
    with SingleTickerProviderStateMixin {
  bool _doubleTapForward = false;
  int _doubleTapFeedbackId = 0;
  Duration? _pendingDoubleTapTarget;
  Timer? _doubleTapTargetReset;

  bool _scrubbing = false;
  _DragDirection _scrubDirection = _DragDirection.forward;
  Duration _scrubBase = Duration.zero;
  Duration _scrubTarget = Duration.zero;
  double _scrubStartDx = 0;
  double _pointerDownDx = 0;
  double _scrubWidth = 1;
  bool _resumeOnScrubEnd = false;
  int _lastHapticTick = 0;
  Timer? _scrubThrottle;

  bool _speedHoldActive = false;
  double _speedBeforeHold = 1.0;
  bool _disposed = false;

  VideoPlayerController get _controller => widget.controller;

  bool get _canControl => _controller.value.isInitialized;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerValue);
  }

  @override
  void didUpdateWidget(covariant PlayerGestureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerValue);
      _resetGestureState();
      widget.controller.addListener(_onControllerValue);
      _notifyGesturesActive(false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.removeListener(_onControllerValue);
    _resetGestureState();
    if (_resumeOnScrubEnd) {
      _resumeOnScrubEnd = false;
      _safe(() => _controller.play());
    }
    if (_speedHoldActive) {
      _speedHoldActive = false;
      _safe(() => _controller.setPlaybackSpeed(_speedBeforeHold));
    }
    super.dispose();
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
    HapticFeedback.selectionClick();

    final value = _controller.value;
    final base = _pendingDoubleTapTarget ?? value.position;
    var target = _doubleTapForward
        ? base + widget.doubleTapSeek
        : base - widget.doubleTapSeek;
    if (target < Duration.zero) target = Duration.zero;
    if (target > value.duration) target = value.duration;

    _pendingDoubleTapTarget = target;
    _doubleTapTargetReset?.cancel();
    _doubleTapTargetReset = Timer(widget.doubleTapWindow, () {
      _pendingDoubleTapTarget = null;
    });

    unawaited(_seekClamped(target));
    setState(() => _doubleTapFeedbackId++);
  }

  // ------------------------------------------------------- horizontal scrub

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canControl) return;
    final value = _controller.value;
    HapticFeedback.lightImpact();

    _scrubStartDx = _pointerDownDx;
    _scrubBase = value.position;
    _scrubTarget = value.position;
    _scrubDirection = _DragDirection.forward;
    _resumeOnScrubEnd = value.isPlaying;
    _lastHapticTick = _tickIndex(_scrubTarget);

    if (value.isPlaying) {
      _safe(() => _controller.pause());
    }

    setState(() => _scrubbing = true);
    _notifyGesturesActive(true);

    _scrubThrottle?.cancel();
    _scrubThrottle = Timer.periodic(widget.seekThrottle, (_) {
      if (_scrubbing) unawaited(_seekClamped(_scrubTarget));
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_scrubbing) return;

    final pixelsPerSecond = _scrubWidth / widget.fullScreenDragSeconds;
    final deltaSeconds =
        (details.localPosition.dx - _scrubStartDx) / pixelsPerSecond;
    final delta = Duration(
      microseconds: (deltaSeconds * Duration.microsecondsPerSecond).round(),
    );
    final target = _scrubBase + delta;

    final clamped = _clampToDuration(target);
    setState(() {
      _scrubTarget = clamped;
      _scrubDirection = delta.isNegative
          ? _DragDirection.backward
          : _DragDirection.forward;
    });

    final tick = _tickIndex(clamped);
    if (tick != _lastHapticTick) {
      _lastHapticTick = tick;
      HapticFeedback.selectionClick();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) => _finishScrub();

  void _onHorizontalDragCancel() => _finishScrub();

  void _finishScrub() {
    if (!_scrubbing) return;
    _scrubThrottle?.cancel();
    _scrubThrottle = null;
    HapticFeedback.lightImpact();

    unawaited(_seekClamped(_scrubTarget));
    if (_resumeOnScrubEnd) {
      _resumeOnScrubEnd = false;
      _safe(() => _controller.play());
    }
    setState(() => _scrubbing = false);
    _notifyGesturesActive(false);
  }

  void _resetGestureState() {
    _doubleTapTargetReset?.cancel();
    _pendingDoubleTapTarget = null;
    _scrubThrottle?.cancel();
    _scrubThrottle = null;
    _scrubbing = false;
    _resumeOnScrubEnd = false;
    _speedHoldActive = false;
  }

  // ------------------------------------------------------- long-press speed

  void _onLongPressStart(LongPressStartDetails details) {
    if (!_canControl) return;
    HapticFeedback.mediumImpact();
    _speedBeforeHold = _controller.value.playbackSpeed;
    _safe(() => _controller.setPlaybackSpeed(widget.longPressSpeed));
    setState(() => _speedHoldActive = true);
    _notifyGesturesActive(true);
  }

  void _onLongPressEnd(LongPressEndDetails details) => _cancelSpeedHold();

  void _onLongPressCancel() => _cancelSpeedHold();

  void _cancelSpeedHold() {
    if (!_speedHoldActive) return;
    _safe(() => _controller.setPlaybackSpeed(_speedBeforeHold));
    _speedHoldActive = false;
    if (mounted) setState(() {});
    _notifyGesturesActive(false);
  }

  void _safe(Future<void> Function() action) {
    action().catchError((Object _) {});
  }

  // ---------------------------------------------------------------- helpers

  Duration _clampToDuration(Duration target) {
    final duration = _controller.value.duration;
    if (target < Duration.zero) return Duration.zero;
    if (target > duration) return duration;
    return target;
  }

  Future<void> _seekClamped(Duration target) async {
    if (!_canControl) return;
    try {
      await _controller.seekTo(_clampToDuration(target));
    } catch (_) {}
  }

  int _tickIndex(Duration position) {
    final interval = widget.hapticTickInterval.inMilliseconds;
    if (interval <= 0) return 0;
    return position.inMilliseconds ~/ interval;
  }

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
                          : _DoubleTapFeedback(
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
                    child: _ScrubHud(
                      direction: _scrubDirection,
                      delta: _scrubTarget - _scrubBase,
                      target: _scrubTarget,
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
                        : _SpeedBadge(
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

class _DoubleTapFeedback extends StatefulWidget {
  const _DoubleTapFeedback({
    super.key,
    required this.forward,
    required this.label,
    required this.theme,
    required this.icons,
  });

  final bool forward;
  final String label;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;

  @override
  State<_DoubleTapFeedback> createState() => _DoubleTapFeedbackState();
}

class _DoubleTapFeedbackState extends State<_DoubleTapFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final double opacity;
        if (t < 0.15) {
          opacity = t / 0.15;
        } else if (t > 0.75) {
          opacity = ((1.0 - t) / 0.25).clamp(0.0, 1.0);
        } else {
          opacity = 1;
        }
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: 0.85 + 0.15 * Curves.easeOut.transform(opacity),
            child: child,
          ),
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.theme.gestureOverlayColor,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.forward
                    ? widget.icons.fastForward
                    : widget.icons.fastRewind,
                color: widget.theme.gestureIconColor,
                size: 30,
              ),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: widget.theme.gestureTextStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrubHud extends StatelessWidget {
  const _ScrubHud({
    required this.direction,
    required this.delta,
    required this.target,
    required this.theme,
    required this.icons,
  });

  final _DragDirection direction;
  final Duration delta;
  final Duration target;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;

  @override
  Widget build(BuildContext context) {
    final forward = direction == _DragDirection.forward;
    final secondaryColor = theme.gestureIconColor.withValues(alpha: 0.7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: theme.gestureOverlayColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatClock(target),
            style: theme.gestureTextStyle.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                forward ? icons.fastForward : icons.fastRewind,
                color: secondaryColor,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                formatDelta(delta),
                style: theme.gestureTextStyle.copyWith(
                  color: secondaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({
    required this.speed,
    required this.theme,
    required this.icons,
    required this.strings,
  });

  final double speed;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;
  final ChorkiPlayerStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.gestureOverlayColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icons.fastForward, color: theme.gestureIconColor, size: 18),
          const SizedBox(width: 6),
          Text(
            '${speed == speed.roundToDouble() ? speed.toInt() : speed}× '
            '${strings.speed}',
            style: theme.gestureTextStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
