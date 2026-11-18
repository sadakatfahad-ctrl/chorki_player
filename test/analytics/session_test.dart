import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/diagnostics.dart';

const _duration = Duration(seconds: 60);

VideoPlayerValue _value({
  Duration position = Duration.zero,
  bool playing = false,
  bool buffering = false,
  bool completed = false,
  double volume = 1,
  Duration duration = _duration,
}) => VideoPlayerValue(
  duration: duration,
  size: const Size(720, 1280),
  position: position,
  isInitialized: true,
  isPlaying: playing,
  isBuffering: buffering,
  isCompleted: completed,
  volume: volume,
);

void main() {
  late ValueNotifier<VideoPlayerValue> video;
  late MemoryAnalyticsSink sink;
  late ChorkiAnalyticsSession session;
  late DateTime now;
  var ids = 0;

  ChorkiAnalyticsSession create({bool newSessionOnLoop = true}) =>
      ChorkiAnalyticsSession(
        config: ChorkiAnalyticsConfig(
          sinks: [sink],
          // Heartbeats are triggered by hand.
          heartbeatInterval: const Duration(hours: 1),
          newSessionOnLoop: newSessionOnLoop,
        ),
        metadata: () =>
            const ChorkiMediaMetadata(contentId: 'c1', title: 'Episode 1'),
        clock: () => now,
        idGenerator: () => 'id${ids++}',
      );

  /// Plays from the current position to [to], one 500 ms tick at a time,
  /// like video_player does.
  void playTo(Duration to) {
    var pos = video.value.position;
    while (pos < to) {
      pos += const Duration(milliseconds: 500);
      if (pos > to) pos = to;
      now = now.add(const Duration(milliseconds: 500));
      video.value = _value(position: pos, playing: true);
    }
  }

  List<Map<String, Object?>> dataOf(ChorkiAnalyticsEventType type) => [
    for (final e in sink.events)
      if (e.type == type) e.data,
  ];

  setUp(() {
    ids = 0;
    now = DateTime(2026, 11, 17, 12);
    video = ValueNotifier(_value());
    sink = MemoryAnalyticsSink();
    session = create();
  });

  tearDown(() => session.dispose());

  test('reports nothing until both active and bound', () {
    session.bind(video);
    video.value = _value(playing: true, position: const Duration(seconds: 1));
    expect(sink.events, isEmpty);

    session.activate();
    expect(sink.types.first, ChorkiAnalyticsEventType.impression);
    expect(sink.events.first.sessionId, 'id0');
    expect(sink.events.first.metadata.title, 'Episode 1');
  });

  test('impression → play with time to play → watched time grows only while '
      'playing', () {
    session
      ..activate()
      ..bind(video);
    now = now.add(const Duration(seconds: 2));
    video.value = _value(playing: true);
    expect(dataOf(ChorkiAnalyticsEventType.play).single['timeToPlayMs'], 2000);

    playTo(const Duration(seconds: 10));
    expect(session.watchedTime, const Duration(seconds: 10));

    // Pause: no watched time while paused, even as the clock runs.
    video.value = _value(position: const Duration(seconds: 10));
    now = now.add(const Duration(seconds: 30));
    session.heartbeat();
    expect(session.watchedTime, const Duration(seconds: 10));
    expect(sink.types, contains(ChorkiAnalyticsEventType.pause));

    video.value = _value(position: const Duration(seconds: 10), playing: true);
    expect(sink.types, contains(ChorkiAnalyticsEventType.resume));
  });

  test('heartbeats carry only newly watched 5 s segments', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 12));
    session.heartbeat();
    playTo(const Duration(seconds: 17));
    session.heartbeat();
    session.heartbeat();

    final beats = dataOf(ChorkiAnalyticsEventType.heartbeat)
        .where((d) => d['trigger'] == 'interval')
        .map((d) => d['newSegments'])
        .toList();
    expect(beats, [
      [5, 10, 15],
      [20],
      <int>[],
    ]);
  });

  test('a user seek is reported with its source and the jump is not counted '
      'as watched', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 4));

    session.recordSeek(
      const Duration(seconds: 4),
      const Duration(seconds: 40),
      ChorkiSeekSource.scrub,
    );
    video.value = _value(position: const Duration(seconds: 40), playing: true);
    playTo(const Duration(seconds: 42));

    final seek = dataOf(ChorkiAnalyticsEventType.seek).single;
    expect(seek, {'fromMs': 4000, 'toMs': 40000, 'source': 'scrub'});
    expect(session.watchedTime, const Duration(seconds: 6));
  });

  test('the pause caused by a scrub is not reported as a pause', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 3));
    session.recordScrubStart();
    video.value = _value(position: const Duration(seconds: 3));
    session.recordSeek(
      const Duration(seconds: 3),
      const Duration(seconds: 20),
      ChorkiSeekSource.seekBarDrag,
    );
    video.value = _value(position: const Duration(seconds: 20), playing: true);

    expect(sink.types, isNot(contains(ChorkiAnalyticsEventType.pause)));
    expect(sink.types, isNot(contains(ChorkiAnalyticsEventType.resume)));
  });

  test('quartiles fire once each', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 50));
    session.recordSeek(
      const Duration(seconds: 50),
      const Duration(seconds: 5),
      ChorkiSeekSource.api,
    );
    video.value = _value(position: const Duration(seconds: 5), playing: true);
    playTo(const Duration(seconds: 50));

    expect(dataOf(ChorkiAnalyticsEventType.quartile).map((d) => d['percent']), [
      25,
      50,
      75,
    ]);
  });

  test('a looping video wrapping around completes, loops and starts a new '
      'session', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(milliseconds: 59500));
    now = now.add(const Duration(milliseconds: 500));
    video.value = _value(
      position: const Duration(milliseconds: 300),
      playing: true,
    );

    final types = sink.types.toList();
    final loopAt = types.indexOf(ChorkiAnalyticsEventType.loop);
    expect(types.sublist(loopAt - 3, loopAt + 1), [
      ChorkiAnalyticsEventType.heartbeat,
      ChorkiAnalyticsEventType.quartile,
      ChorkiAnalyticsEventType.complete,
      ChorkiAnalyticsEventType.loop,
    ]);
    final end = sink.events.firstWhere(
      (e) => e.type == ChorkiAnalyticsEventType.sessionEnd,
    );
    expect(end.sessionId, 'id0');
    expect(end.data['reason'], 'looped');
    expect(end.watchedTime, _duration);

    final next = sink.events.last;
    expect(next.sessionId, 'id1');
    expect(session.watchedTime, const Duration(milliseconds: 300));
  });

  test('without newSessionOnLoop the loop keeps the session', () {
    session.dispose();
    session = create(newSessionOnLoop: false);
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(milliseconds: 59500));
    now = now.add(const Duration(milliseconds: 500));
    video.value = _value(
      position: const Duration(milliseconds: 300),
      playing: true,
    );

    expect(sink.events.map((e) => e.sessionId).toSet(), {'id0'});
    expect(dataOf(ChorkiAnalyticsEventType.loop).single['loopCount'], 1);
  });

  test('ads freeze the watched time and are not viewer pauses', () {
    session
      ..activate()
      ..bind(video);
    session.adContext = const {'adCampaignId': 'camp-7'};
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 20));

    session.recordAdBreakStart();
    video.value = _value(position: const Duration(seconds: 20));
    now = now.add(const Duration(seconds: 15));
    session.recordAd(ChorkiAnalyticsEventType.adStart, {'adId': 'a1'});
    session.recordAdBreakEnd();
    video.value = _value(position: const Duration(seconds: 20), playing: true);
    playTo(const Duration(seconds: 22));

    expect(session.watchedTime, const Duration(seconds: 22));
    expect(sink.types, isNot(contains(ChorkiAnalyticsEventType.pause)));
    final start = dataOf(ChorkiAnalyticsEventType.adBreakStart).single;
    expect(start['breakKind'], 'midRoll');
    expect(start['adCampaignId'], 'camp-7');
    expect(dataOf(ChorkiAnalyticsEventType.adStart).single['adId'], 'a1');
    expect(
      dataOf(ChorkiAnalyticsEventType.adBreakEnd).single['durationMs'],
      15000,
    );
  });

  test('rebuffering after the first frame is timed', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 2));
    video.value = _value(
      position: const Duration(seconds: 2),
      playing: true,
      buffering: true,
    );
    now = now.add(const Duration(milliseconds: 1200));
    video.value = _value(position: const Duration(seconds: 2), playing: true);

    expect(
      dataOf(ChorkiAnalyticsEventType.bufferEnd).single['durationMs'],
      1200,
    );
    session.deactivate(ChorkiSessionEndReason.swipedAway);
    final end = dataOf(ChorkiAnalyticsEventType.sessionEnd).single;
    expect(end['rebufferCount'], 1);
    expect(end['rebufferMs'], 1200);
    expect(end['reason'], 'swipedAway');
  });

  test('deactivate ends the session; reactivating starts a fresh one', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 6));
    session.deactivate(ChorkiSessionEndReason.swipedAway);

    final end = sink.events.last;
    expect(end.type, ChorkiAnalyticsEventType.sessionEnd);
    expect(end.data['dwellMs'], 6000);
    expect(session.isHeartbeatRunning, isFalse);

    video.value = _value();
    session.activate();
    expect(sink.events.last.type, ChorkiAnalyticsEventType.impression);
    expect(sink.events.last.sessionId, 'id1');
    expect(session.watchedTime, Duration.zero);
  });

  test('swiping away mid-break closes the break; the next visit is not '
      'frozen and has no stray adBreakEnd', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 3));
    session.recordAdBreakStart();
    video.value = _value(position: const Duration(seconds: 3));
    now = now.add(const Duration(seconds: 4));
    session.deactivate(ChorkiSessionEndReason.swipedAway);

    final closed = dataOf(ChorkiAnalyticsEventType.adBreakEnd).single;
    expect(closed['interrupted'], isTrue);
    expect(closed['durationMs'], 4000);

    sink.clear();
    session.activate();
    video.value = _value(position: const Duration(seconds: 3), playing: true);
    playTo(const Duration(seconds: 6));
    expect(session.watchedTime, const Duration(seconds: 3));
    expect(sink.types, contains(ChorkiAnalyticsEventType.play));
    session.recordAdBreakEnd();
    expect(sink.types, isNot(contains(ChorkiAnalyticsEventType.adBreakEnd)));
  });

  test('a drag cut off by the end of a session does not hide later pauses', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 2));
    session.recordScrubStart();
    session.deactivate(ChorkiSessionEndReason.swipedAway);

    sink.clear();
    session.activate();
    video.value = _value(position: const Duration(seconds: 2), playing: true);
    playTo(const Duration(seconds: 4));
    video.value = _value(position: const Duration(seconds: 4));
    expect(sink.types, contains(ChorkiAnalyticsEventType.pause));
  });

  test('leaving before the first frame is an abandon (exit before start)', () {
    session.activate();
    now = now.add(const Duration(seconds: 3));
    session.recordError(
      const ChorkiPlayerError(
        ChorkiErrorCode.videoLoad,
        stage: ChorkiErrorStage.load,
      ),
      willRetry: true,
    );
    session.deactivate(ChorkiSessionEndReason.swipedAway);

    final abandon = dataOf(ChorkiAnalyticsEventType.abandon).single;
    expect(abandon, {
      'waitedMs': 3000,
      'reason': 'swipedAway',
      'abandonStage': 'loading',
      'errorCount': 1,
    });
    expect(
      sink.types,
      isNot(contains(ChorkiAnalyticsEventType.sessionEnd)),
      reason: 'nothing was shown',
    );
  });

  test('loaded but never played is an abandon at the ready stage; a played '
      'view is not an abandon', () {
    session
      ..activate()
      ..bind(video);
    session.deactivate(ChorkiSessionEndReason.disposed);
    expect(
      dataOf(ChorkiAnalyticsEventType.abandon).single['abandonStage'],
      'ready',
    );

    sink.clear();
    session.activate();
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 2));
    session.deactivate(ChorkiSessionEndReason.swipedAway);
    expect(sink.types, isNot(contains(ChorkiAnalyticsEventType.abandon)));
  });

  test('volume and mute changes', () {
    session
      ..activate()
      ..bind(video);
    video.value = _value(volume: 0);
    expect(dataOf(ChorkiAnalyticsEventType.volumeChange).single, {
      'from': 1.0,
      'to': 0.0,
      'muted': true,
    });
  });

  test('nothing is reported without consent', () {
    session.config = ChorkiAnalyticsConfig(
      sinks: [sink],
      consentGranted: false,
    );
    session
      ..activate()
      ..bind(video);
    video.value = _value(playing: true);
    playTo(const Duration(seconds: 5));
    expect(sink.events, isEmpty);
  });

  test('a throwing sink does not break the others', () {
    final reports = captureDiagnostics();
    addTearDown(() => expect(reports.toSet(), {'analytics.sink'}));
    final other = MemoryAnalyticsSink();
    session.config = ChorkiAnalyticsConfig(
      sinks: [CallbackAnalyticsSink((_) => throw StateError('x')), other],
      heartbeatInterval: const Duration(hours: 1),
    );
    session
      ..activate()
      ..bind(video);
    expect(other.types, [ChorkiAnalyticsEventType.impression]);
  });
}
