import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  FakeVideoPlayerPlatform({
    this.defaultDuration = const Duration(minutes: 2),
    this.defaultSize = const Size(720, 1280),
  });

  final Duration defaultDuration;
  final Size defaultSize;

  final Map<int, FakePlayer> players = {};
  int _nextId = 0;

  final List<(int, Duration)> seekCalls = [];
  final List<(int, double)> speedCalls = [];
  final List<(int, double)> volumeCalls = [];
  final List<int> playCalls = [];
  final List<int> pauseCalls = [];
  int initCalls = 0;

  FakePlayer playerOf(int id) => players[id]!;

  FakePlayer get onlyPlayer => players.values.single;

  void resetLog() {
    seekCalls.clear();
    speedCalls.clear();
    volumeCalls.clear();
    playCalls.clear();
    pauseCalls.clear();
  }

  @override
  Future<void> init() async {
    initCalls++;
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    return _create();
  }

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    return _create();
  }

  int _create() {
    final id = _nextId++;
    final player = FakePlayer(id, duration: defaultDuration, size: defaultSize);
    players[id] = player;
    scheduleMicrotask(player.emitInitialized);
    return id;
  }

  @override
  Future<void> dispose(int playerId) async {
    players.remove(playerId);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    return playerOf(playerId).events.stream;
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {
    playCalls.add(playerId);
    playerOf(playerId).isPlaying = true;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls.add(playerId);
    playerOf(playerId).isPlaying = false;
  }

  @override
  Future<void> setVolume(int playerId, double volume) async {
    volumeCalls.add((playerId, volume));
    playerOf(playerId).volume = volume;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seekCalls.add((playerId, position));
    playerOf(playerId).position = position;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {
    speedCalls.add((playerId, speed));
    playerOf(playerId).speed = speed;
  }

  @override
  Future<Duration> getPosition(int playerId) async {
    return playerOf(playerId).position;
  }

  @override
  Widget buildView(int playerId) {
    return SizedBox(key: Key('fake_video_view_$playerId'));
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) {
    return const SizedBox.shrink();
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

class FakePlayer {
  FakePlayer(this.id, {required this.duration, required this.size});

  final int id;
  final Duration duration;
  final Size size;

  final StreamController<VideoEvent> events = StreamController();

  Duration position = Duration.zero;
  bool isPlaying = false;
  double speed = 1.0;
  double volume = 1.0;

  void emitInitialized() {
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: duration,
        size: size,
      ),
    );
  }

  void emitBufferingStart() =>
      events.add(VideoEvent(eventType: VideoEventType.bufferingStart));

  void emitBufferingEnd() =>
      events.add(VideoEvent(eventType: VideoEventType.bufferingEnd));

  void emitBuffered(Duration through) {
    events.add(
      VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered: [DurationRange(Duration.zero, through)],
      ),
    );
  }
}

Future<VideoPlayerController> createTestController(
  FakeVideoPlayerPlatform platform,
) async {
  final controller = VideoPlayerController.networkUrl(
    Uri.parse('https://test.local/video.mp4'),
  );
  await controller.initialize();
  return controller;
}
