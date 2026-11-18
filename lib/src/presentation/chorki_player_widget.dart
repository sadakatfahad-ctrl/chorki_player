import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

import '../ads/chorki_ad_config.dart';
import '../analytics/chorki_analytics_config.dart';
import '../analytics/chorki_analytics_event.dart';
import '../analytics/chorki_analytics_scope.dart';
import '../analytics/chorki_analytics_session.dart';
import '../analytics/chorki_media_metadata.dart';
import '../controllers/chorki_player_controller.dart';
import '../controllers/video_load_scheduler.dart';
import '../controllers/video_preloader.dart';
import '../core/diagnostics.dart';
import '../core/guard.dart';
import '../core/services.dart';
import '../domain/entity/byte_data_entity.dart';
import '../errors/chorki_player_error.dart';
import '../media/chorki_media_options.dart';
import '../network/chorki_network_config.dart';
import '../theme/chorki_player_theme.dart';
import 'bytes_screen/byte_screen_event.dart';
import 'bytes_screen/byte_screen_state.dart';
import 'bytes_screen/bytes_screen_bloc.dart';
import 'player/player_loading_view.dart';
import 'player/player_source.dart';
import 'player/player_video_view.dart';
import 'player/retry_policy.dart';
import 'widgets/chorki_settings_sheet.dart';
import 'widgets/player_error_view.dart';

part 'chorki_player_state.dart';
part 'player/player_analytics_binding.dart';

