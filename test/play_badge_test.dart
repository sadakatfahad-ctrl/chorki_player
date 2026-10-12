import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as pi;

import 'fakes/fake_video_player_platform.dart';

void main() {
  testWidgets('tapping the center play badge toggles play/pause', (
    tester,
  ) async {
    final platform = FakeVideoPlayerPlatform();
    pi.VideoPlayerPlatform.instance = platform;
    var toggles = 0;
    late final dynamic video;
    await tester.runAsync(() async {
      video = await createTestController(platform);
      await pumpEventQueue();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChorkiPlayerSurface(
              controller: video,
              onTogglePlayPause: () => toggles++,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump(const Duration(milliseconds: 400));
    expect(toggles, 1);
  });
}
