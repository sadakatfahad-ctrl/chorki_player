import 'dart:async';

import 'package:flutter/foundation.dart';

/// Limits how many native players are created and initialized at once, and
/// lets the visible player go first.
///
/// In a feed every built page loads a video. When you swipe fast, pages are
/// built and dropped faster than the platform can create and dispose their
/// players. On Android this uses up the hardware decoders and the bandwidth,
/// and loads fail. With this limit a dropped page whose load is still queued
/// never creates a player at all.
class VideoLoadScheduler {
  VideoLoadScheduler({
    this.maxConcurrent = 2,
    this.disposalGrace = const Duration(milliseconds: 500),
  }) : assert(maxConcurrent > 0);

  /// Shared by every `ChorkiPlayer` in the app.
  static VideoLoadScheduler instance = VideoLoadScheduler();

  /// Replaces [instance], e.g. between tests so a job stuck in one test
  /// cannot hold a slot in the next. No disposal grace by default: under
  /// fake async a player's dispose() never finishes on its own.
  @visibleForTesting
  static void resetForTesting({
    int maxConcurrent = 2,
    Duration disposalGrace = Duration.zero,
  }) {
    instance = VideoLoadScheduler(
      maxConcurrent: maxConcurrent,
      disposalGrace: disposalGrace,
    );
  }

  /// Loads that may run at the same time.
  final int maxConcurrent;

  /// How long a load waits for pending disposals (see [trackDisposal]) to
  /// free their decoders before it starts anyway.
  final Duration disposalGrace;

  final List<_Job<Object?>> _queue = [];
  final Set<Future<void>> _disposals = {};
  int _running = 0;

  /// Loads currently running, for tests.
  @visibleForTesting
  int get running => _running;

  /// Runs [task] when a slot is free. Returns null without running it when
  /// [isCancelled] is true by then.
  ///
  /// Among queued tasks, the first whose [isHighPriority] is true runs first,
  /// otherwise the oldest. Both callbacks are checked when a slot frees up,
  /// so a preload that becomes the visible page moves ahead.
  Future<T?> run<T>(
    Future<T> Function() task, {
    bool Function()? isHighPriority,
    bool Function()? isCancelled,
  }) {
    final job = _Job<T>(task, isHighPriority ?? _always, isCancelled ?? _never);
    _queue.add(job);
    _pump();
    return job.completer.future;
  }

  /// Registers a player disposal in progress. Loads that start while it is
  /// pending wait for it, up to [disposalGrace].
  void trackDisposal(Future<void> disposal) {
    final tracked = disposal.catchError((Object _) {});
    _disposals.add(tracked);
    unawaited(tracked.whenComplete(() => _disposals.remove(tracked)));
  }

  void _pump() {
    while (_running < maxConcurrent) {
      _queue.removeWhere((job) {
        if (!job.isCancelled()) return false;
        job.completer.complete(null);
        return true;
      });
      if (_queue.isEmpty) return;
      final job = _queue.firstWhere(
        (j) => j.isHighPriority(),
        orElse: () => _queue.first,
      );
      _queue.remove(job);
      _running++;
      unawaited(
        _start(job).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }

  Future<void> _start(_Job<Object?> job) async {
    try {
      if (_disposals.isNotEmpty && disposalGrace > Duration.zero) {
        final pending = _disposals.toList();
        try {
          await Future.wait(pending).timeout(disposalGrace);
        } catch (_) {
          // Still not done: probably stuck (e.g. a player the platform never
          // finished creating). Stop waiting for it, or every later load
          // would pay the grace period too.
          _disposals.removeAll(pending);
        }
        if (job.isCancelled()) {
          job.completer.complete(null);
          return;
        }
      }
      job.completer.complete(await job.task());
    } catch (error, stack) {
      job.completer.completeError(error, stack);
    }
  }

  static bool _always() => true;
  static bool _never() => false;
}

class _Job<T> {
  _Job(this.task, this.isHighPriority, this.isCancelled);

  final Future<T> Function() task;
  final bool Function() isHighPriority;
  final bool Function() isCancelled;
  final Completer<T?> completer = Completer<T?>();
}
