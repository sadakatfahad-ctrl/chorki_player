// Widget-level behaviour scenarios: each test/scenarios/widget/*.yaml file
// drives a real ChorkiPlayer (see widget_scenario_runner.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'scenario_runner.dart';
import 'widget_scenario_runner.dart';

void main() {
  group('runner self-check', () {
    Scenario inline(String yaml) =>
        Scenario('inline', loadYaml(yaml) as YamlMap);

    testWidgets('a wrong expectation fails', (tester) async {
      final s = inline('''
name: wrong
given: {source: url}
steps: [{play: {to: 1s}}]
expect: {events: [sessionEnd]}
''');
      expect(check(s, await runWidget(tester, s)), isNotEmpty);
    });

    testWidgets('an unknown step is an error', (tester) async {
      final s = inline('''
name: unknown
given: {source: url}
steps: [fly]
''');
      Object? error;
      try {
        await runWidget(tester, s);
      } on ScenarioFailure catch (e) {
        error = e;
      }
      expect(error, isA<ScenarioFailure>());
    });
  });

  for (final scenario in loadScenarios('test/scenarios/widget')) {
    testWidgets('${scenario.name}: ${scenario.description}', (tester) async {
      final result = await runWidget(tester, scenario);
      final problems = check(scenario, result);
      if (problems.isNotEmpty) printOnFailure(describeRun(result));
      expect(problems, isEmpty, reason: scenario.path);
    });
  }
}
