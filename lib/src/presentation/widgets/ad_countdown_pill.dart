import 'package:flutter/material.dart';

import '../../theme/chorki_player_theme.dart';

class AdCountdownPill extends StatelessWidget {
  const AdCountdownPill({
    super.key,
    required this.seconds,
    required this.onStartNow,
    this.theme = const ChorkiPlayerTheme(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
  });

  final int? seconds;
  final VoidCallback? onStartNow;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerStrings strings;
  final ChorkiPlayerBuilders builders;

  @override
  Widget build(BuildContext context) {
    final s = seconds;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
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
