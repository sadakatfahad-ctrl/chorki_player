import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});
  //https://admin-bytes-stage.chorki.net/v1/bytes/butes1
  //https://admin-bytes-stage.chorki.net/v1/videos/test-2
  static const String byteRoute =
      'https://admin-bytes-stage.chorki.net/v1/bytes/butes1';

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final ChorkiPlayerController _controller = ChorkiPlayerController();

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

  @override
  Widget build(BuildContext context) {
    final player = ChorkiPlayer(
      route: PlayerPage.byteRoute,
      controller: _controller,
      mediaOptions: const ChorkiMediaOptions(
        startPosition: Duration(seconds: 5),
        backBuffer: Duration(seconds: 30),
      ),
      enableGestures: true,
      longPressSpeed: 3.0,
      theme: const ChorkiPlayerTheme(
        seekBarPlayedColor: Colors.red,
        seekBarBufferedColor: Colors.grey,
        seekBarThumbColor: Colors.deepOrange,
      ),
      seekBarBottomOffset: 20,
      ads: const ChorkiAdConfig(),
    );

    // In PiP the whole app is shrunk, so render the player alone.
    return ValueListenableBuilder<ChorkiPipStatus>(
      valueListenable: _controller.pipStatus,
      builder: (context, pip, _) {
        if (pip == ChorkiPipStatus.enabled) {
          return ColoredBox(color: Colors.black, child: player);
        }
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(title: const Text('Chorki Player')),
          body: Column(
            children: [
              Expanded(child: player),
              _ControlsRow(controller: _controller),
            ],
          ),
        );
      },
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
