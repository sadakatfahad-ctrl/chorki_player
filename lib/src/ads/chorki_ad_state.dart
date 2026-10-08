import 'package:flutter/widgets.dart';

import 'ad_timeline.dart';

class ChorkiAdState extends ChangeNotifier {
  List<ChorkiAdMarker> _markers = const [];
  int? _countdownSeconds;

  VoidCallback? startNow;

  List<ChorkiAdMarker> get markers => _markers;

  int? get countdownSeconds => _countdownSeconds;

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

class ChorkiAdScope extends InheritedNotifier<ChorkiAdState> {
  const ChorkiAdScope({
    super.key,
    required ChorkiAdState state,
    required super.child,
  }) : super(notifier: state);

  static ChorkiAdState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChorkiAdScope>()?.notifier;
}
