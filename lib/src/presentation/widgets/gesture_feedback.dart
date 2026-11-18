import 'package:flutter/material.dart';

import '../../helpers/time_format.dart';
import '../../theme/chorki_player_theme.dart';

/// The double-tap seek bubble: an arrow and how far it jumped. Fades in,
/// holds, fades out.
class GestureSeekFeedback extends StatefulWidget {
  const GestureSeekFeedback({
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
  State<GestureSeekFeedback> createState() => _GestureSeekFeedbackState();
}

class _GestureSeekFeedbackState extends State<GestureSeekFeedback>
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

/// The horizontal-scrub HUD: target time and the jump from where it began.
class GestureScrubHud extends StatelessWidget {
  const GestureScrubHud({
    super.key,
    required this.forward,
    required this.delta,
    required this.target,
    required this.theme,
    required this.icons,
  });

  final bool forward;
  final Duration delta;
  final Duration target;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;

  @override
  Widget build(BuildContext context) {
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

/// The long-press speed badge, e.g. `2× Speed`.
class GestureSpeedBadge extends StatelessWidget {
  const GestureSpeedBadge({
    super.key,
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
            '${formatSpeed(speed)}× ${strings.speed}',
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
