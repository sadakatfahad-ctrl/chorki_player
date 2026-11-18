// The guardrail rules, as pure functions over [SourceFile]s so each one can
// be proven against an inline fixture before it is run on `lib/`.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '_guardrail.dart';

// --------------------------------------------------------- swallowed errors

/// A `catch` (or `.catchError(...)` handler) must do one of:
/// rethrow / throw, call `ChorkiDiagnostics.report`, or carry
/// `// guardrail:allow swallowed_error - <reason>`.
List<Violation> swallowedErrors(SourceFile f) {
  final v = _SwallowVisitor(f);
  f.unit.accept(v);
  return v.found;
}

class _SwallowVisitor extends RecursiveAstVisitor<void> {
  _SwallowVisitor(this.f);
  final SourceFile f;
  final found = <Violation>[];

  static bool _handles(String body) =>
      body.contains('rethrow') ||
      RegExp(r'\bthrow\b').hasMatch(body) ||
      body.contains('ChorkiDiagnostics.report');

  void _check(AstNode node, String body, String what) {
    if (_handles(body)) return;
    final line = f.lineOf(node.offset);
    if (f.allows('swallowed_error', line)) return;
    found.add(Violation(f.path, line, '$what neither reports nor rethrows'));
  }

  @override
  void visitCatchClause(CatchClause node) {
    // A narrow `on SomeType` is a deliberate decision about that type.
    final type = node.exceptionType?.toSource();
    final narrow = type != null && type != 'Object' && type != 'dynamic';
    // Passing the caught error on (converting, completing, forwarding)
    // handles it.
    final name = node.exceptionParameter?.name.lexeme;
    final used =
        name != null &&
        name != '_' &&
        RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(node.body.toSource());
    if (!narrow && !used) _check(node, node.body.toSource(), 'catch');
    super.visitCatchClause(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'catchError') {
      for (final a in node.argumentList.arguments) {
        if (a is FunctionExpression) {
          _check(node, a.body.toSource(), 'catchError handler');
        }
      }
    }
    super.visitMethodInvocation(node);
  }
}

// ----------------------------------------------------------------- layering

/// One import rule: files matching [from] must not import targets matching
/// [forbidden].
class LayerRule {
  const LayerRule(this.name, this.from, this.forbidden, {this.except});
  final String name;
  final bool Function(String path) from;
  final bool Function(String target) forbidden;
  final bool Function(String path)? except;
}

bool _under(String p, String dir) => p.startsWith(dir);

/// The package's layering. Keep in sync with CLAUDE.md "Architecture".
final List<LayerRule> layerRules = [
  LayerRule(
    'domain is pure (no data / presentation / Flutter UI)',
    (p) => _under(p, 'lib/src/domain/'),
    (t) =>
        _under(t, 'lib/src/data/') ||
        _under(t, 'lib/src/presentation/') ||
        t.startsWith('package:flutter/'),
  ),
  LayerRule(
    'analytics core does not know Matomo',
    (p) => _under(p, 'lib/src/analytics/') && !p.contains('/matomo/'),
    (t) => _under(t, 'lib/src/analytics/matomo/'),
  ),
  LayerRule(
    'analytics does not import presentation',
    (p) => _under(p, 'lib/src/analytics/'),
    (t) => _under(t, 'lib/src/presentation/'),
  ),
  LayerRule(
    'get_it is confined to the service container',
    (p) => _under(p, 'lib/'),
    (t) => t.startsWith('package:get_it/'),
    except: (p) =>
        p == 'lib/src/injection_container.dart' ||
        p == 'lib/src/core/services.dart',
  ),
  LayerRule(
    'lib/ never imports test-only packages',
    (p) => _under(p, 'lib/'),
    (t) =>
        t.startsWith('package:flutter_test/') ||
        t.startsWith('package:test/') ||
        t.startsWith('package:fake_async/') ||
        t.startsWith('package:analyzer/') ||
        t.startsWith('package:yaml/') ||
        t.startsWith('package:video_player_platform_interface/'),
  ),
  LayerRule(
    'lib/src never imports the public barrels',
    (p) => _under(p, 'lib/src/'),
    (t) =>
        t == 'lib/chorki_player.dart' || t == 'lib/chorki_player_testing.dart',
  ),
];

