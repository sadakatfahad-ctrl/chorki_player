import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';

import 'chorki_media_metadata.dart';

/// Broad grouping of [ChorkiAnalyticsEventType]s.
enum ChorkiAnalyticsCategory {
  /// What the viewer watched: impressions, plays, pauses, seeks, progress.
  playback,

  /// Quality of experience: startup time, rebuffering, errors, retries.
  qoe,

  /// IMA ads.
  ad,

  /// Settings and player UI: quality, audio, speed, fit, PiP, volume.
  ux,
}

/// Every event the player reports.
///
/// Each value's `Data:` line lists the [ChorkiAnalyticsEvent.data] keys it
/// carries (constants in [ChorkiAnalyticsKeys]); [ChorkiAnalyticsSchema] has
/// their types. Ad events also carry the *ad context* (`breakIndex`,
/// `adCampaignId`, `adCampaignTitle`) and, when IMA provides them, the *ad
/// details* (`adId`, `adTitle`, `adSystem`, `advertiser`, `adDurationMs`,
/// `skippable`, `podPosition`, `podTotal`).
enum ChorkiAnalyticsEventType {
  // ----------------------------------------------------------------- playback
  /// The item is on screen with its video loaded. Once per view.
  ///
  /// Data: `loopCount` (a loop's new view).
  impression(ChorkiAnalyticsCategory.playback),

  /// First frame played in this view.
  ///
  /// Data: `timeToPlayMs`, `loopCount`.
  play(ChorkiAnalyticsCategory.playback),

  /// The viewer (or the app) paused.
  ///
  /// Data: none.
  pause(ChorkiAnalyticsCategory.playback),

  /// Playback resumed after a [pause].
  ///
  /// Data: none.
  resume(ChorkiAnalyticsCategory.playback),

  /// A seek. `source` is a [ChorkiSeekSource] name.
  ///
  /// Data: `fromMs`, `toMs`, `source`.
  seek(ChorkiAnalyticsCategory.playback),

  /// Periodic progress while playing, and a final one before pause / seek /
  /// complete / ad / background / end (`trigger`).
  ///
  /// Data: `trigger`, `newSegments`.
  heartbeat(ChorkiAnalyticsCategory.playback),

  /// 25 / 50 / 75 / 100 % of the duration reached.
  ///
  /// Data: `percent`.
  quartile(ChorkiAnalyticsCategory.playback),

  /// Played to the end (also on every loop of a looping video).
  ///
  /// Data: none.
  complete(ChorkiAnalyticsCategory.playback),

  /// A looping video restarted.
  ///
  /// Data: `loopCount`.
  loop(ChorkiAnalyticsCategory.playback),

  /// The view is over. `reason` is a [ChorkiSessionEndReason] name.
  ///
  /// Data: `reason`, `dwellMs`, `watchedPercent`, `maxPositionMs`,
  /// `rebufferCount`, `rebufferMs`, `pauseCount`, `seekCount`, `loopCount`,
  /// `errorCount`.
  sessionEnd(ChorkiAnalyticsCategory.playback),

  // ---------------------------------------------------------------------- QoE
  /// The video load started (it may still wait in [ChorkiVideoLoadScheduler]).
  ///
  /// Data: none.
  loadStart(ChorkiAnalyticsCategory.qoe),

  /// The first frame is shown. `startupMs` counts from activation or load
  /// start, whichever is later; load timings only when this view waited for
  /// the load.
  ///
  /// Data: `startupMs`, `queueWaitMs`, `initMs`, `preloaded`.
  firstFrame(ChorkiAnalyticsCategory.qoe),

  /// Playback stalled to buffer (after the first frame).
  ///
  /// Data: `afterSeek`.
  bufferStart(ChorkiAnalyticsCategory.qoe),

  /// The stall ended.
  ///
  /// Data: `durationMs`.
  bufferEnd(ChorkiAnalyticsCategory.qoe),

  /// A route, load or playback failure (see [ChorkiPlayerError]).
  ///
  /// Data: `code`, `stage`, `transient`, `willRetry`, `statusCode`,
  /// `detail`.
  error(ChorkiAnalyticsCategory.qoe),

  /// A reload; `auto` when it was not the viewer's.
  ///
  /// Data: `attempt`, `auto`.
  retry(ChorkiAnalyticsCategory.qoe),

  /// The rendition changed (null heights mean Auto).
  ///
  /// Data: `fromHeight`, `toHeight`, `bitrate`, `label`, `auto`.
  qualityChange(ChorkiAnalyticsCategory.qoe),

  /// The view ended before anything played ("exit before video start").
  /// `abandonStage` is `loading` (never loaded) or `ready` (loaded, never
  /// played). Views = plays + abandons.
  ///
  /// Data: `waitedMs`, `reason`, `abandonStage`, `errorCount`.
  abandon(ChorkiAnalyticsCategory.qoe),

  // ---------------------------------------------------------------------- ads
  /// An ad break paused the content.
  ///
  /// Data: `breakKind` + the ad context.
  adBreakStart(ChorkiAnalyticsCategory.ad),

  /// An ad started.
  ///
  /// Data: the ad context and details.
  adStart(ChorkiAnalyticsCategory.ad),

