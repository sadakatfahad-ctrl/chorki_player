import 'dart:async';

import 'package:video_player/video_player.dart';

class VideoPreloader {
  VideoPreloader({this.initTimeout = const Duration(seconds: 15)});

  final Duration initTimeout;

  Future<VideoPlayerController?> load(Uri source) async {
    final controller = VideoPlayerController.networkUrl(source);
    try {
      await controller.initialize().timeout(initTimeout);
      return controller;
    } catch (_) {
      await disposeQuietly(controller);
      return null;
    }
  }

  Future<void> disposeQuietly(VideoPlayerController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {}
  }
}
