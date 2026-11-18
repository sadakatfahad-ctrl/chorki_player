// README excerpts (see usage.dart). Placeholders the snippets use are
// declared as parameters, so every region compiles as written.
// ignore_for_file: unused_local_variable, avoid_print

import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';

/// A feed item (placeholder for the README).
class ReadmeByte {
  const ReadmeByte(this.route);
  final String route;
}

/// A signed-in viewer (placeholder for the README).
class ReadmeUser {
  const ReadmeUser(this.id, this.tier);
  final String id;
  final String tier;
}

Widget playUrl(String vastOrVmapUrl) {
  // #region play-url
  final remote = ChorkiPlayer.url(
    'https://example.com/clip.m3u8',
    posterUrl: 'https://example.com/poster.jpg', // optional
    adTagUrl: vastOrVmapUrl, // optional, needs `ads:`
  );
  const bundled = ChorkiPlayer.url('asset:assets/videos/intro.mp4');
  // #endregion
  return Column(children: [remote, bundled]);
}

Widget sizeToVideo(String byteRoute) {
  return
  // #region size-to-video
  ListView(children: [ChorkiPlayer(route: byteRoute, sizeToVideo: true)])
  // #endregion
  ;
}

Widget uxOptions(String byteRoute) {
  return
  // #region ux-options
  ChorkiPlayer(
    route: byteRoute,
    showSeekBar: true, // shorts-style scrub bar (default)
    seekBarBottomOffset: 0, // lift the scrub bar N px above the bottom edge
    enableGestures: true, // full gesture stack (default)
    doubleTapSeek: const Duration(seconds: 10),
    longPressSpeed: 2.0,
  )
  // #endregion
  ;
}

Widget feed(
  List<ReadmeByte> bytes,
  int current,
  ChorkiPlayerController controller,
  void Function(VoidCallback) setState,
) {
  return
  // #region feed
  PageView.builder(
    scrollDirection: Axis.vertical,
    // Keeps the page above and below the current one built, so they preload.
    allowImplicitScrolling: true,
    itemCount: bytes.length,
    onPageChanged: (i) => setState(() => current = i),
    itemBuilder: (context, i) => ChorkiPlayer(
      route: bytes[i].route,
      controller: controller, // optional: one controller can serve the feed
      preload: i != current,
    ),
  )
  // #endregion
  ;
}

Future<Widget?> customFeed(String videoUrl) async {
  // #region custom-feed
  final preloader = ChorkiVideoPreloader();
  final controller = await preloader.load(Uri.parse(videoUrl));
  if (controller == null) return null; // failed or timed out
  // You own the controller: dispose it with
  // preloader.disposeQuietly(controller) when done.

  final surface = ChorkiPlayerSurface(
    controller: controller,
    onTogglePlayPause: () {
      /* ... */
    },
    overlayButton: IconButton(
      icon: const Icon(Icons.more_horiz),
      onPressed: () {
        /* ... */
      },
    ),
  );
  // #endregion
  return surface;
}

Widget theming(String byteRoute) {
  return
  // #region theming
  ChorkiPlayer(
    route: byteRoute,
    theme: const ChorkiPlayerTheme(
      seekBarPlayedColor: Colors.red,
      seekBarBufferedColor: Colors.grey,
      seekBarBaseColor: Colors.white12,
    ),
    icons: const ChorkiPlayerIcons(play: Icons.play_circle_outline),
    strings: const ChorkiPlayerStrings(
      retry: 'Try again',
      genericError: 'Could not play this video',
    ),
    builders: ChorkiPlayerBuilders(
      loadingBuilder: (context) => const Center(child: Text('Loading...')),
      errorViewBuilder: (context, error, onRetry) => TextButton(
        onPressed: onRetry,
        child: Text(error.message(const ChorkiPlayerStrings())),
      ),
    ),
  )
  // #endregion
  ;
}

