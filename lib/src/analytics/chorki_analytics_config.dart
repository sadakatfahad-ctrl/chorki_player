import 'package:flutter/foundation.dart';

import 'chorki_analytics_sink.dart';

/// Turns analytics on for a [ChorkiPlayer] (or every player sharing a
/// [ChorkiPlayerController], via [ChorkiPlayerController.analytics]).
@immutable
class ChorkiAnalyticsConfig {
  const ChorkiAnalyticsConfig({
    required this.sinks,
    this.enabled = true,
    this.consentGranted = true,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.segmentLength = const Duration(seconds: 5),
    this.newSessionOnLoop = true,
  }) : assert(segmentLength > Duration.zero);

  /// Where the events go.
  final List<ChorkiAnalyticsSink> sinks;

  /// Master switch.
  final bool enabled;

  /// Set to false until the viewer agrees to analytics; nothing is reported
  /// (or buffered) while it is false.
  final bool consentGranted;

  /// How often a [ChorkiAnalyticsEventType.heartbeat] is sent while playing.
  /// Matomo recommends about 10 seconds.
  final Duration heartbeatInterval;

  /// Size of the watched-segment buckets reported in heartbeats (Matomo
  /// `ma_se`). Matomo recommends 5 seconds.
  final Duration segmentLength;

  /// When a looping video restarts, end the session and start a new one (a
  /// new `ma_id`), so each loop counts as a play. When false a loop only
  /// emits `complete` + `loop` and the watched time keeps growing.
  final bool newSessionOnLoop;

  bool get isActive => enabled && consentGranted && sinks.isNotEmpty;
}
