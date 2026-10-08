import 'vmap.dart';

class ChorkiAdMarker {
  const ChorkiAdMarker({
    required this.id,
    required this.fraction,
    required this.played,
  });

  final String id;
  final double fraction;
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

class AdTimeline {
  AdTimeline(Iterable<ChorkiAdBreak> breaks)
    : breaks = (breaks.toList()..sort((a, b) => a.offset.compareTo(b.offset)));

  static const Duration countdownWindow = Duration(seconds: 5);

  static const Duration matchTolerance = Duration(seconds: 2);

  final List<ChorkiAdBreak> breaks;
  final Set<String> _played = {};

  bool isPlayed(String id) => _played.contains(id);

  ChorkiAdBreak? upcoming(Duration position) {
    for (final b in breaks) {
      if (b.kind == ChorkiAdBreakKind.preRoll || isPlayed(b.id)) continue;
      if (b.offset > position) return b;
    }
    return null;
  }

  int? countdownSeconds(Duration position) {
    final next = upcoming(position);
    if (next == null) return null;
    final remaining = next.offset - position;
    if (remaining > countdownWindow) return null;
    return (remaining.inMilliseconds / 1000).ceil().clamp(1, 5);
  }

  ChorkiAdBreak? markPlayedNear(Duration position) {
    ChorkiAdBreak? best;
    var bestDiff = matchTolerance + const Duration(milliseconds: 1);
    for (final b in breaks) {
      if (isPlayed(b.id)) continue;
      final diff = (b.offset - position).abs();
      if (diff < bestDiff) {
        best = b;
        bestDiff = diff;
      }
    }
    if (best != null) _played.add(best.id);
    return best;
  }

  void markAllPlayed() => _played.addAll(breaks.map((b) => b.id));

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
