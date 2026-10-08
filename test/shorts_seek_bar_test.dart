import 'package:chorki_player/src/presentation/widgets/shorts_seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fakes/fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform platform;
  late VideoPlayerController controller;

  setUp(() async {
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    controller = await createTestController(platform);
  });

  tearDown(() async {
    await controller.dispose();
  });

  Future<void> pumpBar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(child: ShortsSeekBar(controller: controller)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> dragBy(
    WidgetTester tester,
    TestGesture gesture,
    double dx, {
    int steps = 10,
  }) async {
    final step = Offset(dx / steps, 0);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(step);
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> stopPlayback() async {
    if (controller.value.isPlaying) {
      await controller.pause();
    }
  }

  group('ShortsSeekBar regression: pointer visibility', () {
    testWidgets('shows an always-visible pointer at rest '
        '(bug: thumb only rendered while dragging)', (tester) async {
      await pumpBar(tester);

      expect(find.byKey(const Key('chorki_seek_bar_pointer')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const Key('chorki_seek_bar_pointer'))).dx,
        closeTo(8, 1.0),
      );
    });

    testWidgets('pointer tracks the playhead fraction', (tester) async {
      await pumpBar(tester);

      await controller.seekTo(const Duration(seconds: 60));
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        tester.getCenter(find.byKey(const Key('chorki_seek_bar_pointer'))).dx,
        closeTo(400, 1.5),
      );
    });

    testWidgets('pointer sits at the far end at the end of the video', (
      tester,
    ) async {
      await pumpBar(tester);

      await controller.seekTo(controller.value.duration);
      await tester.pump(const Duration(milliseconds: 700));

      expect(
        tester.getCenter(find.byKey(const Key('chorki_seek_bar_pointer'))).dx,
        closeTo(792, 1.5),
      );
    });
  });

  group('ShortsSeekBar tap-to-seek', () {
    testWidgets('tapping the middle of the bar seeks to ~50%', (tester) async {
      await pumpBar(tester);

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      await tester.tapAt(Offset(400, trackCenter.dy));
      await tester.pump();

      final (_, position) = platform.seekCalls.single;
      expect(position.inSeconds, closeTo(60, 1));
    });

    testWidgets('tapping near the right edge seeks close to the end', (
      tester,
    ) async {
      await pumpBar(tester);

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      await tester.tapAt(Offset(780, trackCenter.dy));
      await tester.pump();

      final (_, position) = platform.seekCalls.single;
      expect(position.inSeconds, inInclusiveRange(117, 119));
    });
  });

  group('ShortsSeekBar drag scrubbing', () {
    testWidgets('dragging pauses, seeks proportionally, and resumes', (
      tester,
    ) async {
      await pumpBar(tester);
      await controller.play();
      await tester.pump();
      platform.resetLog();
      final id = platform.onlyPlayer.id;

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );

      final gesture = await tester.startGesture(trackCenter);
      await tester.pump();
      await dragBy(tester, gesture, 200);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final (_, position) = platform.seekCalls.last;
      expect(position.inSeconds, inInclusiveRange(89, 92));

      expect(platform.pauseCalls, contains(id));
      expect(platform.playCalls.where((c) => c == id).length, greaterThan(0));
      expect(controller.value.isPlaying, isTrue);
      await stopPlayback();
    });

    testWidgets('scrub started while paused stays paused afterwards', (
      tester,
    ) async {
      await pumpBar(tester);
      expect(controller.value.isPlaying, isFalse);
      platform.resetLog();

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      final gesture = await tester.startGesture(trackCenter);
      await tester.pump();
      await dragBy(tester, gesture, 100);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(platform.seekCalls, isNotEmpty);
      expect(platform.playCalls, isEmpty);
      expect(controller.value.isPlaying, isFalse);
    });

    testWidgets('dragging cannot seek outside [0, duration]', (tester) async {
      await pumpBar(tester);
      platform.resetLog();

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );

      var gesture = await tester.startGesture(trackCenter);
      await tester.pump();
      await dragBy(tester, gesture, -500);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(platform.seekCalls.where((c) => c.$2 != Duration.zero), isEmpty);

      gesture = await tester.startGesture(trackCenter);
      await tester.pump();
      await dragBy(tester, gesture, 1200);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(platform.seekCalls.last.$2, controller.value.duration);
    });

    testWidgets('time preview bubble appears only while dragging', (
      tester,
    ) async {
      await pumpBar(tester);
      expect(find.text('1:30'), findsNothing);

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      final gesture = await tester.startGesture(trackCenter);
      await tester.pump();
      await dragBy(tester, gesture, 196);
      await tester.pump();

      expect(find.text('1:30'), findsOneWidget);

      await gesture.up();
      await tester.pump();
      expect(find.text('1:30'), findsNothing);
    });
  });

  group('ShortsSeekBar buffered indicator', () {
    testWidgets('renders a buffered tint when ranges arrive', (tester) async {
      await pumpBar(tester);
      platform.onlyPlayer.emitBuffered(const Duration(seconds: 80));
      await tester.pump();

      expect(find.byKey(const Key('chorki_seek_bar_buffered')), findsOneWidget);
    });
  });

  group('ShortsSeekBar controller swap safety', () {
    testWidgets('replacing the controller mid-drag does not seek the new one '
        '(bug: stale drag state drove the recycled controller)', (
      tester,
    ) async {
      await pumpBar(tester);
      platform.resetLog();

      final trackCenter = tester.getCenter(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      final gesture = await tester.startGesture(trackCenter);
      await tester.pump();
      await dragBy(tester, gesture, 200);
      await tester.pump();

      final secondController = VideoPlayerController.networkUrl(
        Uri.parse('https://test.local/video2.mp4'),
      );
      await tester.runAsync(() => secondController.initialize());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(
              child: ShortsSeekBar(controller: secondController),
            ),
          ),
        ),
      );
      await tester.pump();

      await gesture.up();
      await tester.pump();
      expect(secondController.value.position, Duration.zero);
      expect(
        platform.seekCalls.where((c) => c.$1 == secondController.playerId),
        isEmpty,
      );

      await tester.runAsync(() => secondController.dispose());
    });
  });
}