List<Violation> layeringViolations(SourceFile f) => [
  for (final rule in layerRules)
    if (rule.from(f.path) && !(rule.except?.call(f.path) ?? false))
      for (final d in directivesOf(f))
        if (rule.forbidden(d.target) && !f.allows('layering', d.line))
          Violation(f.path, d.line, '${rule.name}: imports ${d.target}'),
];

// -------------------------------------------------------------- determinism

/// Files allowed to read the wall clock or create random sources.
const determinismHomes = {'lib/src/core/clock.dart', 'lib/src/core/ids.dart'};

/// `DateTime.now`, `Random()` and `Random.secure()` outside
/// [determinismHomes]: everything else takes an injectable clock / id source.
List<Violation> nondeterminism(SourceFile f) {
  if (determinismHomes.contains(f.path)) return const [];
  final v = _NowVisitor(f);
  f.unit.accept(v);
  return v.found;
}

class _NowVisitor extends RecursiveAstVisitor<void> {
  _NowVisitor(this.f);
  final SourceFile f;
  final found = <Violation>[];

  void _add(AstNode n, String what) {
    final line = f.lineOf(n.offset);
    if (!f.allows('determinism', line)) {
      found.add(Violation(f.path, line, '$what: inject a clock / id source'));
    }
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final target = node.target?.toSource();
    final name = node.methodName.name;
    if (target == 'DateTime' && name == 'now') _add(node, 'DateTime.now()');
    if (target == null && name == 'Random') _add(node, 'Random()');
    if (target == 'Random' && name == 'secure') _add(node, 'Random.secure()');
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.toSource();
    if (type == 'Random' || type == 'Random.secure') _add(node, '$type()');
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    if (node.toSource() == 'DateTime.now' && node.parent is! MethodInvocation) {
      _add(node, 'DateTime.now tear-off');
    }
    super.visitPrefixedIdentifier(node);
  }
}

// ----------------------------------------------------------------- file size

/// Most *code* lines a lib/ file may have. Blank lines and comments do not
/// count, so documenting a file never pushes it over.
const maxLibFileLines = 350;

/// Lines of [f] that are not blank and not comments.
int codeLines(SourceFile f) => f.lines.where((l) {
  final t = l.trim();
  return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('*');
}).length;

List<Violation> oversizedFile(SourceFile f) {
  final n = codeLines(f);
  if (n <= maxLibFileLines || f.allows('file_size', 1)) return const [];
  // One violation per 50 lines over, so shrinking is visible in the ratchet.
  return [
    for (var i = 0; i < (n - maxLibFileLines + 49) ~/ 50; i++)
      Violation(f.path, 1, '$n code lines (max $maxLibFileLines): split it'),
  ];
}

// ------------------------------------------------------------ magic numbers

/// `Duration(...)` with numeric literals inside a function body. Durations
/// belong in named constants or documented parameter defaults.
List<Violation> magicDurations(SourceFile f) {
  final v = _DurationVisitor(f);
  f.unit.accept(v);
  return v.found;
}

class _DurationVisitor extends RecursiveAstVisitor<void> {
  _DurationVisitor(this.f);
  final SourceFile f;
  final found = <Violation>[];

  bool _isNamedConstant(AstNode node) {
    for (AstNode? p = node.parent; p != null; p = p.parent) {
      if (p is FunctionBody) return false;
      if (p is FormalParameterDefaultClause) return true;
      if (p is TopLevelVariableDeclaration) return true;
      if (p is FieldDeclaration) return true;
      if (p is ConstructorFieldInitializer) return false;
      if (p is VariableDeclarationList && p.isConst) return true;
    }
    return true;
  }

