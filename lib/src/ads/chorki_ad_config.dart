import 'package:flutter/foundation.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';

@immutable
class ChorkiAdConfig {
  const ChorkiAdConfig({
    this.enabled = true,
    this.progressInterval = const Duration(milliseconds: 200),
    this.enablePreloading = true,
    this.onAdEvent,
    this.onAdError,
  });

  final bool enabled;

  final Duration progressInterval;

  final bool enablePreloading;

  final ValueChanged<AdEvent>? onAdEvent;

  final ValueChanged<String>? onAdError;
}
