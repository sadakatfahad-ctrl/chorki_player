import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/chorki_player_testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final c in analyticsSinkConformance(
    () => ChorkiBufferedAnalyticsSink(onBatch: (_) {}),
  )) {
    test(c.name, c.body);
  }

  test('batches by size and on flush; consent revocation drops', () async {
    final batches = <int>[];
    final sink = ChorkiBufferedAnalyticsSink(
      onBatch: (b) => batches.add(b.length),
      batchSize: 3,
    );
    for (var i = 0; i < 4; i++) {
      sink.onEvent(sampleAnalyticsEvent(ChorkiAnalyticsEventType.heartbeat));
    }
    expect(batches, [3]);
    await sink.flush();
    expect(batches, [3, 1]);
    await sink.flush();
    expect(batches, [3, 1], reason: 'never an empty batch');
    sink.onEvent(sampleAnalyticsEvent(ChorkiAnalyticsEventType.pause));
    await sink.onConsentRevoked();
    await sink.flush();
    expect(batches, [3, 1]);
  });
}
