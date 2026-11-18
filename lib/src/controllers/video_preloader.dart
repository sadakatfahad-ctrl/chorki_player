import 'dart:async';

import 'package:video_player/video_player.dart';

import '../core/diagnostics.dart';
import '../errors/chorki_player_error.dart';
import '../media/chorki_media_options.dart';
import 'video_load_scheduler.dart';

/// The outcome of [ChorkiVideoPreloader.loadResult]: an initialized [controller],
/// or the [error] that prevented it (both null when the load was cancelled).
class ChorkiVideoLoadResult {
  /// A successful load.
  const ChorkiVideoLoadResult.loaded(VideoPlayerController this.controller)
    : error = null;

  /// A failed load.
  const ChorkiVideoLoadResult.failed(ChorkiPlayerError this.error)
    : controller = null;

  /// A load cancelled before it created a player.
  const ChorkiVideoLoadResult.cancelled() : controller = null, error = null;

  /// The initialized controller, on success.
  final VideoPlayerController? controller;

  /// Why it failed ([ChorkiErrorCode.timeout] or [ChorkiErrorCode.videoLoad]).
  final ChorkiPlayerError? error;
}

/// Creates and initializes [VideoPlayerController]s through the app-wide
/// [ChorkiVideoLoadScheduler], so a feed never decodes more videos at once than
/// the device handles.
class ChorkiVideoPreloader {
  /// Creates a preloader; [initTimeout] bounds each initialization.
  ChorkiVideoPreloader({
    this.initTimeout = const Duration(seconds: 15),
    this.scheduler,
  });

  /// Longest time a video may take to initialize once its load starts.
  final Duration initTimeout;

  /// Queue for the loads; defaults to [ChorkiVideoLoadScheduler.instance].
  final ChorkiVideoLoadScheduler? scheduler;
  ChorkiVideoLoadScheduler get _loads =>
      scheduler ?? ChorkiVideoLoadScheduler.instance;

  /// Creates and initializes a controller for [source], or returns null on
  /// failure / timeout. An `asset:` URI (`asset:assets/clip.mp4`) loads a
  /// bundled file; anything else is fetched over the network. Applies
  /// [options] (headers, buffering, start position).
  ///
  /// The load waits its turn in [ChorkiVideoLoadScheduler]: [isHighPriority] (the
  /// visible page) goes first, and once [isCancelled] is true a load still
  /// queued returns null without creating a player. [initTimeout] counts
  /// only from the moment the load starts, which is when [onStarted] is
  /// called (used to measure the queue wait).
  ///
  /// Use [loadResult] to also learn why a load failed.
  Future<VideoPlayerController?> load(
    Uri source, {
    ChorkiMediaOptions options = const ChorkiMediaOptions(),
    bool Function()? isHighPriority,
    bool Function()? isCancelled,
    void Function()? onStarted,
  }) async => (await loadResult(
    source,
    options: options,
    isHighPriority: isHighPriority,
    isCancelled: isCancelled,
    onStarted: onStarted,
  )).controller;

  /// Like [load], but a failure carries its reason.
  Future<ChorkiVideoLoadResult> loadResult(
    Uri source, {
    ChorkiMediaOptions options = const ChorkiMediaOptions(),
    bool Function()? isHighPriority,
    bool Function()? isCancelled,
    void Function()? onStarted,
  }) async {
    final result = await _loads.run<ChorkiVideoLoadResult>(
      () {
        onStarted?.call();
        return _load(source, options);
      },
      isHighPriority: isHighPriority,
      isCancelled: isCancelled,
    );
    return result ?? const ChorkiVideoLoadResult.cancelled();
  }

  Future<ChorkiVideoLoadResult> _load(
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
    } catch (e) {
      // A timed-out initialize may still fail later; that result is moot.
      unawaited(initFuture.then<void>((_) {}, onError: _ignoreLateInitError));
      // Not awaited: dispose() waits for the platform to finish creating the
      // player, which may be exactly what is stuck.
      unawaited(disposeQuietly(controller));
      return ChorkiVideoLoadResult.failed(
        e is TimeoutException
            ? const ChorkiPlayerError(
                ChorkiErrorCode.timeout,
                stage: ChorkiErrorStage.load,
              )
            : ChorkiPlayerError(
                ChorkiErrorCode.videoLoad,
                stage: ChorkiErrorStage.load,
                detail: '$e',
              ),
      );
    }
    final start = options.startPosition;
    if (start != null && start > Duration.zero) {
      try {
        await controller.seekTo(start);
      } catch (e, st) {
        // The video still plays, from the start.
        ChorkiDiagnostics.report(e, st, 'preloader.seekToStart');
      }
    }
    return ChorkiVideoLoadResult.loaded(controller);
  }

  static void _ignoreLateInitError(Object _) {
    // guardrail:allow swallowed_error - the load already failed by timeout and reported that.
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
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'preloader.dispose');
    }
  }
}
