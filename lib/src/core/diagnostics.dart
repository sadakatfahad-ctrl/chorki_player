/// Receives an internal error the player recovered from.
///
/// [context] names where it happened, e.g. `controller.selectQuality` or
/// `matomo.flush`.
typedef ChorkiErrorHandler =
    void Function(Object error, StackTrace stack, String context);

/// Where the player reports errors it handles internally instead of
/// throwing them at the app: a quality switch the platform rejected, an ad
/// SDK call that failed, an analytics sink that threw, and so on.
///
/// The SDK never logs. Set [onError] to forward these to your crash
/// reporting or logs:
///
/// ```dart
/// ChorkiDiagnostics.onError = (error, stack, context) =>
///     FirebaseCrashlytics.instance.recordError(error, stack, reason: context);
/// ```
abstract final class ChorkiDiagnostics {
  /// Called for every recovered internal error. Null (the default) ignores
  /// them.
  static ChorkiErrorHandler? onError;

  /// Reports a recovered error to [onError]. A throwing handler is ignored,
  /// so reporting can never break playback.
  static void report(Object error, StackTrace stack, String context) {
    final handler = onError;
    if (handler == null) return;
    try {
      handler(error, stack, context);
    } catch (_) {
      // guardrail:allow swallowed_error - the reporter itself failed; there is nowhere left to report to.
    }
  }
}
