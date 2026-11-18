import 'dart:async';

/// Silent retries of transient failures (route fetch, video init, playback
/// error) before the error view shows.
///
/// [schedule] arms the next retry while attempts remain; [pending] is true
/// until it fires (the player keeps the poster meanwhile). [reset] starts a
/// fresh round (manual retry, new source, a preloading byte becoming
/// active).
class RetryPolicy {
  /// Retries after each of [delays], in order.
  RetryPolicy({this.delays = defaultDelays});

  /// Waits before each silent retry: one entry per retry.
  static const List<Duration> defaultDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// The waits in use.
  final List<Duration> delays;

  int _attempts = 0;
  Timer? _timer;

  /// Silent retries used in this round.
  int get attempts => _attempts;

  /// A silent retry is armed.
  bool get pending => _timer != null;

  /// Whether a failure that [transient] would be retried silently.
  bool canRetry({required bool transient}) =>
      transient && _attempts < delays.length;

  /// Arms the next silent retry if [canRetry]; [onRetry] gets the attempt
  /// number (from 1). Returns whether one was armed.
  bool schedule({
    required bool transient,
    required void Function(int attempt) onRetry,
  }) {
    if (!canRetry(transient: transient)) return false;
    final delay = delays[_attempts++];
    final attempt = _attempts;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      onRetry(attempt);
    });
    return true;
  }

  /// Disarms a pending retry, keeping the attempt count.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Disarms and starts a fresh round of retries.
  void reset() {
    cancel();
    _attempts = 0;
  }
}