  void _check(AstNode node, String name, ArgumentList args) {
    if (name != 'Duration') return;
    final hasLiteral = args.arguments.any((a) {
      final e = a.argumentExpression;
      return e is IntegerLiteral && e.value != 0 || e is DoubleLiteral;
    });
    if (!hasLiteral || _isNamedConstant(node)) return;
    final line = f.lineOf(node.offset);
    if (f.allows('magic_number', line)) return;
    found.add(
      Violation(f.path, line, '${node.toSource()}: name it as a constant'),
    );
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.target == null) {
      _check(node, node.methodName.name, node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    _check(node, node.constructorName.toSource(), node.argumentList);
    super.visitInstanceCreationExpression(node);
  }
}

// ---------------------------------------------------------- exported surface

/// A file exported by a public library, with its `show` / `hide` filters.
class ExportedFile {
  ExportedFile(this.path, {this.show, this.hide = const {}, this.via});
  final String path;
  final Set<String>? show;
  final Set<String> hide;

  /// The export this one is reached through (a `src/` file re-exporting
  /// another); its `show`/`hide` apply too.
  final ExportedFile? via;

  bool exports(String name) =>
      isPublic(name) &&
      !hide.contains(name) &&
      (show?.contains(name) ?? true) &&
      (via?.exports(name) ?? true);
}

/// The package's public libraries.
const publicLibraries = [
  'lib/chorki_player.dart',
  'lib/chorki_player_testing.dart',
];

/// Files (inside this package) exported by [library].
/// The files [library] exports. With [byPath], exports of exported files
/// are followed too (a `src/` file may re-export the files it was split
/// into), keeping every `show`/`hide` on the way.
List<ExportedFile> exportsOf(
  SourceFile library, [
  Map<String, SourceFile>? byPath,
  ExportedFile? via,
  Set<String>? visited,
]) {
  final seen = visited ?? {library.path};
  final out = <ExportedFile>[];
  for (final d in library.unit.directives.whereType<ExportDirective>()) {
    final uri = d.uri.stringValue;
    if (uri == null) continue;
    final path = resolveUri(library.path, uri);
    if (path.contains(':')) continue;
    final e = ExportedFile(
      path,
      show: _names<ShowCombinator>(d),
      hide: _names<HideCombinator>(d) ?? const {},
      via: via,
    );
    out.add(e);
    final next = byPath?[path];
    if (next != null && seen.add(path)) {
      out.addAll(exportsOf(next, byPath, e, seen));
    }
  }
  return out;
}

Set<String>? _names<T extends Combinator>(ExportDirective d) {
  final c = d.combinators.whereType<T>();
  if (c.isEmpty) return null;
  return {
    for (final x in c)
      ...switch (x as Combinator) {
        final ShowCombinator s => s.shownNames.map((n) => n.name),
        final HideCombinator h => h.hiddenNames.map((n) => n.name),
      },
  };
}

/// One exported top-level declaration and its public members.
class ApiDeclaration {
  ApiDeclaration(this.file, this.name, this.node);
  final SourceFile file;
  final String name;
  final CompilationUnitMember node;

  bool get isDeprecated => _deprecated(node.metadata);

  /// Public members (constructors, methods, fields, enum values).
  List<ClassMember> get members {
    final out = <ClassMember>[];
    node.accept(_MemberCollector(node, out));
    return out;
  }
}

class _MemberCollector extends RecursiveAstVisitor<void> {
  _MemberCollector(this.owner, this.out);
  final CompilationUnitMember owner;
  final List<ClassMember> out;

