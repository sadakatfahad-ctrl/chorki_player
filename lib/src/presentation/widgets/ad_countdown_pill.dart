import 'package:flutter/material.dart';

import '../../theme/chorki_player_theme.dart';

/// The "Ad starts in N" pill shown before a mid-roll; tap to start the ad
/// now.
class AdCountdownPill extends StatelessWidget {
  static const Duration _fade = Duration(milliseconds: 200);

  /// A pill for [seconds] (hidden when null).
  const AdCountdownPill({
    super.key,
    required this.seconds,
    required this.onStartNow,
    this.theme = const ChorkiPlayerTheme(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
  });

  /// Seconds until the break; null hides the pill.
  final int? seconds;

  /// Starts the break now.
  final VoidCallback? onStartNow;

  /// Colors and text style.
  final ChorkiPlayerTheme theme;

  /// The countdown text.
  final ChorkiPlayerStrings strings;

  /// May replace the pill.
  final ChorkiPlayerBuilders builders;

  @override
  Widget build(BuildContext context) {
    final s = seconds;
    return AnimatedSwitcher(
      duration: _fade,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: s == null
          ? const SizedBox.shrink(key: Key('chorki_ad_countdown_hidden'))
          : KeyedSubtree(
              key: const Key('chorki_ad_countdown'),
              child: _content(context, s),
            ),
    );
  }

  Widget _content(BuildContext context, int s) {
    void start() => onStartNow?.call();
    final custom = builders.adCountdownBuilder;
    if (custom != null) return custom(context, s, start);

    final text = strings.adCountdown(s);
    return Semantics(
      button: true,
      label: text,
      hint: strings.adStartNowHint,
      child: Material(
        color: theme.adCountdownBackgroundColor,
        shape: StadiumBorder(
          side: BorderSide(color: theme.adCountdownAccentColor, width: 1),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onStartNow == null ? null : start,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.adCountdownAccentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(text, style: theme.adCountdownTextStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
