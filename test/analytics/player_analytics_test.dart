import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:chorki_player/src/domain/usecases/bytes_usecase.dart';
import 'package:chorki_player/src/errors/server_failure.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;

import '../fakes/fake_pip_delegate.dart';
import '../fakes/fake_video_player_platform.dart';

class _NoRoutes implements ByteRepository {
  @override
  Future<Either<Failure, ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  }) async => throw UnimplementedError();
}

void main() {
  const a = 'https://test.local/a.mp4';
  const b = 'https://test.local/b.mp4';

  late FakeVideoPlayerPlatform platform;
  late ChorkiPlayerController chorki;
  late MemoryAnalyticsSink sink;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<BytesUsecase>(BytesUsecase(_NoRoutes()));
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    sink = MemoryAnalyticsSink();
    chorki = ChorkiPlayerController(
      pipDelegate: FakePipDelegate(),
      analytics: ChorkiAnalyticsConfig(
        sinks: [sink],
        heartbeatInterval: const Duration(hours: 1),
      ),
    );
  });

  tearDown(() async {
    chorki.dispose();
    await getIt.reset();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  Widget feed({required bool aActive}) => MaterialApp(
    home: Column(
      children: [
        Expanded(
          child: ChorkiPlayer.url(
            a,
            preload: !aActive,
            controller: chorki,
            metadata: const ChorkiMediaMetadata(contentId: 'A', feedIndex: 0),
          ),
        ),
        Expanded(
          child: ChorkiPlayer.url(
            b,
            preload: aActive,
            controller: chorki,
            metadata: const ChorkiMediaMetadata(contentId: 'B', feedIndex: 1),
          ),
        ),
      ],
    ),
  );

  List<ChorkiAnalyticsEvent> of(String contentId) =>
      sink.events.where((e) => e.metadata.contentId == contentId).toList();

  testWidgets('in a feed only the active item reports; swiping ends its '
      'session and starts the next one', (tester) async {
    await tester.pumpWidget(feed(aActive: true));
    await settle(tester);

    expect(
      of('A').map((e) => e.type),
      contains(ChorkiAnalyticsEventType.impression),
    );
    expect(of('B'), isEmpty, reason: 'a preloading item reports nothing');
    expect(of('A').first.metadata.mediaUrl, a);

    await tester.pumpWidget(feed(aActive: false));
    await settle(tester);

    final endA = of('A').last;
    expect(endA.type, ChorkiAnalyticsEventType.sessionEnd);
    expect(endA.data['reason'], 'swipedAway');
    expect(
      of('B').map((e) => e.type),
      contains(ChorkiAnalyticsEventType.impression),
    );
    expect(of('B').first.sessionId, isNot(endA.sessionId));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(of('B').last.data['reason'], 'disposed');
  });

  testWidgets('controller commands report to the active item', (tester) async {
    await tester.pumpWidget(feed(aActive: true));
    await settle(tester);

    await chorki.seekTo(const Duration(seconds: 30));
    await chorki.setSpeed(1.5);
    chorki.setFit(ChorkiVideoFit.fill);
    await tester.pump();

    final types = of('A').map((e) => e.type);
    expect(types, contains(ChorkiAnalyticsEventType.seek));
    expect(types, contains(ChorkiAnalyticsEventType.speedChange));
    expect(types, contains(ChorkiAnalyticsEventType.fitChange));
    final seek = of(
      'A',
    ).firstWhere((e) => e.type == ChorkiAnalyticsEventType.seek);
    expect(seek.data['source'], 'api');
    expect(of('B'), isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('changing the URL ends the old view and the new impression '
      'waits for the new video', (tester) async {
    Widget player(String url) =>
        MaterialApp(home: ChorkiPlayer.url(url, controller: chorki));
    await tester.pumpWidget(player(a));
    await settle(tester);
    final first = sink.events.firstWhere(
      (e) => e.type == ChorkiAnalyticsEventType.impression,
    );
    expect(first.metadata.mediaUrl, a);

    sink.clear();
    await tester.pumpWidget(player(b));
    expect(sink.types.first, ChorkiAnalyticsEventType.heartbeat);
    final end = sink.events.firstWhere(
      (e) => e.type == ChorkiAnalyticsEventType.sessionEnd,
    );
    expect(end.data['reason'], 'sourceChanged');
    expect(end.metadata.mediaUrl, a);
    await settle(tester);
    final types = sink.types.toList();
    // The new impression comes after the new load, never from the old video.
    expect(
      types.indexOf(ChorkiAnalyticsEventType.impression),
      greaterThan(types.indexOf(ChorkiAnalyticsEventType.loadStart)),
    );
    final impressions = sink.events
        .where((e) => e.type == ChorkiAnalyticsEventType.impression)
        .toList();
    expect(impressions, hasLength(1));
    expect(impressions.single.metadata.mediaUrl, b);
    expect(impressions.single.sessionId, isNot(first.sessionId));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a double tap is reported as a doubleTap seek', (tester) async {
    await tester.pumpWidget(feed(aActive: true));
    await settle(tester);

    final overlay = find.byType(PlayerGestureOverlay).first;
    final box = tester.getRect(overlay);
    final right = Offset(box.right - 20, box.center.dy);
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(right);
    await tester.pump(const Duration(milliseconds: 900));

    final seeks = of('A').where((e) => e.type == ChorkiAnalyticsEventType.seek);
    expect(seeks.single.data['source'], 'doubleTap');
    expect(seeks.single.data['toMs'], 10000);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
