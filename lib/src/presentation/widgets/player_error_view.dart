import 'package:flutter/material.dart';

import '../../errors/chorki_player_error.dart';
import '../../theme/chorki_player_theme.dart';
import '../chorki_player_widget.dart';

/// The error view for [error]: [ChorkiPlayerBuilders.errorViewBuilder],
/// else the deprecated `errorBuilder`, else [PlayerErrorView].
Widget buildPlayerError(
  BuildContext context,
  ChorkiPlayerError error, {
  required ChorkiPlayer player,
  required VoidCallback onRetry,
}) {
  final message = error.message(player.strings);
  final builders = player.builders;
  final custom = builders.errorViewBuilder;
  if (custom != null) return custom(context, error, onRetry);
  // ignore: deprecated_member_use_from_same_package
  final legacy = builders.errorBuilder;
  if (legacy != null) return legacy(context, message, onRetry);
  return PlayerErrorView(
    message: message,
    onRetry: onRetry,
    theme: player.theme,
    icons: player.icons,
    strings: player.strings,
  );
}

/// The default error view: the message and a Retry button, shrunk to one
/// line when the player is short.
class PlayerErrorView extends StatelessWidget {
  /// Creates the view.
  const PlayerErrorView({
    super.key,
    required this.message,
    required this.theme,
    required this.icons,
    required this.strings,
    this.onRetry,
  });

  /// The localized message.
  final String message;

  /// Retry action; null hides the button.
  final VoidCallback? onRetry;

  /// Colors and styles.
  final ChorkiPlayerTheme theme;

  /// The retry icon.
  final ChorkiPlayerIcons icons;

  /// The retry label.
  final ChorkiPlayerStrings strings;

  /// Below this height the stacked message + button can't fit, e.g. a very
  /// wide video with `ChorkiPlayer.sizeToVideo`.
  static const double _compactBelowHeight = 160;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxHeight < _compactBelowHeight ? _compact() : _full(),
    );
  }

  /// One line, scaled down to whatever space there is.
  Widget _compact() {
    final retry = onRetry;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, maxLines: 1, style: theme.errorTextStyle),
              if (retry != null)
                IconButton(
                  onPressed: retry,
                  tooltip: strings.retry,
                  icon: Icon(icons.refresh, color: theme.iconColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _full() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.errorTextStyle,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                style: theme.retryButtonStyle,
                icon: Icon(icons.refresh, color: theme.iconColor),
                label: Text(
                  strings.retry,
                  style: TextStyle(color: theme.iconColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