/// Plays a Chorki byte: resolves [route] (or plays [videoUrl] with
/// [ChorkiPlayer.url]), shows the poster while loading, then the video with
/// the shorts controls, gestures, settings, ads and analytics.
class ChorkiPlayer extends StatefulWidget {
  /// Plays the byte behind [route].
  const ChorkiPlayer({
    super.key,
    required this.route,
    this.autoPlay = true,
    this.preload = false,
    this.looping = true,
    this.showSeekBar = true,
    this.seekBarBottomOffset = 0,
    this.enableGestures = true,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.longPressSpeed = 2.0,
    this.theme = const ChorkiPlayerTheme(),
    this.icons = const ChorkiPlayerIcons(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
    this.initTimeout = const Duration(seconds: 15),
    this.ads,
    this.controller,
    this.mediaOptions = const ChorkiMediaOptions(),
    this.showSettingsButton = true,
    this.speedOptions = defaultChorkiSpeedOptions,
    this.initialFit = ChorkiVideoFit.fit,
    this.sizeToVideo = false,
    this.placeholderAspectRatio = 16 / 9,
    this.metadata,
    this.analytics,
  }) : videoUrl = null,
       posterUrl = '',
       adTagUrl = '',
       assert(seekBarBottomOffset >= 0),
       assert(placeholderAspectRatio > 0);

  /// Plays [videoUrl] directly instead of fetching a Chorki route.
  ///
  /// [videoUrl] is a network URL (MP4, HLS, DASH…) or an `asset:` URI for a
  /// bundled file, e.g. `asset:assets/videos/clip.mp4`. [posterUrl] is shown
  /// while the video loads; [adTagUrl] enables IMA ads when [ads] is set.
  const ChorkiPlayer.url(
    String this.videoUrl, {
    super.key,
    this.posterUrl = '',
    this.adTagUrl = '',
    this.autoPlay = true,
    this.preload = false,
    this.looping = true,
    this.showSeekBar = true,
    this.seekBarBottomOffset = 0,
    this.enableGestures = true,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.longPressSpeed = 2.0,
    this.theme = const ChorkiPlayerTheme(),
    this.icons = const ChorkiPlayerIcons(),
    this.strings = const ChorkiPlayerStrings(),
    this.builders = const ChorkiPlayerBuilders(),
    this.initTimeout = const Duration(seconds: 15),
    this.ads,
    this.controller,
    this.mediaOptions = const ChorkiMediaOptions(),
    this.showSettingsButton = true,
    this.speedOptions = defaultChorkiSpeedOptions,
    this.initialFit = ChorkiVideoFit.fit,
    this.sizeToVideo = false,
    this.placeholderAspectRatio = 16 / 9,
    this.metadata,
    this.analytics,
  }) : route = '',
       assert(seekBarBottomOffset >= 0),
       assert(placeholderAspectRatio > 0);

  /// Chorki API route that resolves to the video. Empty for [ChorkiPlayer.url].
  final String route;

  /// Set by [ChorkiPlayer.url]; null when playing a [route].
  final String? videoUrl;

  /// Poster for [ChorkiPlayer.url].
  final String posterUrl;

  /// IMA ad tag for [ChorkiPlayer.url].
  final String adTagUrl;

  /// Starts playing once loaded (and after a pre-roll). Default true.
  final bool autoPlay;

  /// Loads and buffers the video without playing it, for feeds that build
  /// the next byte ahead of time: `preload: index != current`.
  ///
  /// While preloading, the player shows only the first frame (no controls),
  /// requests no ads, and leaves [controller] unattached, so one controller
  /// can be shared by every page of a feed. Its load waits behind the
  /// visible player's (see [ChorkiVideoLoadScheduler]). A failure while preloading
  /// keeps the poster instead of the error view, and retries when the byte
  /// becomes active. Turning it off attaches
  /// [controller], starts the ads and plays when [autoPlay] is set. Turning
  /// it back on pauses and rewinds to the start
  /// ([ChorkiMediaOptions.startPosition], else 0:00).
  final bool preload;

  /// Restarts at the end. Default true.
  final bool looping;

  /// Shows the shorts seek bar. Default true.
  final bool showSeekBar;

  /// Lifts the seek bar this many pixels above the bottom edge.
  final double seekBarBottomOffset;

  /// Double tap to seek, drag to scrub, long press for speed. Default true.
  final bool enableGestures;

  /// How far a double tap jumps. Default 10 s.
  final Duration doubleTapSeek;

  /// Playback speed while long-pressing. Default 2.0.
  final double longPressSpeed;

  /// Colors and sizes.
  final ChorkiPlayerTheme theme;

  /// Icon overrides.
  final ChorkiPlayerIcons icons;

  /// Text overrides (localization).
  final ChorkiPlayerStrings strings;

  /// Widget builders that replace default UI pieces.
  final ChorkiPlayerBuilders builders;

  /// Longest wait for the video to initialize before it fails as a
  /// `timeout`. Default 15 s.
  final Duration initTimeout;

  /// IMA ad settings; null turns ads off.
  final ChorkiAdConfig? ads;

  /// External handle for quality, audio, speed, fit, PiP and playback. When
  /// null the player owns an internal one. You dispose the one you pass.
  final ChorkiPlayerController? controller;

  /// Headers, start position, buffering and background options. Applied on
  /// the next load (route change or retry).
  final ChorkiMediaOptions mediaOptions;

  /// Gear button that opens [showChorkiSettings].
  final bool showSettingsButton;

  /// Choices in the settings speed menu.
  final List<double> speedOptions;

  /// Initial fit of the internal controller (ignored when [controller] is set).
  final ChorkiVideoFit initialFit;

  /// Sizes the player to the video's aspect ratio instead of filling the
  /// parent, so it can sit in a `Column` or `ListView` without a fixed height.
  /// Needs a bounded width. Under tight constraints the parent still wins.
  final bool sizeToVideo;

  /// Aspect ratio used by [sizeToVideo] until the video is loaded (and on
  /// errors).
  final double placeholderAspectRatio;

  /// What is playing, for analytics: content id, title, series, category…
  /// Without it events only carry the byte id and video URL.
  final ChorkiMediaMetadata? metadata;

  /// Turns on analytics (e.g. Matomo via [MatomoAnalyticsSink]). Falls back
  /// to [ChorkiPlayerController.analytics]. A preloading player reports
  /// nothing until it becomes active.
  final ChorkiAnalyticsConfig? analytics;

  /// Sets the HTTP settings for route and VMAP requests (headers, an auth
  /// token provider, timeouts). Call it once at startup, before the first
  /// player; cached routes are dropped when the settings change.
  static void configure({required ChorkiNetworkConfig network}) =>
      ChorkiServices.configure(network: network);

  @override
  State<ChorkiPlayer> createState() => _ChorkiPlayerState();
}
