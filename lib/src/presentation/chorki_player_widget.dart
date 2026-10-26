import 'dart:async';

import 'package:chorki_player/src/ads/chorki_ad_config.dart';
import 'package:chorki_player/src/ads/chorki_ad_layer.dart';
import 'package:chorki_player/src/controllers/chorki_player_controller.dart';
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

  @override
  void initState() {
    super.initState();
    initChorkiPlayer();
    _bloc = BytesBloc(getByteDataUsecase: getIt<BytesUsecase>())
      ..add(_loadEvent());
  }

  ByteScreenEvent _loadEvent() {
    final url = widget.videoUrl;
    if (url == null) return ByteScreenInitialEvent(widget.route);
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
      old?.detach(_controller);
      old?.setAdPlaying(false);
      if (widget.controller != null) {
        _ownController?.dispose();
        _ownController = null;
      }
      final c = _controller;
      if (c != null) _chorki.attach(c, onRetry: _retry);
    }
    if (oldWidget.route != widget.route ||
        oldWidget.videoUrl != widget.videoUrl ||
        oldWidget.posterUrl != widget.posterUrl ||
        oldWidget.adTagUrl != widget.adTagUrl) {
      unawaited(_resetVideo());
      _bloc.add(_loadEvent());
    } else if (oldWidget.looping != widget.looping) {
      final c = _controller;
      if (c != null) unawaited(_safe(() => c.setLooping(widget.looping)));
    }
  }

  Future<void> _safe(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {}
  }

  Future<void> _startVideo(ByteDataEntity byteData) async {
    try {
      await _loadVideo(byteData);
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  Future<void> _loadVideo(ByteDataEntity byteData) async {
    final gen = ++_loadGen;
    if (byteData.url.isEmpty) {
      if (mounted) setState(() => _videoFailed = true);
      return;
    }

    final controller = await _preloader.load(
      Uri.parse(byteData.url),
      options: widget.mediaOptions,
    );

    if (!mounted || gen != _loadGen) {
      await _preloader.disposeQuietly(controller);
      return;
    }

    if (controller == null) {
      setState(() => _videoFailed = true);
      return;
    }

    final previous = _controller;
    previous?.removeListener(_onControllerValue);
    if (previous != null) _chorki.detach(previous);
    unawaited(_preloader.disposeQuietly(previous));
    controller.addListener(_onControllerValue);
    _chorki.attach(controller, onRetry: _retry);

    unawaited(_safe(() => controller.setLooping(widget.looping)));
    if (widget.autoPlay && !_adsActive(byteData)) {
      unawaited(_safe(controller.play));
    }

    setState(() {
      _controller = controller;
      _videoFailed = false;
    });
  }

  void _onControllerValue() {
    final c = _controller;
    if (c != null && c.value.hasError && !_videoFailed && mounted) {
      setState(() => _videoFailed = true);
    }
  }

  bool _adsActive(ByteDataEntity? data) =>
      (widget.ads?.enabled ?? false) && (data?.adTagUrl.isNotEmpty ?? false);

  Future<void> _resetVideo() async {
    _loadGen++;
    final controller = _controller;
    controller?.removeListener(_onControllerValue);
    if (controller != null) _chorki.detach(controller);
    _chorki.setAdPlaying(false);
    _controller = null;
    _byteData = null;
    _videoFailed = false;
    await _preloader.disposeQuietly(controller);
    if (mounted) setState(() {});
  }

  void _retry() {
    unawaited(_resetVideo());
    _bloc.add(_loadEvent());
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
    _bloc.close();
    _loadGen++;
    final controller = _controller;
    controller?.removeListener(_onControllerValue);
    if (controller != null) widget.controller?.detach(controller);
    widget.controller?.setAdPlaying(false);
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
    if (state is ByteScreenLoadingState || state is ByteScreenInitialState) {
      return _buildLoading();
    }
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
    if (ads == null || !ads.enabled || tag.isEmpty) return surface;
    return ChorkiAdLayer(
      key: ObjectKey(controller),
      controller: controller,
      adTagUrl: tag,
      config: ads,
      autoPlay: widget.autoPlay,
      onAdPlayingChanged: _chorki.setAdPlaying,
      child: surface,
    );
  }

  Widget _buildSurface(VideoPlayerController controller) {
    return ChorkiPlayerSurface(
      controller: controller,
      onTogglePlayPause: _togglePlayPause,
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
