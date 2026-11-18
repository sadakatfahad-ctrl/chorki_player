import 'package:flutter/widgets.dart';

import 'ad_timeline.dart';

/// What the ad layer shares with the controls: the seek-bar markers, the
/// countdown and a way to start the next break early.
class ChorkiAdState extends ChangeNotifier {
  List<ChorkiAdMarker> _markers = const [];
  int? _countdownSeconds;

  /// Starts the upcoming break now (the countdown pill's tap); null when no
  /// break is coming.
  VoidCallback? startNow;

  /// Mid-roll markers for the seek bar.
  List<ChorkiAdMarker> get markers => _markers;

  /// Seconds until the next break while the countdown shows, else null.
  int? get countdownSeconds => _countdownSeconds;

  /// Sets the [markers] and [countdownSeconds]; notifies only on a change.
  void update({
    required List<ChorkiAdMarker> markers,
    required int? countdownSeconds,
  }) {
    final changed =
        countdownSeconds != _countdownSeconds || !_sameMarkers(markers);
    _markers = markers;
    _countdownSeconds = countdownSeconds;
    if (changed) notifyListeners();
  }

  bool _sameMarkers(List<ChorkiAdMarker> other) {
    if (other.length != _markers.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != _markers[i]) return false;
    }
    return true;
  }
}

/// Provides a [ChorkiAdState] to the controls below the ad layer.
class ChorkiAdScope extends InheritedNotifier<ChorkiAdState> {
  /// Exposes [state] to [child].
  const ChorkiAdScope({
    super.key,
    required ChorkiAdState state,
    required super.child,
  }) : super(notifier: state);

  /// The nearest ad state, or null outside an ad layer.
  static ChorkiAdState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChorkiAdScope>()?.notifier;
}
