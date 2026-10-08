import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

@immutable
class ChorkiPlayerTheme {
  const ChorkiPlayerTheme({
    this.backgroundColor = Colors.black,
    this.spinnerColor = Colors.white,
    this.spinnerSize = 28,
    this.spinnerStrokeWidth = 2.5,
    this.iconColor = Colors.white,
    this.errorTextStyle = const TextStyle(color: Colors.white70),
    this.retryButtonStyle,
    this.playBadgeColor = Colors.black45,
    this.playBadgeIconColor = Colors.white,
    this.playBadgeIconSize = 56,
    this.seekBarPlayedColor = Colors.white,
    this.seekBarBufferedColor = Colors.white38,
    this.seekBarBaseColor = Colors.white24,
    this.seekBarThumbColor = Colors.white,
    this.seekBarBubbleColor = Colors.black87,
    this.seekBarBubbleTextStyle = const TextStyle(color: Colors.white),
    this.seekBarHeight = 44,
    this.gestureOverlayColor = const Color(0x73000000),
    this.gestureIconColor = Colors.white,
    this.gestureTextStyle = const TextStyle(color: Colors.white),
    this.adMarkerColor = const Color(0xFFFFC107),
    this.adMarkerPlayedColor = const Color(0x66FFC107),
    this.adMarkerWidth = 3,
    this.adMarkerHeight = 9,
    this.adCountdownBackgroundColor = const Color(0xCC000000),
    this.adCountdownAccentColor = const Color(0xFFFFC107),
    this.adCountdownTextStyle = const TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  });

  final Color backgroundColor;
  final Color spinnerColor;
  final double spinnerSize;
  final double spinnerStrokeWidth;
  final Color iconColor;
  final TextStyle errorTextStyle;
  final ButtonStyle? retryButtonStyle;
  final Color playBadgeColor;
  final Color playBadgeIconColor;
  final double playBadgeIconSize;
  final Color seekBarPlayedColor;
  final Color seekBarBufferedColor;
  final Color seekBarBaseColor;
  final Color seekBarThumbColor;
  final Color seekBarBubbleColor;
  final TextStyle seekBarBubbleTextStyle;
  final double seekBarHeight;
  final Color gestureOverlayColor;
  final Color gestureIconColor;
  final TextStyle gestureTextStyle;

  /// Seek-bar tick for an upcoming ad break / one already played.
  final Color adMarkerColor;
  final Color adMarkerPlayedColor;
  final double adMarkerWidth;
  final double adMarkerHeight;

  /// "Ad starts in N" pill.
  final Color adCountdownBackgroundColor;
  final Color adCountdownAccentColor;
  final TextStyle adCountdownTextStyle;

  ChorkiPlayerTheme copyWith({
    Color? backgroundColor,
    Color? spinnerColor,
    double? spinnerSize,
    double? spinnerStrokeWidth,
    Color? iconColor,
    TextStyle? errorTextStyle,
    ButtonStyle? retryButtonStyle,
    Color? playBadgeColor,
    Color? playBadgeIconColor,
    double? playBadgeIconSize,
    Color? seekBarPlayedColor,
    Color? seekBarBufferedColor,
    Color? seekBarBaseColor,
    Color? seekBarThumbColor,
    Color? seekBarBubbleColor,
    TextStyle? seekBarBubbleTextStyle,
    double? seekBarHeight,
    Color? gestureOverlayColor,
    Color? gestureIconColor,
    TextStyle? gestureTextStyle,
    Color? adMarkerColor,
    Color? adMarkerPlayedColor,
    double? adMarkerWidth,
    double? adMarkerHeight,
    Color? adCountdownBackgroundColor,
    Color? adCountdownAccentColor,
    TextStyle? adCountdownTextStyle,
  }) {
    return ChorkiPlayerTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      spinnerColor: spinnerColor ?? this.spinnerColor,
      spinnerSize: spinnerSize ?? this.spinnerSize,
      spinnerStrokeWidth: spinnerStrokeWidth ?? this.spinnerStrokeWidth,
      iconColor: iconColor ?? this.iconColor,
      errorTextStyle: errorTextStyle ?? this.errorTextStyle,
      retryButtonStyle: retryButtonStyle ?? this.retryButtonStyle,
      playBadgeColor: playBadgeColor ?? this.playBadgeColor,
      playBadgeIconColor: playBadgeIconColor ?? this.playBadgeIconColor,
      playBadgeIconSize: playBadgeIconSize ?? this.playBadgeIconSize,
      seekBarPlayedColor: seekBarPlayedColor ?? this.seekBarPlayedColor,
      seekBarBufferedColor: seekBarBufferedColor ?? this.seekBarBufferedColor,
      seekBarBaseColor: seekBarBaseColor ?? this.seekBarBaseColor,
      seekBarThumbColor: seekBarThumbColor ?? this.seekBarThumbColor,
      seekBarBubbleColor: seekBarBubbleColor ?? this.seekBarBubbleColor,
      seekBarBubbleTextStyle:
          seekBarBubbleTextStyle ?? this.seekBarBubbleTextStyle,
      seekBarHeight: seekBarHeight ?? this.seekBarHeight,
      gestureOverlayColor: gestureOverlayColor ?? this.gestureOverlayColor,
      gestureIconColor: gestureIconColor ?? this.gestureIconColor,
      gestureTextStyle: gestureTextStyle ?? this.gestureTextStyle,
      adMarkerColor: adMarkerColor ?? this.adMarkerColor,
      adMarkerPlayedColor: adMarkerPlayedColor ?? this.adMarkerPlayedColor,
      adMarkerWidth: adMarkerWidth ?? this.adMarkerWidth,
      adMarkerHeight: adMarkerHeight ?? this.adMarkerHeight,
      adCountdownBackgroundColor:
          adCountdownBackgroundColor ?? this.adCountdownBackgroundColor,
      adCountdownAccentColor:
          adCountdownAccentColor ?? this.adCountdownAccentColor,
      adCountdownTextStyle: adCountdownTextStyle ?? this.adCountdownTextStyle,
    );
  }
}

