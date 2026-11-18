// Proof of implementation: code in lib/ must be exercised by tests.
//
// Static and cheap, so it runs on every commit. The coverage gate
// (tool/coverage_gate.dart) and the mutation smoke run
// (tool/mutation_smoke.dart) prove the tests also *check* what they run.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '_guardrail.dart';

/// Every lib/src file must be imported by a test or have one of its public
/// declarations named in a test. A `part of` file is covered by its library.
List<Violation> untestedFiles(List<SourceFile> lib, List<SourceFile> tests) {
  final testText = tests.map((t) => t.content).join('\n');
  final byPath = {for (final f in lib) f.path: f};
  bool covered(SourceFile f) {
    final partOf = f.unit.directives.whereType<PartOfDirective>().firstOrNull;
    final uri = partOf?.uri?.stringValue;
    if (uri != null) {
      final parent = byPath[Uri.parse(f.path).resolve(uri).path];
      return parent != null && covered(parent);
    }
    final rel = f.path.substring('lib/'.length);
    if (testText.contains(rel)) return true;
    final names = [
      for (final m in f.unit.declarations)
        for (final n in declaredNames(m))
          if (isPublic(n)) n,
    ];
    return names.any(
      (n) => RegExp('\\b${RegExp.escape(n)}\\b').hasMatch(testText),
    );
  }

  return [
    for (final f in lib)
      if (f.path.startsWith('lib/src/') &&
          !covered(f) &&
          !f.allows('untested', 1))
        Violation(f.path, 1, 'no test imports it or names its public types'),
  ];
}

/// Public methods of [className] (in [file]) that no test calls.
List<Violation> uncalledMethods(
  SourceFile file,
  String className,
  List<SourceFile> tests, {
  bool Function(String name)? only,
}) {
  final testText = tests.map((t) => t.content).join('\n');
  final cls = file.unit.declarations.whereType<ClassDeclaration>().firstWhere(
    (c) => c.namePart.typeName.lexeme == className,
  );
  final out = <Violation>[];
  cls.accept(
    _Methods((m) {
      final name = m.name.lexeme;
      if (!isPublic(name) || m.isGetter || m.isSetter || m.isOperator) return;
      if (m.metadata.any((a) => a.name.name == 'override')) return;
      if (only != null && !only(name)) return;
      final called = RegExp('\\.${RegExp.escape(name)}\\(').hasMatch(testText);
      if (!called) {
        out.add(
          Violation(
            file.path,
            file.lineOf(m.offset),
            '$className.$name never called in a test',
          ),
        );
      }
    }),
  );
  return out;
}

class _Methods extends RecursiveAstVisitor<void> {
  _Methods(this.onMethod);
  final void Function(MethodDeclaration) onMethod;
  @override
  void visitMethodDeclaration(MethodDeclaration node) => onMethod(node);
}

SourceFile _lib(String path) => libSources.firstWhere((f) => f.path == path);

void main() {
  test('fixture: untested files and uncalled methods are found', () {
    final a = SourceFile('lib/src/a.dart', 'class Alpha {}');
    final b = SourceFile(
      'lib/src/b.dart',
      'class Beta { void go() {} void stop() {} }',
    );
    final c = SourceFile(
      'lib/src/c.dart',
      "part 'c_part.dart';\nclass Gamma {}",
    );
    final cPart = SourceFile('lib/src/c_part.dart', "part of 'c.dart';\n");
    final aPart = SourceFile('lib/src/a_part.dart', "part of 'a.dart';\n");
    final t = SourceFile(
      'test/t.dart',
      "import 'package:x/src/c.dart';\nBeta().go();",
    );
    expect(untestedFiles([a, b, c, cPart, aPart], [t]).map((v) => v.path), [
      'lib/src/a.dart',
      'lib/src/a_part.dart',
    ]);
    expect(uncalledMethods(b, 'Beta', [t]).map((v) => v.message), [
      'Beta.stop never called in a test',
    ]);
  });

  test('every lib/src file is exercised by a test', () {
    expectRatchet('untested_file', untestedFiles(libSources, testSources));
  });

  test('every controller command and session recorder is called in a test', () {
    expectRatchet('uncalled_method', [
      ...uncalledMethods(
        _lib('lib/src/controllers/chorki_player_controller.dart'),
        'ChorkiPlayerController',
        testSources,
      ),
      ...uncalledMethods(
        _lib('lib/src/analytics/chorki_analytics_session.dart'),
        'ChorkiAnalyticsSession',
        testSources,
        only: (n) => n.startsWith('record'),
      ),
    ]);
  });
}
