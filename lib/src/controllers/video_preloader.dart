import 'dart:async';

import 'package:video_player/video_player.dart';

import '../media/chorki_media_options.dart';
import 'video_load_scheduler.dart';

class VideoPreloader {
  VideoPreloader({
    this.initTimeout = const Duration(seconds: 15),
    this.scheduler,
  });

  final Duration initTimeout;

  /// Queue for the loads; defaults to [VideoLoadScheduler.instance].
  final VideoLoadScheduler? scheduler;
  VideoLoadScheduler get _loads => scheduler ?? VideoLoadScheduler.instance;

  /// Creates and initializes a controller for [source], or returns null on
  /// failure / timeout. An `asset:` URI (`asset:assets/clip.mp4`) loads a
  /// bundled file; anything else is fetched over the network. Applies
  /// [options] (headers, buffering, start position).
  ///
  /// The load waits its turn in [VideoLoadScheduler]: [isHighPriority] (the
  /// visible page) goes first, and once [isCancelled] is true a load still
  /// queued returns null without creating a player. [initTimeout] counts
  /// only from the moment the load starts, which is when [onStarted] is
  /// called (used to measure the queue wait).
  Future<VideoPlayerController?> load(
    Uri source, {
    ChorkiMediaOptions options = const ChorkiMediaOptions(),
    bool Function()? isHighPriority,
    bool Function()? isCancelled,
    void Function()? onStarted,
  }) {
    return _loads.run<VideoPlayerController?>(
      () {
        onStarted?.call();
        return _load(source, options);
      },
      isHighPriority: isHighPriority,
      isCancelled: isCancelled,
    );
  }

  Future<VideoPlayerController?> _load(
    Uri source,
    ChorkiMediaOptions options,
  ) async {
    final controller = source.scheme == 'asset'
        ? VideoPlayerController.asset(
            // `asset:///a.mp4` and `asset:a.mp4` name the same asset.
            source.path.replaceFirst(RegExp('^/+'), ''),
            videoPlayerOptions: options.toVideoPlayerOptions(),
            viewType: options.viewType,
          )
        : VideoPlayerController.networkUrl(
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
      // Not awaited: dispose() waits for the platform to finish creating the
      // player, which may be exactly what is stuck.
      unawaited(disposeQuietly(controller));
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

  /// Disposes [controller], ignoring errors. Loads that start meanwhile wait
  /// briefly for it, so its decoder is free first.
  Future<void> disposeQuietly(VideoPlayerController? controller) {
    if (controller == null) return Future.value();
    final disposal = _dispose(controller);
    _loads.trackDisposal(disposal);
    return disposal;
  }

  Future<void> _dispose(VideoPlayerController controller) async {
    try {
      await controller.dispose();
    } catch (_) {}
  }
}
