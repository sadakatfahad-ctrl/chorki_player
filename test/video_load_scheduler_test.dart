import 'dart:async';

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoLoadScheduler', () {
    late VideoLoadScheduler scheduler;
    late List<String> started;
    late Map<String, Completer<String>> gates;

    setUp(() {
      scheduler = VideoLoadScheduler(disposalGrace: Duration.zero);
      started = [];
      gates = {};
    });

    Future<String?> load(
      String name, {
      bool Function()? high,
      bool Function()? cancelled,
    }) {
      return scheduler.run<String>(
        () {
          started.add(name);
          return (gates[name] = Completer<String>()).future;
        },
        isHighPriority: high ?? () => false,
        isCancelled: cancelled,
      );
    }

    test('runs at most maxConcurrent loads at once', () async {
      final results = [load('a'), load('b'), load('c')];
      await pumpEventQueue();
      expect(started, ['a', 'b']);
      expect(scheduler.running, 2);

      gates['a']!.complete('A');
      await pumpEventQueue();
      expect(started, ['a', 'b', 'c']);

      gates['b']!.complete('B');
      gates['c']!.complete('C');
      expect(await Future.wait(results), ['A', 'B', 'C']);
      expect(scheduler.running, 0);
    });

    test('a queued high-priority load runs before older preloads', () async {
      var cActive = false;
      unawaited(load('a'));
      unawaited(load('b'));
      unawaited(load('c', high: () => cActive));
      unawaited(load('d'));
      unawaited(load('e', high: () => false));
      await pumpEventQueue();

      // c became the visible page while it was queued.
      cActive = true;
      gates['a']!.complete('');
      await pumpEventQueue();
      expect(started, ['a', 'b', 'c']);

      gates['b']!.complete('');
      await pumpEventQueue();
      expect(started, ['a', 'b', 'c', 'd'], reason: 'then oldest first');
      gates['c']!.complete('');
      gates['d']!.complete('');
      await pumpEventQueue();
      gates['e']!.complete('');
    });

    test('a load cancelled while queued never runs and returns null', () async {
      var dropped = false;
      unawaited(load('a'));
      unawaited(load('b'));
      final c = load('c', cancelled: () => dropped);
      await pumpEventQueue();

      dropped = true;
      gates['a']!.complete('');
      expect(await c, isNull);
      expect(started, ['a', 'b']);
      gates['b']!.complete('');
    });

    test('a failing load frees its slot and reports the error', () async {
      final a = scheduler.run<String>(() async => throw StateError('boom'));
      await expectLater(a, throwsStateError);
      expect(scheduler.running, 0);
      expect(await scheduler.run<String>(() async => 'ok'), 'ok');
    });

    testWidgets('a load waits for a pending disposal, then for no longer '
        'than the grace period', (tester) async {
      final s = VideoLoadScheduler(
        disposalGrace: const Duration(milliseconds: 500),
      );
      final disposal = Completer<void>();
      final stuck = Completer<void>();
      s.trackDisposal(disposal.future);
      var ran = 0;
      unawaited(s.run<void>(() async => ran++));
      await tester.pump();
      expect(ran, 0, reason: 'waits for the decoder to be freed');
      disposal.complete();
      await tester.pump();
      expect(ran, 1);

      // A disposal that never finishes delays one load by the grace period
      // and is then forgotten.
      s.trackDisposal(stuck.future);
      unawaited(s.run<void>(() async => ran++));
      await tester.pump(const Duration(milliseconds: 499));
      expect(ran, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(ran, 2);
      unawaited(s.run<void>(() async => ran++));
      await tester.pump();
      expect(ran, 3, reason: 'the stuck disposal no longer delays loads');
    });
  });
}
