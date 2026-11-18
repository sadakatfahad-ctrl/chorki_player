import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';

/// Matomo server. Pass it with `--dart-define`, or keep it in a local file:
///
/// ```sh
/// # example/matomo.local.json (gitignored):
/// # {"MATOMO_URL": "https://analytics.example.com/matomo.php",
/// #  "MATOMO_SITE_ID": "3", "MATOMO_DIMENSIONS": "false"}
/// flutter run --dart-define-from-file=matomo.local.json
/// ```
///
/// Without a URL, events are only logged.
const _matomoUrl = String.fromEnvironment('MATOMO_URL');
const _matomoSiteId = int.fromEnvironment('MATOMO_SITE_ID', defaultValue: 1);

/// Sends the example's Custom Dimensions. Turn it off for a site whose
/// dimension ids already mean something else.
const _matomoDimensions = bool.fromEnvironment(
  'MATOMO_DIMENSIONS',
  defaultValue: true,
);

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
          dimensionIds: _matomoDimensions
              ? {'contentId': 1, 'category': 2, 'contentType': 3}
              : {},
        ),
        transport: _LoggingTransport(DioMatomoTransport()),
        userProperties: const {'appVariant': 'example'},
      );

/// Logs each batch sent to Matomo and whether it was accepted (debug builds).
class _LoggingTransport implements MatomoTransport {
  _LoggingTransport(this._inner);
  final MatomoTransport _inner;

  @override
  Future<bool> send(Uri endpoint, List<String> requests) async {
    final ok = await _inner.send(endpoint, requests);
    if (kDebugMode) {
      debugPrint(
        '[matomo] ${requests.length} requests -> ${endpoint.host} '
        '${ok ? 'accepted' : 'FAILED (will retry)'}',
      );
    }
    return ok;
  }
}

/// Prints errors the SDK recovered from (debug builds).
void logChorkiDiagnostics() {
  ChorkiDiagnostics.onError = (error, stack, context) {
    if (kDebugMode) debugPrint('[chorki] $context: $error');
  };
}

final ChorkiAnalyticsConfig exampleAnalytics = ChorkiAnalyticsConfig(
  sinks: [debugLogSink, ?matomoSink],
);
