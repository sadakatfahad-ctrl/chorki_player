import 'dart:async';

import 'package:video_player/video_player.dart';

import '../media/chorki_media_options.dart';

class VideoPreloader {
  VideoPreloader({this.initTimeout = const Duration(seconds: 15)});

  final Duration initTimeout;

  /// Creates and initializes a controller for [source], or returns null on
  /// failure / timeout. Applies [options] (headers, buffering, start position).
  Future<VideoPlayerController?> load(
    Uri source, {
    ChorkiMediaOptions options = const ChorkiMediaOptions(),
  }) async {
    final controller = VideoPlayerController.networkUrl(
      source,
      httpHeaders: options.httpHeaders,
      videoPlayerOptions: options.toVideoPlayerOptions(),
      viewType: options.viewType,
    );
    final initFuture = controller.initialize();
    try {
      await initFuture.timeout(initTimeout);
    } catch (_) {
      initFuture.catchError((Object _) {});
      await disposeQuietly(controller);
      return null;
    }
    final start = options.startPosition;
    if (start != null && start > Duration.zero) {
      try {
        await controller.seekTo(start);
      } catch (_) {}
    }
    return controller;
  }

  Future<void> disposeQuietly(VideoPlayerController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }
}
