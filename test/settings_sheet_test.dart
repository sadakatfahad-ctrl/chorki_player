import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as pi;

import 'fakes/fake_pip_delegate.dart';
import 'fakes/fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform platform;
  late FakePipDelegate pip;
  late ChorkiPlayerController chorki;
  late VideoPlayerController video;

  setUp(() {
    platform = FakeVideoPlayerPlatform()
      ..videoTracks = const [
        pi.VideoTrack(id: 'low', isSelected: false, height: 480),
        pi.VideoTrack(id: 'hi', isSelected: true, height: 1080),
        pi.VideoTrack(id: 'mid', isSelected: false, height: 720),
      ]
      ..audioTracks = const [
        pi.VideoAudioTrack(
          id: 'a1',
          label: 'English',
          language: 'en',
          isSelected: true,
        ),
      ];
    pi.VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    pip = FakePipDelegate();
    chorki = ChorkiPlayerController(pipDelegate: pip);
  });

  Future<void> pumpSurface(WidgetTester tester) async {
    await tester.runAsync(() async {
      video = await createTestController(platform);
      chorki.attach(video);
      await pumpEventQueue();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: ChorkiPlayerSurface(
              controller: video,
              onTogglePlayPause: () {},
              chorkiController: chorki,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    chorki.dispose();
    await tester.runAsync(video.dispose);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('chorki_settings_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('sheet lists quality, speed, fit, PiP; hides single audio', (
    tester,
  ) async {
    await pumpSurface(tester);
    await openSheet(tester);

    expect(find.byKey(const Key('chorki_settings_quality')), findsOneWidget);
    expect(find.byKey(const Key('chorki_settings_audio')), findsNothing);
    expect(find.byKey(const Key('chorki_settings_speed')), findsOneWidget);
    expect(find.byKey(const Key('chorki_settings_fit')), findsOneWidget);
    expect(find.byKey(const Key('chorki_settings_pip')), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('quality list is sorted and selecting calls the platform', (
    tester,
  ) async {
    await pumpSurface(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('chorki_settings_quality')));
    await tester.pumpAndSettle();

    final labels = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text?)?.data)
        .toList();
    expect(labels, ['Quality', 'Auto', '1080p', '720p', '480p']);

    await tester.tap(find.byKey(const Key('chorki_quality_mid')));
    await tester.pumpAndSettle();
    expect(platform.videoTrackCalls.single.$2?.id, 'mid');
    expect(chorki.selectedVideoTrack.value?.id, 'mid');
    // Back on the root page with the new value.
    expect(find.text('720p'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('speed menu sets the speed', (tester) async {
    await pumpSurface(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('chorki_settings_speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chorki_speed_1.5')));
    await tester.pumpAndSettle();

    expect(chorki.speed.value, 1.5);
    expect(video.value.playbackSpeed, 1.5);
    expect(find.text('1.5x'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('fit row toggles the video box fit', (tester) async {
    await pumpSurface(tester);
    BoxFit fit() =>
        tester.widget<FittedBox>(find.byKey(const Key('chorki_video_fit'))).fit;
    expect(fit(), BoxFit.contain);

    await openSheet(tester);
    await tester.tap(find.byKey(const Key('chorki_settings_fit')));
    await tester.pumpAndSettle();
    expect(chorki.fit.value, ChorkiVideoFit.fill);
    expect(fit(), BoxFit.cover);
    await cleanUp(tester);
  });

  testWidgets('audio row appears with several tracks', (tester) async {
    platform.audioTracks = const [
      pi.VideoAudioTrack(
        id: 'a1',
        label: 'English',
        language: 'en',
        isSelected: true,
      ),
      pi.VideoAudioTrack(
        id: 'a2',
        label: 'Bangla',
        language: 'bn',
        isSelected: false,
      ),
    ];
    await pumpSurface(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('chorki_settings_audio')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chorki_audio_a2')));
    await tester.pumpAndSettle();
    expect(platform.audioTrackCalls.single.$2, 'a2');
    expect(find.text('Bangla'), findsOneWidget);
    await cleanUp(tester);
  });

  testWidgets('PiP row enters PiP and closes the sheet', (tester) async {
    await pumpSurface(tester);
    await openSheet(tester);
    await tester.tap(find.byKey(const Key('chorki_settings_pip')));
    await tester.pumpAndSettle();
    expect(pip.enterCalls, hasLength(1));
    expect(find.byKey(const Key('chorki_settings_speed')), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await cleanUp(tester);
  });

  testWidgets('in PiP the surface shows only the video', (tester) async {
    await pumpSurface(tester);
    expect(find.byKey(const Key('chorki_settings_button')), findsOneWidget);
    expect(find.byType(ShortsSeekBar), findsOneWidget);

    await chorki.enterPip();
    await tester.pump();
    expect(find.byKey(const Key('chorki_settings_button')), findsNothing);
    expect(find.byType(ShortsSeekBar), findsNothing);
    expect(find.byType(PlayerGestureOverlay), findsNothing);
    expect(find.byKey(const Key('chorki_video_fit')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await cleanUp(tester);
  });

  testWidgets('entering PiP mid-scrub still resumes playback on release', (
    tester,
  ) async {
    await pumpSurface(tester);
    await video.play();
    await tester.pump();

    final gesture = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(video.value.isPlaying, isFalse); // paused by the scrub

    await chorki.enterPip();
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(video.value.isPlaying, isTrue);
    await video.pause();
    await tester.pump(const Duration(seconds: 2));
    await cleanUp(tester);
  });

  testWidgets('no settings button without a chorkiController', (tester) async {
    await tester.runAsync(() async {
      video = await createTestController(platform);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChorkiPlayerSurface(controller: video, onTogglePlayPause: () {}),
      ),
    );
    expect(find.byKey(const Key('chorki_settings_button')), findsNothing);
    await cleanUp(tester);
  });

  testWidgets(
    'settingsButtonBuilder and qualityLabelBuilder override defaults',
    (tester) async {
      await tester.runAsync(() async {
        video = await createTestController(platform);
        chorki.attach(video);
        await pumpEventQueue();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChorkiPlayerSurface(
              controller: video,
              onTogglePlayPause: () {},
              chorkiController: chorki,
              builders: ChorkiPlayerBuilders(
                settingsButtonBuilder: (ctx, open) => TextButton(
                  key: const Key('custom_gear'),
                  onPressed: open,
                  child: const Text('gear'),
                ),
                qualityLabelBuilder: (t) => 'Q${t.height}',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('custom_gear')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chorki_settings_quality')));
      await tester.pumpAndSettle();
      expect(find.text('Q1080'), findsOneWidget);
      await cleanUp(tester);
    },
  );

  test('defaultQualityLabel adds bitrate on height ties', () {
    const a = VideoTrack(
      id: 'a',
      isSelected: false,
      height: 720,
      bitrate: 1500000,
    );
    const b = VideoTrack(
      id: 'b',
      isSelected: false,
      height: 720,
      bitrate: 800000,
    );
    const c = VideoTrack(id: 'c', isSelected: false, height: 1080);
    const d = VideoTrack(id: 'd', isSelected: false, label: 'Audio only');
    final all = [a, b, c, d];
    expect(defaultQualityLabel(a, all), '720p · 1.5 Mbps');
    expect(defaultQualityLabel(b, all), '720p · 800 kbps');
    expect(defaultQualityLabel(c, all), '1080p');
    expect(defaultQualityLabel(d, all), 'Audio only');
  });
}
