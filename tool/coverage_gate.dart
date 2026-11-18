// Coverage gate: fails when line coverage drops.
//
//   flutter test --coverage && dart run tool/coverage_gate.dart
//   dart run tool/coverage_gate.dart --update   # raise floors to current
//
// * Global floors: [overallFloor] for lib/, [analyticsFloor] for
//   lib/src/analytics/.
// * Per-file floors in tool/coverage_baseline.json. They only go up:
//   `--update` never lowers a floor, so coverage is a ratchet.
import 'dart:convert';
import 'dart:io';

const overallFloor = 90.0;
const analyticsFloor = 90.0;

/// Slack under a per-file floor before failing (line counts shift a little
/// when code is reformatted).
const tolerance = 0.5;

const _baselinePath = 'tool/coverage_baseline.json';

void main(List<String> args) {
  final update = args.contains('--update');
  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info missing: run `flutter test --coverage`.',
    );
    exit(2);
  }

  final files = <String, (int found, int hit)>{};
  String? current;
  var found = 0;
  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).replaceAll(r'\', '/');
      final i = current.indexOf('lib/');
      if (i > 0) current = current.substring(i);
    } else if (line.startsWith('LF:')) {
      found = int.parse(line.substring(3));
    } else if (line.startsWith('LH:') && current != null) {
      files[current] = (found, int.parse(line.substring(3)));
    }
  }

  double pct(Iterable<(int, int)> xs) {
    final f = xs.fold<int>(0, (a, x) => a + x.$1);
    final h = xs.fold<int>(0, (a, x) => a + x.$2);
    return f == 0 ? 100 : 100 * h / f;
  }

  final problems = <String>[];
  final overall = pct(files.values);
  final analytics = pct([
    for (final e in files.entries)
      if (e.key.startsWith('lib/src/analytics/')) e.value,
  ]);
  if (overall < overallFloor) {
    problems.add('lib/ ${overall.toStringAsFixed(1)}% < $overallFloor%');
  }
  if (analytics < analyticsFloor) {
    problems.add(
      'lib/src/analytics ${analytics.toStringAsFixed(1)}% < $analyticsFloor%',
    );
  }

  final baselineFile = File(_baselinePath);
  final baseline = baselineFile.existsSync()
      ? (jsonDecode(baselineFile.readAsStringSync()) as Map).cast<String, num>()
      : <String, num>{};

  final next = <String, num>{...baseline};
  for (final e in files.entries) {
    final p = pct([e.value]);
    final floor = baseline[e.key]?.toDouble();
    if (floor != null && p + tolerance < floor) {
      problems.add('${e.key} ${p.toStringAsFixed(1)}% < floor $floor%');
    }
    final rounded = (p * 10).floor() / 10;
    if (floor == null || rounded > floor) next[e.key] = rounded;
  }
  // Files that no longer exist drop out of the baseline.
  next.removeWhere((k, _) => !files.containsKey(k));

  stdout.writeln(
    'coverage: lib ${overall.toStringAsFixed(1)}% '
    '(floor $overallFloor), analytics ${analytics.toStringAsFixed(1)}% '
    '(floor $analyticsFloor), ${files.length} files',
  );

  if (update) {
    final sorted = Map.fromEntries(
      next.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    baselineFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
    );
    stdout.writeln('Per-file floors written to $_baselinePath.');
  }
  if (problems.isNotEmpty) {
    stderr.writeln('Coverage dropped:\n  ${problems.join('\n  ')}');
    exit(1);
  }
}
