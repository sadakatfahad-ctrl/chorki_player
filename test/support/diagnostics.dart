import 'package:chorki_player/chorki_player.dart';

/// Declares that the current test expects ChorkiDiagnostics reports and
/// returns their contexts (replacing the fail-on-report collector installed
/// by test/flutter_test_config.dart).
List<String> captureDiagnostics() {
  final contexts = <String>[];
  ChorkiDiagnostics.onError = (error, stack, context) => contexts.add(context);
  return contexts;
}
