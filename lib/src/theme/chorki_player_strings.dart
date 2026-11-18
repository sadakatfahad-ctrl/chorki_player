import 'package:flutter/material.dart';

/// Icon overrides.
@immutable
class ChorkiPlayerIcons {
  /// Material icons by default; override any of them.
  const ChorkiPlayerIcons({
    this.play = Icons.play_arrow,
    this.refresh = Icons.refresh,
    this.fastForward = Icons.fast_forward,
    this.fastRewind = Icons.fast_rewind,
    this.settings = Icons.settings,
    this.quality = Icons.high_quality_outlined,
    this.audio = Icons.audiotrack_outlined,
    this.speed = Icons.speed,
    this.fit = Icons.fit_screen_outlined,
    this.pip = Icons.picture_in_picture_alt_outlined,
    this.check = Icons.check,
    this.back = Icons.arrow_back,
  });

  /// The play badge.
  final IconData play;

  /// The retry button.
  final IconData refresh;

  /// Seeking forward (double tap, scrub, speed boost).
  final IconData fastForward;

  /// Seeking backward.
  final IconData fastRewind;

  /// The settings button.
  final IconData settings;

  /// The quality row of the settings sheet.
  final IconData quality;

  /// The audio row.
  final IconData audio;

  /// The speed row.
  final IconData speed;

  /// The video size row.
  final IconData fit;

  /// The picture-in-picture row.
  final IconData pip;

  /// The selected choice in a settings list.
  final IconData check;

  /// Back to the settings root.
  final IconData back;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChorkiPlayerIcons &&
          other.play == play &&
          other.refresh == refresh &&
          other.fastForward == fastForward &&
          other.fastRewind == fastRewind &&
          other.settings == settings &&
          other.quality == quality &&
          other.audio == audio &&
          other.speed == speed &&
          other.fit == fit &&
          other.pip == pip &&
          other.check == check &&
          other.back == back);

  @override
  int get hashCode => Object.hashAll([
    play,
    refresh,
    fastForward,
    fastRewind,
    settings,
    quality,
    audio,
    speed,
    fit,
    pip,
    check,
    back,
  ]);
}

/// Text overrides (localization).
@immutable
class ChorkiPlayerStrings {
  /// English by default; pass translations for the rest.
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
    this.settings = 'Settings',
    this.quality = 'Quality',
    this.auto = 'Auto',
    this.audio = 'Audio',
    this.normalSpeed = 'Normal',
    this.fit = 'Fit',
    this.fill = 'Fill',
    this.videoFit = 'Video size',
    this.pictureInPicture = 'Picture-in-picture',
  });

  /// The video could not be played.
  final String videoFailed;

  /// The retry button.
  final String retry;

  /// Unit after the double-tap seek amount, e.g. `10 Seconds`.
  final String seconds;

  /// After the long-press speed, e.g. `2× Speed`.
  final String speed;

  /// Shown for `ChorkiErrorCode.noInternet` and timeouts.
  final String noInternet;

  /// Shown for server errors (5xx, malformed responses).
  final String serverError;

  /// Shown for any other failure.
  final String genericError;

  /// Text for the pill shown before an ad break.
  final String Function(int seconds) adCountdown;

  /// Accessibility hint for the countdown pill.
  final String adStartNowHint;

  /// Title of the settings sheet.
  final String settings;

  /// The quality row.
  final String quality;

  /// Automatic quality.
  final String auto;

  /// The audio row.
  final String audio;

  /// Speed 1.0.
  final String normalSpeed;

  /// Fit the whole video in the player.
  final String fit;

  /// Fill the player, cropping the video.
  final String fill;

  /// The video size row.
  final String videoFit;

  /// The picture-in-picture row.
  final String pictureInPicture;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChorkiPlayerStrings &&
          other.videoFailed == videoFailed &&
          other.retry == retry &&
          other.seconds == seconds &&
          other.speed == speed &&
          other.noInternet == noInternet &&
          other.serverError == serverError &&
          other.genericError == genericError &&
          other.adCountdown == adCountdown &&
          other.adStartNowHint == adStartNowHint &&
          other.settings == settings &&
          other.quality == quality &&
          other.auto == auto &&
          other.audio == audio &&
          other.normalSpeed == normalSpeed &&
          other.fit == fit &&
          other.fill == fill &&
          other.videoFit == videoFit &&
          other.pictureInPicture == pictureInPicture);

  @override
  int get hashCode => Object.hashAll([
    videoFailed,
    retry,
    seconds,
    speed,
    noInternet,
    serverError,
    genericError,
    adCountdown,
    adStartNowHint,
    settings,
    quality,
    auto,
    audio,
    normalSpeed,
    fit,
    fill,
    videoFit,
    pictureInPicture,
  ]);
}

/// The default [ChorkiPlayerStrings.adCountdown]: `Ad starts in 5s`.
String defaultAdCountdown(int seconds) => 'Ad starts in ${seconds}s';