  bool _direct(AstNode n) =>
      n.thisOrAncestorOfType<CompilationUnitMember>() == owner;

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (_direct(node)) out.add(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (_direct(node)) out.add(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (_direct(node)) out.add(node);
  }
}

bool _deprecated(NodeList<Annotation> metadata) => metadata.any(
  (a) => a.name.name == 'Deprecated' || a.name.name == 'deprecated',
);

bool _isOverride(NodeList<Annotation> metadata) =>
    metadata.any((a) => a.name.name == 'override');

/// Every exported, public top-level declaration of the public libraries.
List<ApiDeclaration> exportedDeclarations(Map<String, SourceFile> byPath) {
  final out = <ApiDeclaration>[];
  for (final lib in publicLibraries) {
    final library = byPath[lib];
    if (library == null) continue;
    for (final e in exportsOf(library, byPath)) {
      final file = byPath[e.path];
      if (file == null) continue;
      for (final m in file.unit.declarations) {
        for (final name in declaredNames(m)) {
          if (e.exports(name)) out.add(ApiDeclaration(file, name, m));
        }
      }
    }
  }
  return out;
}

/// Public member names of [m] (empty for private ones and overrides).
List<String> publicMemberNames(ClassMember m) => switch (m) {
  final ConstructorDeclaration c => [
    if (c.name == null) '' else if (isPublic(c.name!.lexeme)) c.name!.lexeme,
  ],
  final MethodDeclaration x =>
    isPublic(x.name.lexeme) && !_isOverride(x.metadata) ? [x.name.lexeme] : [],
  final FieldDeclaration x => [
    if (!_isOverride(x.metadata))
      for (final v in x.fields.variables)
        if (isPublic(v.name.lexeme)) v.name.lexeme,
  ],
  _ => const [],
};

/// Exported declarations / members without a `///` doc comment. Unnamed
/// generative constructors are exempt (the class doc covers them).
List<Violation> undocumented(List<ApiDeclaration> api) {
  final out = <Violation>[];
  final seen = <CompilationUnitMember>{};
  for (final d in api) {
    if (!seen.add(d.node) && d.node is! TopLevelVariableDeclaration) continue;
    final f = d.file;
    if (d.node.documentationComment == null &&
        !f.allows('dartdoc', f.lineOf(d.node.offset))) {
      out.add(Violation(f.path, f.lineOf(d.node.offset), '${d.name}: no ///'));
    }
    if (d.node is TopLevelVariableDeclaration) continue;
    for (final m in d.members) {
      // A setter shares its getter's doc.
      if (m is MethodDeclaration && m.isSetter) continue;
      for (final name in publicMemberNames(m)) {
        if (name.isEmpty) continue; // unnamed constructor
        if (m.documentationComment != null) continue;
        final line = f.lineOf(m.offset);
        if (f.allows('dartdoc', line)) continue;
        out.add(Violation(f.path, line, '${d.name}.$name: no ///'));
      }
    }
  }
  return out;
}

// ----------------------------------------------------------- API snapshot

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _header(ApiDeclaration d) {
  final n = d.node;
  final src = d.file.content;
  final start = n.firstTokenAfterCommentAndMetadata.offset;
  final dep = d.isDeprecated ? ' [deprecated]' : '';
  switch (n) {
    case FunctionDeclaration():
      final body = n.functionExpression.body;
      return _clean(src.substring(start, body.offset)) + dep;
    case TopLevelVariableDeclaration():
      final list = n.variables;
      final kw = list.keyword?.lexeme ?? '';
      final type = list.type?.toSource() ?? '';
      return _clean('$kw $type ${d.name}') + dep;
    case TypeAlias():
      return _clean(
            n.toSource().replaceFirst(RegExp(r'^(@\w+(\(.*?\))?\s*)+'), ''),
          ) +
          dep;
    default:
      final brace = src.indexOf('{', start);
      return _clean(src.substring(start, brace < 0 ? n.end : brace)) + dep;
  }
}

String _memberLine(ClassMember m, String owner) {
  final dep = _deprecated(m.metadata) ? ' [deprecated]' : '';
  switch (m) {
    case ConstructorDeclaration():
      final kw = [
        if (m.externalKeyword != null) 'external',
        if (m.constKeyword != null) 'const',
        if (m.factoryKeyword != null) 'factory',
      ].join(' ');
      final name = m.name == null ? owner : '$owner.${m.name!.lexeme}';
      return _clean('$kw $name${m.parameters.toSource()}') + dep;
    case MethodDeclaration():
      final kw = [
        if (m.isStatic) 'static',
        m.returnType?.toSource() ?? 'dynamic',
        if (m.isGetter) 'get',
        if (m.isSetter) 'set',
        if (m.isOperator) 'operator',
      ].join(' ');
      final tp = m.typeParameters?.toSource() ?? '';
      final params = m.parameters?.toSource() ?? '';
      return _clean('$kw ${m.name.lexeme}$tp$params') + dep;
    case FieldDeclaration():
      final kw = [
        if (m.isStatic) 'static',
        if (m.fields.lateKeyword != null) 'late',
        m.fields.keyword?.lexeme ?? '',
        m.fields.type?.toSource() ?? '',
      ].join(' ');
      final names = [
        for (final v in m.fields.variables)
          if (isPublic(v.name.lexeme)) v.name.lexeme,
      ].join(', ');
      return _clean('$kw $names') + dep;
    default:
      return _clean(m.toSource());
  }
}

/// A stable, line-based description of the public API. Each top-level
/// declaration starts a block (`# <name>`), so changes map back to names.
String apiSnapshot(Map<String, SourceFile> byPath) {
  final buf = StringBuffer();
  for (final lib in publicLibraries) {
    final library = byPath[lib];
    if (library == null) continue;
    buf.writeln('## $lib');
    for (final d in library.unit.directives.whereType<ExportDirective>()) {
      final uri = d.uri.stringValue!;
      if (resolveUri(library.path, uri).contains(':')) {
        buf.writeln(_clean(d.toSource()));
      }
    }
    final api = exportedDeclarations({lib: library, ...byPath})
      ..sort((a, b) => a.name.compareTo(b.name));
    final seen = <String>{};
    for (final d in api) {
      if (!seen.add(d.name)) continue;
      buf.writeln('# ${d.name}');
      buf.writeln(_header(d));
      final n = d.node;
      if (n is EnumDeclaration) {
        final values = <String>[];
        n.accept(_EnumValues(values));
        buf.writeln('  values: ${values.join(', ')}');
      }
      final lines = <String>[
        for (final m in d.members)
          if (publicMemberNames(m).isNotEmpty) '  ${_memberLine(m, d.name)}',
      ]..sort();
      lines.forEach(buf.writeln);
    }
  }
  return buf.toString();
}

class _EnumValues extends RecursiveAstVisitor<void> {
  _EnumValues(this.out);
  final List<String> out;
  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    out.add(node.name.lexeme);
  }
}

/// Top-level names whose block differs between two snapshots.
Set<String> changedApiNames(String before, String after) {
  Map<String, String> blocks(String s) {
    final out = <String, String>{};
    String? current;
    for (final line in s.split('\n')) {
      if (line.startsWith('# ')) {
        current = line.substring(2);
        out[current] = '';
      } else if (current != null) {
        out[current] = '${out[current]}$line\n';
      }
    }
    return out;
  }

  final a = blocks(before);
  final b = blocks(after);
  return {
    for (final k in {...a.keys, ...b.keys})
      if (a[k] != b[k]) k,
  };
}

// ------------------------------------------------------------ deprecations

/// `@Deprecated` messages must name a replacement and the removal version.
List<Violation> badDeprecations(SourceFile f) {
  final out = <Violation>[];
  f.unit.accept(_DeprecationVisitor(f, out));
  return out;
}

final _removal = RegExp(r'Removed in \d+\.\d+\.\d+');
final _replacement = RegExp(r'\b(Use|use|Replaced by|No longer needed)\b');

class _DeprecationVisitor extends RecursiveAstVisitor<void> {
  _DeprecationVisitor(this.f, this.out);
  final SourceFile f;
  final List<Violation> out;

