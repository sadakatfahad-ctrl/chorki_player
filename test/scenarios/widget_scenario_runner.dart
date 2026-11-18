// Runs the widget-level scenarios in test/scenarios/widget/*.yaml.
//
// Same file format and `expect` block as the session scenarios
// (scenario_runner.dart), but the steps drive a real ChorkiPlayer: fake
// video platform, fake route repository, fake clock. They cover what only
// the widget decides: preloading, retries, error stages, viewer taps.
import 'package:chorki_player/chorki_player.dart'
    hide AdCampaignEntity, ByteDataEntity;
import 'package:chorki_player/src/core/result.dart';
import 'package:chorki_player/src/core/services.dart';
import 'package:chorki_player/src/domain/entity/byte_data_entity.dart';
import 'package:chorki_player/src/domain/repositories/bytes_repository.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    show VideoPlayerPlatform;
import 'package:yaml/yaml.dart';

import '../fakes/fake_video_player_platform.dart';
import 'scenario_runner.dart';

const _videoUrl = 'https://test.local/v.mp4';
const _route = 'bytes/7';
const _step = Duration(milliseconds: 500);

/// Answers route lookups from the scenario's `given.route` list, in order:
/// `ok` or a `ChorkiErrorCode` name. The last answer repeats.
class _ScriptedRoutes implements ByteRepository {
  _ScriptedRoutes(this.script);
  final List<String> script;
  int calls = 0;

  @override
  Future<Result<ByteDataEntity>> getByteData(
    String url, {
    bool refresh = false,
  }) async {
    final answer = script[calls < script.length ? calls : script.length - 1];
    calls++;
    if (answer == 'ok') {
      return const Ok(ByteDataEntity(id: 7, thumbnailUrl: '', url: _videoUrl));
    }
    final code = ChorkiErrorCode.values.byName(answer);
    return Err(ChorkiPlayerError(code, stage: ChorkiErrorStage.route));
  }
}

/// Executes a widget scenario; same result shape as [run].
Future<
  ({
    List<ChorkiAnalyticsEvent> events,
    List<Map<String, String>> matomo,
    List<String> diagnostics,
  })
>
runWidget(WidgetTester tester, Scenario scenario) async {
  final given = scenario.yaml['given'] as YamlMap? ?? YamlMap();
  final platform = FakeVideoPlayerPlatform(
    defaultDuration: parseDuration(given['duration'] ?? '10s'),
  );
  VideoPlayerPlatform.instance = platform;
  final routes = _ScriptedRoutes([
    for (final r in (given['route'] as YamlList?) ?? YamlList.wrap(['ok']))
      '$r',
  ]);
  ChorkiServices.overrideForTesting(repository: routes);

  var now = DateTime.utc(2026, 1, 1, 12);
  var ids = 0;
  final sink = MemoryAnalyticsSink();
  final analytics = ChorkiAnalyticsConfig(
    sinks: [sink],
    heartbeatInterval: const Duration(hours: 1),
    clock: () => now,
    idGenerator: () => 'view${++ids}',
  );
  const metadata = ChorkiMediaMetadata(contentId: 'c1', title: 'Title');
  final byUrl = given['source'] == 'url';
  var preload = given['preload'] as bool? ?? false;

  Widget player() => MaterialApp(
    home: byUrl
        ? ChorkiPlayer.url(
            _videoUrl,
            preload: preload,
            analytics: analytics,
            metadata: metadata,
          )
        : ChorkiPlayer(
            route: _route,
            preload: preload,
            analytics: analytics,
            metadata: metadata,
          ),
  );

  Future<void> advance(Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  final diagnostics = <String>[];
  final previous = ChorkiDiagnostics.onError;
  ChorkiDiagnostics.onError = (e, st, c) => diagnostics.add(c);
  try {
    await tester.pumpWidget(player());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    for (final step in (scenario.yaml['steps'] as YamlList?) ?? YamlList()) {
      final (name, arg) = step is YamlMap
          ? (step.keys.single as String, step.values.single)
          : ('$step', null);
      switch (name) {
        case 'wait':
          await advance(parseDuration(arg));
        case 'play':
          // The fake video advances; video_player polls it every 500 ms.
          final to = parseDuration((arg as YamlMap)['to']);
          final video = platform.players.values.last;
          while (video.position < to) {
            final left = to - video.position;
            final d = left < _step ? left : _step;
            video.position += d;
            await advance(d);
          }
        case 'preload':
          preload = arg as bool;
          await tester.pumpWidget(player());
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
        case 'tap':
          // A single tap fires once the double-tap window has passed.
          await tester.tapAt(tester.getCenter(find.byType(ChorkiPlayer)));
          await advance(kDoubleTapTimeout + const Duration(milliseconds: 10));
        case 'videoError':
          platform.players.values.last.emitError('$arg');
          await tester.pump();
        case 'retry':
          await tester.tap(find.text(const ChorkiPlayerStrings().retry));
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        default:
          throw ScenarioFailure('${scenario.path}: unknown step $name');
      }
    }
  } finally {
    // Remove the player and let its timers run out, even after a failure.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    ChorkiDiagnostics.onError = previous;
    ChorkiServices.resetForTesting();
  }
  return (
    events: sink.events,
    matomo: const <Map<String, String>>[],
    diagnostics: diagnostics,
  );
}
