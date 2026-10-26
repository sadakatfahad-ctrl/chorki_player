import 'package:flutter/foundation.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';

@immutable
class ChorkiAdConfig {
  const ChorkiAdConfig({
    this.enabled = true,
    this.progressInterval = const Duration(milliseconds: 200),
    this.enablePreloading = true,
    this.loadTimeout = const Duration(seconds: 8),
    this.onAdEvent,
    this.onAdError,
  });

  final bool enabled;

  final Duration progressInterval;

  final bool enablePreloading;

  /// Content is shown and played if no ad has started (or been ruled out)
  /// within this time, e.g. when the IMA SDK hangs. Reported through
  /// [onAdError]. Ads that arrive later still play. Null disables it.
  final Duration? loadTimeout;

  final ValueChanged<AdEvent>? onAdEvent;

  final ValueChanged<String>? onAdError;
}