  @override
  void visitAnnotation(Annotation node) {
    final name = node.name.name;
    final line = f.lineOf(node.offset);
    if (name == 'deprecated') {
      out.add(
        Violation(f.path, line, 'use @Deprecated("Use X. Removed in N")'),
      );
    } else if (name == 'Deprecated') {
      final arg = node.arguments?.arguments.firstOrNull;
      final msg = arg is StringLiteral ? arg.stringValue ?? '' : '';
      if (!_removal.hasMatch(msg) || !_replacement.hasMatch(msg)) {
        out.add(
          Violation(
            f.path,
            line,
            '@Deprecated message must say what to use instead and '
            '"Removed in x.y.z": "$msg"',
          ),
        );
      }
    }
    super.visitAnnotation(node);
  }
}

/// Names of declarations / members annotated `@Deprecated` in [f].
List<String> deprecatedNames(SourceFile f) {
  final out = <String>[];
  for (final m in f.unit.declarations) {
    if (_deprecated(m.metadata)) out.addAll(declaredNames(m));
    final members = <ClassMember>[];
    m.accept(_MemberCollector(m, members));
    for (final x in members) {
      if (_deprecated(x.metadata)) out.addAll(publicMemberNames(x));
    }
  }
  return out.where((n) => n.isNotEmpty).toList();
}

// ------------------------------------------------------ analytics key literals

/// Map literal keys spelled as strings that are analytics keys. Payloads
/// must use the `ChorkiAnalyticsKeys` constants so renames stay consistent.
List<Violation> analyticsKeyLiterals(SourceFile f, Set<String> keys) {
  if (f.path.endsWith('chorki_analytics_schema.dart')) return const [];
  final v = _KeyLiteralVisitor(f, keys);
  f.unit.accept(v);
  return v.found;
}

class _KeyLiteralVisitor extends RecursiveAstVisitor<void> {
  _KeyLiteralVisitor(this.f, this.keys);
  final SourceFile f;
  final Set<String> keys;
  final found = <Violation>[];

