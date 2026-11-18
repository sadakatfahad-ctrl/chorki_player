// README excerpt for the Chorki app (see usage.dart). The app depends on
// package:matomo_tracker; this example does not, so the few app types the
// snippet uses are placeholders declared below, outside the region.
// ignore_for_file: non_constant_identifier_names, unused_local_variable

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/widgets.dart';

/// Placeholder for the app's remote settings.
class ReadmeAppSettings {
  const ReadmeAppSettings(
    this.analytics_matomo_url,
    this.analytics_matomo_site_id,
  );
  final String? analytics_matomo_url;
  final String? analytics_matomo_site_id;
}

/// Placeholder for `MatomoTracker` from package:matomo_tracker.
class MatomoTracker {
  MatomoTracker._();
  static final MatomoTracker instance = MatomoTracker._();
  final ({String id}) visitor = (id: 'visitor-id');
}

/// Placeholder for a byte in the app's feed.
class ReadmeAppByte {
  const ReadmeAppByte(this.id, this.title, this.routeUri);
  final String id;
  final String title;
  final String routeUri;
}

/// Placeholder for the signed-in viewer.
class ReadmeAppUser {
  const ReadmeAppUser(this.id);
  final String id;
}

Widget chorkiApp(
  ReadmeAppSettings settings,
  ReadmeAppUser user,
  ReadmeAppByte byte, {
  required bool subscribed,
  required String appVersion,
  required String frontendUrl,
}) {
  // #region chorki-app
  final matomo = MatomoAnalyticsSink(
    MatomoConfig(
      url: settings.analytics_matomo_url!,
      siteId: int.parse(settings.analytics_matomo_site_id!),
      // Same visitor as the app's screen views.
      visitorIdProvider: () => MatomoTracker.instance.visitor.id,
      // MediaVideo / play / pause / finished, e_v = position.
      naming: MatomoNaming.chorkiLegacy,
      playerName: 'ShortsPlayer',
      // dimension1 user id, 2 subscription, 3 app version, 4/5 cast output.
      dimensionIds: MatomoConfig.chorkiAppDimensions,
      mediaSize:
          MatomoMediaSize.viewport, // ma_w/ma_h = screen, as the app does
    ),
  );
  matomo
    ..userId = user.id
    ..setUserProperty('userId', user.id)
    ..setUserProperty(
      'subscription',
      subscribed ? 'Subscribed' : 'Non-Subscribed',
    )
    ..setUserProperty('appVersion', appVersion);

  ChorkiPlayer(
    route: byte.routeUri,
    metadata: ChorkiMediaMetadata(
      contentId: byte.id,
      title: byte.title,
      pageUrl: '$frontendUrl${byte.routeUri}',
      contentType: 'byte',
    ),
    analytics: ChorkiAnalyticsConfig(sinks: [matomo]),
  );
  // #endregion
  return const SizedBox();
}
