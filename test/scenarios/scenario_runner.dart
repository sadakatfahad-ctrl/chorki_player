// Runs the behaviour scenarios in test/scenarios/*.yaml.
//
// A scenario drives a real ChorkiAnalyticsSession with a fake clock and a
// fake video value, then checks the exact events (and optionally the Matomo
// requests) it produced. See test/scenarios/README.md for the format.

import 'dart:io';

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/widgets.dart';
import 'package:yaml/yaml.dart';

/// One parsed scenario file.
class Scenario {
  Scenario(this.path, this.yaml);

  factory Scenario.load(String path) =>
      Scenario(path, loadYaml(File(path).readAsStringSync()) as YamlMap);

  final String path;
  final YamlMap yaml;

  String get name => yaml['name'] as String? ?? path;
  String get description => yaml['description'] as String? ?? '';

  /// Event types the expected sequence asserts on (counted for coverage).
  Set<ChorkiAnalyticsEventType> get covered {
    final expect = yaml['expect'] as YamlMap?;
    final seq = expect?['events'] as YamlList? ?? YamlList();
    return {for (final e in seq) _typeOf(_entryType(e))};
  }
}

/// A scenario run failed; [message] explains where.
class ScenarioFailure implements Exception {
  ScenarioFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

Duration parseDuration(Object? v) {
  if (v is int) return Duration(milliseconds: v);
  final s = '$v'.trim();
  final m = RegExp(r'^(\d+(?:\.\d+)?)(ms|s|m|h)$').firstMatch(s);
  if (m == null) throw ScenarioFailure('bad duration "$v" (use 500ms, 3s, 2m)');
  final n = double.parse(m[1]!);
  return switch (m[2]) {
    'ms' => Duration(microseconds: (n * 1000).round()),
    's' => Duration(microseconds: (n * 1e6).round()),
    'm' => Duration(microseconds: (n * 6e7).round()),
    _ => Duration(microseconds: (n * 3.6e9).round()),
  };
}

ChorkiAnalyticsEventType _typeOf(String name) =>
    ChorkiAnalyticsEventType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => throw ScenarioFailure('unknown event type "$name"'),
    );

String _entryType(Object? e) => e is YamlMap ? e.keys.single as String : '$e';

