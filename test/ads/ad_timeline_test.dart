import 'package:chorki_player/src/ads/ad_timeline.dart';
import 'package:chorki_player/src/ads/vmap.dart';
import 'package:flutter_test/flutter_test.dart';

ChorkiAdBreak _mid(String id, Duration offset) =>
    ChorkiAdBreak(id: id, kind: ChorkiAdBreakKind.midRoll, offset: offset);

ChorkiAdBreak _pre(String id) => ChorkiAdBreak(
  id: id,
  kind: ChorkiAdBreakKind.preRoll,
  offset: Duration.zero,
);

ChorkiAdBreak _post(String id, Duration duration) =>
    ChorkiAdBreak(id: id, kind: ChorkiAdBreakKind.postRoll, offset: duration);

void main() {
  group('AdTimeline ordering', () {
    test('breaks are sorted by offset regardless of input order', () {
      final timeline = AdTimeline([
        _mid('c', const Duration(minutes: 6)),
        _mid('a', const Duration(minutes: 2)),
        _mid('b', const Duration(minutes: 4)),
      ]);
      expect(timeline.breaks.map((b) => b.id), ['a', 'b', 'c']);
    });

    test('empty timeline has no upcoming break or countdown', () {
      final timeline = AdTimeline(const []);
      expect(timeline.breaks, isEmpty);
      expect(timeline.upcoming(Duration.zero), isNull);
      expect(timeline.countdownSeconds(Duration.zero), isNull);
    });
  });

  group('countdownSeconds', () {
    final timeline = AdTimeline([_mid('m', const Duration(seconds: 60))]);

    test('exactly 5s away shows 5', () {
      expect(timeline.countdownSeconds(const Duration(seconds: 55)), 5);
    });

    test('4.2s away rounds up to 5', () {
      expect(
        timeline.countdownSeconds(const Duration(milliseconds: 55800)),
        5,
      );
    });

    test('0.1s away shows 1', () {
      expect(
        timeline.countdownSeconds(const Duration(milliseconds: 59900)),
        1,
      );
    });

    test('exactly 1s away shows 1', () {
      expect(timeline.countdownSeconds(const Duration(seconds: 59)), 1);
    });

    test('5.001s away shows nothing', () {
      expect(
        timeline.countdownSeconds(const Duration(milliseconds: 54999)),
        isNull,
      );
    });

    test('position exactly at the break is not upcoming', () {
      expect(timeline.countdownSeconds(const Duration(seconds: 60)), isNull);
    });

    test('position past the break uses the next break', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 60)),
        _mid('b', const Duration(seconds: 120)),
      ]);
      expect(t.countdownSeconds(const Duration(seconds: 61)), isNull);
      expect(t.countdownSeconds(const Duration(seconds: 117)), 3);
    });

    test('played break is skipped for the countdown', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 60)),
        _mid('b', const Duration(seconds: 63)),
      ]);
      t.markPlayedNear(const Duration(seconds: 60));
      expect(t.countdownSeconds(const Duration(seconds: 58)), 5);
      expect(t.upcoming(const Duration(seconds: 58))!.id, 'b');
    });

    test('pre-roll is ignored', () {
      final t = AdTimeline([_pre('pre')]);
      expect(t.countdownSeconds(Duration.zero), isNull);
      expect(t.upcoming(Duration.zero), isNull);
    });

    test('post-roll counts toward the countdown', () {
      const duration = Duration(seconds: 600);
      final t = AdTimeline([_post('post', duration)]);
      expect(
        t.countdownSeconds(const Duration(seconds: 596)),
        4,
      );
      expect(t.countdownSeconds(const Duration(seconds: 590)), isNull);
    });
  });

  group('upcoming', () {
    test('returns the next break strictly after the position', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 120)),
        _mid('b', const Duration(seconds: 240)),
      ]);
      expect(t.upcoming(Duration.zero)!.id, 'a');
      expect(t.upcoming(const Duration(seconds: 120))!.id, 'b');
      expect(t.upcoming(const Duration(seconds: 200))!.id, 'b');
      expect(t.upcoming(const Duration(seconds: 240)), isNull);
    });

    test('ignores pre-roll breaks', () {
      final t = AdTimeline([
        _pre('pre'),
        _mid('a', const Duration(seconds: 30)),
      ]);
      expect(t.upcoming(Duration.zero)!.id, 'a');
    });
  });

  group('markPlayedNear', () {
    test('matches a position exactly 2s away (inclusive)', () {
      final t = AdTimeline([_mid('a', const Duration(seconds: 100))]);
      final hit = t.markPlayedNear(const Duration(seconds: 98));
      expect(hit?.id, 'a');
      expect(t.isPlayed('a'), isTrue);
    });

    test('does not match a position 2.001s away', () {
      final t = AdTimeline([_mid('a', const Duration(seconds: 100))]);
      final miss = t.markPlayedNear(const Duration(milliseconds: 97999));
      expect(miss, isNull);
      expect(t.isPlayed('a'), isFalse);
    });

    test('picks the closest break within tolerance', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 100)),
        _mid('b', const Duration(seconds: 103)),
      ]);
      final hit = t.markPlayedNear(const Duration(seconds: 102));
      expect(hit?.id, 'b');
      expect(t.isPlayed('b'), isTrue);
      expect(t.isPlayed('a'), isFalse);
    });

    test('does not double-mark a break', () {
      final t = AdTimeline([_mid('a', const Duration(seconds: 100))]);
      expect(t.markPlayedNear(const Duration(seconds: 100))?.id, 'a');
      expect(t.markPlayedNear(const Duration(seconds: 100)), isNull);
      expect(t.isPlayed('a'), isTrue);
    });

    test('skips already-played breaks when choosing a match', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 100)),
        _mid('b', const Duration(seconds: 101)),
      ]);
      t.markPlayedNear(const Duration(seconds: 100));
      expect(t.markPlayedNear(const Duration(seconds: 100))?.id, 'b');
    });

    test('no match when nothing is near', () {
      final t = AdTimeline([_mid('a', const Duration(seconds: 100))]);
      expect(t.markPlayedNear(const Duration(seconds: 10)), isNull);
    });
  });

  group('markAllPlayed', () {
    test('marks every break played and clears upcoming and countdown', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 100)),
        _mid('b', const Duration(seconds: 200)),
        _pre('pre'),
      ]);
      t.markAllPlayed();
      expect(t.isPlayed('a'), isTrue);
      expect(t.isPlayed('b'), isTrue);
      expect(t.isPlayed('pre'), isTrue);
      expect(t.upcoming(Duration.zero), isNull);
      expect(t.countdownSeconds(const Duration(seconds: 96)), isNull);
    });
  });

  group('markers', () {
    test('computes fractions of the duration', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 30)),
        _mid('b', const Duration(seconds: 90)),
      ]);
      final markers = t.markers(const Duration(seconds: 120));
      expect(markers.length, 2);
      expect(markers[0].id, 'a');
      expect(markers[0].fraction, closeTo(0.25, 1e-9));
      expect(markers[1].fraction, closeTo(0.75, 1e-9));
      expect(markers.every((m) => !m.played), isTrue);
    });

    test('reflects the played flag', () {
      final t = AdTimeline([
        _mid('a', const Duration(seconds: 30)),
        _mid('b', const Duration(seconds: 90)),
      ]);
      t.markPlayedNear(const Duration(seconds: 90));
      final markers = t.markers(const Duration(seconds: 120));
      expect(markers.firstWhere((m) => m.id == 'a').played, isFalse);
      expect(markers.firstWhere((m) => m.id == 'b').played, isTrue);
    });

    test('zero or negative duration returns no markers', () {
      final t = AdTimeline([_mid('a', const Duration(seconds: 30))]);
      expect(t.markers(Duration.zero), isEmpty);
      expect(t.markers(const Duration(seconds: -1)), isEmpty);
    });

    test('only mid-rolls become markers', () {
      final t = AdTimeline([
        _pre('pre'),
        _mid('m', const Duration(seconds: 30)),
        _post('post', const Duration(seconds: 120)),
      ]);
      final markers = t.markers(const Duration(seconds: 120));
      expect(markers.map((m) => m.id), ['m']);
    });

    test('ChorkiAdMarker equality uses all fields', () {
      const a = ChorkiAdMarker(id: 'x', fraction: 0.5, played: false);
      const same = ChorkiAdMarker(id: 'x', fraction: 0.5, played: false);
      const diff = ChorkiAdMarker(id: 'x', fraction: 0.5, played: true);
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      expect(a == diff, isFalse);
    });
  });
}
