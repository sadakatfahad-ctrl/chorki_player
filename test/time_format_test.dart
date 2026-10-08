import 'package:chorki_player/src/helpers/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatClock', () {
    test('formats sub-minute durations as m:ss', () {
      expect(formatClock(Duration.zero), '0:00');
      expect(formatClock(const Duration(seconds: 5)), '0:05');
      expect(formatClock(const Duration(seconds: 42)), '0:42');
    });

    test('pads seconds to two digits below an hour', () {
      expect(formatClock(const Duration(minutes: 3, seconds: 7)), '3:07');
      expect(formatClock(const Duration(minutes: 12)), '12:00');
      expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    });

    test('switches to h:mm:ss at one hour and pads minutes', () {
      expect(formatClock(const Duration(hours: 1)), '1:00:00');
      expect(
        formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(formatClock(const Duration(hours: 10, minutes: 30)), '10:30:00');
    });

    test('truncates sub-second remainders', () {
      expect(formatClock(const Duration(milliseconds: 999)), '0:00');
      expect(
        formatClock(const Duration(minutes: 1, milliseconds: 500)),
        '1:00',
      );
    });
  });

  group('formatDelta', () {
    test('signs the delta and appends seconds', () {
      expect(formatDelta(const Duration(seconds: 12)), '+12s');
      expect(formatDelta(const Duration(seconds: 5)), '+5s');
      expect(formatDelta(const Duration(seconds: -10)), '-10s');
      expect(formatDelta(Duration.zero), '+0s');
    });

    test('truncates fractional seconds', () {
      expect(formatDelta(const Duration(milliseconds: 1900)), '+1s');
      expect(formatDelta(const Duration(milliseconds: -1900)), '-1s');
    });
  });
}
