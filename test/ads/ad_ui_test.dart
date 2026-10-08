import 'package:chorki_player/chorki_player.dart';
import 'package:chorki_player/src/ads/chorki_ad_state.dart';
import 'package:chorki_player/src/presentation/widgets/ad_countdown_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../fakes/fake_video_player_platform.dart';

bool _isAdMarkerKey(Widget w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('chorki_ad_marker_');

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

  Future<void> pumpIn(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 400, child: child)),
      ),
    ),
  );

  group('AdCountdownPill', () {
    testWidgets('hidden when seconds is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCountdownPill(seconds: null, onStartNow: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('chorki_ad_countdown')), findsNothing);
      expect(find.textContaining('Ad starts in'), findsNothing);
    });

    testWidgets('shows default text and updates 3 -> 2', (tester) async {
      Future<void> pumpSeconds(int? s) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdCountdownPill(seconds: s, onStartNow: () {}),
          ),
        ),
      );

      await pumpSeconds(3);
      await tester.pump();
      expect(find.byKey(const Key('chorki_ad_countdown')), findsOneWidget);
      expect(find.text('Ad starts in 3s'), findsOneWidget);

      await pumpSeconds(2);
      await tester.pump();
      expect(find.text('Ad starts in 2s'), findsOneWidget);
      expect(find.text('Ad starts in 3s'), findsNothing);
    });

    testWidgets('tap calls onStartNow exactly once', (tester) async {
      var taps = 0;
      await pumpIn(
        tester,
        AdCountdownPill(seconds: 3, onStartNow: () => taps++),
      );
      await tester.tap(find.text('Ad starts in 3s'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('null onStartNow does not crash on tap', (tester) async {
      await pumpIn(tester, const AdCountdownPill(seconds: 3, onStartNow: null));
      await tester.tap(find.text('Ad starts in 3s'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Ad starts in 3s'), findsOneWidget);
    });

    testWidgets('custom strings.adCountdown is used', (tester) async {
      await pumpIn(
        tester,
        AdCountdownPill(
          seconds: 4,
          onStartNow: () {},
          strings: ChorkiPlayerStrings(adCountdown: (s) => 'Ad in $s seconds'),
        ),
      );
      expect(find.text('Ad in 4 seconds'), findsOneWidget);
      expect(find.text('Ad starts in 4s'), findsNothing);
    });

    testWidgets('theme colors are applied to background and accent dot', (
      tester,
    ) async {
      const theme = ChorkiPlayerTheme(
        adCountdownBackgroundColor: Color(0xFF112233),
        adCountdownAccentColor: Color(0xFF445566),
        adCountdownTextStyle: TextStyle(color: Color(0xFF778899)),
      );
      await pumpIn(
        tester,
        AdCountdownPill(seconds: 3, onStartNow: () {}, theme: theme),
      );

      final pill = find.byType(AdCountdownPill);
      final material = tester.widget<Material>(
        find.descendant(of: pill, matching: find.byType(Material)).first,
      );
      expect(material.color, const Color(0xFF112233));

      final dots = tester
          .widgetList<Container>(
            find.descendant(of: pill, matching: find.byType(Container)),
          )
          .where((c) => c.decoration is BoxDecoration)
          .map((c) => (c.decoration as BoxDecoration).color);
      expect(dots, contains(const Color(0xFF445566)));

      final text = tester.widget<Text>(find.text('Ad starts in 3s'));
      expect(text.style?.color, const Color(0xFF778899));
    });

    testWidgets(
      'builders.adCountdownBuilder replaces default and gets seconds + '
      'working startNow',
      (tester) async {
        int? seenSeconds;
        VoidCallback? seenStartNow;
        var defaultStartNowCalls = 0;
        await pumpIn(
          tester,
          AdCountdownPill(
            seconds: 3,
            onStartNow: () => defaultStartNowCalls++,
            builders: ChorkiPlayerBuilders(
              adCountdownBuilder: (context, s, startNow) {
                seenSeconds = s;
                seenStartNow = startNow;
                return TextButton(
                  onPressed: startNow,
                  child: Text('custom $s'),
                );
              },
            ),
          ),
        );

        expect(find.text('Ad starts in 3s'), findsNothing);
        expect(find.text('custom 3'), findsOneWidget);
        expect(seenSeconds, 3);
        expect(seenStartNow, isNotNull);

        await tester.tap(find.text('custom 3'));
        await tester.pump();
        expect(defaultStartNowCalls, 1);
      },
    );

    testWidgets('semantics label contains the countdown text', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpIn(tester, AdCountdownPill(seconds: 3, onStartNow: () {}));
      expect(find.bySemanticsLabel(RegExp('Ad starts in 3s')), findsOneWidget);
      handle.dispose();
    });
  });

  group('ShortsSeekBar ad markers', () {
    Finder markerFinders() => find.byWidgetPredicate(_isAdMarkerKey);

    Future<void> pumpBar(
      WidgetTester tester, {
      List<ChorkiAdMarker>? markers,
      ChorkiPlayerTheme theme = const ChorkiPlayerTheme(),
    }) => pumpIn(
      tester,
      ShortsSeekBar(controller: controller, adMarkers: markers, theme: theme),
    );

    testWidgets('explicit adMarkers render one keyed widget per marker', (
      tester,
    ) async {
      await pumpBar(
        tester,
        markers: const [
          ChorkiAdMarker(id: 'a', fraction: 0.2, played: false),
          ChorkiAdMarker(id: 'b', fraction: 0.6, played: true),
        ],
      );
      await tester.pump();
      expect(markerFinders(), findsNWidgets(2));
      expect(find.byKey(const Key('chorki_ad_marker_a')), findsOneWidget);
      expect(find.byKey(const Key('chorki_ad_marker_b')), findsOneWidget);
    });

    testWidgets('marker x-position matches fraction of the track', (
      tester,
    ) async {
      const fractions = [0.0, 0.25, 0.5, 0.9, 1.0];
      await pumpBar(
        tester,
        markers: [
          for (var i = 0; i < fractions.length; i++)
            ChorkiAdMarker(id: 'f$i', fraction: fractions[i], played: false),
        ],
      );
      await tester.pump();

      final track = tester.getRect(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      for (var i = 0; i < fractions.length; i++) {
        final center = tester.getCenter(
          find.byKey(Key('chorki_ad_marker_f$i')),
        );
        expect(
          center.dx,
          closeTo(track.left + fractions[i] * track.width, 0.5),
          reason: 'fraction ${fractions[i]}',
        );
      }
    });

    testWidgets('marker colors use adMarkerColor vs adMarkerPlayedColor', (
      tester,
    ) async {
      const theme = ChorkiPlayerTheme(
        adMarkerColor: Color(0xFF0000FF),
        adMarkerPlayedColor: Color(0xFF00FF00),
      );
      await pumpBar(
        tester,
        theme: theme,
        markers: const [
          ChorkiAdMarker(id: 'up', fraction: 0.3, played: false),
          ChorkiAdMarker(id: 'done', fraction: 0.7, played: true),
        ],
      );
      await tester.pump();

      Color colorOf(String id) {
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byKey(Key('chorki_ad_marker_$id')),
            matching: find.byType(Container),
          ),
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(colorOf('up'), const Color(0xFF0000FF));
      expect(colorOf('done'), const Color(0xFF00FF00));
    });

    testWidgets('out-of-range fractions clamp within the bar', (tester) async {
      await pumpBar(
        tester,
        markers: const [
          ChorkiAdMarker(id: 'low', fraction: -1, played: false),
          ChorkiAdMarker(id: 'high', fraction: 2, played: false),
        ],
      );
      await tester.pump();

      final track = tester.getRect(
        find.byKey(const Key('chorki_seek_bar_track')),
      );
      final low = tester.getCenter(
        find.byKey(const Key('chorki_ad_marker_low')),
      );
      final high = tester.getCenter(
        find.byKey(const Key('chorki_ad_marker_high')),
      );
      expect(low.dx, closeTo(track.left, 0.5));
      expect(high.dx, closeTo(track.right, 0.5));
    });

    testWidgets('empty adMarkers renders no marker widgets', (tester) async {
      await pumpBar(tester, markers: const []);
      await tester.pump();
      expect(markerFinders(), findsNothing);
      expect(find.byKey(const Key('chorki_seek_bar_track')), findsOneWidget);
    });

    testWidgets('markers are read from ChorkiAdScope when adMarkers is null', (
      tester,
    ) async {
      final state = ChorkiAdState();
      state.update(
        markers: const [ChorkiAdMarker(id: 's1', fraction: 0.4, played: false)],
        countdownSeconds: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: ChorkiAdScope(
                  state: state,
                  child: ShortsSeekBar(controller: controller),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('chorki_ad_marker_s1')), findsOneWidget);

      state.update(
        markers: const [
          ChorkiAdMarker(id: 's2', fraction: 0.1, played: false),
          ChorkiAdMarker(id: 's3', fraction: 0.8, played: true),
        ],
        countdownSeconds: null,
      );
      await tester.pump();
      expect(find.byKey(const Key('chorki_ad_marker_s1')), findsNothing);
      expect(find.byKey(const Key('chorki_ad_marker_s2')), findsOneWidget);
      expect(find.byKey(const Key('chorki_ad_marker_s3')), findsOneWidget);
    });

    testWidgets('explicit adMarkers take precedence over ChorkiAdScope', (
      tester,
    ) async {
      final state = ChorkiAdState();
      state.update(
        markers: const [
          ChorkiAdMarker(id: 'scoped', fraction: 0.4, played: false),
        ],
        countdownSeconds: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: ChorkiAdScope(
                  state: state,
                  child: ShortsSeekBar(
                    controller: controller,
                    adMarkers: const [
                      ChorkiAdMarker(
                        id: 'explicit',
                        fraction: 0.5,
                        played: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('chorki_ad_marker_explicit')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('chorki_ad_marker_scoped')), findsNothing);
    });

    testWidgets('markers do not intercept taps; tap still seeks', (
      tester,
    ) async {
      await pumpBar(
        tester,
        markers: const [
          ChorkiAdMarker(id: 'tap', fraction: 0.5, played: false),
        ],
      );
      await tester.pump();

      final markerCenter = tester.getCenter(
        find.byKey(const Key('chorki_ad_marker_tap')),
      );
      platform.resetLog();
      await tester.tapAt(markerCenter);
      await tester.pump();

      expect(platform.seekCalls, isNotEmpty);
      final target = platform.seekCalls.last.$2;
      final duration = controller.value.duration;
      expect(
        (target.inMilliseconds - duration.inMilliseconds / 2).abs(),
        lessThan(1000),
      );
    });

    testWidgets('theme adMarkerWidth and adMarkerHeight are respected', (
      tester,
    ) async {
      await pumpBar(
        tester,
        theme: const ChorkiPlayerTheme(adMarkerWidth: 6, adMarkerHeight: 12),
        markers: const [
          ChorkiAdMarker(id: 'sized', fraction: 0.5, played: false),
        ],
      );
      await tester.pump();

      final size = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('chorki_ad_marker_sized')),
          matching: find.byType(Container),
        ),
      );
      expect(size.width, 6);
      expect(size.height, 12);
    });
  });

  group('ChorkiPlayerSurface with ChorkiAdScope', () {
    const pillKey = Key('chorki_ad_countdown_pill');

    Future<void> pumpSurface(WidgetTester tester, {ChorkiAdState? state}) {
      final surface = ChorkiPlayerSurface(
        controller: controller,
        onTogglePlayPause: () {},
      );
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: state == null
                  ? surface
                  : ChorkiAdScope(state: state, child: surface),
            ),
          ),
        ),
      );
    }

    testWidgets('pill visible when countdownSeconds set, gone when null', (
      tester,
    ) async {
      final state = ChorkiAdState();
      await pumpSurface(tester, state: state);
      await tester.pump();
      expect(find.byKey(pillKey), findsOneWidget);
      expect(find.byKey(const Key('chorki_ad_countdown')), findsNothing);

      state.update(markers: const [], countdownSeconds: 4);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ad starts in 4s'), findsOneWidget);

      state.update(markers: const [], countdownSeconds: null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ad starts in 4s'), findsNothing);
      expect(find.byKey(const Key('chorki_ad_countdown')), findsNothing);
    });

    testWidgets('tapping pill invokes state.startNow', (tester) async {
      final state = ChorkiAdState();
      var started = 0;
      state.startNow = () => started++;
      state.update(markers: const [], countdownSeconds: 2);

      await pumpSurface(tester, state: state);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Ad starts in 2s'));
      await tester.pump();
      expect(started, 1);
    });

    testWidgets('no pill widget when there is no ChorkiAdScope', (
      tester,
    ) async {
      await pumpSurface(tester);
      await tester.pump();
      expect(find.byKey(pillKey), findsNothing);
      expect(find.byType(AdCountdownPill), findsNothing);
      expect(find.textContaining('Ad starts in'), findsNothing);
    });
  });
}
