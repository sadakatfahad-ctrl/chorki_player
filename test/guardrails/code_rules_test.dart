// Source-level antipattern guardrails. Each rule is first proven on an inline
// fixture, then run on lib/ against the shrink-only baseline.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '_guardrail.dart';
import '_rules.dart';

SourceFile fixture(String code, {String path = 'lib/src/x/fixture.dart'}) =>
    SourceFile(path, code);

List<Violation> onLib(List<Violation> Function(SourceFile) rule) => [
  for (final f in libSources) ...rule(f),
];

void main() {
  group('swallowed_error', () {
    test('catches empty catches and silent catchError handlers', () {
      final f = fixture('''
void a() { try { x(); } catch (_) {} }
void b() { try { x(); } catch (_) { return; } }
void c() { f.catchError((Object _) {}); }
void ok1() { try { x(); } catch (e, st) { ChorkiDiagnostics.report(e, st, 'a'); } }
void ok2() { try { x(); } catch (_) { rethrow; } }
void ok3() {
  // guardrail:allow swallowed_error - best effort cleanup
  try { x(); } catch (_) {}
}
void bad4() {
  // guardrail:allow swallowed_error
  try { x(); } catch (_) {}
}
void ok4() { try { x(); } on FormatException { return; } }
void ok5() { try { x(); } catch (e, st) { completer.completeError(e, st); } }
void bad6() { try { x(); } on Object catch (e) { return; } }
''');
      expect(swallowedErrors(f).map((v) => v.line), [1, 2, 3, 12, 16]);
    });

    test('lib/ is within the baseline', () {
      expectRatchet('swallowed_error', onLib(swallowedErrors));
    });
  });

  group('layering', () {
    test('catches forbidden imports', () {
      final domain = fixture(
        "import '../../data/model/byte_model.dart';\n"
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:meta/meta.dart';\n",
        path: 'lib/src/domain/entity/x.dart',
      );
      expect(layeringViolations(domain).map((v) => v.line), [1, 2]);

      final core = fixture(
        "import 'matomo/matomo_sink.dart';\n"
        "import 'package:get_it/get_it.dart';\n"
        "import 'package:flutter_test/flutter_test.dart';\n"
        "import '../../chorki_player.dart';\n",
        path: 'lib/src/analytics/x.dart',
      );
      expect(layeringViolations(core).map((v) => v.line), [1, 2, 3, 4]);
    });

    test('lib/ follows the layering', () {
      expect(onLib(layeringViolations), isEmpty);
    });
  });

  group('determinism', () {
    test('catches wall clock and unseeded randomness', () {
      final f = fixture('''
final a = DateTime.now();
final b = Random();
final c = Random.secure();
DateTime Function() d = DateTime.now;
final e = DateTime(2020);
''');
      expect(nondeterminism(f).map((v) => v.line), [1, 2, 3, 4]);
      expect(
        nondeterminism(
          fixture('final a = DateTime.now();', path: 'lib/src/core/clock.dart'),
        ),
        isEmpty,
      );
    });

    test('lib/ is within the baseline', () {
      expectRatchet('determinism', onLib(nondeterminism));
    });
  });

  group('magic_number', () {
    test('catches inline durations, allows named constants and defaults', () {
      final f = fixture('''
const kWait = Duration(milliseconds: 300);
class A {
  static const tick = Duration(seconds: 1);
  A({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;
  void run() {
    Future.delayed(const Duration(milliseconds: 200));
    final z = Duration.zero;
    final d = Duration(milliseconds: ms);
    const local = Duration(seconds: 2);
  }
}
''');
      expect(magicDurations(f).map((v) => v.line), [7]);
    });

    test('lib/ is within the baseline', () {
      expectRatchet('magic_number', onLib(magicDurations));
    });
  });

  group('analytics_key', () {
    final keys = {
      for (final m in RegExp(r"static const (\w+) = '\w+';").allMatches(
        File(
          'lib/src/analytics/chorki_analytics_schema.dart',
        ).readAsStringSync(),
      ))
        m[1]!,
    };

    test('catches analytics keys written as string literals', () {
      final f = fixture('''
final a = {'percent': 50, ChorkiAnalyticsKeys.percent: 50, 'other': 1};
''');
      expect(analyticsKeyLiterals(f, keys).map((v) => v.line), [1]);
      expect(keys, contains('percent'));
    });

    test('lib/ uses ChorkiAnalyticsKeys', () {
      expectRatchet('analytics_key', [
        for (final f in libSources) ...analyticsKeyLiterals(f, keys),
      ]);
    });
  });

  group('file_size', () {
    test('flags files over the limit, one violation per 50 lines over', () {
      final f = fixture(List.filled(maxLibFileLines + 51, 'x;').join('\n'));
      expect(oversizedFile(f), hasLength(2));
      final docs = fixture(
        List.filled(maxLibFileLines * 2, '/// doc').join('\n'),
      );
      expect(oversizedFile(docs), isEmpty, reason: 'comments do not count');
    });

    test('lib/ is within the baseline', () {
      expectRatchet('file_size', onLib(oversizedFile));
    });
  });

  group('equality', () {
    test('flags fields missing from == or hashCode', () {
      final f = fixture('''
class A {
  const A(this.a, this.b);
  static const zero = 0;
  final int a;
  final int b;
  @override
  bool operator ==(Object other) => other is A && other.a == a;
  @override
  int get hashCode => Object.hash(a, b);
}
class B {
  final int x;
  @override
  bool operator ==(Object other) => other is B && other.x == x;
}
class C {
  final int y;
  final int z;
  Map<String, int> toMap() => {'y': y, 'z': z};
  @override
  bool operator ==(Object other) => other is C && other.toMap() == toMap();
  @override
  int get hashCode => toMap().hashCode;
}
''');
      expect(incompleteEquality(f).map((v) => v.message), [
        'A.b is missing from ==',
        'B overrides == but not hashCode',
      ]);
    });

    test('lib/ is within the baseline', () {
      expectRatchet('equality', onLib(incompleteEquality));
    });
  });
}
