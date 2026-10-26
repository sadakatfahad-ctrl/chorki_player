import 'package:flutter_test/flutter_test.dart';

import 'package:example_app/main.dart';
import 'package:example_app/test_videos.dart';

void main() {
  testWidgets('catalog lists every group', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Chorki Player test videos'), findsOneWidget);
    for (final group in testVideoGroups) {
      await tester.scrollUntilVisible(find.text(group.title), 200);
      expect(find.text(group.title), findsOneWidget);
    }
  });

  testWidgets('player page switches through every layout', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.scrollUntilVisible(find.text('Tall strip'), 200);
    await tester.tap(find.text('Tall strip'));
    // The loading spinner never settles: pump fixed steps instead.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('Expected 1:3 (240×720) · Reported: loading…'),
      findsOneWidget,
    );
    // Every layout must lay out cleanly, including sizeToVideo in a ListView.
    for (final layout in PlayerLayout.values) {
      await tester.tap(find.text(layout.label));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: layout.label);
    }
    // No video plugin in widget tests: the load fails after the init timeout
    // and the player offers a retry.
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
  });
}
