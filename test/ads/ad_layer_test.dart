import 'package:chorki_player/src/ads/chorki_ad_config.dart';
import 'package:chorki_player/src/ads/chorki_ad_layer.dart';
import 'package:chorki_player/src/ads/chorki_ad_state.dart';
import 'package:chorki_player/src/ads/vmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';
import 'package:interactive_media_ads/src/platform_interface/platform_interface.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_ima_platform.dart';
import '../fakes/fake_video_player_platform.dart';

const _adTagUrl = 'https://ads.test/tag';

/// One mid-roll at 00:00:10 (the default video duration is 2 minutes).
const _midrollVmap = '''
<?xml version="1.0" encoding="UTF-8"?>
<vmap:VMAP xmlns:vmap="http://www.iab.net/videosuite/vmap" version="1.0">
  <vmap:AdBreak breakType="linear" breakId="mid1" timeOffset="00:00:10">
    <vmap:AdSource id="a1" allowMultipleAds="false" followRedirects="true"/>
  </vmap:AdBreak>
</vmap:VMAP>
''';

Future<String> _fetchMidroll(String url) async => _midrollVmap;

const _loadingError = AdError(
  type: AdErrorType.loading,
  code: AdErrorCode.failedToRequestAds,
  message: 'no fill',
);

const _playingError = AdError(
  type: AdErrorType.playing,
  code: AdErrorCode.videoPlayError,
  message: 'playback failed',
);

