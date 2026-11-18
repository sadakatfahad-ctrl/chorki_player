import 'package:flutter/foundation.dart';

import '../chorki_analytics_event.dart';

/// How events are named in Matomo (`e_c` / `e_a` / `e_v`).
///
/// [standard] groups events into four categories. [chorkiLegacy] keeps the
/// names the Chorki app already sends (`MediaVideo` / `play` / `pause` /
/// `finished`, with the position as the value), so existing Matomo
/// dashboards keep working when a player moves to this SDK.
@immutable
class MatomoNaming {
  const MatomoNaming({
    this.playbackCategory = 'Video',
    this.qoeCategory = 'Video QoE',
    this.adCategory = 'Video Ads',
    this.uxCategory = 'Video Player',
    this.actions = const {},
    this.positionValue = const {},
  });

  final String playbackCategory;
  final String qoeCategory;
  final String adCategory;
  final String uxCategory;

  /// Replaces the default `e_a` of these event types.
  final Map<ChorkiAnalyticsEventType, String> actions;

  /// These event types send the playback position (whole seconds) as `e_v`
  /// instead of their default value.
  final Set<ChorkiAnalyticsEventType> positionValue;

  static const MatomoNaming standard = MatomoNaming();

  /// Matches the Chorki app's existing Matomo events:
  /// * category `MediaVideo` for playback events;
  /// * `play` on the first play and on every resume, `pause`, and `finished`
  ///   on completion;
  /// * `e_v` = position in seconds for those three.
  ///
  /// Pair it with `MatomoConfig(playerName: 'ShortsPlayer')` for bytes (the
  /// app uses `OttstackPlayer` for long-form) and with
  /// [MatomoConfig.chorkiAppDimensions].
  static const MatomoNaming chorkiLegacy = MatomoNaming(
    playbackCategory: 'MediaVideo',
    actions: {
      ChorkiAnalyticsEventType.resume: 'play',
      ChorkiAnalyticsEventType.complete: 'finished',
    },
    positionValue: {
      ChorkiAnalyticsEventType.play,
      ChorkiAnalyticsEventType.resume,
      ChorkiAnalyticsEventType.pause,
      ChorkiAnalyticsEventType.complete,
    },
  );

  String categoryOf(ChorkiAnalyticsCategory category) => switch (category) {
    ChorkiAnalyticsCategory.playback => playbackCategory,
    ChorkiAnalyticsCategory.qoe => qoeCategory,
    ChorkiAnalyticsCategory.ad => adCategory,
    ChorkiAnalyticsCategory.ux => uxCategory,
  };
}
