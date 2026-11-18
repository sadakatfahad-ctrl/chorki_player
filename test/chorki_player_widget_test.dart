import 'dart:async';

import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/ads/chorki_ad_layer.dart';
import 'package:chorki_player/src/core/result.dart';
import 'package:chorki_player/src/core/services.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:chorki_player/src/presentation/bytes_screen/bytes_screen_bloc.dart';
import 'package:chorki_player/src/presentation/widgets/player_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_media_ads/src/platform_interface/platform_interface.dart'
    show AdEventType, InteractiveMediaAdsPlatform;
import 'package:video_player/video_player.dart'
    hide VideoTrack, VideoAudioTrack;
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show DataSourceType, VideoCreationOptions, VideoEvent, VideoPlayerPlatform;

import 'fakes/fake_ima_platform.dart';
import 'fakes/fake_pip_delegate.dart';
import 'fakes/fake_video_player_platform.dart';
import 'support/diagnostics.dart';

const _videoUrl = 'https://test.local/v.mp4';

ByteDataEntity _byte(String url, {String thumbnail = ''}) =>
    ByteDataEntity(id: 1, thumbnailUrl: thumbnail, url: url);

/// A transient route failure (5xx); the player shows its generic server
/// error text, never the server's own message.
const _boom = ChorkiPlayerError(
  ChorkiErrorCode.server,
  statusCode: 500,
  detail: 'boom',
);
final _boomText = const ChorkiPlayerStrings().serverError;

/// Answers each route with the next queued result; a [Completer] result
/// stays pending until the test completes it.
class _FakeRepository implements ByteRepository {
  final Map<String, List<Object>> results = {};
  final List<String> calls = [];
  final List<bool> refreshes = [];

  @override
  Future<Result<ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  }) async {
    calls.add(url);
    refreshes.add(refresh);
    final next = results[url]!.removeAt(0);
    if (next is ChorkiPlayerError) return Err(next);
    final data = next is Completer<ByteDataEntity>
        ? await next.future
        : next as ByteDataEntity;
    return Ok(data);
  }
}

/// Never reports `initialized`, so the player stays on its poster.
class _HangingPlatform extends FakeVideoPlayerPlatform {
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      const Stream<VideoEvent>.empty().asBroadcastStream();
}

/// Never finishes creating a player.
class _StuckCreatePlatform extends FakeVideoPlayerPlatform {
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) =>
      Completer<int?>().future;
}

/// Fails the first [failures] player creations, like a decoder that is
/// still held by a player being disposed.
class _FailingCreatePlatform extends FakeVideoPlayerPlatform {
  int failures = 1;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (failures > 0) {
      failures--;
      throw PlatformException(code: 'decoder_unavailable');
    }
    return super.createWithOptions(options);
  }
}

