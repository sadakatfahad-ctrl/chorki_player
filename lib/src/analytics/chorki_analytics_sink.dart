import 'package:flutter/foundation.dart';

import 'chorki_analytics_event.dart';

/// Receives the player's analytics events. Implement it to forward events to
/// any backend (Firebase, Mixpanel, your own API). [MatomoAnalyticsSink] is
/// the built-in Matomo implementation.
///
/// One sink is usually shared by every player in the app; create it once and
/// dispose it when the app shuts down.
abstract class ChorkiAnalyticsSink {
  /// Called synchronously, in order, for every event. Do not throw: errors
  /// are reported to [ChorkiDiagnostics] and otherwise ignored, so analytics
  /// can never break playback. Ignore keys you do not know: new ones may be
  /// added in minor versions (see [ChorkiAnalyticsSchema]).
  void onEvent(ChorkiAnalyticsEvent event);

  /// Sends anything buffered. Called when the app goes to the background.
  Future<void> flush() async {}

  /// The viewer withdrew consent ([ChorkiAnalyticsConfig.consentGranted]
  /// became false): drop anything buffered and not yet sent.
  Future<void> onConsentRevoked() async {}

  /// Releases resources. The player never calls this; the owner does.
  Future<void> dispose() async {}
}

/// Forwards every event to [callback], e.g. to log them during development.
class CallbackAnalyticsSink extends ChorkiAnalyticsSink {
  /// Forwards to [callback].
  CallbackAnalyticsSink(this.callback);

  /// Receives every event.
  final ValueChanged<ChorkiAnalyticsEvent> callback;

  @override
  void onEvent(ChorkiAnalyticsEvent event) => callback(event);
}

/// Keeps every event in [events]; handy in tests.
class MemoryAnalyticsSink extends ChorkiAnalyticsSink {
  /// Everything received, oldest first.
  final List<ChorkiAnalyticsEvent> events = [];

  /// The types of [events].
  Iterable<ChorkiAnalyticsEventType> get types => events.map((e) => e.type);

  @override
  void onEvent(ChorkiAnalyticsEvent event) => events.add(event);

  /// Forgets everything received (consent was revoked).
  @override
  Future<void> onConsentRevoked() async => events.clear();

  /// Forgets everything received.
  void clear() => events.clear();
}
