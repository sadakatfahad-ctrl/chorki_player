// Every error the SDK recovers from internally must reach
// ChorkiDiagnostics.onError (see test/guardrails: swallowed_error). These
// tests drive each recovery path and check the report's context.
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:async';

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as pi;

import 'fakes/fake_pip_delegate.dart';
import 'fakes/fake_video_player_platform.dart';

class _ThrowingPip extends FakePipDelegate {
  @override
  Future<ChorkiPipStatus> status() async => throw StateError('status');

  @override
  Future<ChorkiPipStatus> enter(double aspectRatio) async =>
      throw StateError('enter');
}

/// Never finishes initializing.
class _HangingPlatform extends FakeVideoPlayerPlatform {
  @override
  Stream<pi.VideoEvent> videoEventsFor(int playerId) =>
      const Stream<pi.VideoEvent>.empty().asBroadcastStream();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVideoPlayerPlatform platform;
  late List<String> reported;

  setUp(() {
    platform = FakeVideoPlayerPlatform();
    pi.VideoPlayerPlatform.instance = platform;
    reported = [];
    ChorkiDiagnostics.onError = (e, st, context) => reported.add(context);
  });
  tearDown(() => ChorkiDiagnostics.onError = null);

  group('ChorkiPlayerController', () {
    late ChorkiPlayerController chorki;

    setUp(
      () => chorki = ChorkiPlayerController(pipDelegate: FakePipDelegate()),
    );
    tearDown(() => chorki.dispose());

    Future<VideoPlayerController> attached() async {
      final c = await createTestController(platform);
      chorki.attach(c);
      await pumpEventQueue();
      return c;
    }

    test('failed track reads are reported, menus stay empty', () async {
      platform.failing.addAll({'getVideoTracks', 'getAudioTracks'});
      await attached();
      expect(chorki.videoTracks.value, isEmpty);
      expect(reported, [
        'controller.getVideoTracks',
        'controller.getAudioTracks',
      ]);
    });

    test(
      'a rejected quality / audio switch is reported, state unchanged',
      () async {
        await attached();
        platform.failing.addAll({'selectVideoTrack', 'selectAudioTrack'});
        await chorki.selectQuality(null);
        await chorki.selectAudioTrack('a');
        expect(chorki.selectedAudioTrackId.value, isNull);
        expect(reported, [
          'controller.selectQuality',
          'controller.selectAudioTrack',
        ]);
      },
    );

    test('a failing seek is reported', () async {
      await attached();
      platform.failing.add('seekTo');
      await chorki.seekTo(const Duration(seconds: 3));
      expect(reported, ['controller.video']);
    });

    test('PiP delegate errors are reported', () async {
      final pip = ChorkiPlayerController(pipDelegate: _ThrowingPip());
      addTearDown(pip.dispose);
      await pip.refreshPipStatus();
      expect(reported, ['controller.pipStatus']);
    });

    testWidgets('enterPip errors are reported', (tester) async {
      final pip = ChorkiPlayerController(pipDelegate: _ThrowingPip());
      await pip.enterPip();
      expect(reported, contains('controller.enterPip'));
      pip.dispose();
      // Disposing cancels the status probes enterPip scheduled (no pending
      // timers at the end of the test).
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('ChorkiVideoPreloader', () {
    test(
      'a failed seek to the start position is reported; it still plays',
      () async {
        platform.failing.add('seekTo');
        final c = await ChorkiVideoPreloader().load(
          Uri.parse('https://test.local/v.mp4'),
          options: const ChorkiMediaOptions(
            startPosition: Duration(seconds: 5),
          ),
        );
        expect(c, isNotNull);
        expect(reported, ['preloader.seekToStart']);
        await c!.dispose();
      },
    );

    test('a failed dispose is reported', () async {
      final c = await ChorkiVideoPreloader().load(
        Uri.parse('https://test.local/v'),
      );
      platform.failing.add('dispose');
      await ChorkiVideoPreloader().disposeQuietly(c);
      expect(reported, ['preloader.dispose']);
    });

    test('loadResult tells a timeout from a load failure', () async {
      pi.VideoPlayerPlatform.instance = _HangingPlatform();
      final slow = await ChorkiVideoPreloader(
        initTimeout: const Duration(milliseconds: 10),
      ).loadResult(Uri.parse('https://test.local/v'));
      expect(slow.controller, isNull);
      expect(slow.error?.code, ChorkiErrorCode.timeout);

      pi.VideoPlayerPlatform.instance = platform..failing.add('create');
      final broken = await ChorkiVideoPreloader().loadResult(
        Uri.parse('https://test.local/v'),
      );
      expect(broken.error?.code, ChorkiErrorCode.videoLoad);
      expect(broken.error?.isTransient, isTrue);
    });
  });

  group('ChorkiVideoLoadScheduler', () {
    test('a failing disposal does not break later loads', () async {
      final s = ChorkiVideoLoadScheduler(
        disposalGrace: const Duration(milliseconds: 50),
      );
      s.trackDisposal(Future<void>.error(StateError('dispose')));
      expect(await s.run(() async => 1), 1);
    });

    test('a stuck disposal is waited for at most disposalGrace', () async {
      final s = ChorkiVideoLoadScheduler(
        disposalGrace: const Duration(milliseconds: 20),
      );
      s.trackDisposal(Completer<void>().future);
      expect(await s.run(() async => 2), 2);
    });

    test('configure replaces the shared scheduler', () {
      ChorkiVideoLoadScheduler.configure(maxConcurrent: 3);
      expect(ChorkiVideoLoadScheduler.instance.maxConcurrent, 3);
      ChorkiVideoLoadScheduler.resetForTesting();
    });

    test('the deprecated instance setter still works', () {
      final mine = ChorkiVideoLoadScheduler();
      ChorkiVideoLoadScheduler.instance = mine;
      expect(ChorkiVideoLoadScheduler.instance, same(mine));
      ChorkiVideoLoadScheduler.resetForTesting();
    });
  });

  test('deprecated getIt / initChorkiPlayer still compile and do nothing', () {
    initChorkiPlayer();
    expect(getIt, isNotNull);
  });

  group('ChorkiFloatingPipDelegate on Android', () {
    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('floating'),
            (call) async => throw PlatformException(code: 'no-pip'),
          );
    });
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('floating'), null);
    });

    test('platform errors are reported and read as unavailable', () async {
      final pip = ChorkiFloatingPipDelegate();
      expect(await pip.status(), ChorkiPipStatus.unavailable);
      expect(await pip.enter(16 / 9), ChorkiPipStatus.unavailable);
      await pip.setAuto(true, 1);
      expect(reported, ['pip.status', 'pip.enter', 'pip.setAuto']);
    });
  });
}
