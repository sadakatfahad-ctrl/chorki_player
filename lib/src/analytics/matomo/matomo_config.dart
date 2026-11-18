import 'package:flutter/foundation.dart';

import '../chorki_analytics_event.dart';
import 'analytics_storage.dart';
import 'matomo_naming.dart';

/// What `ma_w` / `ma_h` report.
enum MatomoMediaSize {
  /// The video's own resolution (e.g. 1080x1920).
  video,

  /// The screen area in logical pixels, like the Chorki app's other players
  /// (`MediaQuery.sizeOf(context)`).
  viewport,
}

/// Settings for [MatomoAnalyticsSink].
@immutable
class MatomoConfig {
  const MatomoConfig({
    required this.url,
    required this.siteId,
    this.dimensionIds = const {},
    this.mediaAnalytics = true,
    this.eventTracking = true,
    this.excludedEvents = defaultExcludedEvents,
    this.playerName = 'chorki_player',
    this.appUrl = 'app://chorki',
    this.fullscreen,
    this.userAgent,
    this.batchSize = 20,
    this.flushInterval = const Duration(seconds: 10),
    this.maxQueueLength = 500,
    this.requestTimeout = const Duration(seconds: 10),
    this.storage,
    this.visitorIdProvider,
    this.naming = MatomoNaming.standard,
    this.mediaSize = MatomoMediaSize.video,
  }) : assert(batchSize > 0),
       assert(maxQueueLength > 0);

  /// Your Matomo base URL, e.g. `https://analytics.example.com`, or the full
  /// tracker endpoint ending in `matomo.php`.
  final String url;

  /// The Matomo website / app id (`idsite`).
  final int siteId;

  /// Maps value keys to the ids of Custom Dimensions you created in Matomo
  /// (Administration › Websites › Custom Dimensions). Keys can be:
  /// * any [ChorkiMediaMetadata.toMap] key (`contentId`, `title`, `seriesId`,
  ///   `category`, `contentType`, `seasonNumber`, `episodeNumber`,
  ///   `feedIndex`, or a key of `extra`),
  /// * a key of [MatomoAnalyticsSink.userProperties] (e.g.
  ///   `subscriptionTier`),
  /// * `sessionId`, `playerName`, `adCampaignId`, `adCampaignTitle`,
  ///   `qualityHeight`, `eventType`.
  ///
  /// Example: `{'contentId': 1, 'category': 2, 'subscriptionTier': 3}`.
  final Map<String, int> dimensionIds;

  /// Send Media Analytics (`ma_*`) requests: an impression and heartbeats
  /// with the watched time and segments. Needs the premium Media Analytics
  /// plugin on the Matomo server; without it the requests are ignored as
  /// actions (they carry `ca=1`).
  final bool mediaAnalytics;

  /// Send every other event as a Matomo Event (`e_c` / `e_a` / `e_n` /
  /// `e_v`).
  final bool eventTracking;

  /// Event types never sent as Matomo Events.
  final Set<ChorkiAnalyticsEventType> excludedEvents;

  static const Set<ChorkiAnalyticsEventType> defaultExcludedEvents = {
    // Media Analytics covers progress; bufferEnd carries the stall length.
    ChorkiAnalyticsEventType.heartbeat,
    ChorkiAnalyticsEventType.loadStart,
    ChorkiAnalyticsEventType.bufferStart,
  };

  /// `ma_pn`.
  final String playerName;

  /// Base of the `url` reported with every request; the content id is
  /// appended (`app://chorki/video/<contentId>`).
  final String appUrl;

  /// `ma_fs`. Null leaves it out.
  final bool? fullscreen;

  /// Sent as the `ua` parameter, so Matomo can detect the device and OS.
  /// Defaults to the HTTP client's user agent.
  final String? userAgent;

  /// Requests per HTTP call (Matomo bulk tracking).
  final int batchSize;

  /// Longest time a request waits before it is sent.
  final Duration flushInterval;

  /// Oldest requests are dropped beyond this.
  final int maxQueueLength;

  final Duration requestTimeout;

  /// Keeps the visitor id and unsent requests. Defaults to memory only.
  final ChorkiAnalyticsStorage? storage;

  /// The visitor id (`_id`) of another Matomo tracker in the app, read when
  /// requests are sent. Use it so the app's screen views and the player's
  /// video data stay one Matomo visitor, e.g. with `matomo_tracker`:
  /// `visitorIdProvider: () => MatomoTracker.instance.visitor.id`.
  /// Returning null (tracker not ready) or an invalid id (not 16 hex
  /// characters) falls back to the sink's own persistent id.
  final String? Function()? visitorIdProvider;

  /// Event categories and actions; [MatomoNaming.chorkiLegacy] keeps the
  /// Chorki app's existing names.
  final MatomoNaming naming;

  /// What `ma_w` / `ma_h` report.
  final MatomoMediaSize mediaSize;

  /// The Chorki app's custom dimensions: `dimension1` user id, `2`
  /// subscription (`Subscribed` / `Non-Subscribed`), `3` app version, `4`
  /// playback output, `5` output model. Set the values with
  /// [MatomoAnalyticsSink.setUserProperty] (`userId`, `subscription`,
  /// `appVersion`, ...).
  static const Map<String, int> chorkiAppDimensions = {
    'userId': 1,
    'subscription': 2,
    'appVersion': 3,
    'playbackOutput': 4,
    'outputModel': 5,
  };

  /// The tracker endpoint.
  Uri get endpoint {
    final trimmed = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return Uri.parse(
      trimmed.endsWith('.php') ? trimmed : '$trimmed/matomo.php',
    );
  }
}
