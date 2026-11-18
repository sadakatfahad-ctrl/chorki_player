import 'dart:async';

import 'diagnostics.dart';

/// Runs [action] without awaiting it. An error it throws (synchronously or
/// later) goes to [ChorkiDiagnostics] under [context] instead of becoming an
/// unhandled zone error.
void fireAndReport(FutureOr<void> Function() action, String context) {
  unawaited(guardAsync(action, context));
}

/// Awaits [action]; an error is reported under [context] and swallowed.
/// Returns whether it completed without error.
Future<bool> guardAsync(
  FutureOr<void> Function() action,
  String context,
) async {
  try {
    await action();
    return true;
  } catch (e, st) {
    ChorkiDiagnostics.report(e, st, context);
    return false;
  }
}

/// Runs [action]; an error is reported under [context] and [fallback] is
/// returned instead.
T guardSync<T>(T Function() action, String context, T fallback) {
  try {
    return action();
  } catch (e, st) {
    ChorkiDiagnostics.report(e, st, context);
    return fallback;
  }
}
