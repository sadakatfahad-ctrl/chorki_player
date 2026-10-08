import 'package:chorki_player/src/ads/ad_timeline.dart';
import 'package:chorki_player/src/ads/chorki_ad_state.dart';
import 'package:chorki_player/src/ads/vmap.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _marker = ChorkiAdMarker(id: 'm1', fraction: 0.5, played: false);
const _markerPlayed = ChorkiAdMarker(id: 'm1', fraction: 0.5, played: true);

void main() {
  group('ChorkiAdState.update', () {
    test('initial values are empty', () {
      final state = ChorkiAdState();
      expect(state.markers, isEmpty);
      expect(state.countdownSeconds, isNull);
      expect(state.startNow, isNull);
    });

    test('notifies listeners when the countdown changes', () {
      final state = ChorkiAdState();
      var calls = 0;
      state.addListener(() => calls++);

      state.update(markers: const [], countdownSeconds: 5);
      expect(calls, 1);
      expect(state.countdownSeconds, 5);

      state.update(markers: const [], countdownSeconds: 4);
      expect(calls, 2);
      expect(state.countdownSeconds, 4);

      state.update(markers: const [], countdownSeconds: null);
      expect(calls, 3);
      expect(state.countdownSeconds, isNull);
    });

    test('notifies listeners when markers change', () {
      final state = ChorkiAdState();
      var calls = 0;
      state.addListener(() => calls++);

      state.update(markers: const [_marker], countdownSeconds: null);
      expect(calls, 1);
      expect(state.markers, const [_marker]);

      state.update(markers: const [_markerPlayed], countdownSeconds: null);
      expect(calls, 2);
      expect(state.markers.single.played, isTrue);

      state.update(markers: const [], countdownSeconds: null);
      expect(calls, 3);
    });

    test('identical update does not notify', () {
      final state = ChorkiAdState();
      var calls = 0;
      state.addListener(() => calls++);

      state.update(markers: const [_marker], countdownSeconds: 3);
      expect(calls, 1);

      state.update(markers: const [_marker], countdownSeconds: 3);
      state.update(
        markers: [
          const ChorkiAdMarker(id: 'm1', fraction: 0.5, played: false),
        ],
        countdownSeconds: 3,
      );
      expect(calls, 1);
    });

    test('an empty update on empty state does not notify', () {
      final state = ChorkiAdState();
      var calls = 0;
      state.addListener(() => calls++);
      state.update(markers: const [], countdownSeconds: null);
      expect(calls, 0);
    });

    test('a changed marker order counts as a change', () {
      final state = ChorkiAdState();
      const a = ChorkiAdMarker(id: 'a', fraction: 0.2, played: false);
      const b = ChorkiAdMarker(id: 'b', fraction: 0.8, played: false);
      state.update(markers: const [a, b], countdownSeconds: null);

      var calls = 0;
      state.addListener(() => calls++);
      state.update(markers: const [b, a], countdownSeconds: null);
      expect(calls, 1);
      expect(state.markers.first.id, 'b');
    });

    test('startNow is a settable callback field', () {
      final state = ChorkiAdState();
      var fired = 0;
      state.startNow = () => fired++;
      state.startNow!();
      expect(fired, 1);
      state.startNow = null;
      expect(state.startNow, isNull);
    });

    test('markers from AdTimeline feed the state', () {
      final timeline = AdTimeline([
        ChorkiAdBreak(
          id: 'mid',
          kind: ChorkiAdBreakKind.midRoll,
          offset: const Duration(seconds: 30),
        ),
      ]);
      final state = ChorkiAdState();
      state.update(
        markers: timeline.markers(const Duration(seconds: 60)),
        countdownSeconds: timeline.countdownSeconds(
          const Duration(seconds: 25),
        ),
      );
      expect(state.markers.single.fraction, closeTo(0.5, 1e-9));
      expect(state.countdownSeconds, 5);
    });
  });

  group('ChorkiAdScope', () {
    testWidgets('maybeOf returns null without a scope', (tester) async {
      ChorkiAdState? found = ChorkiAdState();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              found = ChorkiAdScope.maybeOf(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(found, isNull);
    });

    testWidgets('maybeOf returns the provided state', (tester) async {
      final state = ChorkiAdState();
      ChorkiAdState? found;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChorkiAdScope(
            state: state,
            child: Builder(
              builder: (context) {
                found = ChorkiAdScope.maybeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(identical(found, state), isTrue);
    });

    testWidgets('dependents rebuild when the state changes', (tester) async {
      final state = ChorkiAdState();
      var builds = 0;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChorkiAdScope(
            state: state,
            child: Builder(
              builder: (context) {
                builds++;
                final s = ChorkiAdScope.maybeOf(context)!;
                return Text(
                  'countdown:${s.countdownSeconds ?? 'none'}',
                  textDirection: TextDirection.ltr,
                );
              },
            ),
          ),
        ),
      );
      expect(find.text('countdown:none'), findsOneWidget);
      final initialBuilds = builds;

      state.update(markers: const [], countdownSeconds: 3);
      await tester.pump();
      expect(builds, greaterThan(initialBuilds));
      expect(find.text('countdown:3'), findsOneWidget);

      final afterChange = builds;
      state.update(markers: const [], countdownSeconds: 3);
      await tester.pump();
      expect(builds, afterChange);
    });
  });
}
