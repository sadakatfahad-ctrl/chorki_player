import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/presentation/widgets/gesture_feedback.dart';
import 'package:chorki_player/src/presentation/widgets/scrub_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as pi;

import '../fakes/fake_video_player_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVideoPlayerPlatform platform;
  late VideoPlayerController controller;
  late MemoryAnalyticsSink sink;
  late ChorkiAnalyticsSession session;

  setUp(() async {
    platform = FakeVideoPlayerPlatform();
    pi.VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    controller = await createTestController(platform);
    sink = MemoryAnalyticsSink();
    session =
        ChorkiAnalyticsSession(
            config: ChorkiAnalyticsConfig(
              sinks: [sink],
              heartbeatInterval: const Duration(hours: 1),
            ),
            metadata: () => const ChorkiMediaMetadata(contentId: 'c'),
          )
          ..bind(controller)
          ..activate();
  });

  tearDown(() async {
    session.dispose();
    await controller.dispose();
  });

  ScrubSession scrub({bool skip = false}) => ScrubSession(
    controller: () => controller,
    analytics: () => session,
    source: ChorkiSeekSource.scrub,
    context: 'test',
    tickInterval: const Duration(seconds: 5),
    throttle: const Duration(milliseconds: 150),
    skipSeekToCurrent: skip,
  );

  Iterable<ChorkiAnalyticsEventType> types() => sink.types;

  test('a drag pauses, seeks to the target, reports it and resumes', () async {
    await controller.play();
    final s = scrub()..begin(Duration.zero);
    expect(s.active, isTrue);
    expect(controller.value.isPlaying, isFalse);
    expect(s.update(const Duration(seconds: 20)), const Duration(seconds: 20));
    expect(s.finish(), const Duration(seconds: 20));
    await pumpEventQueue();
    expect(s.active, isFalse);
    expect(platform.seekCalls.last.$2, const Duration(seconds: 20));
    expect(controller.value.isPlaying, isTrue);
    expect(types(), contains(ChorkiAnalyticsEventType.seek));
  });

  test('ending where it began is a cancelled scrub, not a seek', () async {
    scrub()
      ..begin(Duration.zero)
      ..finish();
    await pumpEventQueue();
    expect(types(), isNot(contains(ChorkiAnalyticsEventType.seek)));
  });

  test('targets are clamped to the video', () {
    final s = scrub()..begin(Duration.zero);
    expect(s.update(const Duration(seconds: -3)), Duration.zero);
    expect(s.update(controller.value.duration * 2), controller.value.duration);
    s.abandon();
  });

  test('abandon neither seeks nor resumes; finish is then a no-op', () async {
    await controller.play();
    final s = scrub()..begin(Duration.zero);
    platform.resetLog();
    s.abandon(reportCancel: true);
    expect(s.finish(), isNull);
    await pumpEventQueue();
    expect(platform.seekCalls, isEmpty);
    expect(controller.value.isPlaying, isFalse);
  });

  test('skipSeekToCurrent skips a seek to where the video is', () async {
    platform.resetLog();
    await scrub(skip: true).seek(Duration.zero);
    expect(platform.seekCalls, isEmpty);
    await scrub().seek(Duration.zero);
    expect(platform.seekCalls, hasLength(1));
  });

  group('gesture feedback', () {
    Widget host(Widget child) => MaterialApp(home: Center(child: child));

    testWidgets('the speed badge drops a needless .0', (tester) async {
      await tester.pumpWidget(
        host(
          const GestureSpeedBadge(
            speed: 2,
            theme: ChorkiPlayerTheme(),
            icons: ChorkiPlayerIcons(),
            strings: ChorkiPlayerStrings(),
          ),
        ),
      );
      expect(find.text('2× Speed'), findsOneWidget);
    });

    testWidgets('the scrub HUD shows the target and the jump', (tester) async {
      await tester.pumpWidget(
        host(
          const GestureScrubHud(
            forward: false,
            delta: Duration(seconds: -15),
            target: Duration(minutes: 1, seconds: 5),
            theme: ChorkiPlayerTheme(),
            icons: ChorkiPlayerIcons(),
          ),
        ),
      );
      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('-15s'), findsOneWidget);
    });

    testWidgets('the seek bubble fades out', (tester) async {
      await tester.pumpWidget(
        host(
          const GestureSeekFeedback(
            forward: true,
            label: '10 seconds',
            theme: ChorkiPlayerTheme(),
            icons: ChorkiPlayerIcons(),
          ),
        ),
      );
      expect(find.text('10 seconds'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0);
    });
  });
}
