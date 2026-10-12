import 'package:chorki_player/chorki_player.dart';

class FakePipDelegate implements ChorkiPipDelegate {
  ChorkiPipStatus current = ChorkiPipStatus.disabled;
  final List<double> enterCalls = [];
  final List<(bool, double)> autoCalls = [];

  @override
  Future<ChorkiPipStatus> status() async => current;

  @override
  Future<ChorkiPipStatus> enter(double aspectRatio) async {
    enterCalls.add(aspectRatio);
    return current = ChorkiPipStatus.enabled;
  }

  @override
  Future<void> setAuto(bool enabled, double aspectRatio) async {
    autoCalls.add((enabled, aspectRatio));
    current = enabled ? ChorkiPipStatus.automatic : ChorkiPipStatus.disabled;
  }
}
