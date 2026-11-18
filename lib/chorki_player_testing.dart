/// Conformance suites and test helpers for code that plugs into
/// `chorki_player`: analytics sinks, storages, Matomo transports and PiP
/// delegates.
///
/// The suites do not depend on `flutter_test`. Each returns a list of
/// [ChorkiConformanceCase]s whose body throws a [ConformanceFailure] when
/// the contract is broken; run them with your test framework:
///
/// ```dart
/// import 'package:chorki_player/chorki_player_testing.dart';
/// import 'package:flutter_test/flutter_test.dart';
///
/// void main() {
///   for (final c in analyticsSinkConformance(() => FirebaseSink())) {
///     test(c.name, c.body);
///   }
/// }
/// ```
library;

import 'dart:async';

import 'package:flutter/painting.dart' show Size;

import 'chorki_player.dart';

/// One contract check.
class ChorkiConformanceCase {
  /// A check named [name].
  const ChorkiConformanceCase(this.name, this.body);

  /// What is checked, e.g. `sink: never throws for any event type`.
  final String name;

  /// Throws a [ConformanceFailure] when the contract is broken.
  final Future<void> Function() body;
}

/// A broken contract.
class ConformanceFailure implements Exception {
  /// Describes what broke.
  const ConformanceFailure(this.message);

  /// What broke.
  final String message;

  @override
  String toString() => 'ConformanceFailure: $message';
}

void _check(bool ok, String message) {
  if (!ok) throw ConformanceFailure(message);
}

/// A clock you move by hand. Pass [call] as a clock
/// (`ChorkiAnalyticsConfig(clock: clock.call)`).
class ChorkiFakeClock {
  /// Starts at [start] (default 2026-01-01 12:00 UTC).
  ChorkiFakeClock([DateTime? start])
    : now = start ?? DateTime.utc(2026, 1, 1, 12);

  /// The current time.
  DateTime now;

  /// Returns [now].
  DateTime call() => now;

  /// Moves [now] forward by [by].
  void advance(Duration by) => now = now.add(by);
}

/// Ids `<prefix>1`, `<prefix>2`, ... for `ChorkiAnalyticsConfig.idGenerator`.
ChorkiIdGenerator sequentialIds([String prefix = 'view']) {
  var n = 0;
  return () => '$prefix${++n}';
}

const _samplePosition = Duration(seconds: 12);
const _sampleDuration = Duration(seconds: 60);
const _sampleWatched = Duration(seconds: 10);
const _sampleTimeToPlay = Duration(milliseconds: 300);

/// An event of [type] whose data satisfies [ChorkiAnalyticsSchema], for
/// feeding sinks in tests.
ChorkiAnalyticsEvent sampleAnalyticsEvent(
  ChorkiAnalyticsEventType type, {
  DateTime? at,
  Map<String, Object?>? data,
}) => ChorkiAnalyticsEvent(
  type: type,
  sessionId: 'view1',
  timestamp: at ?? DateTime.utc(2026, 1, 1, 12),
  metadata: const ChorkiMediaMetadata(
    contentId: 'c1',
    title: 'Title',
    mediaUrl: 'https://test.local/v.m3u8',
  ),
  position: _samplePosition,
  duration: _sampleDuration,
  watchedTime: _sampleWatched,
  videoSize: const Size(720, 1280),
  timeToPlay: _sampleTimeToPlay,
  data: data ?? _sampleData(type),
);

Map<String, Object?> _sampleData(ChorkiAnalyticsEventType type) => {
  for (final f in ChorkiAnalyticsSchema.of(type))
    if (f.required)
      f.key: switch (f.type) {
        ChorkiAnalyticsValueType.integer => 1,
        ChorkiAnalyticsValueType.number => 1.5,
        ChorkiAnalyticsValueType.boolean => true,
        ChorkiAnalyticsValueType.string => 'x',
        ChorkiAnalyticsValueType.integerList => const [5, 10],
      },
};

