import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Per-source playback options passed to the underlying [VideoPlayerController].
@immutable
class ChorkiMediaOptions {
  const ChorkiMediaOptions({
    this.httpHeaders = const <String, String>{},
    this.startPosition,
    this.backBuffer,
    this.allowBackgroundPlayback = false,
    this.mixWithOthers = false,
    this.keepScreenOn = true,
    this.viewType = VideoViewType.textureView,
  });

  /// Sent with every media request (manifest, segments).
  final Map<String, String> httpHeaders;

  /// Position to seek to once the video is initialized (resume playback).
  final Duration? startPosition;

  /// How much already-played media to keep buffered for fast backward seeks.
  /// **Android only.**
  final Duration? backBuffer;

  /// Keep playing when the app goes to the background.
  final bool allowBackgroundPlayback;

  /// Mix audio with other apps instead of interrupting them.
  final bool mixWithOthers;

  /// Prevent the display from sleeping during playback. **iOS / macOS only.**
  final bool keepScreenOn;

  /// Render through a texture (default) or a native platform view.
  final VideoViewType viewType;

  VideoPlayerOptions toVideoPlayerOptions() => VideoPlayerOptions(
    allowBackgroundPlayback: allowBackgroundPlayback,
    mixWithOthers: mixWithOthers,
    preventsDisplaySleepDuringVideoPlayback: keepScreenOn,
    backBufferDurationMs: backBuffer?.inMilliseconds,
  );

  ChorkiMediaOptions copyWith({
    Map<String, String>? httpHeaders,
    Duration? startPosition,
    Duration? backBuffer,
    bool? allowBackgroundPlayback,
    bool? mixWithOthers,
    bool? keepScreenOn,
    VideoViewType? viewType,
  }) {
    return ChorkiMediaOptions(
      httpHeaders: httpHeaders ?? this.httpHeaders,
      startPosition: startPosition ?? this.startPosition,
      backBuffer: backBuffer ?? this.backBuffer,
      allowBackgroundPlayback:
          allowBackgroundPlayback ?? this.allowBackgroundPlayback,
      mixWithOthers: mixWithOthers ?? this.mixWithOthers,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
      viewType: viewType ?? this.viewType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChorkiMediaOptions &&
          mapEquals(other.httpHeaders, httpHeaders) &&
          other.startPosition == startPosition &&
          other.backBuffer == backBuffer &&
          other.allowBackgroundPlayback == allowBackgroundPlayback &&
          other.mixWithOthers == mixWithOthers &&
          other.keepScreenOn == keepScreenOn &&
          other.viewType == viewType;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      httpHeaders.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    startPosition,
    backBuffer,
    allowBackgroundPlayback,
    mixWithOthers,
    keepScreenOn,
    viewType,
  );
}