/// Executes [scenario] and returns the events and Matomo requests.
({
  List<ChorkiAnalyticsEvent> events,
  List<Map<String, String>> matomo,
  List<String> diagnostics,
})
run(Scenario scenario) {
  final given = scenario.yaml['given'] as YamlMap? ?? YamlMap();
  final analytics = given['analytics'] as YamlMap? ?? YamlMap();
  var now = DateTime.utc(2026, 1, 1, 12);
  var ids = 0;
  final sink = MemoryAnalyticsSink();
  final sinks = <ChorkiAnalyticsSink>[
    sink,
    if (given['throwingSink'] == true) _ThrowingSink(),
  ];
  ChorkiAnalyticsConfig config({bool? consent, bool? enabled}) =>
      ChorkiAnalyticsConfig(
        sinks: sinks,
        consentGranted: consent ?? analytics['consentGranted'] as bool? ?? true,
        enabled: enabled ?? analytics['enabled'] as bool? ?? true,
        heartbeatInterval: const Duration(hours: 1),
        segmentLength: parseDuration(analytics['segmentLength'] ?? '5s'),
        newSessionOnLoop: analytics['newSessionOnLoop'] as bool? ?? true,
        clock: () => now,
        idGenerator: () => 'view${++ids}',
      );

  final meta = given['metadata'] as YamlMap? ?? YamlMap();
  final metadata = ChorkiMediaMetadata(
    contentId: meta['contentId'] as String? ?? 'c1',
    title: meta['title'] as String? ?? 'Title',
    mediaUrl: meta['mediaUrl'] as String? ?? 'https://test.local/v.mp4',
  );
  final diagnostics = <String>[];
  final previous = ChorkiDiagnostics.onError;
  ChorkiDiagnostics.onError = (e, st, c) => diagnostics.add(c);

  final video = ValueNotifier(
    VideoPlayerValue(
      duration: parseDuration(given['duration'] ?? '30s'),
      size: const Size(720, 1280),
    ),
  );
  var current = config();
  final session = ChorkiAnalyticsSession(
    config: current,
    metadata: () => metadata,
  );

  void set({
    bool? initialized,
    bool? playing,
    bool? buffering,
    Duration? position,
    bool? completed,
    double? volume,
    double? speed,
    String? error,
  }) {
    final v = video.value;
    video.value = v.copyWith(
      isInitialized: initialized ?? v.isInitialized,
      isPlaying: playing ?? v.isPlaying,
      isBuffering: buffering ?? v.isBuffering,
      position: position ?? v.position,
      isCompleted: completed ?? v.isCompleted,
      volume: volume ?? v.volume,
      playbackSpeed: speed ?? v.playbackSpeed,
      errorDescription: error,
    );
  }

  try {
    final steps = scenario.yaml['steps'] as YamlList? ?? YamlList();
    for (final (i, raw) in steps.indexed) {
      final (op, arg) = raw is YamlMap
          ? (raw.keys.single as String, raw.values.single)
          : ('$raw', null);
      String where() => '${scenario.path} step ${i + 1} ($op)';
      YamlMap args() => arg is YamlMap
          ? arg
          : throw ScenarioFailure('${where()}: needs a map');
      switch (op) {
        case 'activate':
          session.activate();
        case 'deactivate':
          session.deactivate(
            ChorkiSessionEndReason.values.byName('${arg ?? 'swipedAway'}'),
          );
        case 'bind':
          session.bind(video);
        case 'unbind':
          session.unbind();
        case 'dispose':
          session.dispose();
        case 'value':
          final a = args();
          set(
            initialized: a['initialized'] as bool?,
            playing: a['playing'] as bool?,
            buffering: a['buffering'] as bool?,
            position: a['position'] == null
                ? null
                : parseDuration(a['position']),
            completed: a['completed'] as bool?,
            volume: (a['volume'] as num?)?.toDouble(),
            speed: (a['speed'] as num?)?.toDouble(),
            error: a['error'] as String?,
          );
        case 'advance':
          now = now.add(parseDuration(arg));
        case 'play':
          // Real playback: position and clock move together, one tick at a
          // time, up to `to`.
          final a = args();
          final to = parseDuration(a['to']);
          final step = parseDuration(a['step'] ?? '500ms');
          final speed = video.value.playbackSpeed;
          if (!video.value.isPlaying) set(playing: true);
          while (video.value.position < to) {
            final next = video.value.position + step * speed;
            now = now.add(step);
            set(position: next > to ? to : next);
          }
        case 'wrap':
          // A looping video jumps from its end back to `to` (default 0.2s).
          set(position: parseDuration(arg ?? '200ms'));
        case 'heartbeat':
          session.heartbeat();
        case 'seek':
          final a = args();
          final from = video.value.position;
          final to = parseDuration(a['to']);
          session.recordSeek(
            from,
            to,
            ChorkiSeekSource.values.byName('${a['source'] ?? 'api'}'),
          );
          set(position: to);
        case 'scrubStart':
          session.recordScrubStart();
        case 'scrubCancel':
          session.recordScrubCancel();
        case 'loadStart':
          session.recordLoadStart();
        case 'loadRunning':
          session.recordLoadRunning();
        case 'loaded':
          session.recordLoaded();
        case 'error':
          final a = args();
          session.recordError(
            ChorkiPlayerError(
              ChorkiErrorCode.values.byName('${a['code']}'),
              stage: ChorkiErrorStage.values.byName('${a['stage'] ?? 'load'}'),
              statusCode: a['statusCode'] as int?,
            ),
            willRetry: a['willRetry'] as bool? ?? false,
          );
        case 'retry':
          final a = args();
          session.recordRetry(
            attempt: a['attempt'] as int? ?? 1,
            auto: a['auto'] as bool? ?? false,
          );
        case 'consent':
          session.config = current = config(consent: arg as bool);
        case 'enabled':
          session.config = current = config(enabled: arg as bool);
        case 'adBreakStart':
          session.recordAdBreakStart();
        case 'adBreakEnd':
          session.recordAdBreakEnd();
        case 'ad':
          final a = args();
          session.recordAd(_typeOf('${a['type']}'), {
            ...?(a['data'] as YamlMap?)?.cast<String, Object?>(),
          });
        case 'speedChange':
          final a = args();
          session.recordSpeedChange(
            (a['from'] as num).toDouble(),
            (a['to'] as num).toDouble(),
          );
          set(speed: (a['to'] as num).toDouble());
        case 'boostStart':
          session.recordSpeedBoostStart((arg as num).toDouble());
        case 'boostEnd':
          session.recordSpeedBoostEnd();
        case 'quality':
          final a = args();
          session.recordQualityChange(
            fromHeight: a['from'] as int?,
            toHeight: a['to'] as int?,
            bitrate: a['bitrate'] as int?,
            label: a['label'] as String?,
          );
        case 'audio':
          final a = args();
          session.recordAudioTrackChange(a['from'] as String?, '${a['to']}');
        case 'fit':
          session.recordFitChange('$arg');
        case 'pip':
          session.recordPipChange('$arg');
        case 'settingsOpen':
          session.recordSettingsOpen();
        case 'appHidden':
          final binding = WidgetsBinding.instance;
          binding
            ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
            ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
            ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
            ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        default:
          throw ScenarioFailure('${where()}: unknown step "$op"');
      }
    }
    session.dispose();
  } finally {
    ChorkiDiagnostics.onError = previous;
  }

  final matomo = given['matomo'] as YamlMap? ?? YamlMap();
  final builder = MatomoRequestBuilder(
    MatomoConfig(
      url: 'https://matomo.test',
      siteId: 1,
      mediaAnalytics: matomo['mediaAnalytics'] as bool? ?? true,
      naming: matomo['naming'] == 'chorkiLegacy'
          ? MatomoNaming.chorkiLegacy
          : MatomoNaming.standard,
    ),
  );
  return (
    events: sink.events,
    matomo: [for (final e in sink.events) ...builder.build(e)],
    diagnostics: diagnostics,
  );
}

