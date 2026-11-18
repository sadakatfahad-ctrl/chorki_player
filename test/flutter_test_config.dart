import 'dart:async';

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file in this directory.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The scheduler is app-wide: a load stuck in one test (e.g. a platform
  // that never creates the player) must not hold a slot in the next.
  setUp(ChorkiVideoLoadScheduler.resetForTesting);

  // Internal errors the SDK recovers from are reported, never swallowed.
  // A test fails on any it did not expect; tests that expect some install
  // their own ChorkiDiagnostics.onError.
  final unexpected = <String>[];
  setUp(() {
    unexpected.clear();
    ChorkiDiagnostics.onError = (error, stack, context) =>
        unexpected.add('$context: $error');
  });
  tearDown(() {
    final reports = List.of(unexpected);
    ChorkiDiagnostics.onError = null;
    if (reports.isNotEmpty) {
      fail('Unexpected ChorkiDiagnostics reports: $reports');
    }
  });

  await testMain();
}
