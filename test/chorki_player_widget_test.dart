import 'dart:async';

import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_state.dart';
import 'package:chorki_player/src/presentation/bytes_screen/bytes_screen_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart'
    hide VideoTrack, VideoAudioTrack;
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show DataSourceType, VideoCreationOptions, VideoEvent, VideoPlayerPlatform;

import 'fakes/fake_pip_delegate.dart';
import 'fakes/fake_video_player_platform.dart';

ByteDataEntity _byte(String url, {String thumbnail = ''}) =>
    ByteDataEntity(id: 1, thumbnailUrl: thumbnail, url: url);

/// Answers each route with the next queued result; a [Completer] result
/// stays pending until the test completes it.
class _FakeRepository implements ByteRepository {
  final Map<String, List<Object>> results = {};
  final List<String> calls = [];

  @override
  Future<Either<Failure, ByteDataEntity>> getByteData(String url) async {
    calls.add(url);
    final next = results[url]!.removeAt(0);
    final data = next is Completer<ByteDataEntity>
        ? await next.future
        : next as ByteDataEntity;
    return Right(data);
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

void main() {
  group('VideoPreloader', () {
    testWidgets('times out even when the platform never creates the player '
        '(bug: awaiting dispose() hung the load forever)', (tester) async {
      VideoPlayerPlatform.instance = _StuckCreatePlatform();
      final preloader = VideoPreloader(initTimeout: const Duration(seconds: 2));
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
      await getIt.reset();
      repo = _FakeRepository();
      getIt.registerSingleton<BytesUsecase>(BytesUsecase(repo));
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
      await getIt.reset();
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

      // Let the preloader's init timeout fire.
      await tester.pump(const Duration(seconds: 16));
      await unmount(tester);
    });
  });

  group('ChorkiPlayer.url', () {
    late FakeVideoPlayerPlatform platform;
    late _FakeRepository repo;
    late ChorkiPlayerController chorki;

    setUp(() async {
      await getIt.reset();
      repo = _FakeRepository();
      getIt.registerSingleton<BytesUsecase>(BytesUsecase(repo));
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
      await getIt.reset();
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

  group('ChorkiPlayerSurface', () {
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
