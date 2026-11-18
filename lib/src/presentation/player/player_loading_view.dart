import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../controllers/chorki_player_controller.dart';
import '../../theme/chorki_player_theme.dart';

/// The poster (when [posterUrl] is set) under a spinner, while the route or
/// the video loads, or a silent retry is pending.
class PlayerLoadingView extends StatelessWidget {
  /// Creates the view.
  const PlayerLoadingView({
    super.key,
    required this.theme,
    required this.fit,
    this.posterUrl,
  });

  /// Spinner size and colors.
  final ChorkiPlayerTheme theme;

  /// The video fit, so the poster-to-video handoff is seamless.
  final ValueListenable<ChorkiVideoFit> fit;

  /// Poster image; none when null or empty.
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final poster = posterUrl;
    // StackFit.expand: otherwise the Stack shrinks to the spinner under loose
    // constraints and the poster renders tiny.
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (poster != null && poster.isNotEmpty)
          Positioned.fill(
            child: ValueListenableBuilder<ChorkiVideoFit>(
              valueListenable: fit,
              builder: (context, fit, _) => Image.network(
                poster,
                fit: fit == ChorkiVideoFit.fill ? BoxFit.cover : BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        Center(
          child: SizedBox(
            width: theme.spinnerSize,
            height: theme.spinnerSize,
            child: CircularProgressIndicator(
              color: theme.spinnerColor,
              strokeWidth: theme.spinnerStrokeWidth,
            ),
          ),
        ),
      ],
    );
  }
}
