import 'package:chorki_player/src/analytics/watch_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

const _s = Duration(seconds: 1);

void main() {
  late WatchTracker t;
  setUp(() => t = WatchTracker(const Duration(seconds: 5)));

  test('segments are reported once, by their end second', () {
    t.played(Duration.zero, _s * 12);
    expect(t.takeNewSegments(), [5, 10, 15]);
    t.played(_s * 12, _s * 17);
    expect(t.takeNewSegments(), [20]);
    expect(t.takeNewSegments(), isEmpty);
  });

  test('a range ending exactly on a boundary does not enter the next '
      'segment (bug: a 30 s loop reported segment 35)', () {
    t.played(_s * 25, _s * 30);
    expect(t.takeNewSegments(), [30]);
  });

  test('watchedPercent counts covered time, not touched buckets '
      '(bug: 5.1 s of a 6 s short read as 100 %)', () {
    t.played(Duration.zero, const Duration(milliseconds: 5100));
    expect(t.watchedPercent(_s * 6), 85);
  });

  test('rewatching does not count twice; overlapping ranges merge', () {
    t
      ..played(Duration.zero, _s * 10)
      ..played(_s * 5, _s * 15)
      ..played(Duration.zero, _s * 3);
    expect(t.watchedPercent(_s * 30), 50);
    expect(t.watched, _s * 23, reason: 'watched time does count repeats');
  });

  test('quartiles fire once until reset; the end once', () {
    expect(t.reachedQuartiles(_s * 16, _s * 20), [25, 50, 75]);
    expect(t.reachedQuartiles(_s * 19, _s * 20), isEmpty);
    expect(t.reachedEnd(), isTrue);
    expect(t.reachedEnd(), isFalse);
    t.resetQuartiles();
    expect(t.reachedQuartiles(_s * 6, _s * 20), [25]);
    expect(t.reachedQuartiles(_s, Duration.zero), isEmpty);
  });

  test('reset forgets everything; empty ranges are ignored', () {
    t
      ..played(Duration.zero, _s * 5)
      ..played(_s * 5, _s * 5)
      ..reset();
    expect(t.watched, Duration.zero);
    expect(t.takeNewSegments(), isEmpty);
    expect(t.watchedPercent(_s * 10), 0);
    expect(t.watchedPercent(Duration.zero), 0);
  });
}
