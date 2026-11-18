// Public API guardrails: an intentional-change snapshot, dartdoc coverage
// and the deprecation policy.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_guardrail.dart';
import '_rules.dart';

const _goldenPath = 'test/guardrails/goldens/public_api.txt';

Map<String, SourceFile> get _byPath => {for (final f in libSources) f.path: f};

/// The top section of CHANGELOG.md (first `## ` heading to the next).
String topChangelogSection() {
  final text = File('CHANGELOG.md').readAsStringSync();
  final start = text.indexOf('## ');
  final next = text.indexOf('\n## ', start + 3);
  return text.substring(start, next < 0 ? text.length : next);
}

void main() {
  group('public API snapshot', () {
    test('fixture: changed blocks map back to top-level names', () {
      const before = '# A\nclass A\n  int x\n# B\nclass B\n';
      const after = '# A\nclass A\n  int x\n  int y\n# C\nclass C\n';
      expect(changedApiNames(before, after), {'A', 'B', 'C'});
    });

    test('fixture: re-exports from src files are followed, filters kept', () {
      final lib = SourceFile(
        'lib/chorki_player.dart',
        "export 'src/theme.dart' hide Hidden;",
      );
      final theme = SourceFile(
        'lib/src/theme.dart',
        "export 'parts.dart' show Shown, Hidden;\nclass Theme {}",
      );
      final parts = SourceFile(
        'lib/src/parts.dart',
        'class Shown {}\nclass Hidden {}\nclass Unlisted {}',
      );
      final names = exportedDeclarations({
        lib.path: lib,
        theme.path: theme,
        parts.path: parts,
      }).map((d) => d.name);
      expect(names, unorderedEquals(['Theme', 'Shown']));
    });

    test('matches the golden; API changes are deliberate and logged', () {
      final actual = apiSnapshot(_byPath);
      final golden = File(_goldenPath);
      final expected = golden.existsSync() ? golden.readAsStringSync() : '';
      if (actual == expected) return;

      final changed = changedApiNames(expected, actual);
      final changelog = topChangelogSection();
      final unlogged = [
        for (final n in changed)
          if (expected.isNotEmpty && !changelog.contains(n)) n,
      ]..sort();

      if (updateGoldens && unlogged.isEmpty) {
        golden.writeAsStringSync(actual);
        return;
      }
      fail(
        'The public API changed: ${changed.toList()..sort()}\n'
        '${unlogged.isEmpty ? '' : 'Not mentioned in the top CHANGELOG section: $unlogged\n'}'
        'If intended: describe it in CHANGELOG.md, then run\n'
        '  UPDATE_GOLDENS=1 flutter test test/guardrails\n'
        'and review the diff of $_goldenPath.',
      );
    });
  });

  group('dartdoc', () {
    test('fixture: undocumented exports and members are found', () {
      final lib = SourceFile(
        'lib/chorki_player.dart',
        "export 'src/a.dart' hide Hidden;",
      );
      final a = SourceFile('lib/src/a.dart', '''
/// Documented.
class A {
  A(this.x);
  /// Named.
  A.named() : x = 0;
  A.other() : x = 1;
  final int x;
  /// y.
  int get y => 0;
  @override
  String toString() => '';
  void _private() {}
}
class B {}
class Hidden {}
''');
      final api = exportedDeclarations({lib.path: lib, a.path: a});
      expect(undocumented(api).map((v) => v.message), [
        'A.other: no ///',
        'A.x: no ///',
        'B: no ///',
      ]);
    });

    test('exported API documentation is within the baseline', () {
      expectRatchet('dartdoc', undocumented(exportedDeclarations(_byPath)));
    });
  });

  test('docs never recommend deprecated names', () {
    // Deprecated top-level names (members like a setter can share a name
    // with a live getter).
    final names = {
      for (final f in libSources)
        for (final m in f.unit.declarations)
          if (m.metadata.any((a) => a.name.name == 'Deprecated'))
            ...declaredNames(m),
    };
    final docs = [
      File('README.md'),
      File('CLAUDE.md'),
      ...Directory('docs')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.html') || f.path.endsWith('.md')),
    ];
    final hits = [
      for (final doc in docs)
        for (final (i, line) in doc.readAsLinesSync().indexed)
          for (final n in names)
            if (RegExp('\\b${RegExp.escape(n)}\\b').hasMatch(line) &&
                !line.contains('deprecated') &&
                !line.contains('Deprecated'))
              '${doc.path}:${i + 1} mentions $n',
    ];
    expect(hits, isEmpty, reason: 'Update the docs to the new names');
  });

  group('deprecation policy', () {
    test('fixture: messages must name a replacement and removal version', () {
      final f = SourceFile('lib/src/a.dart', '''
@deprecated
void a() {}
@Deprecated('old')
void b() {}
@Deprecated('Use c2 instead. Removed in 2.0.0.')
void c() {}
''');
      expect(badDeprecations(f).map((v) => v.line), [1, 3]);
      expect(deprecatedNames(f), ['a', 'b', 'c']);
    });

    test('lib/ deprecations follow the policy and are in the CHANGELOG', () {
      final bad = [for (final f in libSources) ...badDeprecations(f)];
      expect(bad, isEmpty);

      final changelog = File('CHANGELOG.md').readAsStringSync();
      final deprecatedSections = RegExp(
        r'### Deprecated\n([\s\S]*?)(?=\n##|$)',
      ).allMatches(changelog).map((m) => m.group(1)!).join('\n');
      final missing = [
        for (final f in libSources)
          for (final n in deprecatedNames(f))
            if (!deprecatedSections.contains(n)) '${f.path}: $n',
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Every @Deprecated name needs a line under a '
            '"### Deprecated" heading in CHANGELOG.md',
      );
    });
  });
}
