part of 'chorki_player_widget.dart';

class _ChorkiPlayerState extends State<ChorkiPlayer> {
  late final ChorkiVideoPreloader _preloader = ChorkiVideoPreloader(
    initTimeout: widget.initTimeout,
  );

  late final BytesBloc _bloc;

  ChorkiPlayerController? _ownController;
  ChorkiPlayerController get _chorki =>
      widget.controller ??
      (_ownController ??= ChorkiPlayerController(
        initialFit: widget.initialFit,
        seekStep: widget.doubleTapSeek,
      ));

  VideoPlayerController? _controller;
  ByteDataEntity? _byteData;

  /// Why the video (not the route) failed; null while it is fine.
  ChorkiPlayerError? _videoError;
  bool get _videoFailed => _videoError != null;
  int _loadGen = 0;

  /// Silent retries of transient failures; the poster shows while one is
  /// pending.
  final RetryPolicy _retries = RetryPolicy();

  /// Where to resume after a playback error on screen, so a retry continues
  /// instead of restarting the byte.
  Duration? _resumeAt;

  /// Position of [_controller] before any error (an erroneous value has none).
  Duration _lastPosition = Duration.zero;

  /// [ChorkiPlayer.preload] as applied. A flip is applied after the frame
  /// (see [_syncPreload]): attaching, playing and pausing notify a shared
  /// controller's listeners, which may live outside this subtree and must
  /// not be marked dirty during build.
  late bool _preloading;

  /// Analytics for this player (one per widget: a feed's controller is
  /// shared, its views are not).
  ChorkiAnalyticsSession? _session;

  @override
  void initState() {
    super.initState();
    _preloading = widget.preload;
    _syncSession();
    _bloc = BytesBloc(getByteDataUsecase: ChorkiServices.instance.bytesUsecase)
      ..add(_loadEvent());
  }

  ByteScreenEvent _loadEvent({bool refresh = false}) => loadEventFor(
    route: widget.route,
    videoUrl: widget.videoUrl,
    posterUrl: widget.posterUrl,
    adTagUrl: widget.adTagUrl,
    refresh: refresh,
  );

