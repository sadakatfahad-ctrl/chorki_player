// reportAdEvent's event mapping is driven through the fake IMA platform in
// ad_layer_test ("IMA events are reported to the analytics session");
// AdEvent has no public constructor to call it directly.
import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/ads/ad_event_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';
import 'package:interactive_media_ads/src/platform_interface/platform_interface.dart';

PlatformAd _ad({String? title = 'Spring sale', String advertiser = 'Acme'}) =>
    PlatformAd(
      adId: 'ad1',
      adPodInfo: PlatformAdPodInfo(
        adPosition: 2,
        maxDuration: null,
        podIndex: 0,
        timeOffset: Duration.zero,
        totalAds: 3,
        isBumper: false,
      ),
      adSystem: 'GDFP',
      wrapperCreativeIds: const [],
      wrapperIds: const [],
      wrapperSystems: const [],
      advertiserName: advertiser,
      companionAds: const [],
      contentType: null,
      creativeAdId: '',
      creativeId: '',
      dealId: '',
      description: null,
      duration: const Duration(seconds: 15),
      width: 0,
      height: 0,
      skipTimeOffset: null,
      surveyUrl: null,
      title: title,
      traffickingParameters: '',
      uiElements: const {},
      universalAdIds: const [],
      vastMediaBitrate: 0,
      vastMediaWidth: 0,
      vastMediaHeight: 0,
      isLinear: true,
      isSkippable: true,
    );

void main() {
  test('no ad means no ad details', () {
    expect(adDetailsOf(null), isEmpty);
  });

  test('an ad is described by the schema keys', () {
    expect(adDetailsOf(Ad.fromPlatform(_ad())), {
      ChorkiAnalyticsKeys.adId: 'ad1',
      ChorkiAnalyticsKeys.adTitle: 'Spring sale',
      ChorkiAnalyticsKeys.adSystem: 'GDFP',
      ChorkiAnalyticsKeys.advertiser: 'Acme',
      ChorkiAnalyticsKeys.adDurationMs: 15000,
      ChorkiAnalyticsKeys.skippable: true,
      ChorkiAnalyticsKeys.podPosition: 2,
      ChorkiAnalyticsKeys.podTotal: 3,
    });
  });

  test('empty title and advertiser are left out', () {
    final details = adDetailsOf(
      Ad.fromPlatform(_ad(title: '', advertiser: '')),
    );
    expect(details.containsKey(ChorkiAnalyticsKeys.adTitle), isFalse);
    expect(details.containsKey(ChorkiAnalyticsKeys.advertiser), isFalse);
  });
}
