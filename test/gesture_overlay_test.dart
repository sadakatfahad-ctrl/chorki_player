import 'package:chorki_player/src/presentation/widgets/gesture_overlay.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fakes/fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform platform;
  late VideoPlayerController controller;
  late List<bool> gestureActivityLog;

  setUp(() async {
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    controller = await createTestController(platform);
    gestureActivityLog = [];
  });

  tearDown(() async {
    await controller.dispose();
  });

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SizedBox.expand(
            child: PlayerGestureOverlay(
              controller: controller,
              onTogglePlayPause: () => controller.value.isPlaying
                  ? controller.pause()
                  : controller.play(),
              onGesturesActiveChanged: gestureActivityLog.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    platform.resetLog();
  }

  /// Drags horizontally in small increments so the drag recognizer emits
  /// update events (a single huge move is swallowed by slop acceptance).
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

  /// Flushes the 800ms double-tap accumulation window so no timers are
  /// pending at test end.
  Future<void> settleAfterGesture(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 900));
    if (controller.value.isPlaying) {
      await controller.pause();
    }
  }

  group('tap', () {
    testWidgets('single tap toggles play/pause', (tester) async {
      await pumpOverlay(tester);

      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(platform.playCalls, hasLength(1));
      expect(platform.pauseCalls, isEmpty);

      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(platform.pauseCalls, hasLength(1));
      await settleAfterGesture(tester);
    });
  });

  group('double-tap seek', () {
    testWidgets('double tap on the right half seeks forward by 10s', (
      tester,
    ) async {
      await pumpOverlay(tester);

      await tester.tapAt(const Offset(600, 300));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(const Offset(600, 300));
      await tester.pump(kDoubleTapTimeout);

      expect(platform.seekCalls, hasLength(1));
      expect(platform.seekCalls.single.$2, const Duration(seconds: 10));
      expect(platform.playCalls, isEmpty);
      expect(platform.pauseCalls, isEmpty);
      await settleAfterGesture(tester);
    });

    testWidgets('double tap on the left half seeks backward, clamped at 0', (
      tester,
    ) async {
      await pumpOverlay(tester);

      await tester.tapAt(const Offset(200, 300));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(const Offset(200, 300));
      await tester.pump(kDoubleTapTimeout);

      // Position starts at 0 → -10s clamps to 0.
      expect(platform.seekCalls.single.$2, Duration.zero);
      await settleAfterGesture(tester);
    });

    testWidgets('rapid double taps accumulate '
        '(bug: stale position collapsed N taps into one hop)', (tester) async {
      await pumpOverlay(tester);

      for (var i = 0; i < 3; i++) {
        await tester.tapAt(const Offset(600, 300));
        await tester.pump(kDoubleTapMinTime);
        await tester.tapAt(const Offset(600, 300));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pump(const Duration(milliseconds: 900));

      // 3 double taps = 3 hops of 10s from a base of 0 → 30s total.
      expect(platform.seekCalls.last.$2, const Duration(seconds: 30));
    });

    testWidgets('shows the seek feedback ripple with the step label', (
      tester,
    ) async {
      await pumpOverlay(tester);

      await tester.tapAt(const Offset(600, 300));
      await tester.pump(kDoubleTapMinTime);
      await tester.tapAt(const Offset(600, 300));
      await tester.pump();

      expect(find.text('10 Seconds'), findsOneWidget);
      expect(find.byIcon(Icons.fast_forward), findsOneWidget);
      await settleAfterGesture(tester);
    });
  });

  group('horizontal drag scrub', () {
    testWidgets(
      'dragging right seeks proportionally with HUD, pauses, and resumes',
      (tester) async {
        await pumpOverlay(tester);
        await controller.seekTo(const Duration(seconds: 30));
        await tester.pump();
        await controller.play();
        await tester.pump();
        platform.resetLog();

        final gesture = await tester.startGesture(const Offset(200, 300));
        await tester.pump();
        await dragBy(tester, gesture, 400);
        await tester.pump();

        // HUD visible while dragging: 30s + (400/800 * 90s) = 75s.
        expect(find.text('1:15'), findsOneWidget);
        expect(find.text('+45s'), findsOneWidget);
        expect(gestureActivityLog, contains(true));
        expect(controller.value.isPlaying, isFalse); // paused while scrubbing

        await gesture.up();
        await tester.pump();

        final (_, position) = platform.seekCalls.last;
        expect(position.inSeconds, closeTo(75, 1));
        expect(controller.value.isPlaying, isTrue); // resumed
        expect(gestureActivityLog.last, isFalse);
        await settleAfterGesture(tester);
      },
    );

    testWidgets('dragging left seeks backward', (tester) async {
      await pumpOverlay(tester);
      await controller.seekTo(const Duration(seconds: 60));
      await tester.pump();
      platform.resetLog();

      final gesture = await tester.startGesture(const Offset(600, 300));
      await tester.pump();
      await dragBy(tester, gesture, -400);
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final (_, position) = platform.seekCalls.last;
      expect(position.inSeconds, closeTo(15, 1));
    });

    testWidgets('scrub clamps to [0, duration]', (tester) async {
      await pumpOverlay(tester);
      platform.resetLog();

      // From 0, drag far left → clamp at 0.
      var gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await dragBy(tester, gesture, -500);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(platform.seekCalls.last.$2, Duration.zero);

      // Drag far right beyond the end → clamp at duration.
      gesture = await tester.startGesture(const Offset(100, 300));
      await tester.pump();
      await dragBy(tester, gesture, 2000);
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(platform.seekCalls.last.$2, controller.value.duration);
    });
  });

  group('long-press speed', () {
    testWidgets('holding engages 2x speed and releasing restores it', (
      tester,
    ) async {
      await pumpOverlay(tester);
      // video_player only forwards speed changes to the platform while playing.
      await controller.play();
      await tester.pump();
      platform.resetLog();

      await tester.longPressAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.speedCalls, hasLength(2));
      expect(platform.speedCalls.first.$2, 2.0);
      // Long-press end restores the previous speed.
      expect(platform.speedCalls.last.$2, 1.0);
      // Speed badge is gone after release.
      expect(find.text('2× Speed'), findsNothing);
      await controller.pause(); // stop the position timer
      await tester.pump();
    });

    testWidgets('restores the custom speed that was active before the hold', (
      tester,
    ) async {
      await pumpOverlay(tester);
      await controller.play();
      await controller.setPlaybackSpeed(1.5);
      await tester.pump();
      platform.resetLog();

      await tester.longPressAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.speedCalls.first.$2, 2.0);
      expect(platform.speedCalls.last.$2, 1.5);
      await controller.pause(); // stop the position timer
      await tester.pump();
    });

    testWidgets('long press does not toggle play/pause', (tester) async {
      await pumpOverlay(tester);
      platform.resetLog();

      await tester.longPressAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.playCalls, isEmpty);
      expect(platform.pauseCalls, isEmpty);
    });
  });

  group('controller swap safety', () {
    testWidgets('swapping controllers mid-scrub resets gesture state '
        '(bug: stale scrub resumed the wrong controller)', (tester) async {
      await pumpOverlay(tester);
      await controller.seekTo(const Duration(seconds: 30));
      await tester.pump();
      await controller.play();
      await tester.pump();
      platform.resetLog();

      final gesture = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      await dragBy(tester, gesture, 400);
      await tester.pump();
      expect(controller.value.isPlaying, isFalse); // paused mid-scrub

      final secondController = VideoPlayerController.networkUrl(
        Uri.parse('https://test.local/video2.mp4'),
      );
      await tester.runAsync(() => secondController.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox.expand(
              child: PlayerGestureOverlay(
                controller: secondController,
                onTogglePlayPause: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // The swap reset the scrub without resuming the OLD controller (which
      // would keep it playing in the background forever).
      expect(controller.value.isPlaying, isFalse);
      await tester.runAsync(() => secondController.dispose());
      await gesture.up();
      await tester.pump();
    });
  });
}
