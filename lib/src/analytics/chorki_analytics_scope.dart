import 'package:flutter/widgets.dart';

import 'chorki_analytics_session.dart';

/// Gives the player's own widgets (gestures, seek bar, settings, ad layer)
/// access to the [ChorkiAnalyticsSession] of the [ChorkiPlayer] above them,
/// so they can report what the viewer did (a scrub, a double tap) instead of
/// it being guessed from position jumps.
///
/// Controls you build yourself outside the player report through
/// [ChorkiPlayerController] instead (its commands are recorded).
class ChorkiAnalyticsScope extends InheritedWidget {
  /// Provides [session] to [child].
  const ChorkiAnalyticsScope({
    super.key,
    required this.session,
    required super.child,
  });

  /// The player's session, null when analytics are off.
  final ChorkiAnalyticsSession? session;

  /// The session above [context], if any. Does not register a dependency, so
  /// it is safe to call from gesture and event callbacks.
  static ChorkiAnalyticsSession? maybeOf(BuildContext context) {
    try {
      return context
          .getInheritedWidgetOfExactType<ChorkiAnalyticsScope>()
          ?.session;
    } on FlutterError {
      // A deactivated element (a callback firing during teardown): the view
      // it belonged to is over, so there is nothing to report to.
      return null;
    }
  }

  @override
  bool updateShouldNotify(ChorkiAnalyticsScope oldWidget) =>
      !identical(session, oldWidget.session);
}
