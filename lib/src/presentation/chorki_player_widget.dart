import 'dart:async';

import 'package:chorki_player/src/ads/chorki_ad_config.dart';
import 'package:chorki_player/src/ads/chorki_ad_layer.dart';
import 'package:chorki_player/src/controllers/chorki_player_controller.dart';
import 'package:chorki_player/src/controllers/video_load_scheduler.dart';
import 'package:chorki_player/src/controllers/video_preloader.dart';
import 'package:chorki_player/src/domain/entity/ad_campaign_entity.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/injection_container.dart';
import 'package:chorki_player/src/media/chorki_media_options.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:chorki_player/src/presentation/bytes_screen/bytes_screen_bloc.dart';
import 'package:chorki_player/src/presentation/widgets/chorki_player_surface.dart';
import 'package:chorki_player/src/presentation/widgets/chorki_settings_sheet.dart';
import 'package:chorki_player/src/theme/chorki_player_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

class ChorkiPlayer extends StatefulWidget {
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

  final bool autoPlay;

  /// Loads and buffers the video without playing it, for feeds that build
  /// the next byte ahead of time: `preload: index != current`.
  ///
  /// While preloading, the player shows only the first frame (no controls),
  /// requests no ads, and leaves [controller] unattached, so one controller
  /// can be shared by every page of a feed. Its load waits behind the
  /// visible player's (see [VideoLoadScheduler]). A failure while preloading
  /// keeps the poster instead of the error view, and retries when the byte
  /// becomes active. Turning it off attaches
  /// [controller], starts the ads and plays when [autoPlay] is set. Turning
  /// it back on pauses and rewinds to the start
  /// ([ChorkiMediaOptions.startPosition], else 0:00).
  final bool preload;

  final bool looping;

  final bool showSeekBar;

  final double seekBarBottomOffset;

  final bool enableGestures;

  final Duration doubleTapSeek;

  final double longPressSpeed;

  final ChorkiPlayerTheme theme;

  final ChorkiPlayerIcons icons;

  final ChorkiPlayerStrings strings;

  final ChorkiPlayerBuilders builders;

  final Duration initTimeout;

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

  @override
  State<ChorkiPlayer> createState() => _ChorkiPlayerState();
}

class _ChorkiPlayerState extends State<ChorkiPlayer> {
  late final VideoPreloader _preloader = VideoPreloader(
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
  bool _videoFailed = false;
  int _loadGen = 0;

  /// Waits before each silent retry of a transient failure (route fetch,
  /// video init, playback error). The error view shows once they are used
  /// up. The count resets on a manual retry, a new source and when a
  /// preloading byte becomes active.
  static const List<Duration> _autoRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];
  int _autoRetries = 0;

  /// Pending silent retry. While set, the player shows the poster.
  Timer? _retryTimer;

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

  @override
  void initState() {
    super.initState();
    _preloading = widget.preload;
    initChorkiPlayer();
    _bloc = BytesBloc(getByteDataUsecase: getIt<BytesUsecase>())
      ..add(_loadEvent());
  }

