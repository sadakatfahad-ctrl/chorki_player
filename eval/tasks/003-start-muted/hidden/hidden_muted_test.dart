import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;

import '../fakes/fake_video_player_platform.dart';

void main() {
  testWidgets('muted starts at volume 0 without a volumeChange; unmuting '
      'restores 1 and is reported', (tester) async {
    final platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final sink = MemoryAnalyticsSink();
    final analytics = ChorkiAnalyticsConfig(
      sinks: [sink],
      heartbeatInterval: const Duration(hours: 1),
    );
    Widget player(bool muted) => MaterialApp(
      home: ChorkiPlayer.url(
        'https://test.local/a.mp4',
        muted: muted,
        analytics: analytics,
      ),
    );
    await tester.pumpWidget(player(true));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(platform.volumeCalls.last.$2, 0);
    expect(sink.types, isNot(contains(ChorkiAnalyticsEventType.volumeChange)));

    await tester.pumpWidget(player(false));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(platform.volumeCalls.last.$2, 1);
    expect(sink.types, contains(ChorkiAnalyticsEventType.volumeChange));
    await tester.pumpWidget(const SizedBox());
  });
}
