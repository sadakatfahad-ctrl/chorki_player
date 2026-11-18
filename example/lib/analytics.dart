import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';

/// Matomo server, e.g.
/// `flutter run --dart-define=MATOMO_URL=https://analytics.example.com
/// --dart-define=MATOMO_SITE_ID=3`. Without it events are only logged.
const _matomoUrl = String.fromEnvironment('MATOMO_URL');
const _matomoSiteId = int.fromEnvironment('MATOMO_SITE_ID', defaultValue: 1);

/// Logs every analytics event to the console (debug builds).
final ChorkiAnalyticsSink debugLogSink = CallbackAnalyticsSink((e) {
  if (!kDebugMode) return;
  debugPrint(
    '[analytics] ${e.type.name.padRight(16)} '
    '${e.metadata.title ?? e.metadata.contentId ?? ''} '
    'pos=${e.position.inSeconds}s watched=${e.watchedTime.inSeconds}s '
    '${e.data.isEmpty ? '' : e.data}',
  );
});

/// One Matomo sink for the whole app.
final MatomoAnalyticsSink? matomoSink = _matomoUrl.isEmpty
    ? null
    : MatomoAnalyticsSink(
        const MatomoConfig(
          url: _matomoUrl,
          siteId: _matomoSiteId,
          // Create these Custom Dimensions in Matomo first (action scope).
          dimensionIds: {'contentId': 1, 'category': 2, 'contentType': 3},
        ),
        userProperties: const {'appVariant': 'example'},
      );

final ChorkiAnalyticsConfig exampleAnalytics = ChorkiAnalyticsConfig(
  sinks: [debugLogSink, ?matomoSink],
);
