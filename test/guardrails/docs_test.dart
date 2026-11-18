// Documentation consistency: CHANGELOG <-> pubspec, CHANGELOG structure,
// README code snippets <-> compiled excerpts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_guardrail.dart';

/// Versions from this one on use Keep a Changelog sections.
const sectionedSince = (1, 6, 0);
const allowedSections = {
  'Added',
  'Changed',
  'Deprecated',
  'Removed',
  'Fixed',
  'Security',
};

(int, int, int)? _parse(String v) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(v);
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

bool _atLeast((int, int, int) a, (int, int, int) b) =>
    a.$1 != b.$1 ? a.$1 > b.$1 : (a.$2 != b.$2 ? a.$2 > b.$2 : a.$3 >= b.$3);

/// Problems in a CHANGELOG given the pubspec [version].
List<String> changelogProblems(String changelog, String version) {
  final problems = <String>[];
  final headings = RegExp(
    r'^## (.+)$',
    multiLine: true,
  ).allMatches(changelog).toList();
  if (headings.isEmpty) return ['no "## <version>" headings'];

  final first = headings.first[1]!.trim();
  if (first == 'Unreleased') {
    final second = headings.length > 1 ? headings[1][1]!.trim() : '';
    if (second != version) {
      problems.add(
        'entry after "## Unreleased" is "$second", pubspec is $version',
      );
    }
  } else if (first != version) {
    problems.add('top entry is "$first", pubspec version is $version');
  }

  for (var i = 0; i < headings.length; i++) {
    final title = headings[i][1]!.trim();
    final parsed = _parse(title);
    if (title != 'Unreleased' &&
        (parsed == null || !_atLeast(parsed, sectionedSince))) {
      continue;
    }
    final end = i + 1 < headings.length
        ? headings[i + 1].start
        : changelog.length;
    final body = changelog.substring(headings[i].end, end);
    final lines = body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) {
      problems.add('## $title is empty');
      continue;
    }
    if (!lines.first.startsWith('### ')) {
      problems.add(
        '## $title must start with a "### Added|Changed|..." section',
      );
    }
    for (final l in lines.where((l) => l.startsWith('### '))) {
      final name = l.substring(4).trim();
      if (!allowedSections.contains(name)) {
        problems.add('## $title has unknown section "### $name"');
      }
    }
  }
  return problems;
}

/// A README dart block and the excerpt name it is tagged with (if any).
typedef Snippet = ({String? excerpt, String code, int line});

List<Snippet> readmeSnippets(String readme) {
  final out = <Snippet>[];
  final lines = readme.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != '```dart') continue;
    final tag = i > 0
        ? RegExp(r'<!--\s*excerpt:\s*([\w-]+)\s*-->').firstMatch(lines[i - 1])
        : null;
    final buf = <String>[];
    var j = i + 1;
    for (; j < lines.length && lines[j].trim() != '```'; j++) {
      buf.add(lines[j]);
    }
    out.add((excerpt: tag?[1], code: buf.join('\n'), line: i + 1));
    i = j;
  }
  return out;
}

/// `// #region name` ... `// #endregion` blocks, dedented.
Map<String, String> excerptRegions(String source) {
  final out = <String, String>{};
  final re = RegExp(
    r'^[ \t]*// #region ([\w-]+)\n([\s\S]*?)^[ \t]*// #endregion',
    multiLine: true,
  );
  for (final m in re.allMatches(source)) {
    final lines = m[2]!.split('\n');
    if (lines.isNotEmpty && lines.last.trim().isEmpty) lines.removeLast();
    final indent = lines
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.length - l.trimLeft().length)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    out[m[1]!] = lines
        .map(
          (l) => l.length >= (indent ?? 0)
              ? l.substring(indent ?? 0)
              : l.trimLeft(),
        )
        .join('\n');
  }
  return out;
}

const excerptsDir = 'example/lib/readme';

void main() {
  test('fixture: changelog problems are found', () {
    expect(changelogProblems('## 1.0.0\n- x\n', '1.0.0'), isEmpty);
    expect(changelogProblems('## 1.0.0\n- x\n', '1.1.0'), hasLength(1));
    expect(changelogProblems('## 1.6.0\n- x\n', '1.6.0'), [
      '## 1.6.0 must start with a "### Added|Changed|..." section',
    ]);
    expect(
      changelogProblems(
        '## Unreleased\n### Fixed\n- a\n## 1.6.0\n### Nope\n- b\n',
        '1.6.0',
      ),
      ['## 1.6.0 has unknown section "### Nope"'],
    );
  });

  test('fixture: excerpts are matched and dedented', () {
    const src =
        'void f() {\n  // #region a\n  final x = 1;\n    x;\n  // #endregion\n}\n';
    expect(excerptRegions(src), {'a': 'final x = 1;\n  x;'});
    final s = readmeSnippets(
      '<!-- excerpt: a -->\n```dart\nfinal x = 1;\n```\n```dart\ny\n```',
    );
    expect(s.map((x) => x.excerpt), ['a', null]);
  });

  test('CHANGELOG matches the pubspec version and section format', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)![1]!;
    expect(
      changelogProblems(File('CHANGELOG.md').readAsStringSync(), version),
      isEmpty,
    );
  });

  test('README dart snippets are compiled excerpts', () {
    final snippets = readmeSnippets(File('README.md').readAsStringSync());
    final regions = <String, String>{
      for (final f in Directory(excerptsDir).listSync().whereType<File>())
        if (f.path.endsWith('.dart')) ...excerptRegions(f.readAsStringSync()),
    };

    final stale = [
      for (final s in snippets)
        if (s.excerpt != null && regions[s.excerpt] != s.code)
          'README.md:${s.line} excerpt "${s.excerpt}" '
              '${regions.containsKey(s.excerpt) ? 'differs from' : 'is missing in'} $excerptsDir',
    ];
    expect(
      stale,
      isEmpty,
      reason: 'Copy the region from $excerptsDir into README.md',
    );

    expectRatchet('untagged_readme_snippet', [
      for (final s in snippets)
        if (s.excerpt == null)
          Violation('README.md', s.line, 'untagged dart snippet'),
    ]);
  });
}
