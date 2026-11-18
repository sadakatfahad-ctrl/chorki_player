// Prints which scenarios cover which analytics event types.
//
//   dart run tool/scenarios_report.dart
//
// Exits non-zero when an event type has no scenario (CI runs it too).
import 'dart:io';

import 'package:yaml/yaml.dart';

void main() {
  final source = File(
    'lib/src/analytics/chorki_analytics_event.dart',
  ).readAsStringSync();
  final types = RegExp(
    r'^  (\w+)\(ChorkiAnalyticsCategory\.(\w+)\)[,;]',
    multiLine: true,
  ).allMatches(source).map((m) => (name: m[1]!, category: m[2]!)).toList();

  final byType = <String, List<String>>{for (final t in types) t.name: []};
  final files =
      Directory('test/scenarios')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final yaml = loadYaml(f.readAsStringSync()) as YamlMap;
    final events = (yaml['expect'] as YamlMap?)?['events'] as YamlList?;
    for (final e in events ?? YamlList()) {
      final name = e is YamlMap ? e.keys.single as String : '$e';
      byType[name]?.add(yaml['name'] as String);
    }
  }

  stdout.writeln('${files.length} scenarios, ${types.length} event types\n');
  final missing = <String>[];
  for (final t in types) {
    final names = byType[t.name]!.toSet();
    if (names.isEmpty) missing.add(t.name);
    stdout.writeln(
      '${t.name.padRight(18)} ${t.category.padRight(9)} '
      '${names.length.toString().padLeft(2)}  ${names.take(4).join(', ')}'
      '${names.length > 4 ? ', ...' : ''}',
    );
  }
  if (missing.isNotEmpty) {
    stderr.writeln('\nNo scenario covers: $missing');
    exitCode = 1;
  }
}