  @override
  void visitMapLiteralEntry(MapLiteralEntry node) {
    final key = node.key;
    if (key is SimpleStringLiteral && keys.contains(key.value)) {
      final line = f.lineOf(key.offset);
      if (!f.allows('analytics_key', line)) {
        found.add(
          Violation(
            f.path,
            line,
            "'${key.value}': use ChorkiAnalyticsKeys.${key.value}",
          ),
        );
      }
    }
    super.visitMapLiteralEntry(node);
  }
}

// ------------------------------------------------------------- equality

/// A class that overrides `==` must compare every instance field in it and
/// hash every one in `hashCode`, so a field added later cannot be forgotten.
/// A call to one of the class's own methods (e.g. `toMap()`) counts as the
/// fields that method reads.
List<Violation> incompleteEquality(SourceFile f) {
  final out = <Violation>[];
  for (final c in f.unit.declarations.whereType<ClassDeclaration>()) {
    final members = c.body.members;
    final eq = members.whereType<MethodDeclaration>().where(
      (m) => m.isOperator && m.name.lexeme == '==',
    );
    if (eq.isEmpty) continue;
    final hash = members.whereType<MethodDeclaration>().where(
      (m) => m.isGetter && m.name.lexeme == 'hashCode',
    );
    final fields = [
      for (final d in members.whereType<FieldDeclaration>())
        if (!d.isStatic)
          for (final v in d.fields.variables) v.name.lexeme,
    ];
    final methods = {
      for (final m in members.whereType<MethodDeclaration>())
        if (!m.isOperator) m.name.lexeme: m.body.toSource(),
    };
    String expand(String src) => [
      src,
      for (final e in methods.entries)
        if (RegExp('\\b${e.key}\\(').hasMatch(src)) e.value,
    ].join('\n');
    final eqSrc = expand(eq.first.body.toSource());
    final hashSrc = hash.isEmpty ? '' : expand(hash.first.body.toSource());
    final name = c.namePart.typeName.lexeme;
    final line = f.lineOf(eq.first.offset);
    if (hash.isEmpty && !f.allows('equality', line)) {
      out.add(Violation(f.path, line, '$name overrides == but not hashCode'));
    }
    for (final field in fields) {
      final word = RegExp('\\b${RegExp.escape(field)}\\b');
      final missing = [
        if (!word.hasMatch(eqSrc)) '==',
        if (hash.isNotEmpty && !word.hasMatch(hashSrc)) 'hashCode',
      ];
      if (missing.isNotEmpty && !f.allows('equality', line)) {
        out.add(
          Violation(
            f.path,
            line,
            '$name.$field is missing from ${missing.join(' and ')}',
          ),
        );
      }
    }
  }
  return out;
}