/// The contract of a [ChorkiAnalyticsSink]. [create] must return a new sink
/// each time.
List<ChorkiConformanceCase> analyticsSinkConformance(
  ChorkiAnalyticsSink Function() create,
) => [
  ChorkiConformanceCase('sink: never throws for any event type', () async {
    final sink = create();
    for (final type in ChorkiAnalyticsEventType.values) {
      try {
        sink.onEvent(sampleAnalyticsEvent(type));
      } catch (e) {
        throw ConformanceFailure('onEvent threw for ${type.name}: $e');
      }
    }
    await sink.dispose();
  }),
  ChorkiConformanceCase(
    'sink: tolerates unknown keys and odd value types',
    () async {
      final sink = create();
      try {
        sink.onEvent(
          sampleAnalyticsEvent(
            ChorkiAnalyticsEventType.quartile,
            data: const {ChorkiAnalyticsKeys.percent: '25', 'futureKey': true},
          ),
        );
      } catch (e) {
        throw ConformanceFailure('onEvent threw on a newer payload: $e');
      }
      await sink.dispose();
    },
  ),
  ChorkiConformanceCase('sink: flush and dispose are idempotent', () async {
    final sink = create()
      ..onEvent(sampleAnalyticsEvent(ChorkiAnalyticsEventType.play));
    await sink.flush();
    await sink.flush();
    await sink.dispose();
    await sink.dispose();
  }),
  ChorkiConformanceCase(
    'sink: events after dispose are ignored without throwing',
    () async {
      final sink = create();
      await sink.dispose();
      try {
        sink.onEvent(sampleAnalyticsEvent(ChorkiAnalyticsEventType.pause));
        await sink.flush();
      } catch (e) {
        throw ConformanceFailure('use after dispose threw: $e');
      }
    },
  ),
  ChorkiConformanceCase(
    'sink: onConsentRevoked completes and the sink keeps working',
    () async {
      final sink = create()
        ..onEvent(sampleAnalyticsEvent(ChorkiAnalyticsEventType.play));
      await sink.onConsentRevoked();
      sink.onEvent(sampleAnalyticsEvent(ChorkiAnalyticsEventType.pause));
      await sink.dispose();
    },
  ),
];

/// The contract of a [ChorkiAnalyticsStorage]. [create] must return an
/// empty storage each time.
List<ChorkiConformanceCase> analyticsStorageConformance(
  ChorkiAnalyticsStorage Function() create,
) => [
  ChorkiConformanceCase('storage: a missing key reads as null', () async {
    _check(await create().read('missing') == null, 'missing key not null');
  }),
  ChorkiConformanceCase(
    'storage: write, read back, overwrite, remove',
    () async {
      final s = create();
      await s.write('k', 'a');
      _check(await s.read('k') == 'a', 'did not read back "a"');
      await s.write('k', 'b');
      _check(await s.read('k') == 'b', 'overwrite lost');
      await s.write('k', null);
      _check(await s.read('k') == null, 'null did not remove the key');
    },
  ),
  ChorkiConformanceCase('storage: keeps large values intact', () async {
    final s = create();
    final big = List.filled(200000, 'x').join();
    await s.write('big', big);
    _check(await s.read('big') == big, 'a 200 kB value was not kept intact');
  }),
  ChorkiConformanceCase('storage: concurrent writes keep the last', () async {
    final s = create();
    await Future.wait([for (var i = 0; i < 20; i++) s.write('k', '$i')]);
    final v = await s.read('k');
    _check(v != null && int.tryParse(v) != null, 'value lost: $v');
  }),
];

/// The contract of a [MatomoTransport]. [unreachable] must return a
/// transport whose requests cannot be delivered (no network, a closed port).
List<ChorkiConformanceCase> matomoTransportConformance(
  MatomoTransport Function() unreachable,
) => [
  ChorkiConformanceCase(
    'transport: an undeliverable batch returns false, never throws',
    () async {
      bool ok;
      try {
        ok = await unreachable().send(
          Uri.parse('https://matomo.invalid/matomo.php'),
          const ['?idsite=1&rec=1'],
        );
      } catch (e) {
        throw ConformanceFailure('send threw instead of returning false: $e');
      }
      _check(!ok, 'send reported success for an undeliverable batch');
    },
  ),
];

/// The contract of a [ChorkiPipDelegate].
List<ChorkiConformanceCase> pipDelegateConformance(
  ChorkiPipDelegate Function() create,
) => [
  ChorkiConformanceCase(
    'pip: status, enter and setAuto complete without throwing',
    () async {
      final pip = create();
      try {
        await pip.status();
        await pip.enter(16 / 9);
        await pip.setAuto(true, 9 / 16);
        await pip.setAuto(false, 9 / 16);
      } catch (e) {
        throw ConformanceFailure(
          'a PiP call threw; report unavailable instead: $e',
        );
      }
    },
  ),
];