  /// 25, 50 or 75 % of the ad played.
  ///
  /// Data: `percent` + the ad context and details.
  adQuartile(ChorkiAnalyticsCategory.ad),

  /// The ad played to the end.
  ///
  /// Data: the ad context and details.
  adComplete(ChorkiAnalyticsCategory.ad),

  /// The viewer skipped the ad.
  ///
  /// Data: the ad context and details.
  adSkip(ChorkiAnalyticsCategory.ad),

  /// The viewer clicked or tapped the ad.
  ///
  /// Data: the ad context and details.
  adClick(ChorkiAnalyticsCategory.ad),

  /// The ad paused.
  ///
  /// Data: the ad context and details.
  adPause(ChorkiAnalyticsCategory.ad),

  /// The ad resumed.
  ///
  /// Data: the ad context and details.
  adResume(ChorkiAnalyticsCategory.ad),

  /// An ad failed (including the load timeout).
  ///
  /// Data: `message` + the ad context and details.
  adError(ChorkiAnalyticsCategory.ad),

  /// The content resumed after a break, or the view ended during one
  /// (`interrupted`).
  ///
  /// Data: `durationMs`, `interrupted` + the ad context.
  adBreakEnd(ChorkiAnalyticsCategory.ad),

  // ----------------------------------------------------------------------- UX
  /// The viewer picked another playback speed.
  ///
  /// Data: `from`, `to`.
  speedChange(ChorkiAnalyticsCategory.ux),

  /// Long-press speed boost started.
  ///
  /// Data: `speed`.
  speedBoostStart(ChorkiAnalyticsCategory.ux),

  /// The long-press speed boost ended.
  ///
  /// Data: `durationMs`.
  speedBoostEnd(ChorkiAnalyticsCategory.ux),

  /// The viewer picked another audio track.
  ///
  /// Data: `fromTrack`, `toTrack`.
  audioTrackChange(ChorkiAnalyticsCategory.ux),

  /// The video fit changed (`fit` / `fill`).
  ///
  /// Data: `fit`.
  fitChange(ChorkiAnalyticsCategory.ux),

  /// The picture-in-picture status changed.
  ///
  /// Data: `status`.
  pipChange(ChorkiAnalyticsCategory.ux),

  /// The volume changed (0..1).
  ///
  /// Data: `from`, `to`, `muted`.
  volumeChange(ChorkiAnalyticsCategory.ux),

  /// The settings sheet was opened.
  ///
  /// Data: none.
  settingsOpen(ChorkiAnalyticsCategory.ux);

  const ChorkiAnalyticsEventType(this.category);

  /// The group this event belongs to.
  final ChorkiAnalyticsCategory category;
}

/// Where a [ChorkiAnalyticsEventType.seek] came from.
enum ChorkiSeekSource {
  /// Double tap on the left / right half.
  doubleTap,

  /// Horizontal drag on the video.
  scrub,

  /// Tap on the seek bar.
  seekBarTap,

  /// Drag on the seek bar.
  seekBarDrag,

  /// The ad countdown pill ("start ad now").
  adSkipAhead,

  /// [ChorkiPlayerController.seekTo] / `seekForward` / `seekBack`.
  api,
}

/// Why a session ended.
enum ChorkiSessionEndReason {
  /// The feed page became a preload again (swiped away).
  swipedAway,

  /// The player was removed from the tree.
  disposed,

  /// The route / URL changed under the same player.
  sourceChanged,

  /// A looping video restarted and [ChorkiAnalyticsConfig.newSessionOnLoop]
  /// is set.
  looped,
}

/// One analytics event. Sinks receive these in order.
@immutable
class ChorkiAnalyticsEvent {
  /// An event of [type] in session [sessionId].
  const ChorkiAnalyticsEvent({
    required this.type,
    required this.sessionId,
    required this.timestamp,
    required this.metadata,
    required this.position,
    required this.duration,
    required this.watchedTime,
    this.videoSize = Size.zero,
    this.timeToPlay,
    this.data = const {},
  });

  /// What happened.
  final ChorkiAnalyticsEventType type;

  /// The [type]'s category.
  ChorkiAnalyticsCategory get category => type.category;

  /// Id of one view of one item. A new id is made each time the item becomes
  /// active (and on each loop with [ChorkiAnalyticsConfig.newSessionOnLoop]).
  /// The Matomo sink uses it as `ma_id`.
  final String sessionId;

  /// When it happened (from the configured clock).
  final DateTime timestamp;

  /// What was playing.
  final ChorkiMediaMetadata metadata;

  /// Playback position when the event happened.
  final Duration position;

  /// Media duration (zero until known).
  final Duration duration;

  /// Media time actually played in this session: it does not grow while
  /// paused, buffering, seeking or during ads. Matomo `ma_st`.
  final Duration watchedTime;

  /// Video size in pixels (zero until known).
  final Size videoSize;

  /// Time from the impression to the first played frame, once known.
  final Duration? timeToPlay;

  /// Event specific values; see [ChorkiAnalyticsEventType].
  final Map<String, Object?> data;

  @override
  String toString() =>
      'ChorkiAnalyticsEvent(${type.name}, session: $sessionId, '
      'position: $position, watched: $watchedTime, data: $data)';
}
