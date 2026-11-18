import 'package:flutter/material.dart';

export 'chorki_player_builders.dart';
export 'chorki_player_strings.dart';

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
    this.settingsButtonColor = Colors.white,
    this.settingsButtonBackgroundColor = const Color(0x59000000),
    this.settingsSheetBackgroundColor = const Color(0xFF1C1C1E),
    this.settingsTextStyle = const TextStyle(color: Colors.white, fontSize: 15),
    this.settingsSecondaryTextStyle = const TextStyle(
      color: Colors.white60,
      fontSize: 14,
    ),
    this.settingsSelectedColor = const Color(0xFFFFC107),
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

  /// Gear button and the settings bottom sheet.
  final Color settingsButtonColor;
  final Color settingsButtonBackgroundColor;
  final Color settingsSheetBackgroundColor;
  final TextStyle settingsTextStyle;
  final TextStyle settingsSecondaryTextStyle;
  final Color settingsSelectedColor;

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
    Color? settingsButtonColor,
    Color? settingsButtonBackgroundColor,
    Color? settingsSheetBackgroundColor,
    TextStyle? settingsTextStyle,
    TextStyle? settingsSecondaryTextStyle,
    Color? settingsSelectedColor,
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
      settingsButtonColor: settingsButtonColor ?? this.settingsButtonColor,
      settingsButtonBackgroundColor:
          settingsButtonBackgroundColor ?? this.settingsButtonBackgroundColor,
      settingsSheetBackgroundColor:
          settingsSheetBackgroundColor ?? this.settingsSheetBackgroundColor,
      settingsTextStyle: settingsTextStyle ?? this.settingsTextStyle,
      settingsSecondaryTextStyle:
          settingsSecondaryTextStyle ?? this.settingsSecondaryTextStyle,
      settingsSelectedColor:
          settingsSelectedColor ?? this.settingsSelectedColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChorkiPlayerTheme &&
          other.backgroundColor == backgroundColor &&
          other.spinnerColor == spinnerColor &&
          other.spinnerSize == spinnerSize &&
          other.spinnerStrokeWidth == spinnerStrokeWidth &&
          other.iconColor == iconColor &&
          other.errorTextStyle == errorTextStyle &&
          other.retryButtonStyle == retryButtonStyle &&
          other.playBadgeColor == playBadgeColor &&
          other.playBadgeIconColor == playBadgeIconColor &&
          other.playBadgeIconSize == playBadgeIconSize &&
          other.seekBarPlayedColor == seekBarPlayedColor &&
          other.seekBarBufferedColor == seekBarBufferedColor &&
          other.seekBarBaseColor == seekBarBaseColor &&
          other.seekBarThumbColor == seekBarThumbColor &&
          other.seekBarBubbleColor == seekBarBubbleColor &&
          other.seekBarBubbleTextStyle == seekBarBubbleTextStyle &&
          other.seekBarHeight == seekBarHeight &&
          other.gestureOverlayColor == gestureOverlayColor &&
          other.gestureIconColor == gestureIconColor &&
          other.gestureTextStyle == gestureTextStyle &&
          other.adMarkerColor == adMarkerColor &&
          other.adMarkerPlayedColor == adMarkerPlayedColor &&
          other.adMarkerWidth == adMarkerWidth &&
          other.adMarkerHeight == adMarkerHeight &&
          other.adCountdownBackgroundColor == adCountdownBackgroundColor &&
          other.adCountdownAccentColor == adCountdownAccentColor &&
          other.adCountdownTextStyle == adCountdownTextStyle &&
          other.settingsButtonColor == settingsButtonColor &&
          other.settingsButtonBackgroundColor ==
              settingsButtonBackgroundColor &&
          other.settingsSheetBackgroundColor == settingsSheetBackgroundColor &&
          other.settingsTextStyle == settingsTextStyle &&
          other.settingsSecondaryTextStyle == settingsSecondaryTextStyle &&
          other.settingsSelectedColor == settingsSelectedColor);

  @override
  int get hashCode => Object.hashAll([
    backgroundColor,
    spinnerColor,
    spinnerSize,
    spinnerStrokeWidth,
    iconColor,
    errorTextStyle,
    retryButtonStyle,
    playBadgeColor,
    playBadgeIconColor,
    playBadgeIconSize,
    seekBarPlayedColor,
    seekBarBufferedColor,
    seekBarBaseColor,
    seekBarThumbColor,
    seekBarBubbleColor,
    seekBarBubbleTextStyle,
    seekBarHeight,
    gestureOverlayColor,
    gestureIconColor,
    gestureTextStyle,
    adMarkerColor,
    adMarkerPlayedColor,
    adMarkerWidth,
    adMarkerHeight,
    adCountdownBackgroundColor,
    adCountdownAccentColor,
    adCountdownTextStyle,
    settingsButtonColor,
    settingsButtonBackgroundColor,
    settingsSheetBackgroundColor,
    settingsTextStyle,
    settingsSecondaryTextStyle,
    settingsSelectedColor,
  ]);
}
