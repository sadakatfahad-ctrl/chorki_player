import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'fakes/fake_video_player_platform.dart';

void main() {
  late FakeVideoPlayerPlatform platform;
  late VideoPlayerController controller;

  setUp(() async {
    platform = FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    controller = await createTestController(platform);
  });

  tearDown(() async => controller.dispose());

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: child)),
    ),
  );

  test('settings fields have defaults and copyWith', () {
    const icons = ChorkiPlayerIcons();
    const strings = ChorkiPlayerStrings();
    expect(icons.settings, Icons.settings);
    expect(strings.auto, 'Auto');
    expect(strings.pictureInPicture, 'Picture-in-picture');
    final t = const ChorkiPlayerTheme().copyWith(
      settingsSelectedColor: Colors.green,
      settingsSheetBackgroundColor: Colors.black,
    );
    expect(t.settingsSelectedColor, Colors.green);
    expect(t.settingsSheetBackgroundColor, Colors.black);
    expect(t.settingsTextStyle, const ChorkiPlayerTheme().settingsTextStyle);
  });

  test('copyWith overrides only given fields', () {
    final t = const ChorkiPlayerTheme().copyWith(
      seekBarPlayedColor: Colors.red,
    );
    expect(t.seekBarPlayedColor, Colors.red);
    expect(
      t.seekBarBufferedColor,
      const ChorkiPlayerTheme().seekBarBufferedColor,
    );
  });

  testWidgets('seek bar uses distinct themed played and buffered colors', (
    tester,
  ) async {
    await pump(
      tester,
      ChorkiShortsSeekBar(
        controller: controller,
        theme: const ChorkiPlayerTheme(
          seekBarPlayedColor: Colors.red,
          seekBarBufferedColor: Colors.green,
        ),
      ),
    );
    platform.onlyPlayer.emitBuffered(const Duration(seconds: 80));
    await tester.pump();
    await tester.pump();

    Color colorOf(String key) =>
        tester.widget<ColoredBox>(find.byKey(Key(key))).color;

    expect(colorOf('chorki_seek_bar_played'), Colors.red);
    expect(colorOf('chorki_seek_bar_buffered'), Colors.green);

    // Regression: layers once collapsed to zero height and were invisible.
    final trackH = tester
        .getSize(find.byKey(const Key('chorki_seek_bar_track')))
        .height;
    for (final k in ['played', 'buffered']) {
      expect(
        tester.getSize(find.byKey(Key('chorki_seek_bar_$k'))).height,
        trackH,
      );
    }
  });

  testWidgets(
    'ChorkiPlayerSurface forwards seekBarPlayedColor to the painted played layer',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: ChorkiPlayerSurface(
                controller: controller,
                onTogglePlayPause: () {},
                theme: const ChorkiPlayerTheme(
                  seekBarPlayedColor: Colors.red,
                  seekBarBufferedColor: Colors.green,
                ),
              ),
            ),
          ),
        ),
      );
      platform.onlyPlayer.emitBuffered(const Duration(seconds: 80));
      await tester.pump();
      await tester.pump();

      Color colorOf(String key) =>
          tester.widget<ColoredBox>(find.byKey(Key(key))).color;

      expect(colorOf('chorki_seek_bar_played'), Colors.red);
      expect(colorOf('chorki_seek_bar_buffered'), Colors.green);
    },
  );

  testWidgets('seekBarBuilder replaces the default bar', (tester) async {
    await pump(
      tester,
      ChorkiShortsSeekBar(
        controller: controller,
        builders: ChorkiPlayerBuilders(
          seekBarBuilder: (context, state, onSeek) => const Text('custom-bar'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('custom-bar'), findsOneWidget);
    expect(find.byKey(const Key('chorki_seek_bar_played')), findsNothing);
  });

  testWidgets('surface shows a spinner while buffering, even when paused', (
    tester,
  ) async {
    await pump(
      tester,
      ChorkiPlayerSurface(controller: controller, onTogglePlayPause: () {}),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    platform.onlyPlayer.emitBufferingStart();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    platform.onlyPlayer.emitBufferingEnd();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('value equality', () {
    test('equal settings are equal and hash alike', () {
      expect(const ChorkiPlayerTheme(), const ChorkiPlayerTheme());
      expect(
        const ChorkiPlayerTheme().hashCode,
        const ChorkiPlayerTheme().hashCode,
      );
      // Not identical: built at runtime.
      final a = const ChorkiPlayerTheme().copyWith(spinnerSize: 30);
      final b = const ChorkiPlayerTheme().copyWith(spinnerSize: 30);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        const ChorkiPlayerIcons(play: Icons.play_arrow),
        const ChorkiPlayerIcons(play: Icons.play_arrow),
      );
      expect(
        const ChorkiPlayerIcons(play: Icons.play_arrow).hashCode,
        const ChorkiPlayerIcons().hashCode,
      );
      expect(
        ChorkiPlayerStrings(retry: 'Retry'.toUpperCase().toLowerCase()),
        const ChorkiPlayerStrings(retry: 'retry'),
      );
      expect(
        const ChorkiPlayerStrings(retry: 'r').hashCode,
        const ChorkiPlayerStrings(retry: 'r').hashCode,
      );
    });

    test('one changed field makes them differ', () {
      expect(
        const ChorkiPlayerTheme(),
        isNot(const ChorkiPlayerTheme(settingsSelectedColor: Colors.red)),
      );
      expect(
        const ChorkiPlayerTheme().copyWith(spinnerSize: 12),
        isNot(const ChorkiPlayerTheme()),
      );
      expect(
        const ChorkiPlayerIcons(),
        isNot(const ChorkiPlayerIcons(back: Icons.close)),
      );
      expect(
        const ChorkiPlayerStrings(),
        isNot(const ChorkiPlayerStrings(pictureInPicture: 'PiP')),
      );
    });
  });
}
