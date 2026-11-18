import 'package:chorki_player/src/presentation/player/retry_policy.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RetryPolicy', () {
    test('retries transient failures after each delay, then gives up', () {
      fakeAsync((async) {
        final fired = <int>[];
        final policy = RetryPolicy();
        expect(policy.schedule(transient: true, onRetry: fired.add), isTrue);
        expect(policy.pending, isTrue);
        async.elapse(const Duration(milliseconds: 999));
        expect(fired, isEmpty, reason: 'the first wait is 1 s');
        async.elapse(const Duration(milliseconds: 1));
        expect(fired, [1]);
        expect(policy.pending, isFalse);

        expect(policy.schedule(transient: true, onRetry: fired.add), isTrue);
        async.elapse(const Duration(seconds: 3));
        expect(fired, [1, 2]);

        expect(policy.canRetry(transient: true), isFalse);
        expect(policy.schedule(transient: true, onRetry: fired.add), isFalse);
        expect(policy.attempts, 2);
      });
    });

    test('never retries a permanent failure', () {
      final policy = RetryPolicy();
      expect(policy.canRetry(transient: false), isFalse);
      expect(policy.schedule(transient: false, onRetry: (_) {}), isFalse);
      expect(policy.pending, isFalse);
    });

    test('cancel keeps the count; reset starts a fresh round', () {
      fakeAsync((async) {
        final fired = <int>[];
        final policy = RetryPolicy(delays: const [Duration(seconds: 1)])
          ..schedule(transient: true, onRetry: fired.add)
          ..cancel();
        async.elapse(const Duration(seconds: 5));
        expect(fired, isEmpty);
        expect(policy.canRetry(transient: true), isFalse);

        policy.reset();
        expect(policy.attempts, 0);
        expect(policy.schedule(transient: true, onRetry: fired.add), isTrue);
        async.elapse(const Duration(seconds: 1));
        expect(fired, [1]);
      });
    });
  });
}
