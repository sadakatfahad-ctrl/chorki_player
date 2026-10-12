import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as pi;

import 'fakes/fake_pip_delegate.dart';
import 'fakes/fake_video_player_platform.dart';

const _p1080 = pi.VideoTrack(
  id: '0_0',
  isSelected: false,
  height: 1080,
  width: 1920,
  bitrate: 5000000,
);
const _p720 = pi.VideoTrack(
  id: '0_1',
  isSelected: true,
  height: 720,
  width: 1280,
  bitrate: 2500000,
);
const _en = pi.VideoAudioTrack(
  id: 'a_en',
  label: 'English',
  language: 'en',
  isSelected: true,
);
const _bn = pi.VideoAudioTrack(
  id: 'a_bn',
  label: 'Bangla',
  language: 'bn',
  isSelected: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeVideoPlayerPlatform platform;
  late FakePipDelegate pip;
  late ChorkiPlayerController chorki;

  setUp(() {
    platform = FakeVideoPlayerPlatform()
      ..videoTracks = const [_p1080, _p720]
      ..audioTracks = const [_en, _bn];
    pi.VideoPlayerPlatform.instance = platform;
    pip = FakePipDelegate();
    chorki = ChorkiPlayerController(pipDelegate: pip);
  });

  tearDown(() => chorki.dispose());

  Future<VideoPlayerController> attached() async {
    final c = await createTestController(platform);
    chorki.attach(c);
    await pumpEventQueue();
    return c;
  }

  test('attach loads video and audio tracks', () async {
    final c = await attached();
    expect(chorki.isAttached, isTrue);
    expect(chorki.videoTracks.value.map((t) => t.id), ['0_0', '0_1']);
    expect(chorki.selectedVideoTrack.value, isNull, reason: 'Auto');
    expect(chorki.audioTracks.value, hasLength(2));
    expect(chorki.selectedAudioTrackId.value, 'a_en');
    expect(chorki.value.value.isInitialized, isTrue);
    await c.dispose();
  });

  test('unsupported platforms report no tracks', () async {
    platform
      ..videoTracksSupported = false
      ..audioTracksSupported = false;
    final c = await attached();
    expect(chorki.videoTracks.value, isEmpty);
    expect(chorki.audioTracks.value, isEmpty);
    await c.dispose();
  });

  test('selectQuality locks a track and null returns to Auto', () async {
    final c = await attached();
    final track = chorki.videoTracks.value.first;
    await chorki.selectQuality(track);
    expect(chorki.selectedVideoTrack.value?.id, '0_0');
    expect(platform.videoTrackCalls.last.$2?.id, '0_0');

    await chorki.selectQuality(null);
    expect(chorki.selectedVideoTrack.value, isNull);
    expect(platform.videoTrackCalls.last.$2, isNull);
    await c.dispose();
  });

  test('selectAudioTrack forwards the id', () async {
    final c = await attached();
    await chorki.selectAudioTrack('a_bn');
    expect(chorki.selectedAudioTrackId.value, 'a_bn');
    expect(platform.audioTrackCalls.single.$2, 'a_bn');
    await c.dispose();
  });

  test('speed chosen while detached is applied on attach', () async {
    await chorki.setSpeed(1.5);
    expect(platform.speedCalls, isEmpty);
    final c = await attached();
    expect(c.value.playbackSpeed, 1.5);
    expect(chorki.speed.value, 1.5);
    await c.dispose();
  });

  test('detach resets per-video state but keeps preferences', () async {
    final c = await attached();
    await chorki.setSpeed(2);
    chorki.setFit(ChorkiVideoFit.fill);
    chorki.detach(c);

    expect(chorki.isAttached, isFalse);
    expect(chorki.videoTracks.value, isEmpty);
    expect(chorki.audioTracks.value, isEmpty);
    expect(chorki.value.value.isInitialized, isFalse);
    expect(chorki.speed.value, 2);
    expect(chorki.fit.value, ChorkiVideoFit.fill);
    await c.dispose();
  });

  test('detach ignores a controller that is not attached', () async {
    final c = await attached();
    final other = await createTestController(platform);
    chorki.detach(other);
    expect(chorki.isAttached, isTrue);
    await other.dispose();
    await c.dispose();
  });

  test('playback calls are no-ops while detached', () async {
    await chorki.play();
    await chorki.pause();
    await chorki.seekForward();
    await chorki.selectQuality(_p720.toAppTrack());
    expect(platform.playCalls, isEmpty);
    expect(platform.seekCalls, isEmpty);
    expect(platform.videoTrackCalls, isEmpty);
  });

  test('seekForward / seekBack clamp to the media bounds', () async {
    final c = await attached();
    await chorki.seekBack();
    expect(platform.seekCalls.last.$2, Duration.zero);

    await chorki.seekTo(const Duration(minutes: 1, seconds: 55));
    await chorki.seekForward();
    expect(platform.seekCalls.last.$2, const Duration(minutes: 2));
    await c.dispose();
  });

  test('toggleFit flips between fit and fill', () {
    expect(chorki.fit.value, ChorkiVideoFit.fit);
    chorki.toggleFit();
    expect(chorki.fit.value, ChorkiVideoFit.fill);
    chorki.toggleFit();
    expect(chorki.fit.value, ChorkiVideoFit.fit);
  });

  test('retry calls the host callback; detach clears it', () async {
    var retries = 0;
    final c = await createTestController(platform);
    chorki.attach(c, onRetry: () => retries++);
    chorki.retry();
    expect(retries, 1);
    chorki.detach(c);
    chorki.retry();
    expect(retries, 1);
    await c.dispose();
  });

  testWidgets('enterPip uses the video aspect ratio', (tester) async {
    late VideoPlayerController c;
    await tester.runAsync(() async => c = await attached());
    await chorki.enterPip();
    expect(chorki.pipStatus.value, ChorkiPipStatus.enabled);
    expect(pip.enterCalls.single, closeTo(720 / 1280, 1e-6));
    await tester.pump(const Duration(seconds: 2)); // drain status probes
    await tester.runAsync(c.dispose);
  });

  test('setAutoPip arms and disarms', () async {
    await chorki.setAutoPip(true);
    expect(chorki.isAutoPipEnabled, isTrue);
    expect(chorki.pipStatus.value, ChorkiPipStatus.automatic);
    await chorki.setAutoPip(false);
    expect(pip.autoCalls.map((c) => c.$1), [true, false]);
    expect(chorki.pipStatus.value, ChorkiPipStatus.disabled);
  });

  test('FloatingPipDelegate is unavailable off Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      expect(await FloatingPipDelegate().status(), ChorkiPipStatus.unavailable);
      expect(await FloatingPipDelegate().enter(1), ChorkiPipStatus.unavailable);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('VideoPreloader with ChorkiMediaOptions', () {
    test('passes headers, buffer and screen options to the platform', () async {
      final c = await VideoPreloader().load(
        Uri.parse('https://test.local/v.m3u8'),
        options: const ChorkiMediaOptions(
          httpHeaders: {'Authorization': 'Bearer x'},
          backBuffer: Duration(seconds: 30),
          allowBackgroundPlayback: true,
          keepScreenOn: false,
        ),
      );
      expect(c, isNotNull);
      final opts = platform.creationOptions.single;
      expect(opts.dataSource.httpHeaders, {'Authorization': 'Bearer x'});
      expect(opts.videoPlayerOptions?.backBufferDurationMs, 30000);
      expect(opts.videoPlayerOptions?.allowBackgroundPlayback, isTrue);
      expect(platform.preventsSleepCalls.single.$2, isFalse);
      await c!.dispose();
    });

    test('seeks to startPosition after init', () async {
      final c = await VideoPreloader().load(
        Uri.parse('https://test.local/v.mp4'),
        options: const ChorkiMediaOptions(startPosition: Duration(seconds: 42)),
      );
      expect(platform.seekCalls.single.$2, const Duration(seconds: 42));
      await c!.dispose();
    });
  });

  test('ChorkiMediaOptions equality and copyWith', () {
    const a = ChorkiMediaOptions(httpHeaders: {'a': '1'});
    expect(a, const ChorkiMediaOptions(httpHeaders: {'a': '1'}));
    expect(
      a.hashCode,
      const ChorkiMediaOptions(httpHeaders: {'a': '1'}).hashCode,
    );
    final b = a.copyWith(keepScreenOn: false);
    expect(b.httpHeaders, {'a': '1'});
    expect(b.keepScreenOn, isFalse);
    expect(b == a, isFalse);
  });
}

extension on pi.VideoTrack {
  VideoTrack toAppTrack() => VideoTrack(id: id, isSelected: isSelected);
}