void main() {
  late FakeVideoPlayerPlatform videoPlatform;
  late VideoPlayerController controller;
  late FakeImaPlatform ima;
  late List<String> adErrors;
  late List<AdEvent> adEvents;

  /// Captured from the child whenever it is built (only built once visible).
  late ChorkiAdState? adState;

  setUp(() async {
    videoPlatform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = videoPlatform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    controller = await createTestController(videoPlatform);

    ima = FakeImaPlatform();
    InteractiveMediaAdsPlatform.instance = ima;

    adErrors = [];
    adEvents = [];
    adState = null;
  });

  tearDown(() async {
    InteractiveMediaAdsPlatform.instance = null;
    await controller.dispose();
  });

  ChorkiAdConfig config({Duration? progressInterval}) => ChorkiAdConfig(
    progressInterval: progressInterval ?? const Duration(milliseconds: 200),
    onAdError: adErrors.add,
    onAdEvent: adEvents.add,
  );

  Future<void> pumpLayer(
    WidgetTester tester, {
    bool autoPlay = true,
    VmapFetcher vmapFetcher = _fetchMidroll,
    ChorkiAdConfig? adConfig,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChorkiAdLayer(
          controller: controller,
          adTagUrl: _adTagUrl,
          config: adConfig ?? config(),
          autoPlay: autoPlay,
          vmapFetcher: vmapFetcher,
          child: Builder(
            builder: (context) {
              adState = ChorkiAdScope.maybeOf(context);
              return const Text('CONTENT');
            },
          ),
        ),
      ),
    );
    // First frame builds the container, post-frame callback adds it.
    await tester.pump();
    // Lets the VMAP future resolve.
    await tester.pump();
  }

  /// Delivers the IMA "ads loaded" callback with a fresh manager.
  FakeAdsManager loadAds() {
    final manager = FakeAdsManager();
    ima.loader.loadManager(manager);
    return manager;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await controller.pause();
  }

  bool contentVisible() => find.text('CONTENT').evaluate().isNotEmpty;

  group('content gating and pre-roll flow', () {
    testWidgets('content child is hidden until contentResumeRequested', (
      tester,
    ) async {
      await pumpLayer(tester);
      expect(contentVisible(), isFalse);
      expect(ima.loader.requests, hasLength(1));

      final manager = loadAds();
      await tester.pump();
      manager.emit(AdEventType.loaded);
      await tester.pump();
      expect(contentVisible(), isFalse);

      manager.emit(AdEventType.contentResumeRequested);
      await tester.pump();
      expect(contentVisible(), isTrue);
      await unmount(tester);
    });

    testWidgets(
      'pre-roll: loaded starts manager, pause hides content and pauses, resume shows and plays',
      (tester) async {
        await pumpLayer(tester);
        final manager = loadAds();
        await tester.pump();

        manager.emit(AdEventType.loaded);
        await tester.pump();
        expect(manager.startCalls, 1);
        expect(manager.initCalls, 1);

        manager.emit(AdEventType.contentPauseRequested);
        await tester.pump();
        expect(contentVisible(), isFalse);
        expect(controller.value.isPlaying, isFalse);

        manager.emit(AdEventType.contentResumeRequested);
        await tester.pump();
        expect(contentVisible(), isTrue);
        expect(controller.value.isPlaying, isTrue);
        expect(videoPlatform.playCalls, isNotEmpty);
        await unmount(tester);
      },
    );

    testWidgets('autoPlay false does not play on the first resume', (
      tester,
    ) async {
      await pumpLayer(tester, autoPlay: false);
      final manager = loadAds();
      await tester.pump();

      manager.emit(AdEventType.loaded);
      manager.emit(AdEventType.contentPauseRequested);
      await tester.pump();
      manager.emit(AdEventType.contentResumeRequested);
      await tester.pump();

      expect(contentVisible(), isTrue);
      expect(videoPlatform.playCalls, isEmpty);
      expect(controller.value.isPlaying, isFalse);
      await unmount(tester);
    });

    testWidgets('allAdsCompleted destroys the manager and shows content', (
      tester,
    ) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump();

      manager.emit(AdEventType.loaded);
      manager.emit(AdEventType.contentPauseRequested);
      await tester.pump();
      manager.emit(AdEventType.contentResumeRequested);
      manager.emit(AdEventType.allAdsCompleted);
      await tester.pump();

      expect(manager.destroyCalls, 1);
      expect(contentVisible(), isTrue);
      await unmount(tester);
    });

    testWidgets('onAdEvent receives every IMA event in order', (tester) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump();

      manager.emit(AdEventType.loaded);
      manager.emit(AdEventType.contentPauseRequested);
      manager.emit(AdEventType.contentResumeRequested);
      await tester.pump();

      expect(adEvents.map((e) => e.type), [
        AdEventType.loaded,
        AdEventType.contentPauseRequested,
        AdEventType.contentResumeRequested,
      ]);
      await unmount(tester);
    });
  });

  group('errors', () {
    testWidgets('ads load error shows content and reports the message', (
      tester,
    ) async {
      await pumpLayer(tester);
      ima.loader.failLoad(_loadingError);
      await tester.pump();

      expect(contentVisible(), isTrue);
      expect(adErrors, ['no fill']);
      await unmount(tester);
    });

    testWidgets('ad error event resumes content and reports the message', (
      tester,
    ) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump();
      manager.emit(AdEventType.loaded);
      manager.emit(AdEventType.contentPauseRequested);
      await tester.pump();
      expect(contentVisible(), isFalse);

      manager.emitError(_playingError);
      await tester.pump();

      expect(contentVisible(), isTrue);
      expect(adErrors, ['playback failed']);
      await unmount(tester);
    });

    testWidgets('no pre-roll: content shows after the 1.5s fallback', (
      tester,
    ) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 1400));
      expect(contentVisible(), isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(contentVisible(), isTrue);
      expect(manager.startCalls, 1);
      await unmount(tester);
    });

    testWidgets('fallback is cancelled when a pause event arrives', (
      tester,
    ) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 500));
      manager.emit(AdEventType.contentPauseRequested);
      await tester.pump(const Duration(milliseconds: 2000));

      expect(contentVisible(), isFalse);
      expect(manager.startCalls, 0);

      manager.emit(AdEventType.contentResumeRequested);
      await tester.pump();
      expect(contentVisible(), isTrue);
      await unmount(tester);
    });
  });

  group('markers and countdown', () {
    testWidgets('markers are published through ChorkiAdScope after VMAP load', (
      tester,
    ) async {
      await pumpLayer(tester);
      loadAds();
      await tester.pump(const Duration(milliseconds: 1600));
      expect(contentVisible(), isTrue);

      final markers = adState!.markers;
      expect(markers, hasLength(1));
      expect(markers.single.id, 'mid1');
      expect(markers.single.played, isFalse);
      expect(markers.single.fraction, closeTo(10 / 120, 1e-9));
      await unmount(tester);
    });

    testWidgets('no countdown when the break is more than 5s away', (
      tester,
    ) async {
      await pumpLayer(tester);
      loadAds();
      await tester.pump(const Duration(milliseconds: 1600));
      expect(adState!.countdownSeconds, isNull);

      await controller.seekTo(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      expect(adState!.countdownSeconds, isNull);
      await unmount(tester);
    });

    testWidgets('countdown is set once within 5s of the break', (tester) async {
      await pumpLayer(tester);
      loadAds();
      await tester.pump(const Duration(milliseconds: 1600));

      await controller.seekTo(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 200));
      expect(adState!.countdownSeconds, 3);
      await unmount(tester);
    });

    testWidgets('startNow seeks the controller to the break offset', (
      tester,
    ) async {
      await pumpLayer(tester);
      loadAds();
      await tester.pump(const Duration(milliseconds: 1600));

      await controller.seekTo(const Duration(seconds: 7));
      await tester.pump(const Duration(milliseconds: 200));
      expect(adState!.countdownSeconds, 3);

      adState!.startNow!();
      await tester.pump();

      expect(controller.value.position, const Duration(seconds: 10));
      expect(
        ima.progressProviders.single.lastProgress,
        const Duration(seconds: 10),
      );
      await unmount(tester);
    });

    testWidgets(
      'contentPauseRequested clears the countdown and marks the break played',
      (tester) async {
        await pumpLayer(tester);
        final manager = loadAds();
        await tester.pump(const Duration(milliseconds: 1600));

        await controller.seekTo(const Duration(seconds: 7));
        await tester.pump(const Duration(milliseconds: 200));
        expect(adState!.countdownSeconds, 3);

        // Within the 2s match tolerance of the break, without a tick in between.
        await controller.seekTo(const Duration(seconds: 9));
        manager.emit(AdEventType.contentPauseRequested);
        await tester.pump();

        expect(adState!.countdownSeconds, isNull);
        expect(adState!.markers.single.played, isTrue);
        await unmount(tester);
      },
    );

    testWidgets('VMAP fetch failure: no markers, but ads still flow', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        vmapFetcher: (_) async => throw Exception('network down'),
      );
      final manager = loadAds();
      await tester.pump(const Duration(milliseconds: 1600));

      expect(ima.loader.requests, hasLength(1));
      expect(manager.startCalls, 1);
      expect(contentVisible(), isTrue);
      expect(adState!.markers, isEmpty);
      expect(adState!.countdownSeconds, isNull);
      await unmount(tester);
    });
  });

  group('dispose', () {
    testWidgets('dispose destroys the manager', (tester) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump();
      manager.emit(AdEventType.loaded);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(manager.destroyCalls, 1);
      await controller.pause();
    });

    testWidgets('events arriving after dispose do not throw', (tester) async {
      await pumpLayer(tester);
      final manager = loadAds();
      await tester.pump(const Duration(milliseconds: 1600));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(() {
        manager.emit(AdEventType.loaded);
        manager.emit(AdEventType.contentPauseRequested);
        manager.emit(AdEventType.contentResumeRequested);
        manager.emit(AdEventType.allAdsCompleted);
        manager.emitError(_playingError);
      }, returnsNormally);
      await tester.pump(const Duration(milliseconds: 2000));
      await controller.pause();
    });
  });
}