  @override
  void didUpdateWidget(covariant ChorkiPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      final old = oldWidget.controller ?? _ownController;
      final c = _controller;
      // detach(null) would unbind whatever video `old` drives, which may
      // belong to another player sharing it.
      if (c != null) old?.detach(c);
      if (widget.controller != null) {
        _ownController?.dispose();
        _ownController = null;
      }
      if (c != null && !_preloading) {
        _chorki.attach(c, onRetry: _retry, analytics: _session);
      }
    }
    if (oldWidget.analytics != widget.analytics ||
        oldWidget.controller?.analytics != widget.controller?.analytics) {
      _syncSession();
    }
    if (oldWidget.route != widget.route ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.adTagUrl != widget.adTagUrl) {
      _resetRetries();
      // End the old view while its video is still bound, then unbind it
      // (the synchronous part of _resetVideo) before the new view starts, so
      // the new impression waits for the new video.
      final session = _session;
      final restart = session != null && session.isActive;
      if (restart) session.deactivate(ChorkiSessionEndReason.sourceChanged);
      unawaited(_resetVideo());
      if (restart) session.activate();
      _bloc.add(_loadEvent());
    } else if (oldWidget.looping != widget.looping) {
      final c = _controller;
      if (c != null) {
        fireAndReport(() => c.setLooping(widget.looping), 'player.setLooping');
      }
    }
    if (oldWidget.preload != widget.preload) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncPreload());
    }
  }

  /// Applies a [ChorkiPlayer.preload] flip. Back-and-forth flips within a
  /// frame cancel out.
  void _syncPreload() {
    if (!mounted || _preloading == widget.preload) return;
    final controller = _controller;
    if (widget.preload) {
      // Swiped away: the next visit plays it as a fresh view.
      _resumeAt = null;
      _session?.deactivate(ChorkiSessionEndReason.swipedAway);
      if (controller != null) {
        _chorki.detach(controller);
        final start = widget.mediaOptions.startPosition ?? Duration.zero;
        fireAndReport(() async {
          await controller.pause();
          await controller.seekTo(start);
        }, 'player.rewindForPreload');
      }
      setState(() => _preloading = true);
      return;
    }
    setState(() => _preloading = false);
    _session?.activate();
    _resetRetries();
    if (_videoFailed || _bloc.state is ByteScreenFailedState) {
      // It failed off screen, e.g. on a network blip, or is waiting for a
      // silent retry: try again now that it is seen.
      _retry(auto: true);
    } else if (controller != null) {
      _chorki.attach(controller, onRetry: _retry, analytics: _session);
      // play() marks the video playing before its first await, so the play
      // badge never shows when the controls appear next frame.
      if (widget.autoPlay && !_adsActive(_byteData)) {
        fireAndReport(controller.play, 'player.play');
      }
    }
  }

  Future<void> _startVideo(ByteDataEntity byteData) async {
    final gen = ++_loadGen;
    try {
      await _loadVideo(byteData, gen);
    } catch (e, st) {
      ChorkiDiagnostics.report(e, st, 'player.loadVideo');
      if (mounted && gen == _loadGen) {
        _onVideoFailed(ChorkiPlayerError.from(e, stage: ChorkiErrorStage.load));
      }
    }
  }

  Future<void> _loadVideo(ByteDataEntity byteData, int gen) async {
    if (byteData.url.isEmpty) {
      _onVideoFailed(
        const ChorkiPlayerError(
          ChorkiErrorCode.noVideoUrl,
          stage: ChorkiErrorStage.load,
        ),
      );
      return;
    }

    final resumeAt = _resumeAt;
    _session?.recordLoadStart();
    final result = await _preloader.loadResult(
      Uri.parse(byteData.url),
      options: resumeAt == null
          ? widget.mediaOptions
          : widget.mediaOptions.copyWith(startPosition: resumeAt),
      // `widget.preload`, not `_preloading`: it is a frame ahead.
      isHighPriority: () => mounted && !widget.preload,
      // Swiped past before its turn: it never creates a player.
      isCancelled: () => !mounted || gen != _loadGen,
      onStarted: () => _session?.recordLoadRunning(),
    );

    final controller = result.controller;
    if (!mounted || gen != _loadGen) {
      await _preloader.disposeQuietly(controller);
      return;
    }

    if (controller == null) {
      _onVideoFailed(result.error!);
      return;
    }
    _resumeAt = null;
    _session?.recordLoaded();

    final previous = _controller;
    previous?.removeListener(_onControllerValue);
    if (previous != null) _chorki.detach(previous);
    unawaited(_preloader.disposeQuietly(previous));
    _lastPosition = controller.value.position;
    controller.addListener(_onControllerValue);
    _session?.bind(controller);
    // A preloading player leaves a shared controller to the visible one.
    if (!_preloading) {
      _chorki.attach(controller, onRetry: _retry, analytics: _session);
    }

    fireAndReport(
      () => controller.setLooping(widget.looping),
      'player.setLooping',
    );
    if (widget.autoPlay && !_preloading && !_adsActive(byteData)) {
      fireAndReport(controller.play, 'player.play');
    }

    setState(() {
      _controller = controller;
      _videoError = null;
    });
  }

  void _onControllerValue() {
    final c = _controller;
    if (c != null && !c.value.hasError && c.value.isInitialized) {
      _lastPosition = c.value.position;
    }
    if (c != null && c.value.hasError && !_videoFailed && mounted) {
      // The erroneous value has no position: use the last one seen.
      final position = _lastPosition;
      _onVideoFailed(
        ChorkiPlayerError(
          ChorkiErrorCode.playback,
          stage: ChorkiErrorStage.playback,
          detail: c.value.errorDescription,
        ),
        resumeAt: !_preloading && position > Duration.zero ? position : null,
      );
    }
    // Nothing may play a preloading video, e.g. the ad layer resuming the
    // content in the frame before it is removed.
    if (c != null && _preloading && c.value.isPlaying) {
      fireAndReport(c.pause, 'player.pausePreloaded');
    }
  }

  void _onVideoFailed(ChorkiPlayerError error, {Duration? resumeAt}) {
    if (!mounted) return;
    _videoError = error;
    _onLoadFailed(error, resumeAt: resumeAt);
  }

  /// A route fetch or the video failed. A transient failure
  /// ([ChorkiPlayerError.isTransient]) is retried silently a few times
  /// ([RetryPolicy]) before the error shows; a permanent one (404, no
  /// video URL, ...) shows at once.
  void _onLoadFailed(ChorkiPlayerError error, {Duration? resumeAt}) {
    if (!mounted) return;
    if (resumeAt != null) _resumeAt = resumeAt;
    _session?.recordError(
      error,
      willRetry: _retries.canRetry(transient: error.isTransient),
    );
    _retries.schedule(
      transient: error.isTransient,
      onRetry: (attempt) {
        if (!mounted) return;
        _session?.recordRetry(attempt: attempt, auto: true);
        _reload();
      },
    );
    setState(() {});
  }

  void _resetRetries() {
    _retries.reset();
    _resumeAt = null;
  }

  bool _adsActive(ByteDataEntity? data) =>
      (widget.ads?.enabled ?? false) && (data?.adTagUrl.isNotEmpty ?? false);

  Future<void> _resetVideo() async {
    _loadGen++;
    final controller = _controller;
    controller?.removeListener(_onControllerValue);
    _session?.unbind();
    // Also clears isAdPlaying, but only if this player is the attached one.
    if (controller != null) _chorki.detach(controller);
    _controller = null;
    _byteData = null;
    _videoError = null;
    await _preloader.disposeQuietly(controller);
    if (mounted) setState(() {});
  }

  /// Manual retry (the Retry button, [ChorkiPlayerController.retry]) or a
  /// byte becoming active: a fresh set of silent retries.
  ///
  /// [auto] is true when it is not the viewer asking (a byte that failed off
  /// screen becoming active).
  void _retry({bool auto = false}) {
    _retries.reset();
    _session?.recordRetry(attempt: 1, auto: auto);
    _reload();
  }

  /// Reloads the route (bypassing the route cache, in case the video URL it
  /// returned went stale) and the video.
  void _reload() {
    _retries.cancel();
    unawaited(_resetVideo());
    _bloc.add(_loadEvent(refresh: true));
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    fireAndReport(
      controller.value.isPlaying ? controller.pause : controller.play,
      'player.togglePlayPause',
    );
  }

  @override
  void dispose() {
    _retries.cancel();
    _session?.dispose();
    _session = null;
    fireAndReport(_bloc.close, 'player.closeBloc');
    _loadGen++;
    final controller = _controller;
    controller?.removeListener(_onControllerValue);
    if (controller != null) widget.controller?.detach(controller);
    _ownController?.dispose();
    _ownController = null;
    _controller = null;
    unawaited(_preloader.disposeQuietly(controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<BytesBloc, ByteScreenState>(
      bloc: _bloc,
      listener: (context, state) {
        if (state is ByteScreenLoadedState) {
          _byteData = state.data;
          _session?.adContext = adContextOf(state.data);
          unawaited(_startVideo(state.data));
        } else if (state is ByteScreenFailedState) {
          _onLoadFailed(state.error);
        }
      },
      child: BlocBuilder<BytesBloc, ByteScreenState>(
        bloc: _bloc,
        builder: (context, state) {
          final body = ChorkiAnalyticsScope(
            session: _session,
            child: ColoredBox(
              color: widget.theme.backgroundColor,
              child: _buildBody(state),
            ),
          );
          if (!widget.sizeToVideo) return body;
          return AspectRatio(aspectRatio: _aspectRatio, child: body);
        },
      ),
    );
  }

  double get _aspectRatio {
    final value = _controller?.value;
    if (_videoFailed || value == null || !value.isInitialized) {
      return widget.placeholderAspectRatio;
    }
    return value.aspectRatio;
  }

  Widget _buildBody(ByteScreenState state) {
    // A silent retry is pending: keep the poster, no error flash.
    if (_retries.pending) return _buildLoading(showPoster: true);
    if (state is ByteScreenLoadingState || state is ByteScreenInitialState) {
      return _buildLoading();
    }
    final failed = state is ByteScreenFailedState || _videoFailed;
    // Off screen (or sliding in during a swipe): it retries when it becomes
    // active, so an error view would only flash.
    if (failed && _preloading) return _buildLoading(showPoster: true);
    final error = state is ByteScreenFailedState ? state.error : _videoError;
    if (error != null) return _buildError(error);

    final controller = _controller;
    if (controller == null) {
      return _buildLoading(showPoster: true);
    }
    return _buildVideo(controller);
  }

  Widget _buildError(ChorkiPlayerError error) => buildPlayerError(
    context,
    error,
    player: widget,
    // The viewer can always retry (the route may be fixed by the time they
    // tap); only the silent retries are reserved for transient errors.
    onRetry: _retry,
  );

  Widget _buildLoading({bool showPoster = false}) {
    final custom = widget.builders.loadingBuilder;
    if (custom != null) return custom(context);
    return PlayerLoadingView(
      theme: widget.theme,
      fit: _chorki.fit,
      posterUrl: showPoster ? _byteData?.thumbnailUrl : null,
    );
  }

  Widget _buildVideo(VideoPlayerController controller) => PlayerVideoView(
    player: widget,
    controller: controller,
    chorki: _chorki,
    adTagUrl: _byteData?.adTagUrl ?? '',
    preloading: _preloading,
    onTogglePlayPause: _togglePlayPause,
    // The layer outlives a flip back to preload by a frame, when a shared
    // controller may already drive another byte: read the state now.
    onAdPlayingChanged: (playing) {
      if (!_preloading) _chorki.setAdPlaying(playing);
    },
  );
}
