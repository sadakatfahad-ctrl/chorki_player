import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'test_videos.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chorki Player Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const CatalogPage(),
    );
  }
}

bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Lists every test video, grouped by source.
class CatalogPage extends StatelessWidget {
  const CatalogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chorki Player test videos')),
      body: ListView(
        children: [
          for (final group in testVideoGroups) ...[
            ListTile(
              title: Text(
                group.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(group.description),
            ),
            for (final video in group.videos) _VideoTile(video: video),
            const Divider(),
          ],
        ],
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.video});

  final TestVideo video;

  @override
  Widget build(BuildContext context) {
    final blocked = video.androidOnly && _isIos;
    final details = [
      video.sizeLabel,
      if (video.note.isNotEmpty) video.note,
      if (blocked) 'Android only: WebM does not play on iOS',
    ].where((s) => s.isNotEmpty).join(' · ');
    return ListTile(
      enabled: !blocked,
      leading: _RatioBadge(video: video),
      title: Text(video.title),
      subtitle: details.isEmpty ? null : Text(details),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => PlayerPage(video: video))),
    );
  }
}

/// Small outline drawn in the video's shape, with the ratio as text.
class _RatioBadge extends StatelessWidget {
  const _RatioBadge({required this.video});

  final TestVideo video;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    const box = 40.0;
    var w = box, h = box;
    if (video.hasSize) {
      final ratio = video.width / video.height;
      if (ratio >= 1) {
        h = (box / ratio).clamp(2, box);
      } else {
        w = (box * ratio).clamp(2, box);
      }
    }
    return SizedBox(
      width: 56,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: box,
            child: Center(
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 1.5),
                ),
              ),
            ),
          ),
          Text(
            video.ratio,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// How the player is placed on the page.
enum PlayerLayout {
  fill('Fill'),
  box16x9('16:9 box'),
  box9x16('9:16 box'),
  sizeToVideo('Size to video');

  const PlayerLayout(this.label);

  final String label;
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.video});

  final TestVideo video;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final ChorkiPlayerController _controller = ChorkiPlayerController();

  // Keeps the player (and its loaded video) alive when the layout changes.
  final GlobalKey _playerKey = GlobalKey();

  PlayerLayout _layout = PlayerLayout.fill;

  @override
  void initState() {
    super.initState();
    // Android: shrink into PiP when the user presses Home.
    _controller.setAutoPip(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _player({required bool sizeToVideo}) {
    final video = widget.video;
    final route = video.route;
    if (route != null) {
      return ChorkiPlayer(
        key: _playerKey,
        route: route,
        controller: _controller,
        sizeToVideo: sizeToVideo,
        mediaOptions: const ChorkiMediaOptions(
          startPosition: Duration(seconds: 5),
          backBuffer: Duration(seconds: 30),
        ),
        longPressSpeed: 3.0,
        theme: const ChorkiPlayerTheme(
          seekBarPlayedColor: Colors.red,
          seekBarBufferedColor: Colors.grey,
          seekBarThumbColor: Colors.deepOrange,
        ),
        seekBarBottomOffset: 20,
        ads: const ChorkiAdConfig(),
      );
    }
    return ChorkiPlayer.url(
      video.url!,
      key: _playerKey,
      controller: _controller,
      sizeToVideo: sizeToVideo,
      placeholderAspectRatio: video.hasSize
          ? video.width / video.height
          : 16 / 9,
      mediaOptions: ChorkiMediaOptions(httpHeaders: video.headers),
      seekBarBottomOffset: 20,
    );
  }

  Widget _framed(double aspectRatio) {
    // The white outline is the box the app gives the player.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54),
            ),
            child: _player(sizeToVideo: false),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return switch (_layout) {
      PlayerLayout.fill => _player(sizeToVideo: false),
      PlayerLayout.box16x9 => _framed(16 / 9),
      PlayerLayout.box9x16 => _framed(9 / 16),
      PlayerLayout.sizeToVideo => ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          const _ListFiller('Content above the player'),
          _player(sizeToVideo: true),
          const _ListFiller('Content below the player'),
        ],
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: const Color(0xFF202020),
      appBar: AppBar(title: Text(widget.video.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: SegmentedButton<PlayerLayout>(
              showSelectedIcon: false,
              segments: [
                for (final l in PlayerLayout.values)
                  ButtonSegment(value: l, label: Text(l.label)),
              ],
              selected: {_layout},
              onSelectionChanged: (s) => setState(() => _layout = s.single),
            ),
          ),
          _VideoInfo(video: widget.video, controller: _controller),
          Expanded(child: _body()),
          _ControlsRow(controller: _controller),
        ],
      ),
    );

    // In PiP the whole app is shrunk, so render the player alone.
    return ValueListenableBuilder<ChorkiPipStatus>(
      valueListenable: _controller.pipStatus,
      builder: (context, pip, _) {
        if (pip == ChorkiPipStatus.enabled) {
          return ColoredBox(
            color: Colors.black,
            child: _player(sizeToVideo: false),
          );
        }
        return page;
      },
    );
  }
}

class _ListFiller extends StatelessWidget {
  const _ListFiller(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.center,
      color: Colors.white10,
      child: Text(text),
    );
  }
}

/// Expected shape next to what the player actually reports.
class _VideoInfo extends StatelessWidget {
  const _VideoInfo({required this.video, required this.controller});

  final TestVideo video;
  final ChorkiPlayerController controller;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ValueListenableBuilder(
        valueListenable: controller.value,
        builder: (context, value, _) {
          final expected = video.hasSize
              ? 'Expected ${video.ratio} (${video.sizeLabel})'
              : 'Expected: from API';
          final reported = value.isInitialized
              ? 'Reported ${value.size.width.toInt()}×'
                    '${value.size.height.toInt()} '
                    '(ratio ${value.aspectRatio.toStringAsFixed(3)}'
                    '${value.rotationCorrection != 0 ? ', rotation ${value.rotationCorrection}°' : ''})'
              : 'Reported: loading…';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$expected · $reported', style: style),
              if (video.note.isNotEmpty) Text(video.note, style: style),
              if (video.credit.isNotEmpty)
                Text(
                  video.credit,
                  style: style?.copyWith(color: Colors.white54),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.controller});

  final ChorkiPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          controller.speed,
          controller.fit,
          controller.videoTracks,
          controller.selectedVideoTrack,
          controller.pipStatus,
        ]),
        builder: (context, _) {
          final selected = controller.selectedVideoTrack.value;
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.replay_10),
                onPressed: controller.seekBack,
              ),
              IconButton(
                color: Colors.white,
                icon: const Icon(Icons.forward_10),
                onPressed: controller.seekForward,
              ),
              TextButton(
                onPressed: () => controller.setSpeed(
                  controller.speed.value >= 2
                      ? 1
                      : controller.speed.value + 0.5,
                ),
                child: Text('${controller.speed.value}x'),
              ),
              TextButton(
                onPressed: controller.toggleFit,
                child: Text(controller.fit.value.name.toUpperCase()),
              ),
              TextButton(
                onPressed: () => showChorkiSettings(context, controller),
                child: Text(
                  selected?.height != null ? '${selected!.height}p' : 'Auto',
                ),
              ),
              if (controller.isPipAvailable)
                IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.picture_in_picture_alt),
                  onPressed: controller.enterPip,
                ),
            ],
          );
        },
      ),
    );
  }
}
