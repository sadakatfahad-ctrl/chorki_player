import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../ads/chorki_ad_layer.dart';
import '../../controllers/chorki_player_controller.dart';
import '../chorki_player_widget.dart';
import '../widgets/chorki_player_surface.dart';

/// The playing video: the surface with controls, wrapped in the IMA ad layer
/// when the byte has an ad tag and ads are on.
class PlayerVideoView extends StatelessWidget {
  /// Shows [controller] with [player]'s options.
  const PlayerVideoView({
    super.key,
    required this.player,
    required this.controller,
    required this.chorki,
    required this.adTagUrl,
    required this.preloading,
    required this.onTogglePlayPause,
    required this.onAdPlayingChanged,
  });

  /// The options (theme, gestures, ads, ...).
  final ChorkiPlayer player;

  /// The video.
  final VideoPlayerController controller;

  /// The controller the surface and the settings drive.
  final ChorkiPlayerController chorki;

  /// The byte's ad tag; empty for none.
  final String adTagUrl;

  /// Off screen: no controls, no ads.
  final bool preloading;

  /// Tap on the video.
  final VoidCallback onTogglePlayPause;

  /// An ad started or stopped. Called later than [build], so it must check
  /// the player's current state itself, not [preloading] as built.
  final ValueChanged<bool> onAdPlayingChanged;

  @override
  Widget build(BuildContext context) {
    final surface = ChorkiPlayerSurface(
      controller: controller,
      onTogglePlayPause: onTogglePlayPause,
      showControls: !preloading,
      showSeekBar: player.showSeekBar,
      seekBarBottomOffset: player.seekBarBottomOffset,
      enableGestures: player.enableGestures,
      doubleTapSeek: player.doubleTapSeek,
      longPressSpeed: player.longPressSpeed,
      chorkiController: chorki,
      showSettingsButton: player.showSettingsButton,
      speedOptions: player.speedOptions,
      theme: player.theme,
      icons: player.icons,
      strings: player.strings,
      builders: player.builders,
    );
    final ads = player.ads;
    // Ads wait until the byte is on screen: while preloading there is no IMA
    // request, no pre-roll and no load timeout.
    if (preloading || ads == null || !ads.enabled || adTagUrl.isEmpty) {
      return surface;
    }
    return ChorkiAdLayer(
      key: ObjectKey(controller),
      controller: controller,
      adTagUrl: adTagUrl,
      config: ads,
      autoPlay: player.autoPlay,
      onAdPlayingChanged: onAdPlayingChanged,
      child: surface,
    );
  }
}
