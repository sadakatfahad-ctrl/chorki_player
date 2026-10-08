import 'dart:async';

import 'package:chorki_player/src/ads/chorki_ad_config.dart';
import 'package:chorki_player/src/ads/chorki_ad_layer.dart';
import 'package:chorki_player/src/controllers/video_preloader.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/injection_container.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:chorki_player/src/presentation/bytes_screen/bytes_screen_bloc.dart';
import 'package:chorki_player/src/presentation/widgets/chorki_player_surface.dart';
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
  }) : assert(seekBarBottomOffset >= 0);

  final String route;

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

  @override
  State<ChorkiPlayer> createState() => _ChorkiPlayerState();
}

class _ChorkiPlayerState extends State<ChorkiPlayer> {
  late final VideoPreloader _preloader = VideoPreloader(
    initTimeout: widget.initTimeout,
  );

  late final BytesBloc _bloc;

  VideoPlayerController? _controller;
  ByteDataEntity? _byteData;
  bool _videoFailed = false;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    initChorkiPlayer();
    _bloc = BytesBloc(getByteDataUsecase: getIt<BytesUsecase>())
      ..add(ByteScreenInitialEvent(widget.route));
  }

  @override
  void didUpdateWidget(covariant ChorkiPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) {
      unawaited(_resetVideo());
      _bloc.add(ByteScreenInitialEvent(widget.route));
    } else if (oldWidget.looping != widget.looping) {
      _controller?.setLooping(widget.looping);
    }
  }

  Future<void> _startVideo(ByteDataEntity byteData) async {
    final gen = ++_loadGen;
    if (byteData.url.isEmpty) {
      if (mounted) setState(() => _videoFailed = true);
      return;
    }

    final controller = await _preloader.load(Uri.parse(byteData.url));

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
    unawaited(_preloader.disposeQuietly(previous));
    controller.addListener(_onControllerValue);

    controller.setLooping(widget.looping);
    if (widget.autoPlay && !_adsActive(byteData)) {
      unawaited(controller.play());
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
    _controller = null;
    _byteData = null;
    _videoFailed = false;
    await _preloader.disposeQuietly(controller);
    if (mounted) setState(() {});
  }

  void _retry() {
    unawaited(_resetVideo());
    _bloc.add(ByteScreenInitialEvent(widget.route));
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  @override
  void dispose() {
    _bloc.close();
    _loadGen++;
    final controller = _controller;
    controller?.removeListener(_onControllerValue);
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
          return ColoredBox(
            color: widget.theme.backgroundColor,
            child: _buildBody(state),
          );
        },
      ),
    );
  }

  Widget _buildBody(ByteScreenState state) {
    if (state is ByteScreenLoadingState || state is ByteScreenInitialState) {
      return _buildLoading();
    }
    if (state is ByteScreenFailedState) {
      return _buildError(state.message, _retry);
    }
    if (_videoFailed) {
      return _buildError(widget.strings.videoFailed, null);
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
            child: Image.network(
              poster,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
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

  @override
  Widget build(BuildContext context) {
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
