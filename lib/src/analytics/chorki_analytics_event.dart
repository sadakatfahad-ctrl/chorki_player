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

/// Every event the player reports. See the README for when each fires and
/// which [ChorkiAnalyticsEvent.data] keys it carries.
enum ChorkiAnalyticsEventType {
  // ----------------------------------------------------------------- playback
  /// The item is on screen with its video loaded. Once per session.
  impression(ChorkiAnalyticsCategory.playback),

  /// First frame played in this session. `timeToPlayMs`.
  play(ChorkiAnalyticsCategory.playback),

  /// The viewer (or the app) paused.
  pause(ChorkiAnalyticsCategory.playback),

  /// Playback resumed after a [pause].
  resume(ChorkiAnalyticsCategory.playback),

  /// A seek. `fromMs`, `toMs`, `source` ([ChorkiSeekSource] name).
  seek(ChorkiAnalyticsCategory.playback),

  /// Periodic progress while playing, and a final one before pause / seek /
  /// complete / end. `newSegments` (List of int seconds), `reason`.
  heartbeat(ChorkiAnalyticsCategory.playback),

  /// 25 / 50 / 75 / 100 % of the duration reached. `percent`.
  quartile(ChorkiAnalyticsCategory.playback),

  /// Played to the end (also on every loop of a looping video).
  complete(ChorkiAnalyticsCategory.playback),

  /// A looping video restarted. `loopCount`.
  loop(ChorkiAnalyticsCategory.playback),

  /// The session is over. `reason` ([ChorkiSessionEndReason] name),
  /// `dwellMs`, `watchedPercent`, `maxPositionMs`, `rebufferCount`,
  /// `rebufferMs`, `pauseCount`, `seekCount`, `loopCount`.
  sessionEnd(ChorkiAnalyticsCategory.playback),

  // ---------------------------------------------------------------------- QoE
  /// The video load started (it may still wait in [VideoLoadScheduler]).
  loadStart(ChorkiAnalyticsCategory.qoe),

  /// The first frame is shown. `startupMs` (from activation or load start,
  /// whichever is later), `queueWaitMs`, `initMs`.
  firstFrame(ChorkiAnalyticsCategory.qoe),

  /// Playback stalled to buffer (after the first frame).
  bufferStart(ChorkiAnalyticsCategory.qoe),

  /// The stall ended. `durationMs`.
  bufferEnd(ChorkiAnalyticsCategory.qoe),

  /// A route fetch, video load or playback error. `message`, `stage`
  /// (`route` | `load` | `playback`), `willRetry`.
  error(ChorkiAnalyticsCategory.qoe),

  /// A reload. `attempt`, `auto` (silent retry vs the Retry button).
  retry(ChorkiAnalyticsCategory.qoe),

  /// The rendition changed. `fromHeight`, `toHeight`, `bitrate`, `auto`.
  qualityChange(ChorkiAnalyticsCategory.qoe),

  /// The view ended before anything played ("exit before video start").
  /// `waitedMs`, `reason` ([ChorkiSessionEndReason] name), `stage`
  /// (`loading`: the video never loaded; `ready`: loaded but never played,
  /// e.g. autoPlay off or a pre-roll still running), `errorCount`.
  /// Sessions = plays + abandons, so this also gives the start-failure rate
  /// (abandons with errors).
  abandon(ChorkiAnalyticsCategory.qoe),

  // ---------------------------------------------------------------------- ads
  /// An ad break paused the content. `breakIndex`, `breakKind`
  /// (`preRoll` | `midRoll` | `postRoll`).
  adBreakStart(ChorkiAnalyticsCategory.ad),

  /// An ad started. `adId`, `adTitle`, `adSystem`, `adDurationMs`,
  /// `podPosition`, `podTotal`, `skippable`.
  adStart(ChorkiAnalyticsCategory.ad),

  /// `percent`: 25, 50 or 75.
  adQuartile(ChorkiAnalyticsCategory.ad),
  adComplete(ChorkiAnalyticsCategory.ad),
  adSkip(ChorkiAnalyticsCategory.ad),
  adClick(ChorkiAnalyticsCategory.ad),
  adPause(ChorkiAnalyticsCategory.ad),
  adResume(ChorkiAnalyticsCategory.ad),

  /// `message`. Includes the ad load timeout.
  adError(ChorkiAnalyticsCategory.ad),

  /// The content resumed after a break, or the session ended during one
  /// (`interrupted: true`). `durationMs`.
  adBreakEnd(ChorkiAnalyticsCategory.ad),

  // ----------------------------------------------------------------------- UX
  /// `from`, `to`.
  speedChange(ChorkiAnalyticsCategory.ux),

  /// Long-press speed boost started. `speed`.
  speedBoostStart(ChorkiAnalyticsCategory.ux),

  /// `durationMs`.
  speedBoostEnd(ChorkiAnalyticsCategory.ux),

  /// `from`, `to` (track ids).
  audioTrackChange(ChorkiAnalyticsCategory.ux),

  /// `fit` (`fit` | `fill`).
  fitChange(ChorkiAnalyticsCategory.ux),

  /// `status` (`enabled` | `disabled` | ...).
  pipChange(ChorkiAnalyticsCategory.ux),

  /// `from`, `to` (0..1), `muted`.
  volumeChange(ChorkiAnalyticsCategory.ux),

  /// The settings sheet was opened.
  settingsOpen(ChorkiAnalyticsCategory.ux);

  const ChorkiAnalyticsEventType(this.category);

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

  final ChorkiAnalyticsEventType type;

  ChorkiAnalyticsCategory get category => type.category;

  /// Id of one view of one item. A new id is made each time the item becomes
  /// active (and on each loop with [ChorkiAnalyticsConfig.newSessionOnLoop]).
  /// The Matomo sink uses it as `ma_id`.
  final String sessionId;

  final DateTime timestamp;

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
