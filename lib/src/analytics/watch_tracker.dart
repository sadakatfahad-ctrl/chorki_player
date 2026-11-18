/// Watched time, watched segments and quartiles of one view.
///
/// Fed with the position ranges that were actually played; knows nothing
/// about players or events, so it is tested on its own.
class WatchTracker {
  /// Buckets segments by [segmentLength].
  WatchTracker(this.segmentLength) : assert(segmentLength > Duration.zero);

  /// Size of a watched segment (Matomo `ma_se`).
  Duration segmentLength;

  /// Media time played.
  Duration get watched => _watched;
  Duration _watched = Duration.zero;

  final Set<int> _segments = {};
  final Set<int> _pending = {};
  final Set<int> _quartiles = {};

  /// Played ranges in milliseconds, sorted and non-overlapping.
  final List<(int, int)> _covered = [];

  /// Forgets everything (a new view).
  void reset() {
    _watched = Duration.zero;
    _segments.clear();
    _pending.clear();
    _quartiles.clear();
    _covered.clear();
  }

  /// [from]..[to] of the media was played.
  void played(Duration from, Duration to) {
    if (to <= from) return;
    _watched += to - from;
    _cover(from.inMilliseconds, to.inMilliseconds);
    final len = segmentLength.inMilliseconds;
    final first = from.inMilliseconds ~/ len;
    // Exclusive end: playing up to exactly 10 s does not enter 10..15 s.
    final last = (to.inMilliseconds - 1) ~/ len;
    for (var b = first; b <= last; b++) {
      if (_segments.add(b)) _pending.add(b);
    }
  }

  /// Segments entered since the last call, as their end offsets in whole
  /// seconds (5, 10, 15 ... with 5 s segments), sorted.
  List<int> takeNewSegments() {
    final len = segmentLength.inMilliseconds;
    final out = [
      for (final b in _pending.toList()..sort()) ((b + 1) * len) ~/ 1000,
    ];
    _pending.clear();
    return out;
  }

  /// Share of [duration] that was played, 0..100. Rewatching a part does
  /// not count twice.
  int watchedPercent(Duration duration) {
    final total = duration.inMilliseconds;
    if (total <= 0) return 0;
    var covered = 0;
    for (final (start, end) in _covered) {
      covered += (end < total ? end : total) - start;
    }
    return (covered * 100 / total).clamp(0, 100).round();
  }

  /// The 25 / 50 / 75 quartiles [position] has newly reached.
  List<int> reachedQuartiles(Duration position, Duration duration) {
    if (duration <= Duration.zero) return const [];
    final pct = position.inMilliseconds / duration.inMilliseconds * 100;
    return [
      for (final q in const [25, 50, 75])
        if (pct >= q && _quartiles.add(q)) q,
    ];
  }

  /// Marks completion; true the first time.
  bool reachedEnd() => _quartiles.add(100);

  /// Quartiles may fire again (a replay or a loop in the same view).
  void resetQuartiles() => _quartiles.clear();

  void _cover(int start, int end) {
    var s = start;
    var e = end;
    final kept = <(int, int)>[];
    for (final (a, b) in _covered) {
      if (b < s || a > e) {
        kept.add((a, b));
      } else {
        s = a < s ? a : s;
        e = b > e ? b : e;
      }
    }
    kept
      ..add((s, e))
      ..sort((x, y) => x.$1.compareTo(y.$1));
    _covered
      ..clear()
      ..addAll(kept);
  }
}
