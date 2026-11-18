// Behaviour scenario specs: each test/scenarios/*.yaml file is one test.
import 'package:chorki_player/chorki_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'scenario_runner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runner self-check', () {
    Scenario inline(String yaml) =>
        Scenario('inline', loadYaml(yaml) as YamlMap);

    test('a wrong expectation fails with a readable message', () {
      final s = inline('''
name: wrong
steps: [activate, bind, {value: {initialized: true}}]
expect:
  events: [play]
''');
      expect(check(s, run(s)), ['event 1: expected play, got impression']);
    });

    test('exact mode reports extra events; matchers and aliases work', () {
      final s = inline(r'''
name: matchers
steps:
  - activate
  - bind
  - value: {initialized: true}
  - play: {to: 4s}
  - deactivate: swipedAway
expect:
  events:
    - impression: {$session: $a}
    - play: {timeToPlayMs: ">=0", $session: $a}
expect_unused: true
''');
      final problems = check(s, run(s));
      expect(problems.single, startsWith('unexpected extra events'));
    });

    test('durations parse', () {
      expect(parseDuration('500ms'), const Duration(milliseconds: 500));
      expect(parseDuration('1.5s'), const Duration(milliseconds: 1500));
      expect(parseDuration('2m'), const Duration(minutes: 2));
      expect(() => parseDuration('soon'), throwsA(isA<ScenarioFailure>()));
    });
  });

  group('scenarios', () {
    for (final scenario in loadScenarios()) {
      test('${scenario.name}: ${scenario.description}', () {
        final result = run(scenario);
        final problems = check(scenario, result);
        if (problems.isNotEmpty) printOnFailure(describeRun(result));
        expect(problems, isEmpty, reason: scenario.path);
      });
    }
  });

  test('every event type is covered by at least one scenario', () {
    final covered = {for (final s in loadScenarios()) ...s.covered};
    final missing = [
      for (final t in ChorkiAnalyticsEventType.values)
        if (!covered.contains(t)) t.name,
    ];
    expect(
      missing,
      isEmpty,
      reason: 'Add a test/scenarios/*.yaml that asserts on these events',
    );
  });
}