/// Holds every creation until the test releases it, to watch the queue.
class _GatedCreatePlatform extends FakeVideoPlayerPlatform {
  final List<String> started = [];
  final List<Completer<void>> _gates = [];
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    started.add(options.dataSource.uri!);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final gate = Completer<void>();
    _gates.add(gate);
    await gate.future;
    inFlight--;
    return super.createWithOptions(options);
  }

  void releaseAll() {
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

void main() {
  group('ChorkiVideoPreloader', () {
    testWidgets('times out even when the platform never creates the player '
        '(bug: awaiting dispose() hung the load forever)', (tester) async {
      VideoPlayerPlatform.instance = _StuckCreatePlatform();
      final preloader = ChorkiVideoPreloader(
        initTimeout: const Duration(seconds: 2),
      );
      var done = false;
      VideoPlayerController? result;
      unawaited(
        preloader.load(Uri.parse('https://test.local/v.mp4')).then((c) {
          done = true;
          result = c;
        }),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(done, isTrue);
      expect(result, isNull);
    });
  });

  group('BytesBloc', () {
    test('a slow response for an old route never replaces the latest one '
        '(bug: concurrent handlers emitted out of order)', () async {
      final repo = _FakeRepository();
      final slowA = Completer<ByteDataEntity>();
      repo.results['a'] = [slowA];
      repo.results['b'] = [_byte('https://test.local/b.mp4')];
      final bloc = BytesBloc(getByteDataUsecase: BytesUsecase(repo));
      final states = <ByteScreenState>[];
      final sub = bloc.stream.listen(states.add);

      bloc.add(const ByteScreenInitialEvent('a'));
      await pumpEventQueue();
      bloc.add(const ByteScreenInitialEvent('b'));
      await pumpEventQueue();
      slowA.complete(_byte('https://test.local/a.mp4'));
      await pumpEventQueue();

      final loaded = states.whereType<ByteScreenLoadedState>();
      expect(loaded.map((s) => s.data.url), ['https://test.local/b.mp4']);
      expect(bloc.state, isA<ByteScreenLoadedState>());
      await sub.cancel();
      await bloc.close();
    });
  });

  group('ChorkiPlayer', () {
    late FakeVideoPlayerPlatform platform;
    late _FakeRepository repo;
    late ChorkiPlayerController chorki;

    setUp(() async {
      repo = _FakeRepository();
      ChorkiServices.overrideForTesting(repository: repo);
      platform = FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
      chorki = ChorkiPlayerController(pipDelegate: FakePipDelegate());
    });

    tearDown(() async {
      chorki.dispose();
      ChorkiServices.resetForTesting();
    });

    Future<void> pumpPlayer(
      WidgetTester tester,
      Widget Function(Widget) wrap, {
      bool sizeToVideo = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: wrap(
              ChorkiPlayer(
                route: 'r',
                autoPlay: false,
                controller: chorki,
                sizeToVideo: sizeToVideo,
              ),
            ),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('playback failure offers a retry that reloads the route '
        '(bug: the error view had no retry button)', (tester) async {
      repo.results['r'] = [_byte(''), _byte('https://test.local/v.mp4')];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);

      expect(find.text('Video failed to play'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await settle(tester);

      expect(repo.calls, ['r', 'r']);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a permanent route error (404) is not retried silently; '
        'errorViewBuilder gets the typed error', (tester) async {
      repo.results['r'] = [
        const ChorkiPlayerError(ChorkiErrorCode.notFound, statusCode: 404),
        _byte('https://test.local/v.mp4'),
      ];
      ChorkiPlayerError? shown;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: ChorkiPlayer(
              route: 'r',
              controller: chorki,
              builders: ChorkiPlayerBuilders(
                errorViewBuilder: (context, error, onRetry) {
                  shown = error;
                  return TextButton(
                    onPressed: onRetry,
                    child: const Text('again'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(shown?.code, ChorkiErrorCode.notFound);
      await tester.pump(const Duration(seconds: 5));
      expect(repo.calls, ['r'], reason: 'no silent retry for a 404');

      await tester.tap(find.text('again'));
      await settle(tester);
      expect(repo.calls, ['r', 'r'], reason: 'the viewer may still retry');
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('the deprecated errorBuilder still gets the localized '
        'message', (tester) async {
      repo.results['r'] = [
        const ChorkiPlayerError(ChorkiErrorCode.notFound, statusCode: 404),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: ChorkiPlayer(
              route: 'r',
              controller: chorki,
              builders: ChorkiPlayerBuilders(
                // ignore: deprecated_member_use_from_same_package
                errorBuilder: (context, message, onRetry) => Text('<$message>'),
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(
        find.text('<${const ChorkiPlayerStrings().serverError}>'),
        findsOneWidget,
      );
      await unmount(tester);
    });

    test('ChorkiPlayer.configure swaps the services only when the settings '
        'change', () {
      final before = ChorkiServices.instance;
      ChorkiPlayer.configure(network: const ChorkiNetworkConfig());
      expect(ChorkiServices.instance.network, const ChorkiNetworkConfig());
      final configured = ChorkiServices.instance;
      ChorkiPlayer.configure(network: const ChorkiNetworkConfig());
      expect(ChorkiServices.instance, same(configured));
      ChorkiPlayer.configure(
        network: const ChorkiNetworkConfig(headers: {'X-A': '1'}),
      );
      expect(ChorkiServices.instance, isNot(same(configured)));
      expect(before, isNotNull);
    });

    testWidgets('a route that fails once retries silently and plays', (
      tester,
    ) async {
      repo.results['r'] = [_boom, _byte('https://test.local/v.mp4')];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);

      expect(find.text(_boomText), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(repo.calls, ['r', 'r']);
      expect(repo.refreshes, [false, true]);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a route that keeps failing shows the error after the silent '
        'retries; Retry starts a fresh round', (tester) async {
      const boom = _boom;
      repo.results['r'] = [boom, boom, boom, boom, _byte(_videoUrl)];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text(_boomText), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);

      expect(repo.calls, hasLength(3));
      expect(find.text(_boomText), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      expect(repo.calls, hasLength(3), reason: 'no more silent retries');

      await tester.tap(find.text('Retry'));
      await settle(tester);
      expect(repo.calls, hasLength(4));
      expect(find.text(_boomText), findsNothing, reason: 'silent again');
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a video that fails to initialize retries silently with a '
        'fresh route', (tester) async {
      VideoPlayerPlatform.instance = _FailingCreatePlatform();
      repo.results['r'] = [_byte(_videoUrl), _byte(_videoUrl)];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);

      expect(find.text('Video failed to play'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(repo.refreshes, [false, true], reason: 'its URL may be stale');
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a playback error on screen reloads and resumes where it '
        'stopped', (tester) async {
      repo.results['r'] = [_byte(_videoUrl), _byte(_videoUrl)];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);
      final first = chorki.videoController.value!;
      await first.seekTo(const Duration(seconds: 30));
      await tester.pump();

      platform.onlyPlayer.events.addError(
        PlatformException(code: 'net', message: 'connection reset'),
      );
      await tester.pump();
      expect(find.text('Video failed to play'), findsNothing);

      platform.seekCalls.clear();
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      final second = chorki.videoController.value!;
      expect(second, isNot(same(first)));
      expect(platform.seekCalls.last.$2, const Duration(seconds: 30));
      await unmount(tester);
    });

    testWidgets('unmounting while a silent retry is pending cancels it', (
      tester,
    ) async {
      repo.results['r'] = [_boom];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);
      // The test framework fails on a timer still pending at the end.
      await unmount(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(repo.calls, ['r']);
    });

    testWidgets('a very short player shows a compact error with retry '
        '(bug: the stacked error view overflowed)', (tester) async {
      repo.results['r'] = [_byte(''), _byte('https://test.local/v.mp4')];
      // e.g. a 12.5:1 clip with sizeToVideo on a phone.
      await pumpPlayer(
        tester,
        (p) => Center(child: SizedBox(width: 400, height: 40, child: p)),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PlayerErrorView), findsOneWidget);
      expect(find.text('Video failed to play'), findsOneWidget);
      expect(find.text('Retry'), findsNothing); // label hidden, icon only
      await tester.tap(find.byTooltip('Retry'));
      await settle(tester);

      expect(repo.calls, ['r', 'r']);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('sizeToVideo sizes the player to the video in a ListView', (
      tester,
    ) async {
      final pending = Completer<ByteDataEntity>();
      repo.results['r'] = [pending];
      await pumpPlayer(
        tester,
        (p) => ListView(children: [p]),
        sizeToVideo: true,
      );
      await tester.pump();

      // Placeholder 16:9 while loading (test surface is 800 wide).
      expect(tester.getSize(find.byType(ChorkiPlayer)), const Size(800, 450));

      pending.complete(_byte('https://test.local/v.mp4'));
      await settle(tester);

      // The fake video is 720x1280 (9:16).
      final size = tester.getSize(find.byType(ChorkiPlayer));
      expect(size.width, 800);
      expect(size.height, closeTo(800 * 1280 / 720, 0.01));
      await unmount(tester);
    });

    testWidgets('without sizeToVideo the player fills its box', (tester) async {
      repo.results['r'] = [_byte('https://test.local/v.mp4')];
      await pumpPlayer(
        tester,
        (p) => Center(child: SizedBox(width: 300, height: 200, child: p)),
      );
      await settle(tester);

      expect(tester.getSize(find.byType(ChorkiPlayer)), const Size(300, 200));
      await unmount(tester);
    });

    testWidgets('the poster uses the same fit as the video', (tester) async {
      VideoPlayerPlatform.instance = _HangingPlatform();
      repo.results['r'] = [
        _byte('https://test.local/v.mp4', thumbnail: 'https://test.local/p'),
      ];
      await pumpPlayer(tester, (p) => SizedBox.expand(child: p));
      await settle(tester);

      BoxFit? posterFit() => tester.widget<Image>(find.byType(Image)).fit;
      expect(posterFit(), BoxFit.contain);
      chorki.setFit(ChorkiVideoFit.fill);
      await tester.pump();
      expect(posterFit(), BoxFit.cover);

      // Unmounted first, so the init timeout below schedules no auto-retry.
      await unmount(tester);
      // Let the preloader's init timeout fire.
      await tester.pump(const Duration(seconds: 16));
    });
  });

  group('ChorkiPlayer.url', () {
    late FakeVideoPlayerPlatform platform;
    late _FakeRepository repo;
    late ChorkiPlayerController chorki;

    setUp(() async {
      repo = _FakeRepository();
      ChorkiServices.overrideForTesting(repository: repo);
      platform = FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
      chorki = ChorkiPlayerController(pipDelegate: FakePipDelegate());
    });

    tearDown(() async {
      chorki.dispose();
      ChorkiServices.resetForTesting();
    });

    Future<void> pumpUrl(WidgetTester tester, String url) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: ChorkiPlayer.url(url, autoPlay: false, controller: chorki),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    String? lastUri() => platform.creationOptions.last.dataSource.uri;

    testWidgets('plays the URL without fetching a route', (tester) async {
      await pumpUrl(tester, 'https://test.local/a.mp4');

      expect(repo.calls, isEmpty);
      expect(lastUri(), 'https://test.local/a.mp4');
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new URL reloads, retry reloads the same URL', (
      tester,
    ) async {
      await pumpUrl(tester, 'https://test.local/a.mp4');
      await pumpUrl(tester, 'https://test.local/b.mp4');
      expect(lastUri(), 'https://test.local/b.mp4');

      chorki.retry();
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(platform.creationOptions, hasLength(3));
      expect(lastUri(), 'https://test.local/b.mp4');
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('asset: URIs load a bundled asset', (tester) async {
      await pumpUrl(tester, 'asset:///assets/videos/clip.mp4');

      final source = platform.creationOptions.last.dataSource;
      expect(source.sourceType, DataSourceType.asset);
      expect(source.asset, 'assets/videos/clip.mp4');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ChorkiPlayer preload', () {
    const a = 'https://test.local/a.mp4';
    const b = 'https://test.local/b.mp4';

    late FakeVideoPlayerPlatform platform;
    late _FakeRepository repo;
    late ChorkiPlayerController chorki;

    setUp(() async {
      repo = _FakeRepository();
      ChorkiServices.overrideForTesting(repository: repo);
      platform = FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => null,
          );
      chorki = ChorkiPlayerController(pipDelegate: FakePipDelegate());
    });

    tearDown(() async {
      chorki.dispose();
      ChorkiServices.resetForTesting();
    });

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    Future<void> pumpUrl(
      WidgetTester tester, {
      required bool preload,
      bool autoPlay = true,
      ChorkiMediaOptions mediaOptions = const ChorkiMediaOptions(),
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: ChorkiPlayer.url(
              a,
              preload: preload,
              autoPlay: autoPlay,
              mediaOptions: mediaOptions,
              controller: chorki,
            ),
          ),
        ),
      );
      await settle(tester);
    }

    Widget twoPlayers({required bool aPreload, required bool bPreload}) {
      return MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: ChorkiPlayer.url(a, preload: aPreload, controller: chorki),
            ),
            Expanded(
              child: ChorkiPlayer.url(b, preload: bPreload, controller: chorki),
            ),
          ],
        ),
      );
    }

    VideoPlayerController shownVideo(WidgetTester tester) => tester
        .widget<ChorkiPlayerSurface>(find.byType(ChorkiPlayerSurface))
        .controller;

    testWidgets('loads the video without playing it, attaching the '
        'controller or showing controls', (tester) async {
      await pumpUrl(tester, preload: true);

      expect(platform.creationOptions, hasLength(1));
      expect(shownVideo(tester).value.isInitialized, isTrue);
      expect(platform.playCalls, isEmpty);
      expect(chorki.isAttached, isFalse);
      expect(find.byType(ChorkiShortsSeekBar), findsNothing);
      expect(find.byKey(const Key('chorki_settings_button')), findsNothing);
      await unmount(tester);
    });

    testWidgets('turning it off plays the preloaded video without reloading', (
      tester,
    ) async {
      await pumpUrl(tester, preload: true);
      await pumpUrl(tester, preload: false);

      expect(platform.creationOptions, hasLength(1));
      expect(chorki.videoController.value?.dataSource, a);
      expect(platform.playCalls, hasLength(1));
      expect(chorki.value.value.isPlaying, isTrue);
      expect(find.byType(ChorkiShortsSeekBar), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('with autoPlay off, turning it off attaches without playing', (
      tester,
    ) async {
      await pumpUrl(tester, preload: true, autoPlay: false);
      await pumpUrl(tester, preload: false, autoPlay: false);

      expect(chorki.isAttached, isTrue);
      expect(platform.playCalls, isEmpty);
      await unmount(tester);
    });

    testWidgets('turning it back on pauses, rewinds and releases the '
        'controller', (tester) async {
      await pumpUrl(tester, preload: false);
      await chorki.seekTo(const Duration(seconds: 30));
      await pumpUrl(tester, preload: true);

      expect(shownVideo(tester).value.isPlaying, isFalse);
      expect(platform.pauseCalls, isNotEmpty);
      expect(platform.seekCalls.last.$2, Duration.zero);
      expect(chorki.isAttached, isFalse);
      expect(find.byType(ChorkiShortsSeekBar), findsNothing);
      await unmount(tester);
    });

    testWidgets('rewinds to the start position when one is set', (
      tester,
    ) async {
      const options = ChorkiMediaOptions(startPosition: Duration(seconds: 5));
      await pumpUrl(tester, preload: false, mediaOptions: options);
      await chorki.seekTo(const Duration(seconds: 30));
      await pumpUrl(tester, preload: true, mediaOptions: options);

      expect(platform.seekCalls.last.$2, const Duration(seconds: 5));
      await unmount(tester);
    });

    testWidgets('a preloading player never takes a shared controller from '
        'the visible one', (tester) async {
      await tester.pumpWidget(twoPlayers(aPreload: false, bPreload: true));
      await settle(tester);
      expect(chorki.videoController.value?.dataSource, a);
      expect(platform.playCalls, hasLength(1));

      await tester.pumpWidget(twoPlayers(aPreload: true, bPreload: false));
      await settle(tester);
      expect(chorki.videoController.value?.dataSource, b);
      expect(chorki.value.value.isPlaying, isTrue);
      expect(platform.creationOptions, hasLength(2));
      await unmount(tester);
    });

    testWidgets("removing a preloading player keeps the visible one's ad flag "
        '(bug: every player cleared isAdPlaying when disposed)', (
      tester,
    ) async {
      await tester.pumpWidget(twoPlayers(aPreload: false, bPreload: true));
      await settle(tester);
      chorki.setAdPlaying(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              Expanded(child: ChorkiPlayer.url(a, controller: chorki)),
            ],
          ),
        ),
      );
      await settle(tester);
      expect(chorki.videoController.value?.dataSource, a);
      expect(chorki.isAdPlaying.value, isTrue);

      await unmount(tester);
      expect(chorki.isAdPlaying.value, isFalse);
    });

    testWidgets('ads wait until the byte is active', (tester) async {
      // The player uses the default VMAP fetcher; the test HTTP client
      // answers 400, so the timeline markers fail (reported, not fatal).
      final reports = captureDiagnostics();
      addTearDown(() => expect(reports.toSet(), {'ads.vmap'}));
      final ima = FakeImaPlatform();
      InteractiveMediaAdsPlatform.instance = ima;
      addTearDown(() => InteractiveMediaAdsPlatform.instance = null);
      final adErrors = <String>[];

      Future<void> pumpAds({required bool preload}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: ChorkiPlayer.url(
                a,
                adTagUrl: 'https://ads.test/tag',
                ads: ChorkiAdConfig(onAdError: adErrors.add),
                preload: preload,
                controller: chorki,
              ),
            ),
          ),
        );
        await settle(tester);
      }

      await pumpAds(preload: true);
      // Past the ad load timeout: nothing may start off screen.
      await tester.pump(const Duration(seconds: 10));
      expect(find.byType(ChorkiAdLayer), findsNothing);
      expect(ima.containers, isEmpty);
      expect(adErrors, isEmpty);
      expect(platform.playCalls, isEmpty);

      await pumpAds(preload: false);
      expect(find.byType(ChorkiAdLayer), findsOneWidget);
      expect(ima.loader.requests, hasLength(1));
      expect(chorki.isAttached, isTrue);
      // Content waits for the ad decision.
      expect(platform.playCalls, isEmpty);

      await pumpAds(preload: true);
      expect(find.byType(ChorkiAdLayer), findsNothing);
      await unmount(tester);
      // Lets the ad layer's VMAP request (Dio, against the test HTTP mock)
      // run out; its error is swallowed.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the ad layer cannot play a byte or flag an ad after it went '
        'back to preload (it stays mounted for one more frame)', (
      tester,
    ) async {
      final reports = captureDiagnostics();
      addTearDown(() => expect(reports.toSet(), {'ads.vmap'}));
      final ima = FakeImaPlatform();
      InteractiveMediaAdsPlatform.instance = ima;
      addTearDown(() => InteractiveMediaAdsPlatform.instance = null);

      Widget player({required bool preload}) => MaterialApp(
        home: SizedBox.expand(
          child: ChorkiPlayer.url(
            a,
            adTagUrl: 'https://ads.test/tag',
            ads: const ChorkiAdConfig(),
            preload: preload,
            controller: chorki,
          ),
        ),
      );

      await tester.pumpWidget(player(preload: false));
      await settle(tester);
      final manager = FakeAdsManager();
      ima.loader.loadManager(manager);
      await tester.pump();
      // Pre-roll, then the content plays.
      manager.emit(AdEventType.loaded);
      manager.emit(AdEventType.contentPauseRequested);
      manager.emit(AdEventType.contentResumeRequested);
      await tester.pump();
      expect(shownVideo(tester).value.isPlaying, isTrue);

      // One frame: the flip is applied after it, so the layer is still there.
      await tester.pumpWidget(player(preload: true));
      expect(find.byType(ChorkiAdLayer), findsOneWidget);
      manager.emit(AdEventType.contentPauseRequested);
      expect(chorki.isAdPlaying.value, isFalse);
      manager.emit(AdEventType.contentResumeRequested);
      await settle(tester);

      expect(find.byType(ChorkiAdLayer), findsNothing);
      expect(shownVideo(tester).value.isPlaying, isFalse);
      expect(platform.onlyPlayer.isPlaying, isFalse, reason: 'last call');
      expect(chorki.isAdPlaying.value, isFalse);
      await unmount(tester);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('changing the controller of a player that is still loading '
        "leaves another player's video attached (bug: detach(null))", (
      tester,
    ) async {
      repo.results['r'] = [Completer<ByteDataEntity>()];
      final other = ChorkiPlayerController(pipDelegate: FakePipDelegate());
      addTearDown(other.dispose);

      Widget players(ChorkiPlayerController loading) => MaterialApp(
        home: Column(
          children: [
            Expanded(child: ChorkiPlayer.url(a, controller: chorki)),
            Expanded(
              child: ChorkiPlayer(route: 'r', controller: loading),
            ),
          ],
        ),
      );

      await tester.pumpWidget(players(chorki));
      await settle(tester);
      expect(chorki.videoController.value?.dataSource, a);

      await tester.pumpWidget(players(other));
      await settle(tester);
      expect(chorki.videoController.value?.dataSource, a);
      await unmount(tester);
    });

    testWidgets('a byte that failed while preloading retries when it becomes '
        'active', (tester) async {
      repo.results['r'] = [_byte(''), _byte(a)];

      Future<void> pumpRoute({required bool preload}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: ChorkiPlayer(
                route: 'r',
                preload: preload,
                controller: chorki,
              ),
            ),
          ),
        );
        await settle(tester);
      }

      await pumpRoute(preload: true);
      // Off screen it keeps the poster: no error view flashing in mid-swipe.
      expect(find.text('Video failed to play'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await pumpRoute(preload: false);
      expect(repo.calls, ['r', 'r']);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      expect(chorki.value.value.isPlaying, isTrue);
      await unmount(tester);
    });

    testWidgets('a preloading byte whose route keeps failing never shows the '
        'error view, and loads when it becomes active', (tester) async {
      const boom = _boom;
      repo.results['r'] = [boom, boom, boom, _byte(a)];

      Widget player({required bool preload}) => MaterialApp(
        home: SizedBox.expand(
          child: ChorkiPlayer(route: 'r', preload: preload, controller: chorki),
        ),
      );

      await tester.pumpWidget(player(preload: true));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      expect(repo.calls, hasLength(3), reason: 'silent retries off screen');
      expect(find.text(_boomText), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(player(preload: false));
      await settle(tester);
      expect(repo.calls, hasLength(4));
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      expect(chorki.value.value.isPlaying, isTrue);
      await unmount(tester);
    });

    testWidgets('swiping fast through a feed creates players only for the '
        'pages it lands near, the visible one first, two at a time', (
      tester,
    ) async {
      final gated = _GatedCreatePlatform();
      VideoPlayerPlatform.instance = gated;
      final pages = PageController();
      addTearDown(pages.dispose);
      var current = 0;
      String url(int i) => 'https://test.local/$i.mp4';

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => PageView.builder(
              controller: pages,
              scrollDirection: Axis.vertical,
              allowImplicitScrolling: true,
              itemCount: 10,
              onPageChanged: (i) => setState(() => current = i),
              itemBuilder: (context, i) => ChorkiPlayer.url(
                url(i),
                preload: i != current,
                controller: chorki,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(gated.started, [url(0), url(1)]);

      // Through 5 to 9 before any of those players could even be created.
      pages.jumpToPage(5);
      await settle(tester);
      pages.jumpToPage(9);
      await settle(tester);
      expect(current, 9);
      expect(gated.started, [url(0), url(1)], reason: 'both slots busy');

      gated.releaseAll();
      await settle(tester);
      expect(gated.started, [url(0), url(1), url(9), url(8)]);
      expect(gated.maxInFlight, 2);

      gated.releaseAll();
      await settle(tester);
      expect(chorki.videoController.value?.dataSource, url(9));
      expect(chorki.value.value.isPlaying, isTrue);
      expect(gated.started, hasLength(4), reason: 'pages 4-6 never created');
      await unmount(tester);
    });

    testWidgets('in a PageView feed, swiping hands the shared controller to '
        'the new byte without marking outside listeners dirty during build', (
      tester,
    ) async {
      var current = 0;
      late StateSetter setCurrent;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setCurrent = setState;
              return Column(
                children: [
                  // Outside the pages, like a progress bar above a feed.
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: chorki.value,
                    builder: (context, value, _) =>
                        Text('playing: ${value.isPlaying}'),
                  ),
                  Expanded(
                    child: PageView.builder(
                      scrollDirection: Axis.vertical,
                      allowImplicitScrolling: true,
                      itemCount: 2,
                      itemBuilder: (context, i) => ChorkiPlayer.url(
                        i == 0 ? a : b,
                        preload: i != current,
                        controller: chorki,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await settle(tester);
      final first = chorki.videoController.value!;
      expect(first.dataSource, a);
      expect(platform.creationOptions, hasLength(2), reason: 'next preloaded');
      await chorki.seekTo(const Duration(seconds: 30));

      setCurrent(() => current = 1);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(chorki.videoController.value?.dataSource, b);
      expect(chorki.value.value.isPlaying, isTrue);
      expect(find.text('playing: true'), findsOneWidget);
      expect(first.value.isPlaying, isFalse);
      expect(first.value.position, Duration.zero);
      await unmount(tester);
    });
  });

  group('ChorkiPlayerSurface', () {
    testWidgets('showControls false shows only the video; turning it on '
        'keeps the same video view', (tester) async {
      VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
      final video = VideoPlayerController.networkUrl(
        Uri.parse('https://test.local/v.mp4'),
      );
      await tester.runAsync(video.initialize);

      Future<void> pumpSurface({required bool showControls}) {
        return tester.pumpWidget(
          MaterialApp(
            home: SizedBox.expand(
              child: ChorkiPlayerSurface(
                controller: video,
                onTogglePlayPause: () {},
                showControls: showControls,
              ),
            ),
          ),
        );
      }

      await pumpSurface(showControls: false);
      expect(find.byType(VideoPlayer), findsOneWidget);
      expect(find.byType(ChorkiShortsSeekBar), findsNothing);
      expect(find.byType(ChorkiGestureOverlay), findsNothing);
      final view = tester.element(find.byType(VideoPlayer));

      await pumpSurface(showControls: true);
      expect(find.byType(ChorkiShortsSeekBar), findsOneWidget);
      expect(find.byType(ChorkiGestureOverlay), findsOneWidget);
      expect(tester.element(find.byType(VideoPlayer)), same(view));

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(video.dispose);
    });

    testWidgets('picks up the video size when the controller initializes '
        'after the first build (bug: the video stayed 0x0)', (tester) async {
      final platform = FakeVideoPlayerPlatform();
      VideoPlayerPlatform.instance = platform;
      final video = VideoPlayerController.networkUrl(
        Uri.parse('https://test.local/v.mp4'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: ChorkiPlayerSurface(
              controller: video,
              onTogglePlayPause: () {},
            ),
          ),
        ),
      );

      // The SizedBox the FittedBox scales: it carries the video's size.
      Size videoBox() {
        final box = tester.widget<SizedBox>(
          find
              .descendant(
                of: find.byKey(const Key('chorki_video_fit')),
                matching: find.byType(SizedBox),
              )
              .first,
        );
        return Size(box.width!, box.height!);
      }

      expect(videoBox(), Size.zero);

      await tester.runAsync(video.initialize);
      await tester.pump();

      expect(videoBox(), const Size(720, 1280));

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(video.dispose);
    });
  });
}