class _ThrowingSink extends ChorkiAnalyticsSink {
  @override
  void onEvent(ChorkiAnalyticsEvent event) => throw StateError('sink');
}

// ------------------------------------------------------------------ matching

/// Problems comparing [actual] with the `expect` block; empty on success.
List<String> check(
  Scenario scenario,
  ({
    List<ChorkiAnalyticsEvent> events,
    List<Map<String, String>> matomo,
    List<String> diagnostics,
  })
  actual,
) {
  final expect = scenario.yaml['expect'] as YamlMap? ?? YamlMap();
  final problems = <String>[];
  final aliases = <String, String>{};

  Object? field(ChorkiAnalyticsEvent e, String key) => switch (key) {
    r'$session' => e.sessionId,
    r'$position' => e.position.inMilliseconds / 1000,
    r'$watched' => e.watchedTime.inMilliseconds / 1000,
    _ => e.data[key],
  };

  String? matchValue(String key, Object? want, Object? got) {
    if (want is String && want.startsWith(r'$') && key == r'$session') {
      final bound = aliases[want];
      if (bound == null) {
        if (aliases.containsValue(got)) {
          return '$want must be a new view id, got the same as another alias';
        }
        aliases[want] = '$got';
        return null;
      }
      return bound == got ? null : '$key: expected $want ($bound), got $got';
    }
    if (want == 'absent') return got == null ? null : '$key should be absent';
    if (want == r'$any') return got != null ? null : '$key missing';
    if (want is String && got is num) {
      final m = RegExp(r'^(>=|<=|>|<|~)\s*(-?[\d.]+)$').firstMatch(want);
      if (m != null) {
        final n = double.parse(m[2]!);
        final ok = switch (m[1]) {
          '>=' => got >= n,
          '<=' => got <= n,
          '>' => got > n,
          '<' => got < n,
          _ => (got - n).abs() <= 1,
        };
        return ok ? null : '$key: expected $want, got $got';
      }
    }
    if (want is num && got is num) {
      return want == got ? null : '$key: expected $want, got $got';
    }
    final normalized = want is YamlList ? want.toList() : want;
    final gotNorm = got is List ? got.toList() : got;
    if ('$normalized' == '$gotNorm') return null;
    return '$key: expected $normalized, got $gotNorm';
  }

  // Events.
  final mode = expect['mode'] as String? ?? 'exact';
  final want = expect['events'] as YamlList? ?? YamlList();
  final got = actual.events;
  var gi = 0;
  for (final (wi, w) in want.indexed) {
    final type = _typeOf(_entryType(w));
    final fields = w is YamlMap ? (w.values.single as YamlMap?) : null;
    List<String> mismatches(ChorkiAnalyticsEvent e, {required bool bind}) {
      final saved = Map.of(aliases);
      final out = [
        for (final MapEntry(:key, :value) in (fields ?? YamlMap()).entries)
          ?matchValue('$key', value, field(e, '$key')),
      ];
      // A candidate that does not match must not bind aliases.
      if (!bind || out.isNotEmpty) {
        aliases
          ..clear()
          ..addAll(saved);
      }
      return out;
    }

    int? found;
    List<String> firstMismatch = const [];
    for (var j = gi; j < got.length; j++) {
      if (got[j].type == type) {
        // Exact mode: the next event must be it. Subsequence mode: the first
        // event of this type whose fields match.
        final m = mismatches(got[j], bind: true);
        if (m.isEmpty || mode == 'exact') {
          found = j;
          firstMismatch = m;
          break;
        }
        if (firstMismatch.isEmpty) firstMismatch = m;
        continue;
      }
      if (mode == 'exact') break;
    }
    if (found == null) {
      problems.add(
        'event ${wi + 1}: expected ${type.name}${fields == null ? '' : ' $fields'}, '
        '${firstMismatch.isNotEmpty ? 'closest: $firstMismatch' : 'got ${gi < got.length ? got[gi].type.name : 'nothing'}'}',
      );
      break;
    }
    for (final p in firstMismatch) {
      problems.add('event ${wi + 1} (${type.name}): $p');
    }
    gi = found + 1;
  }
  if (mode == 'exact' && problems.isEmpty && gi < got.length) {
    problems.add(
      'unexpected extra events: ${got.skip(gi).map((e) => e.type.name).toList()}',
    );
  }

  // Event types that must not appear.
  for (final n in (expect['never'] as YamlList?) ?? YamlList()) {
    if (got.any((e) => e.type == _typeOf('$n'))) {
      problems.add('$n must not fire');
    }
  }

  // Matomo requests, in order, as a subsequence.
  final requests = actual.matomo;
  var ri = 0;
  for (final (wi, w)
      in ((expect['matomo'] as YamlList?) ?? YamlList()).indexed) {
    final wantParams = (w as YamlMap).cast<String, Object?>();
    bool matches(Map<String, String> r) => wantParams.entries.every((p) {
      final v = r[p.key];
      if (p.value == 'absent') return v == null;
      if (p.value == r'$any') return v != null;
      return v == '${p.value}';
    });
    while (ri < requests.length && !matches(requests[ri])) {
      ri++;
    }
    if (ri == requests.length) {
      problems.add('matomo ${wi + 1}: no request matching $wantParams');
      break;
    }
    ri++;
  }

  // Recovered internal errors.
  final wantDiag = (expect['diagnostics'] as YamlList?)?.toList() ?? [];
  if ('${actual.diagnostics}' != '$wantDiag') {
    problems.add('diagnostics: expected $wantDiag, got ${actual.diagnostics}');
  }
  return problems;
}

