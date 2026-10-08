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

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});
  //https://admin-bytes-stage.chorki.net/v1/bytes/butes1
  //https://admin-bytes-stage.chorki.net/v1/videos/test-2
  static const String byteRoute =
      'https://admin-bytes-stage.chorki.net/v1/bytes/butes1';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Chorki Player')),
      body: Center(
        child: ChorkiPlayer(
          route: byteRoute,
          enableGestures: true,
          longPressSpeed: 3.0,
          theme: const ChorkiPlayerTheme(
            seekBarPlayedColor: Colors.red,
            seekBarBufferedColor: Colors.grey,
            seekBarThumbColor: Colors.deepOrange,
          ),
          seekBarBottomOffset: 20,
          ads: const ChorkiAdConfig(),
        ),
      ),
    );
  }
}
