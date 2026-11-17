import 'dart:async';

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file in this directory.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // The scheduler is app-wide: a load stuck in one test (e.g. a platform
  // that never creates the player) must not hold a slot in the next.
  setUp(VideoLoadScheduler.resetForTesting);
  await testMain();
}
