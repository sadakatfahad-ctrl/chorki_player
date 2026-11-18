import 'package:flutter/foundation.dart';
import 'package:interactive_media_ads/interactive_media_ads.dart';

/// IMA ad settings for a [ChorkiPlayer]-style player (`ChorkiPlayer.ads`).
///
/// Ads play only when this is set, [enabled] is true and the byte has an ad
/// tag (a campaign, or `adTagUrl` with `ChorkiPlayer.url`). Break timing
/// comes from the campaign's VMAP; there are no roll settings here. A
/// preloading player (`ChorkiPlayer.preload`) requests no ads: the request,
/// the pre-roll and [loadTimeout] all start when the byte becomes active.
@immutable
class ChorkiAdConfig {
  /// Ads on, IMA preloading on, an 8 s load timeout.
  const ChorkiAdConfig({
    this.enabled = true,
    this.progressInterval = const Duration(milliseconds: 200),
    this.enablePreloading = true,
    this.loadTimeout = const Duration(seconds: 8),
    this.onAdEvent,
    this.onAdError,
  });

  /// Turns ads on or off for this player without removing the config.
  /// Default `true`.
  final bool enabled;

  /// How often content progress is reported to IMA while the content plays;
  /// mid-rolls start on the first report at or past their offset, and the
  /// seek bar's ad markers update at this rate. Default 200 ms.
  final Duration progressInterval;

  /// Lets IMA buffer an ad's media before its break starts, for smoother
  /// breaks (IMA `AdsRenderingSettings.enablePreloading`). Unrelated to
  /// `ChorkiPlayer.preload`. Default `true`.
  final bool enablePreloading;

  /// Content is shown and played if no ad has started (or been ruled out)
  /// within this time, e.g. when the IMA SDK hangs. Reported through
  /// [onAdError]. Ads that arrive later still play. Null disables it.
  /// Default 8 s, counted from when the byte becomes active (never while it
  /// preloads).
  final Duration? loadTimeout;

  /// Called with every raw IMA event (loaded, started, completed, ...), in
  /// addition to the analytics the player reports itself.
  final ValueChanged<AdEvent>? onAdEvent;

  /// Called with a message when an ad fails to load or play, or
  /// [loadTimeout] passes. The content plays on; nothing is shown to the
  /// viewer.
  final ValueChanged<String>? onAdError;
}
