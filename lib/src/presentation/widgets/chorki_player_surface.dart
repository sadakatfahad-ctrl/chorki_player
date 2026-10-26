import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../ads/chorki_ad_state.dart';
import '../../controllers/chorki_player_controller.dart';
import '../../pip/chorki_pip.dart';
import '../../theme/chorki_player_theme.dart';
import 'ad_countdown_pill.dart';
import 'chorki_settings_sheet.dart';
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
    this.chorkiController,
    this.showSettingsButton = true,
    this.speedOptions = defaultChorkiSpeedOptions,
    this.fit = ChorkiVideoFit.fit,
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

  /// Drives fit, PiP-aware rendering and the settings button. When null the
  /// surface uses [fit] and shows no settings button.
  final ChorkiPlayerController? chorkiController;

  /// Shows the gear button (top-right) when [chorkiController] is set.
  final bool showSettingsButton;

  final List<double> speedOptions;

  /// Used when [chorkiController] is null.
  final ChorkiVideoFit fit;

  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;
  final ChorkiPlayerStrings strings;
  final ChorkiPlayerBuilders builders;

  @override
  State<ChorkiPlayerSurface> createState() => _ChorkiPlayerSurfaceState();
}

class _ChorkiPlayerSurfaceState extends State<ChorkiPlayerSurface> {
  bool _gesturesActive = false;

  // The size is only known once the controller is initialized, which may
  // happen after the surface is built (feeds pass controllers early).
  late Size _videoSize = widget.controller.value.size;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVideoValue);
  }

  @override
  void didUpdateWidget(covariant ChorkiPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onVideoValue);
      widget.controller.addListener(_onVideoValue);
      _videoSize = widget.controller.value.size;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVideoValue);
    super.dispose();
  }

  void _onVideoValue() {
    final size = widget.controller.value.size;
    if (size != _videoSize && mounted) setState(() => _videoSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final chorki = widget.chorkiController;
    if (chorki == null) return _build(context, widget.fit, inPip: false);
    return ListenableBuilder(
      listenable: Listenable.merge([chorki.fit, chorki.pipStatus]),
      builder: (context, _) => _build(
        context,
        chorki.fit.value,
        inPip: chorki.pipStatus.value == ChorkiPipStatus.enabled,
      ),
    );
  }

  Widget _build(
    BuildContext context,
    ChorkiVideoFit fit, {
    required bool inPip,
  }) {
    final controller = widget.controller;
    final video = Positioned.fill(
      child: ClipRect(
        child: FittedBox(
          key: const Key('chorki_video_fit'),
          fit: fit == ChorkiVideoFit.fill ? BoxFit.cover : BoxFit.contain,
          child: SizedBox(
            width: _videoSize.width,
            height: _videoSize.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );

    // PiP window: video only. The controls stay mounted offstage rather than
    // being removed, so a scrub or long-press in progress still finishes and
    // resumes playback / restores the speed.
    return Stack(
      alignment: Alignment.center,
      children: [
        video,
        Positioned.fill(
          child: Offstage(
            offstage: inPip,
            child: _controls(context, controller),
          ),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context, VideoPlayerController controller) {
    return Stack(
      alignment: Alignment.center,
      children: [
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

        if (widget.chorkiController != null && widget.showSettingsButton)
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(child: _settingsButton(context)),
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

  void _openSettings() {
    final chorki = widget.chorkiController;
    if (chorki == null) return;
    showChorkiSettings(
      context,
      chorki,
      theme: widget.theme,
      icons: widget.icons,
      strings: widget.strings,
      builders: widget.builders,
      speedOptions: widget.speedOptions,
    );
  }

  Widget _settingsButton(BuildContext context) {
    final custom = widget.builders.settingsButtonBuilder;
    if (custom != null) return custom(context, _openSettings);
    return Material(
      color: widget.theme.settingsButtonBackgroundColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        key: const Key('chorki_settings_button'),
        tooltip: widget.strings.settings,
        icon: Icon(
          widget.icons.settings,
          color: widget.theme.settingsButtonColor,
        ),
        onPressed: _openSettings,
      ),
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
    // The badge is stacked above the gesture layer; without IgnorePointer its
    // circular decoration swallows taps and the video can't be resumed from it.
    return IgnorePointer(
      child: DecoratedBox(
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
      ),
    );
  }
}
