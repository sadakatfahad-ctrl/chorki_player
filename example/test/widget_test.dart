import 'package:flutter_test/flutter_test.dart';

import 'package:example_app/main.dart';

void main() {
  testWidgets('ExampleApp renders and degrades to retry on failure', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    // The byte request is rejected by the test HTTP sandbox, so the player
    // settles on its error view.
    await tester.pumpAndSettle();

    expect(find.text('Chorki Player'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
