import 'package:chorki_player/chorki_player.dart'
    hide AdCampaignEntity, ByteDataEntity;
import 'package:chorki_player/src/ads/chorki_ad_layer.dart';
import 'package:chorki_player/src/domain/entity/ad_campaign_entity.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/presentation/bytes_screen/byte_screen_event.dart';
import 'package:chorki_player/src/presentation/player/player_loading_view.dart';
import 'package:chorki_player/src/presentation/player/player_source.dart';
import 'package:chorki_player/src/presentation/player/player_video_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as pi;

import '../fakes/fake_video_player_platform.dart';

void main() {
  group('player source', () {
    test('a route loads through the repository', () {
      final e = loadEventFor(
        route: 'bytes/1',
        videoUrl: null,
        posterUrl: '',
        adTagUrl: '',
        refresh: true,
      );
      expect(e, isA<ByteScreenInitialEvent>());
      expect((e as ByteScreenInitialEvent).refresh, isTrue);
    });

    test('a direct URL is wrapped as resolved byte data', () {
      final e = loadEventFor(
        route: '',
        videoUrl: 'https://v/1.m3u8',
        posterUrl: 'https://p.jpg',
        adTagUrl: 'https://ads',
      );
      final data = (e as ByteScreenSourceEvent).data;
      expect(data.url, 'https://v/1.m3u8');
      expect(data.thumbnailUrl, 'https://p.jpg');
      expect(data.adTagUrl, 'https://ads');

      final noAds = loadEventFor(
        route: '',
        videoUrl: 'https://v/1.m3u8',
        posterUrl: '',
        adTagUrl: '',
      );
      expect((noAds as ByteScreenSourceEvent).data.adCampaign, isNull);
    });

    test('metadata is completed from the byte, never overridden', () {
      final data = const ByteDataEntity(
        id: 7,
        thumbnailUrl: '',
        url: 'https://v',
      );
      final filled = metadataFor(null, data, null);
      expect(filled.contentId, '7');
      expect(filled.mediaUrl, 'https://v');

      final given = metadataFor(
        const ChorkiMediaMetadata(contentId: 'c', mediaUrl: 'm'),
        data,
        null,
      );
      expect(given.contentId, 'c');
      expect(given.mediaUrl, 'm');

      final direct = metadataFor(null, null, 'https://direct');
      expect(direct.contentId, isNull, reason: 'id 0 / no byte is no id');
      expect(direct.mediaUrl, 'https://direct');
    });

    test('ad context carries the campaign id and title when set', () {
      expect(adContextOf(null), isEmpty);
      final data = const ByteDataEntity(
        id: 1,
        thumbnailUrl: '',
        url: 'u',
        adCampaign: AdCampaignEntity(id: 'c9', title: '', url: 'tag'),
      );
      expect(adContextOf(data), {ChorkiAnalyticsKeys.adCampaignId: 'c9'});
    });
  });

  group('PlayerLoadingView', () {
    Widget host(String? poster) => MaterialApp(
      home: PlayerLoadingView(
        theme: const ChorkiPlayerTheme(),
        fit: ValueNotifier(ChorkiVideoFit.fit),
        posterUrl: poster,
      ),
    );

    testWidgets('shows a spinner and no poster without a URL', (tester) async {
      await tester.pumpWidget(host(''));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('shows the poster under the spinner', (tester) async {
      await tester.pumpWidget(host('https://p.jpg'));
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('PlayerVideoView', () {
    late FakeVideoPlayerPlatform platform;
    setUp(() {
      platform = FakeVideoPlayerPlatform();
      pi.VideoPlayerPlatform.instance = platform;
    });

    Future<void> pumpView(
      WidgetTester tester, {
      required bool preloading,
      ChorkiAdConfig? ads,
      String tag = 'https://ads',
    }) async {
      final controller = await tester.runAsync(
        () => createTestController(platform),
      );
      final chorki = ChorkiPlayerController();
      addTearDown(chorki.dispose);
      addTearDown(controller!.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerVideoView(
            player: ChorkiPlayer.url('https://v', ads: ads),
            controller: controller,
            chorki: chorki,
            adTagUrl: tag,
            preloading: preloading,
            onTogglePlayPause: () {},
            onAdPlayingChanged: (_) {},
          ),
        ),
      );
    }

    testWidgets('without an ad config it is just the surface', (tester) async {
      await pumpView(tester, preloading: false);
      expect(find.byType(ChorkiPlayerSurface), findsOneWidget);
      expect(find.byType(ChorkiAdLayer), findsNothing);
    });

    testWidgets('a preloading byte requests no ads', (tester) async {
      await pumpView(tester, preloading: true, ads: const ChorkiAdConfig());
      expect(find.byType(ChorkiAdLayer), findsNothing);
    });

    testWidgets('no ad tag, no ad layer', (tester) async {
      await pumpView(
        tester,
        preloading: false,
        ads: const ChorkiAdConfig(),
        tag: '',
      );
      expect(find.byType(ChorkiAdLayer), findsNothing);
    });
  });
}
