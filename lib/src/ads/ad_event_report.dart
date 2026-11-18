import 'package:interactive_media_ads/interactive_media_ads.dart';

import '../analytics/chorki_analytics_event.dart';
import '../analytics/chorki_analytics_schema.dart';
import '../analytics/chorki_analytics_session.dart';
import '../core/diagnostics.dart';

/// Records the analytics event for an IMA [event] (start, quartiles,
/// complete, skip, click, pause, resume) on [analytics]. Other IMA events
/// are not reported here.
void reportAdEvent(ChorkiAnalyticsSession analytics, AdEvent event) {
  final (type, percent) = switch (event.type) {
    AdEventType.started => (ChorkiAnalyticsEventType.adStart, null),
    AdEventType.firstQuartile => (ChorkiAnalyticsEventType.adQuartile, 25),
    AdEventType.midpoint => (ChorkiAnalyticsEventType.adQuartile, 50),
    AdEventType.thirdQuartile => (ChorkiAnalyticsEventType.adQuartile, 75),
    AdEventType.complete => (ChorkiAnalyticsEventType.adComplete, null),
    AdEventType.skipped => (ChorkiAnalyticsEventType.adSkip, null),
    AdEventType.clicked ||
    AdEventType.tapped => (ChorkiAnalyticsEventType.adClick, null),
    AdEventType.paused => (ChorkiAnalyticsEventType.adPause, null),
    AdEventType.resumed => (ChorkiAnalyticsEventType.adResume, null),
    _ => (null, null),
  };
  if (type == null) return;
  analytics.recordAd(type, {
    ...adDetailsOf(event.ad),
    ChorkiAnalyticsKeys.percent: ?percent,
  });
}

/// The ad's id, title, system, advertiser, duration, skippability and pod
/// position, as analytics data. Empty when there is no ad or the platform
/// fails to describe it (reported as `ads.adInfo`).
Map<String, Object?> adDetailsOf(Ad? ad) {
  if (ad == null) return const {};
  try {
    final pod = ad.adPodInfo;
    return {
      ChorkiAnalyticsKeys.adId: ad.adId,
      if (ad.title case final t? when t.isNotEmpty)
        ChorkiAnalyticsKeys.adTitle: t,
      ChorkiAnalyticsKeys.adSystem: ad.adSystem,
      if (ad.advertiserName.isNotEmpty)
        ChorkiAnalyticsKeys.advertiser: ad.advertiserName,
      if (ad.duration case final d?)
        ChorkiAnalyticsKeys.adDurationMs: d.inMilliseconds,
      ChorkiAnalyticsKeys.skippable: ad.isSkippable,
      ChorkiAnalyticsKeys.podPosition: pod.adPosition,
      ChorkiAnalyticsKeys.podTotal: pod.totalAds,
    };
  } catch (e, st) {
    ChorkiDiagnostics.report(e, st, 'ads.adInfo');
    return const {};
  }
}
