import 'package:flutter/foundation.dart';

import 'vmap.dart';

/// A mid-roll ad break on the seek bar: where it sits and whether it has
/// played. The built-in seek bar draws these; a custom one gets them as
/// `ChorkiSeekBarState.adMarkers`.
@immutable
class ChorkiAdMarker {
  /// A marker for break [id] at [fraction] of the video.
  const ChorkiAdMarker({
    required this.id,
    required this.fraction,
    required this.played,
  });

  /// The break's id from the VMAP; stable while the video plays.
  final String id;

  /// Where the break sits, from 0 (start) to 1 (end) of the content.
  final double fraction;

  /// Its break has started, or IMA reported every ad of the video done.
  final bool played;

  @override
  bool operator ==(Object other) =>
      other is ChorkiAdMarker &&
      other.id == id &&
      other.fraction == fraction &&
      other.played == played;

  @override
  int get hashCode => Object.hash(id, fraction, played);
}

/// The ad breaks of one video, which of them have played, and the seek-bar
/// markers and countdown derived from them.
class AdTimeline {
  /// A timeline of [breaks], sorted by offset.
  AdTimeline(Iterable<ChorkiAdBreak> breaks)
    : breaks = (breaks.toList()..sort((a, b) => a.offset.compareTo(b.offset)));

  /// How long before a mid-roll the "Ad starts in N" countdown shows.
  static const Duration countdownWindow = Duration(seconds: 5);

  /// How far from a break the content may be when IMA pauses it for that
  /// break (see [markPlayedNear]).
  static const Duration matchTolerance = Duration(seconds: 2);

  /// Every break, earliest first.
  final List<ChorkiAdBreak> breaks;
  final Set<String> _played = {};

  /// Whether the break [id] has played.
  bool isPlayed(String id) => _played.contains(id);

  /// The next unplayed mid- or post-roll after [position], if any.
  ChorkiAdBreak? upcoming(Duration position) {
    for (final b in breaks) {
      if (b.kind == ChorkiAdBreakKind.preRoll || isPlayed(b.id)) continue;
      if (b.offset > position) return b;
    }
    return null;
  }

  /// Whole seconds (1 to 5) until the [upcoming] break, or null when it is
  /// further than [countdownWindow] away.
  int? countdownSeconds(Duration position) {
    final next = upcoming(position);
    if (next == null) return null;
    final remaining = next.offset - position;
    if (remaining > countdownWindow) return null;
    return (remaining.inMilliseconds / 1000).ceil().clamp(1, 5);
  }

  /// Marks the unplayed break closest to [position] (within
  /// [matchTolerance]) as played and returns it; null if none is that close.
  ChorkiAdBreak? markPlayedNear(Duration position) {
    ChorkiAdBreak? best;
    Duration? bestDiff;
    for (final b in breaks) {
      if (isPlayed(b.id)) continue;
      final diff = (b.offset - position).abs();
      if (diff <= matchTolerance && (bestDiff == null || diff < bestDiff)) {
        best = b;
        bestDiff = diff;
      }
    }
    if (best != null) _played.add(best.id);
    return best;
  }

  /// Marks every break as played (IMA reported all ads done).
  void markAllPlayed() => _played.addAll(breaks.map((b) => b.id));

  /// Seek-bar markers for the mid-rolls of a video [duration] long; empty
  /// while the duration is unknown.
  List<ChorkiAdMarker> markers(Duration duration) {
    if (duration <= Duration.zero) return const [];
    return [
      for (final b in breaks)
        if (b.kind == ChorkiAdBreakKind.midRoll)
          ChorkiAdMarker(
            id: b.id,
            fraction: (b.offset.inMicroseconds / duration.inMicroseconds).clamp(
              0.0,
              1.0,
            ),
            played: isPlayed(b.id),
          ),
    ];
  }
}
