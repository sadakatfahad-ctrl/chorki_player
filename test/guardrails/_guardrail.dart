// Shared helpers for the guardrail tests in this directory.
//
// Guardrail tests read the package's own source (with `package:analyzer`'s
// parser, no resolution) and fail when a rule is broken. Each rule is a pure
// function over a [SourceFile] so a test can also run it on a small inline
// fixture and prove it catches what it claims.
//
// Two escape hatches, both visible in review:
// * an inline allow comment on the offending line or the line above:
//   `// guardrail:allow <rule> - <reason>` (the reason is mandatory);
// * a ratchet baseline in `baselines.json` for backlogs that are being paid
//   down. Counts may only go down; see [expectRatchet].

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether golden / baseline files should be rewritten instead of compared.
bool get updateGoldens =>
    Platform.environment['UPDATE_GOLDENS'] == '1' || recordBaselines;

/// First-time recording of a *new* rule's baseline (lets it grow). Never use
/// it to hide new violations of an existing rule; review the diff of
/// `baselines.json`.
bool get recordBaselines => Platform.environment['GUARDRAIL_RECORD'] == '1';

/// One parsed Dart file.
class SourceFile {
  SourceFile(this.path, this.content)
    : lines = const LineSplitter().convert(content),
      _result = parseString(
        content: content,
        path: path,
        throwIfDiagnostics: false,
      );

  /// Reads [path] (relative to the package root).
  factory SourceFile.read(String path) =>
      SourceFile(path, File(path).readAsStringSync());

  /// Package-relative path with `/` separators, e.g. `lib/src/a.dart`.
  final String path;
  final String content;
  final List<String> lines;
  final ParseStringResult _result;

  CompilationUnit get unit => _result.unit;
  LineInfo get lineInfo => _result.lineInfo;

  /// 1-based line of [offset].
  int lineOf(int offset) => lineInfo.getLocation(offset).lineNumber;

  /// Whether line [line] (1-based), the line above or the line below (the
  /// first line of a block) carries
  /// `guardrail:allow <rule> - <reason>` with a non-empty reason.
  bool allows(String rule, int line) {
    for (final l in [line, line - 1, line + 1]) {
      if (l < 1 || l > lines.length) continue;
      final m = _allow.firstMatch(lines[l - 1]);
      if (m != null && m.group(1) == rule && m.group(2)!.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  static final _allow = RegExp(
    r'//\s*guardrail:allow\s+([a-z_]+)\s*[-—:]\s*(.*)$',
  );
}

/// A rule violation at `path:line`.
class Violation {
  const Violation(this.path, this.line, this.message);
  final String path;
  final int line;
  final String message;

  @override
  String toString() => '$path:$line  $message';
}

/// All `.dart` files under [dir], sorted, as package-relative paths.
List<String> dartFiles(String dir) {
  final files = <String>[
    for (final e in Directory(dir).listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e.path.replaceAll(r'\', '/'),
  ]..sort();
  return files;
}

/// Parsed `lib/` sources.
final List<SourceFile> libSources = [
  for (final p in dartFiles('lib')) SourceFile.read(p),
];

/// Parsed `test/` sources (excluding this directory's fixtures).
final List<SourceFile> testSources = [
  for (final p in dartFiles('test')) SourceFile.read(p),
];

/// Name of a top-level declaration, or null when it has none we track.
List<String> declaredNames(CompilationUnitMember m) => switch (m) {
  final ClassDeclaration c => [c.namePart.typeName.lexeme],
  final EnumDeclaration e => [e.namePart.typeName.lexeme],
  final MixinDeclaration x => [x.name.lexeme],
  final ExtensionDeclaration x => [if (x.name != null) x.name!.lexeme],
  final TypeAlias t => [t.name.lexeme],
  final FunctionDeclaration f => [f.name.lexeme],
  final TopLevelVariableDeclaration v => [
    for (final d in v.variables.variables) d.name.lexeme,
  ],
  _ => const [],
};

bool isPublic(String name) => !name.startsWith('_');

/// Resolves an import / export URI written in [fromPath] to a
/// package-relative path (`lib/...`), or returns the URI unchanged for other
/// packages and `dart:` libraries.
String resolveUri(String fromPath, String uri) {
  if (uri.startsWith('package:chorki_player/')) {
    return 'lib/${uri.substring('package:chorki_player/'.length)}';
  }
  if (uri.contains(':')) return uri;
  final parts = fromPath.split('/')..removeLast();
  for (final seg in uri.split('/')) {
    if (seg == '..') {
      parts.removeLast();
    } else if (seg != '.') {
      parts.add(seg);
    }
  }
  return parts.join('/');
}

/// Import and export targets of [file], resolved with [resolveUri].
List<({String target, int line})> directivesOf(SourceFile file) => [
  for (final d in file.unit.directives)
    if (d is NamespaceDirective && d.uri.stringValue != null)
      (
        target: resolveUri(file.path, d.uri.stringValue!),
        line: file.lineOf(d.offset),
      ),
];

// ------------------------------------------------------------------ ratchet

const _baselinePath = 'test/guardrails/baselines.json';

Map<String, Object?> _readBaselines() {
  final f = File(_baselinePath);
  if (!f.existsSync()) return {};
  return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
}

void _writeBaseline(String rule, Map<String, int> counts) {
  final all = _readBaselines();
  if (counts.isEmpty) {
    all.remove(rule);
  } else {
    all[rule] = Map.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }
  final sorted = Map.fromEntries(
    all.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );
  File(_baselinePath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(sorted)}\n',
  );
}

/// Compares [violations] per key (usually a file path) with the recorded
/// baseline for [rule].
///
/// * More violations than the baseline: fails and lists the new ones.
/// * Fewer: fails too, asking to lock the improvement in, so the baseline
///   only ever shrinks (`UPDATE_GOLDENS=1 flutter test test/guardrails`).
/// * With `UPDATE_GOLDENS=1` the baseline is rewritten instead; it never
///   grows unless [allowGrowth] is set (only for first-time recording).
void expectRatchet(
  String rule,
  List<Violation> violations, {
  bool allowGrowth = false,
}) {
  final actual = <String, int>{};
  for (final v in violations) {
    actual[v.path] = (actual[v.path] ?? 0) + 1;
  }
  final raw = (_readBaselines()[rule] as Map?)?.cast<String, Object?>() ?? {};
  final baseline = {
    for (final e in raw.entries) e.key: (e.value! as num).toInt(),
  };

  final grew = <String>[];
  final shrank = <String>[];
  for (final key in {...actual.keys, ...baseline.keys}) {
    final a = actual[key] ?? 0;
    final b = baseline[key] ?? 0;
    if (a > b) grew.add('$key: $b -> $a');
    if (a < b) shrank.add('$key: $b -> $a');
  }

  if (updateGoldens && (grew.isEmpty || allowGrowth || recordBaselines)) {
    _writeBaseline(rule, actual);
    return;
  }

  if (grew.isNotEmpty) {
    final details = violations
        .where((v) => grew.any((g) => g.startsWith('${v.path}:')))
        .join('\n  ');
    fail(
      '[$rule] new violations (baseline only shrinks):\n  '
      '${grew.join('\n  ')}\n\nAll violations in those files:\n  $details\n\n'
      'Fix them, or add `// guardrail:allow $rule - <reason>` where the '
      'pattern is deliberate.',
    );
  }
  if (shrank.isNotEmpty) {
    fail(
      '[$rule] fewer violations than the baseline. Lock it in with\n'
      '  UPDATE_GOLDENS=1 flutter test test/guardrails\n  '
      '${shrank.join('\n  ')}',
    );
  }
}