/// Every scenario file under test/scenarios.
List<Scenario> loadScenarios([String dir = 'test/scenarios']) => [
  for (final f
      in Directory(dir).listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
    if (f.path.endsWith('.yaml')) Scenario.load(f.path.replaceAll(r'\', '/')),
];

/// A readable dump of a run, printed when a scenario fails.
String describeRun(
  ({
    List<ChorkiAnalyticsEvent> events,
    List<Map<String, String>> matomo,
    List<String> diagnostics,
  })
  r,
) {
  final b = StringBuffer('Actual events:\n');
  for (final e in r.events) {
    b.writeln(
      '  - ${e.type.name}: {\$session: ${e.sessionId}, '
      '\$position: ${e.position.inMilliseconds / 1000}, '
      '\$watched: ${e.watchedTime.inMilliseconds / 1000}, '
      '${e.data.entries.map((x) => '${x.key}: ${x.value}').join(', ')}}',
    );
  }
  b.writeln('Matomo requests:');
  for (final m in r.matomo) {
    b.writeln(
      '  - ${{for (final e in m.entries)
        if (e.key.startsWith('ma_') || e.key.startsWith('e_')) e.key: e.value}}',
    );
  }
  b.writeln('Diagnostics: ${r.diagnostics}');
  return b.toString();
}
