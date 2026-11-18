// Mutation smoke test: proves the tests *catch* bugs, not just run code.
//
//   dart run tool/mutation_smoke.dart            all mutants
//   dart run tool/mutation_smoke.dart loop       mutants whose id contains "loop"
//
// Each mutant in tool/mutants.yaml re-introduces one plausible bug (often a
// bug that was really fixed). The tool applies it, runs the listed tests and
// expects them to FAIL. A mutant whose tests still pass "survived": the
// tests do not guard that behaviour. The file is always restored, also on
// Ctrl-C (a `<file>.mutation-backup` is kept during the run, and a later run
// restores it if the process was killed). Do not edit files during a run.
import 'dart:io';

import 'package:yaml/yaml.dart';

const _backupSuffix = '.mutation-backup';

/// Restores any file a previous, interrupted run left mutated.
bool _restoreLeftovers() {
  var found = false;
  for (final dir in ['lib', 'test', 'tool']) {
    for (final e in Directory(dir).listSync(recursive: true)) {
      if (e is File && e.path.endsWith(_backupSuffix)) {
        final target = e.path.substring(
          0,
          e.path.length - _backupSuffix.length,
        );
        e.copySync(target);
        e.deleteSync();
        stderr.writeln('Restored $target from an interrupted run.');
        found = true;
      }
    }
  }
  return found;
}

Future<void> main(List<String> args) async {
  if (_restoreLeftovers()) {
    stderr.writeln('Check `git diff`, then run again.');
    exitCode = 2;
    return;
  }
  // Ctrl-C / CI cancellation: put the original back before exiting.
  final signals = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((_) {
        _restoreLeftovers();
        exit(130);
      }),
  ];
  try {
    await _run(args);
  } finally {
    for (final s in signals) {
      await s.cancel();
    }
  }
}

Future<void> _run(List<String> args) async {
  final filter = args.isEmpty ? '' : args.first;
  final spec =
      loadYaml(File('tool/mutants.yaml').readAsStringSync()) as YamlList;
  final survived = <String>[];
  var ran = 0;

  for (final m in spec.cast<YamlMap>()) {
    final id = m['id'] as String;
    if (!id.contains(filter)) continue;
    final file = File(m['file'] as String);
    final original = file.readAsStringSync();
    final find = m['find'] as String;
    final count = find.allMatches(original).length;
    if (count != 1) {
      stderr.writeln(
        '[$id] "find" must occur exactly once in ${file.path} '
        '(found $count): update tool/mutants.yaml',
      );
      exitCode = 2;
      return;
    }
    ran++;
    final backup = File('${file.path}$_backupSuffix')
      ..writeAsStringSync(original);
    file.writeAsStringSync(original.replaceFirst(find, m['replace'] as String));
    try {
      final tests = (m['tests'] as YamlList).cast<String>();
      final result = await Process.run('flutter', [
        'test',
        '--reporter=failures-only',
        ...tests,
      ]);
      final killed = result.exitCode != 0;
      stdout.writeln('${killed ? 'killed  ' : 'SURVIVED'} $id  (${m['why']})');
      if (!killed) survived.add(id);
    } finally {
      file.writeAsStringSync(original);
      backup.deleteSync();
    }
  }

  stdout.writeln(
    '\n$ran mutants, ${ran - survived.length} killed, '
    '${survived.length} survived.',
  );
  if (survived.isNotEmpty) {
    stderr.writeln('Survivors (add or sharpen a test): $survived');
    exitCode = 1;
  }
}
