import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replay fires once when seeking to the start after completion', () {
    final sink = MemoryAnalyticsSink();
    var now = DateTime.utc(2026);
    final video = ValueNotifier(
      const VideoPlayerValue(duration: Duration(seconds: 10)),
    );
    final s =
        ChorkiAnalyticsSession(
            config: ChorkiAnalyticsConfig(sinks: [sink], clock: () => now),
            metadata: () => const ChorkiMediaMetadata(contentId: 'c'),
          )
          ..bind(video)
          ..activate();
    video.value = video.value.copyWith(isInitialized: true, isPlaying: true);
    for (var ms = 500; ms <= 10000; ms += 500) {
      now = now.add(const Duration(milliseconds: 500));
      video.value = video.value.copyWith(position: Duration(milliseconds: ms));
    }
    video.value = video.value.copyWith(isPlaying: false, isCompleted: true);
    s.recordSeek(
      const Duration(seconds: 10),
      Duration.zero,
      ChorkiSeekSource.api,
    );
    final replays = sink.events.where((e) => e.type.name == 'replay').toList();
    expect(replays, hasLength(1));
    expect(replays.single.data['fromMs'], 10000);
    s.recordSeek(
      const Duration(seconds: 3),
      Duration.zero,
      ChorkiSeekSource.api,
    );
    expect(sink.events.where((e) => e.type.name == 'replay'), hasLength(1));
    s.dispose();
  });
}