Future<Widget> controllerUsage(
  BuildContext context,
  String byteRoute,
  String trackId,
) async {
  // #region controller
  final controller = ChorkiPlayerController(); // dispose() it yourself

  final player = ChorkiPlayer(
    route: byteRoute,
    controller: controller,
    mediaOptions: const ChorkiMediaOptions(
      httpHeaders: {'Authorization': 'Bearer <token>'},
      startPosition: Duration(seconds: 42), // resume
      backBuffer: Duration(seconds: 30), // Android
      allowBackgroundPlayback: false,
      keepScreenOn: true, // iOS
    ),
    showSettingsButton: true, // gear, top-right
    speedOptions: const [0.5, 1.0, 1.5, 2.0],
  );

  // Anywhere:
  await controller.seekForward(); // seekStep, default 10s
  await controller.setSpeed(1.5); // kept across reloads
  controller.toggleFit(); // fit <-> fill
  await controller.selectQuality(controller.videoTracks.value.first);
  await controller.selectQuality(null); // back to Auto
  await controller.selectAudioTrack(trackId);
  if (context.mounted) {
    await showChorkiSettings(context, controller); // open the sheet yourself
  }
  // #endregion
  return player;
}

Future<void> pip(ChorkiPlayerController controller) async {
  // #region pip
  await controller.enterPip(); // now
  await controller.setAutoPip(true); // when the user presses Home
  // #endregion
}

Widget ads(String byteRoute) {
  return
  // #region ads
  ChorkiPlayer(
    route: byteRoute,
    autoPlay: true,
    ads: ChorkiAdConfig(
      enabled: true,
      progressInterval: const Duration(milliseconds: 200),
      enablePreloading: true,
      loadTimeout: const Duration(seconds: 8),
      onAdEvent: (event) => debugPrint('IMA event: ${event.type}'),
      onAdError: (message) => debugPrint('Ad error: $message'),
    ),
  )
  // #endregion
  ;
}

Widget adsMarkers(String byteRoute) {
  return
  // #region ads-markers
  ChorkiPlayer(
    route: byteRoute,
    ads: const ChorkiAdConfig(),
    builders: ChorkiPlayerBuilders(
      seekBarBuilder: (context, state, onSeek) => LayoutBuilder(
        builder: (context, box) {
          final total = state.duration.inMilliseconds;
          final played = total == 0
              ? 0.0
              : state.position.inMilliseconds / total;
          return Stack(
            children: [
              LinearProgressIndicator(value: played),
              // One tick per mid-roll; played breaks are dimmed.
              for (final marker in state.adMarkers)
                Positioned(
                  left: marker.fraction * box.maxWidth - 2,
                  child: Container(
                    width: 4,
                    height: 8,
                    color: marker.played ? Colors.white38 : Colors.amber,
                  ),
                ),
            ],
          );
        },
      ),
    ),
  )
  // #endregion
  ;
}

Widget analytics(String route, ReadmeUser user) {
  // #region analytics
  // Once for the app.
  final matomo = MatomoAnalyticsSink(
    const MatomoConfig(
      url: 'https://analytics.example.com', // or .../matomo.php
      siteId: 3,
      // Custom Dimensions you created in Matomo → their ids.
      dimensionIds: {
        'contentId': 1,
        'category': 2,
        'seriesId': 3,
        'subscriptionTier': 4, // a user property, see below
      },
    ),
  );

  // When the viewer signs in / their plan is known.
  matomo.userId = user.id;
  matomo.setUserProperty('subscriptionTier', user.tier);

  final player = ChorkiPlayer(
    route: route,
    metadata: const ChorkiMediaMetadata(
      contentId: 'ep-1042',
      title: 'Episode 4',
      seriesId: 'show-77',
      category: 'drama',
      contentType: 'episode',
    ),
    analytics: ChorkiAnalyticsConfig(sinks: [matomo]),
  );
  // #endregion
  return player;
}

void diagnostics(void Function(Object, StackTrace, String) recordError) {
  // #region diagnostics
  // Errors the player recovers from internally (it never logs).
  ChorkiDiagnostics.onError = (error, stack, context) =>
      recordError(error, stack, context);
  // #endregion
}