  ByteScreenEvent _loadEvent({bool refresh = false}) {
    final url = widget.videoUrl;
    if (url == null) {
      return ByteScreenInitialEvent(widget.route, refresh: refresh);
    }
    final tag = widget.adTagUrl;
    return ByteScreenSourceEvent(
      ByteDataEntity(
        id: 0,
        thumbnailUrl: widget.posterUrl,
        url: url,
        adCampaign: tag.isEmpty
            ? null
            : AdCampaignEntity(id: '', title: '', url: tag),
      ),
    );
  }

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
      if (c != null && !_preloading) _chorki.attach(c, onRetry: _retry);
    }
    if (oldWidget.route != widget.route ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.adTagUrl != widget.adTagUrl) {
      _resetRetries();
      unawaited(_resetVideo());
      _bloc.add(_loadEvent());
    } else if (oldWidget.looping != widget.looping) {
      final c = _controller;
      if (c != null) unawaited(_safe(() => c.setLooping(widget.looping)));
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
      if (controller != null) {
        _chorki.detach(controller);
        final start = widget.mediaOptions.startPosition ?? Duration.zero;
        unawaited(
          _safe(() async {
            await controller.pause();
            await controller.seekTo(start);
          }),
        );
      }
      setState(() => _preloading = true);
      return;
    }
    setState(() => _preloading = false);
    _resetRetries();
    if (_videoFailed || _bloc.state is ByteScreenFailedState) {
      // It failed off screen, e.g. on a network blip, or is waiting for a
      // silent retry: try again now that it is seen.
      _retry();
    } else if (controller != null) {
      _chorki.attach(controller, onRetry: _retry);
      // play() marks the video playing before its first await, so the play
      // badge never shows when the controls appear next frame.
      if (widget.autoPlay && !_adsActive(_byteData)) {
        unawaited(_safe(controller.play));
      }
    }
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> _startVideo(ByteDataEntity byteData) async {
    final gen = ++_loadGen;
    try {
      await _loadVideo(byteData, gen);
    } catch (_) {
      if (mounted && gen == _loadGen) _onVideoFailed();
    }
  }

  Future<void> _loadVideo(ByteDataEntity byteData, int gen) async {
    if (byteData.url.isEmpty) {
      // Nothing to play: retrying cannot help.
      _onVideoFailed(transient: false);
      return;
    }

    final resumeAt = _resumeAt;
    final controller = await _preloader.load(
      Uri.parse(byteData.url),
      options: resumeAt == null
          ? widget.mediaOptions
          : widget.mediaOptions.copyWith(startPosition: resumeAt),
      // `widget.preload`, not `_preloading`: it is a frame ahead.
      isHighPriority: () => mounted && !widget.preload,
      // Swiped past before its turn: it never creates a player.
      isCancelled: () => !mounted || gen != _loadGen,
    );

    if (!mounted || gen != _loadGen) {
      await _preloader.disposeQuietly(controller);
      return;
    }

    if (controller == null) {
      _onVideoFailed();
      return;
    }
    _resumeAt = null;

    final previous = _controller;
    previous?.removeListener(_onControllerValue);
    if (previous != null) _chorki.detach(previous);
    unawaited(_preloader.disposeQuietly(previous));
    _lastPosition = controller.value.position;
    controller.addListener(_onControllerValue);
    // A preloading player leaves a shared controller to the visible one.
    if (!_preloading) _chorki.attach(controller, onRetry: _retry);

    unawaited(_safe(() => controller.setLooping(widget.looping)));
    if (widget.autoPlay && !_preloading && !_adsActive(byteData)) {
      unawaited(_safe(controller.play));
    }

    setState(() {
      _controller = controller;
      _videoFailed = false;
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
        resumeAt: !_preloading && position > Duration.zero ? position : null,
      );
    }
    // Nothing may play a preloading video, e.g. the ad layer resuming the
    // content in the frame before it is removed.
    if (c != null && _preloading && c.value.isPlaying) {
      unawaited(_safe(c.pause));
    }
  }

  void _onVideoFailed({bool transient = true, Duration? resumeAt}) {
    if (!mounted) return;
    _videoFailed = true;
    _onLoadFailed(transient: transient, resumeAt: resumeAt);
  }

  /// A route fetch or the video failed. A [transient] failure is retried
  /// silently a few times ([_autoRetryDelays]) before the error shows.
  void _onLoadFailed({bool transient = true, Duration? resumeAt}) {
    if (!mounted) return;
    if (resumeAt != null) _resumeAt = resumeAt;
    if (transient && _autoRetries < _autoRetryDelays.length) {
      final delay = _autoRetryDelays[_autoRetries++];
      _retryTimer?.cancel();
      _retryTimer = Timer(delay, () {
        _retryTimer = null;
        if (mounted) _reload();
      });
    }
    setState(() {});
  }

  void _resetRetries() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _autoRetries = 0;
    _resumeAt = null;
  }

  bool _adsActive(ByteDataEntity? data) =>
      (widget.ads?.enabled ?? false) && (data?.adTagUrl.isNotEmpty ?? false);

  Future<void> _resetVideo() async {
    _loadGen++;
    final controller = _controller;
    controller?.removeListener(_onControllerValue);
    // Also clears isAdPlaying, but only if this player is the attached one.
    if (controller != null) _chorki.detach(controller);
    _controller = null;
    _byteData = null;
    _videoFailed = false;
    await _preloader.disposeQuietly(controller);
    if (mounted) setState(() {});
  }

  /// Manual retry (the Retry button, [ChorkiPlayerController.retry]) or a
  /// byte becoming active: a fresh set of silent retries.
  void _retry() {
    _autoRetries = 0;
    _reload();
  }

  /// Reloads the route (bypassing the route cache, in case the video URL it
  /// returned went stale) and the video.
  void _reload() {
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_resetVideo());
    _bloc.add(_loadEvent(refresh: true));
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(
      _safe(controller.value.isPlaying ? controller.pause : controller.play),
    );
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _bloc.close();
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
          unawaited(_startVideo(state.data));
        } else if (state is ByteScreenFailedState) {
          _onLoadFailed();
        }
      },
      child: BlocBuilder<BytesBloc, ByteScreenState>(
        bloc: _bloc,
        builder: (context, state) {
          final body = ColoredBox(
            color: widget.theme.backgroundColor,
            child: _buildBody(state),
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
    if (_retryTimer != null) return _buildLoading(showPoster: true);
    if (state is ByteScreenLoadingState || state is ByteScreenInitialState) {
      return _buildLoading();
    }
    final failed = state is ByteScreenFailedState || _videoFailed;
    // Off screen (or sliding in during a swipe): it retries when it becomes
    // active, so an error view would only flash.
    if (failed && _preloading) return _buildLoading(showPoster: true);
    if (state is ByteScreenFailedState) {
      return _buildError(state.message, _retry);
    }
    if (_videoFailed) {
      return _buildError(widget.strings.videoFailed, _retry);
    }

    final controller = _controller;
    if (controller == null) {
      return _buildLoading(showPoster: true);
    }
    return _buildVideo(controller);
  }

  Widget _buildError(String message, VoidCallback? onRetry) {
    final custom = widget.builders.errorBuilder;
    if (custom != null) return custom(context, message, onRetry);
    return _PlayerErrorView(
      message: message,
      onRetry: onRetry,
      theme: widget.theme,
      icons: widget.icons,
      strings: widget.strings,
    );
  }

  Widget _buildLoading({bool showPoster = false}) {
    final custom = widget.builders.loadingBuilder;
    if (custom != null) return custom(context);
    final poster = _byteData?.thumbnailUrl;
    final hasPoster = showPoster && poster != null && poster.isNotEmpty;

    // StackFit.expand: otherwise the Stack shrinks to the spinner under loose
    // constraints and the poster renders tiny.
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        if (hasPoster)
          Positioned.fill(
            // Same fit as the video, so the poster-to-video handoff is seamless.
            child: ValueListenableBuilder<ChorkiVideoFit>(
              valueListenable: _chorki.fit,
              builder: (context, fit, _) => Image.network(
                poster,
                fit: fit == ChorkiVideoFit.fill ? BoxFit.cover : BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        Center(
          child: SizedBox(
            width: widget.theme.spinnerSize,
            height: widget.theme.spinnerSize,
            child: CircularProgressIndicator(
              color: widget.theme.spinnerColor,
              strokeWidth: widget.theme.spinnerStrokeWidth,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideo(VideoPlayerController controller) {
    final surface = _buildSurface(controller);
    final tag = _byteData?.adTagUrl ?? '';
    final ads = widget.ads;
    // Ads wait until the byte is on screen: while preloading there is no IMA
    // request, no pre-roll and no load timeout.
    if (_preloading || ads == null || !ads.enabled || tag.isEmpty) {
      return surface;
    }
    return ChorkiAdLayer(
      key: ObjectKey(controller),
      controller: controller,
      adTagUrl: tag,
      config: ads,
      autoPlay: widget.autoPlay,
      // The layer outlives a flip back to preload by a frame, when a shared
      // controller may already drive another byte.
      onAdPlayingChanged: (playing) {
        if (!_preloading) _chorki.setAdPlaying(playing);
      },
      child: surface,
    );
  }

  Widget _buildSurface(VideoPlayerController controller) {
    return ChorkiPlayerSurface(
      controller: controller,
      onTogglePlayPause: _togglePlayPause,
      showControls: !_preloading,
      showSeekBar: widget.showSeekBar,
      seekBarBottomOffset: widget.seekBarBottomOffset,
      enableGestures: widget.enableGestures,
      doubleTapSeek: widget.doubleTapSeek,
      longPressSpeed: widget.longPressSpeed,
      chorkiController: _chorki,
      showSettingsButton: widget.showSettingsButton,
      speedOptions: widget.speedOptions,
      theme: widget.theme,
      icons: widget.icons,
      strings: widget.strings,
      builders: widget.builders,
    );
  }
}

class _PlayerErrorView extends StatelessWidget {
  const _PlayerErrorView({
    required this.message,
    required this.theme,
    required this.icons,
    required this.strings,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;
  final ChorkiPlayerTheme theme;
  final ChorkiPlayerIcons icons;
  final ChorkiPlayerStrings strings;

  /// Below this height the stacked message + button can't fit, e.g. a very
  /// wide video with [ChorkiPlayer.sizeToVideo].
  static const double _compactBelowHeight = 160;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.maxHeight < _compactBelowHeight ? _compact() : _full(),
    );
  }

  /// One line, scaled down to whatever space there is.
  Widget _compact() {
    final retry = onRetry;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, maxLines: 1, style: theme.errorTextStyle),
              if (retry != null)
                IconButton(
                  onPressed: retry,
                  tooltip: strings.retry,
                  icon: Icon(icons.refresh, color: theme.iconColor),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _full() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.errorTextStyle,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                style: theme.retryButtonStyle,
                icon: Icon(icons.refresh, color: theme.iconColor),
                label: Text(
                  strings.retry,
                  style: TextStyle(color: theme.iconColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