/// Icon overrides.
@immutable
class ChorkiPlayerIcons {
  const ChorkiPlayerIcons({
    this.play = Icons.play_arrow,
    this.refresh = Icons.refresh,
    this.fastForward = Icons.fast_forward,
    this.fastRewind = Icons.fast_rewind,
  });

  final IconData play;
  final IconData refresh;
  final IconData fastForward;
  final IconData fastRewind;
}

/// Text overrides (localization).
@immutable
class ChorkiPlayerStrings {
  const ChorkiPlayerStrings({
    this.videoFailed = 'Video failed to play',
    this.retry = 'Retry',
    this.seconds = 'Seconds',
    this.speed = 'Speed',
    this.noInternet = 'No internet connection',
    this.serverError = 'Server error occurred',
    this.genericError = 'Something went wrong',
    this.adCountdown = defaultAdCountdown,
    this.adStartNowHint = 'Tap to start now',
  });

  final String videoFailed;
  final String retry;
  final String seconds;
  final String speed;
  final String noInternet;
  final String serverError;
  final String genericError;

  /// Text for the pill shown before an ad break.
  final String Function(int seconds) adCountdown;

  /// Accessibility hint for the countdown pill.
  final String adStartNowHint;
}

String defaultAdCountdown(int seconds) => 'Ad starts in ${seconds}s';

/// Optional widget builders that fully replace default UI pieces.
@immutable
class ChorkiPlayerBuilders {
  const ChorkiPlayerBuilders({
    this.loadingBuilder,
    this.errorBuilder,
    this.playPauseBuilder,
    this.seekBarBuilder,
    this.timeBubbleBuilder,
    this.gestureFeedbackBuilder,
    this.adCountdownBuilder,
  });

  final WidgetBuilder? loadingBuilder;

  final Widget Function(BuildContext, String message, VoidCallback? onRetry)?
  errorBuilder;

  final Widget Function(BuildContext, VideoPlayerController)? playPauseBuilder;

  final Widget Function(
    BuildContext,
    ChorkiSeekBarState state,
    ValueChanged<Duration> onSeek,
  )?
  seekBarBuilder;

  final Widget Function(BuildContext, String text)? timeBubbleBuilder;

  final Widget Function(BuildContext, ChorkiGestureFeedback feedback)?
  gestureFeedbackBuilder;

  /// Replaces the "Ad starts in N" pill; call [startNow] to begin the ad.
  final Widget Function(
    BuildContext,
    int secondsRemaining,
    VoidCallback startNow,
  )?
  adCountdownBuilder;
}

@immutable
class ChorkiSeekBarState {
  const ChorkiSeekBarState({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.dragging,
  });

  final Duration position;
  final Duration buffered;
  final Duration duration;
  final bool dragging;
}

enum ChorkiGestureKind { seekForward, seekBackward, speed }

@immutable
class ChorkiGestureFeedback {
  const ChorkiGestureFeedback({required this.kind, required this.label});

  final ChorkiGestureKind kind;

  final String label;
}
