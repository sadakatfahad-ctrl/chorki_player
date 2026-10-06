import 'dart:async';

import 'package:chorki_player/src/controllers/video_preloader.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/injection_container.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:chorki_player/src/presentation/bytes_screen/bytes_screen_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:video_player/video_player.dart';

class ChorkiPlayer extends StatefulWidget {
  const ChorkiPlayer({
    super.key,
    required this.route,
    this.autoPlay = true,
    this.looping = true,
  });

  final String route;

  final bool autoPlay;

  final bool looping;

  @override
  State<ChorkiPlayer> createState() => _ChorkiPlayerState();
}

class _ChorkiPlayerState extends State<ChorkiPlayer> {
  final VideoPreloader _preloader = VideoPreloader();

  late final BytesBloc _bloc;

  VideoPlayerController? _controller;
  ByteDataEntity? _byteData;
  bool _videoFailed = false;

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
    if (byteData.url.isEmpty) {
      if (mounted) setState(() => _videoFailed = true);
      return;
    }

    final controller = await _preloader.load(Uri.parse(byteData.url));

    if (!mounted) {
      await _preloader.disposeQuietly(controller);
      return;
    }

    if (controller == null) {
      setState(() => _videoFailed = true);
      return;
    }

    final previous = _controller;
    previous?.removeListener(_onVideoUpdate);
    unawaited(_preloader.disposeQuietly(previous));

    controller
      ..setLooping(widget.looping)
      ..addListener(_onVideoUpdate);
    if (widget.autoPlay) {
      unawaited(controller.play());
    }

    setState(() {
      _controller = controller;
      _videoFailed = false;
    });
  }

  void _onVideoUpdate() => setState(() {});

  Future<void> _resetVideo() async {
    final controller = _controller;
    controller?.removeListener(_onVideoUpdate);
    _controller = null;
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
    final controller = _controller;
    controller?.removeListener(_onVideoUpdate);
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
          return ColoredBox(color: Colors.black, child: _buildBody(state));
        },
      ),
    );
  }

  Widget _buildBody(ByteScreenState state) {
    if (state is ByteScreenLoadingState || state is ByteScreenInitialState) {
      return _buildLoading();
    }
    if (state is ByteScreenFailedState) {
      return _PlayerErrorView(message: state.message, onRetry: _retry);
    }
    if (_videoFailed) {
      return const _PlayerErrorView(message: 'Video failed to play');
    }

    final controller = _controller;
    if (controller == null) {
      return _buildLoading(showPoster: true);
    }
    return _buildVideo(controller);
  }

  Widget _buildLoading({bool showPoster = false}) {
    final poster = _byteData?.thumbnailUrl;
    final hasPoster = showPoster && poster != null && poster.isNotEmpty;

    return Stack(
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
        const CircularProgressIndicator(color: Colors.white),
      ],
    );
  }

  Widget _buildVideo(VideoPlayerController controller) {
    final size = controller.value.size;

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
          if (!controller.value.isPlaying) _buildPlayBadge(),
        ],
      ),
    );
  }

  Widget _buildPlayBadge() {
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.play_arrow, size: 48, color: Colors.white),
      ),
    );
  }
}

class _PlayerErrorView extends StatelessWidget {
  const _PlayerErrorView({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

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
              style: const TextStyle(color: Colors.white70),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
