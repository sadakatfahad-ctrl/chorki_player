import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../ads/ad_timeline.dart';
import '../controllers/chorki_player_controller.dart';
import '../errors/chorki_player_error.dart';

/// Optional widget builders that fully replace default UI pieces.
@immutable
class ChorkiPlayerBuilders {
  /// Builders; every one is optional.
  const ChorkiPlayerBuilders({
    this.loadingBuilder,
    this.errorBuilder,
    this.errorViewBuilder,
    this.playPauseBuilder,
    this.seekBarBuilder,
    this.timeBubbleBuilder,
    this.gestureFeedbackBuilder,
    this.adCountdownBuilder,
    this.settingsButtonBuilder,
    this.settingsSheetBuilder,
    this.qualityLabelBuilder,
  });

  /// Replaces the poster and spinner shown while loading.
  final WidgetBuilder? loadingBuilder;

  /// Replaces the error view, given the localized message only.
  @Deprecated(
    'Use errorViewBuilder, which also gets the ChorkiPlayerError. '
    'Removed in 2.0.0.',
  )
  final Widget Function(BuildContext, String message, VoidCallback? onRetry)?
  errorBuilder;

  /// Replaces the error view. [ChorkiPlayerError.message] gives the
  /// localized text; [ChorkiPlayerError.code] lets you show something
  /// specific (e.g. a sign-in prompt for [ChorkiErrorCode.unauthorized]).
  final Widget Function(
    BuildContext,
    ChorkiPlayerError error,
    VoidCallback? onRetry,
  )?
  errorViewBuilder;

  /// Replaces the play badge shown while paused.
  final Widget Function(BuildContext, VideoPlayerController)? playPauseBuilder;

  /// Replaces the seek bar. Call `onSeek` to seek; the target is clamped to
  /// the video and reported to analytics as a seek-bar tap.
  final Widget Function(
    BuildContext,
    ChorkiSeekBarState state,
    ValueChanged<Duration> onSeek,
  )?
  seekBarBuilder;

  /// Replaces the time bubble above the thumb while dragging.
  final Widget Function(BuildContext, String text)? timeBubbleBuilder;

  /// Replaces the double-tap and long-press feedback.
  final Widget Function(BuildContext, ChorkiGestureFeedback feedback)?
  gestureFeedbackBuilder;

  /// Replaces the "Ad starts in N" pill; call `startNow` to begin the ad.
  final Widget Function(
    BuildContext,
    int secondsRemaining,
    VoidCallback startNow,
  )?
  adCountdownBuilder;

  /// Replaces the gear button; call `onPressed` to open the settings.
  final Widget Function(BuildContext, VoidCallback onPressed)?
  settingsButtonBuilder;

  /// Replaces the content of the settings bottom sheet.
  final Widget Function(BuildContext, ChorkiPlayerController controller)?
  settingsSheetBuilder;

  /// Label for a quality entry (default: "720p", plus bitrate on ties).
  final String Function(VideoTrack track)? qualityLabelBuilder;
}

/// What a custom seek bar ([ChorkiPlayerBuilders.seekBarBuilder]) shows.
@immutable
class ChorkiSeekBarState {
  /// Creates a snapshot of the bar.
  const ChorkiSeekBarState({
    required this.position,
    required this.buffered,
    required this.duration,
    required this.dragging,
    this.adMarkers = const [],
  });

  /// The playhead, or the drag target while [dragging].
  final Duration position;

  /// End of the buffered range around [position].
  final Duration buffered;

  /// Length of the video.
  final Duration duration;

  /// The viewer is dragging the bar.
  final bool dragging;

  /// Mid-roll ad breaks to draw on the bar (none without ads).
  final List<ChorkiAdMarker> adMarkers;
}

/// Which gesture a [ChorkiGestureFeedback] is for.
enum ChorkiGestureKind {
  /// A double tap on the right half: jumped forward.
  seekForward,

  /// A double tap on the left half: jumped back.
  seekBackward,

  /// A long press: the speed boost is on.
  speed,
}

/// What [ChorkiPlayerBuilders.gestureFeedbackBuilder] shows.
@immutable
class ChorkiGestureFeedback {
  /// Feedback for [kind] with [label].
  const ChorkiGestureFeedback({required this.kind, required this.label});

  /// The gesture.
  final ChorkiGestureKind kind;

  /// Ready-made text: `+10s`, `-10s` or `2.0x`.
  final String label;
}
