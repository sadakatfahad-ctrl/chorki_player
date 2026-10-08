import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../ads/chorki_ad_state.dart';
import '../../theme/chorki_player_theme.dart';
import 'ad_countdown_pill.dart';
import 'gesture_overlay.dart';
import 'shorts_seek_bar.dart';

class ChorkiPlayerSurface extends StatefulWidget {
  const ChorkiPlayerSurface({
    super.key,
    required this.controller,
    required this.onTogglePlayPause,
    this.showSeekBar = true,
    this.seekBarBottomOffset = 0,
    this.enableGestures = true,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.longPressSpeed = 2.0,
    this.overlayButton,
    this.theme = const ChorkiPlayerTheme(),
    this.icons = const ChorkiPlayerIcons(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
  }) : assert(seekBarBottomOffset >= 0);

  final VideoPlayerController controller;
  final VoidCallback onTogglePlayPause;

  final bool showSeekBar;

  final double seekBarBottomOffset;

  final bool enableGestures;

  final Duration doubleTapSeek;

  final double longPressSpeed;

  final Widget? overlayButton;

  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;
  final ChorkiPlayerStrings strings;
  final ChorkiPlayerBuilders builders;

  @override
  State<ChorkiPlayerSurface> createState() => _ChorkiPlayerSurfaceState();
}

class _ChorkiPlayerSurfaceState extends State<ChorkiPlayerSurface> {
  bool _gesturesActive = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Video, letterboxed by intrinsic aspect ratio.
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
        ),

        Positioned.fill(
          child: widget.enableGestures
              ? PlayerGestureOverlay(
                  controller: controller,
                  onTogglePlayPause: widget.onTogglePlayPause,
                  doubleTapSeek: widget.doubleTapSeek,
                  longPressSpeed: widget.longPressSpeed,
                  theme: widget.theme,
                  icons: widget.icons,
                  strings: widget.strings,
                  builders: widget.builders,
                  onGesturesActiveChanged: _onGesturesActiveChanged,
                )
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onTogglePlayPause,
                ),
        ),

        Positioned.fill(
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (!value.isInitialized) return const SizedBox.shrink();
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (value.isBuffering)
                    SizedBox(
                      width: widget.theme.spinnerSize,
                      height: widget.theme.spinnerSize,
                      child: CircularProgressIndicator(
                        strokeWidth: widget.theme.spinnerStrokeWidth,
                        color: widget.theme.spinnerColor,
                      ),
                    ),
                  if (!value.isPlaying && !_gesturesActive)
                    widget.builders.playPauseBuilder?.call(
                          context,
                          controller,
                        ) ??
                        _PlayBadge(theme: widget.theme, icons: widget.icons),
                ],
              );
            },
          ),
        ),

        if (widget.showSeekBar)
          Positioned(
            left: 0,
            right: 0,
            bottom: widget.seekBarBottomOffset,
            child: ShortsSeekBar(
              controller: controller,
              theme: widget.theme,
              builders: widget.builders,
            ),
          ),

        if (ChorkiAdScope.maybeOf(context) case final ad?)
          Positioned(
            left: 12,
            bottom:
                widget.seekBarBottomOffset +
                (widget.showSeekBar ? widget.theme.seekBarHeight : 0) +
                8,
            child: AdCountdownPill(
              key: const Key('chorki_ad_countdown_pill'),
              seconds: ad.countdownSeconds,
              onStartNow: ad.startNow,
              theme: widget.theme,
              strings: widget.strings,
              builders: widget.builders,
            ),
          ),

        if (widget.overlayButton != null)
          Positioned(
            right: 2,
            bottom: widget.seekBarBottomOffset + (widget.showSeekBar ? 46 : 8),
            child: widget.overlayButton!,
          ),
      ],
    );
  }

  void _onGesturesActiveChanged(bool active) {
    if (_gesturesActive == active) return;
    setState(() => _gesturesActive = active);
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.theme, required this.icons});

  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.playBadgeColor,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          icons.play,
          size: theme.playBadgeIconSize,
          color: theme.playBadgeIconColor,
        ),
      ),
    );
  }
}
