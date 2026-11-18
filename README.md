# chorki_player

[![pub package](https://img.shields.io/pub/v/chorki_player.svg)](https://pub.dev/packages/chorki_player)

A Flutter plugin that resolves a Chorki byte/short-video route and plays it
out of the box — with built-in data fetching over HTTP/2, poster-while-loading,
a shorts-style scrub bar, a premium gesture stack, error views with retry,
and safe video controller lifecycle handling.

## Features

- **Drop-in player widget** — give it a route, it plays the video.
- **Shorts-style scrub bar** — thin always-visible bar that expands with a
  thumb + time bubble while dragging, buffered-range tint, tap-to-seek,
  haptic ticks every 5s of scrubbed time, and pause-while-scrubbing.
- **Premium gesture stack** — double-tap the left/right half to seek ±10s
  (with ripple overlay), drag horizontally anywhere to scrub (full width =
  90s, live-preview with a target-time HUD), and long-press for 2× speed.
  Vertical drags stay free for `PageView` feeds.
- **Poster thumbnail** shown while the video buffers, plus a buffering
  spinner during playback stalls.
- **Looping & auto-play** options.
- **Graceful error handling** — connection failures render an error view
  with a retry button instead of crashing.
- **Clean architecture** — bloc + usecase + repository + Dio datasource,
  with typed `ChorkiPlayerError`s (see `CLAUDE.md` for the layering rules).
- **HTTP/2 networking** via Dio with sane timeouts.
- **`ChorkiVideoPreloader`** helper for building custom shorts/feeds experiences.
- **Preloading for feeds**: `preload: true` fetches and buffers a byte off
  screen without playing it, so the next swipe starts instantly.
- **Google IMA ads** — pre-, mid-, and post-roll ads from the reel's
  `data.ad_campaign` VMAP, with event and error callbacks.
- **Player controller**: `ChorkiPlayerController` lets you drive playback,
  quality, audio track, speed, fit, and picture-in-picture from outside the
  widget.
- **Settings sheet**: a gear button opens Quality (HLS/DASH renditions),
  Audio, Speed, Video size (fit/fill), and Picture-in-picture.
- **Media options**: custom HTTP headers, a start position to resume from,
  back-buffer size, background playback, and keep-screen-on.
- **Picture-in-picture (Android)**: enter PiP manually, or automatically
  when the user leaves the app.
- **Analytics**: detailed playback, QoE, ad and UX events, with a built-in
  Matomo sink (Media Analytics + Events + Custom Dimensions).

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  chorki_player: ^1.6.0
```

## Usage

<!-- excerpt: usage -->
```dart
import 'package:chorki_player/chorki_player.dart';
import 'package:flutter/material.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AspectRatio(
      aspectRatio: 9 / 16,
      child: ChorkiPlayer(
        route: 'https://your-chorki-endpoint.example.com/api/byte/1',
        autoPlay: true,
        looping: true,
      ),
    );
  }
}
```

The widget handles the whole lifecycle: it fetches the byte data, shows the
poster while buffering, plays the video, and disposes everything when it goes
away. If fetching or playback fails, users get an error view with a retry
button.

### Playing a URL directly

`ChorkiPlayer.url` skips the Chorki API and plays a video URL (MP4, HLS,
DASH…) with the same UI, ads and controller. An `asset:` URI plays a file
bundled with the app:

<!-- excerpt: play-url -->
```dart
final remote = ChorkiPlayer.url(
  'https://example.com/clip.m3u8',
  posterUrl: 'https://example.com/poster.jpg', // optional
  adTagUrl: vastOrVmapUrl, // optional, needs `ads:`
);
const bundled = ChorkiPlayer.url('asset:assets/videos/intro.mp4');
```

### Sizing

By default the player fills the box its parent gives it, so it needs bounded
constraints (`Expanded`, `SizedBox`, `AspectRatio`, a full-screen page). Any
video shape works inside that box: `ChorkiVideoFit.fit` letterboxes the whole
frame, `ChorkiVideoFit.fill` crops to cover.

To let the player take the video's own aspect ratio instead, for example in a
`Column` or `ListView`, turn on `sizeToVideo`. It needs a bounded width.
`placeholderAspectRatio` (default 16:9) is used until the video is loaded:

<!-- excerpt: size-to-video -->
```dart
ListView(children: [ChorkiPlayer(route: byteRoute, sizeToVideo: true)])
```

The aspect ratio is read once, when the video loads (`video_player` does not
report size changes mid-stream).

The player targets on-demand video. Live streams (no fixed duration) are not
supported: seeking gestures assume a known duration.

### Playback UX options

<!-- excerpt: ux-options -->
```dart
ChorkiPlayer(
  route: byteRoute,
  showSeekBar: true, // shorts-style scrub bar (default)
  seekBarBottomOffset: 0, // lift the scrub bar N px above the bottom edge
  enableGestures: true, // full gesture stack (default)
  doubleTapSeek: const Duration(seconds: 10),
  longPressSpeed: 2.0,
)
```

| Gesture            | Action                                    |
| ------------------ | ----------------------------------------- |
| Single tap         | Play / pause                              |
| Double tap (left)  | Seek back 10s with ripple overlay         |
| Double tap (right) | Seek forward 10s with ripple overlay      |
| Horizontal drag    | Scrub — one screen width ≈ 90 seconds     |
| Long press         | Hold 2× speed, releases restore 1×        |

### Preloading in a feed

In a Bytes feed, set `preload` on every page except the current one. A
preloading player fetches the route, initializes and buffers the video, and
shows its first frame, but does not play. When `preload` turns off, it plays
at once (if `autoPlay` is on). When it turns back on, the player pauses and
rewinds to the start, so the next visit plays it as a fresh view.

<!-- excerpt: feed -->
```dart
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
```

- A plain `PageView` builds only the current page, so nothing would preload.
  `allowImplicitScrolling: true` keeps one page on each side built.
- Preload at most one page on each side. Every preloaded player holds its own
  video decoder, and some Android devices allow only a few at a time.
- While preloading, the player shows no controls, requests no ads, and leaves
  `controller` unattached. So one `ChorkiPlayerController` can be shared by
  every page: it always drives the byte on screen.
- Ads start when the byte becomes active. With a pre-roll, the content waits
  for the ad as usual, and the pre-roll plays again when the user comes back.
- Players are created at most two at a time, the byte on screen first
  (`ChorkiVideoLoadScheduler`). A page you swipe past before its turn never creates
  a player, so fast swiping doesn't run out of decoders. To change the limit,
  call `ChorkiVideoLoadScheduler.configure(maxConcurrent: 3)` at startup.
- Transient failures (a network drop, a video that fails to initialize or
  errors mid-playback) are retried silently twice, after 1s and 3s, with the
  poster showing. A playback error resumes where it stopped. Only then does
  the byte on screen show the error view. A preloading byte never shows it:
  it retries when it becomes active.
- Resolved routes are cached for 5 minutes, so scrolling back to a byte
  doesn't fetch it again. A retry after a video failure skips the cache, in
  case the video URL went stale. A route request whose connection drops
  (for example a stale HTTP/2 connection) is retried twice right away.
- `onPageChanged` fires once a page is more than half on screen, so the new
  byte starts during the swipe.

### Reusable widgets for custom feeds

`ChorkiPlayerSurface`, `ChorkiShortsSeekBar`, and `ChorkiGestureOverlay` are all
exported and take a `VideoPlayerController` you own — combine them with
`ChorkiVideoPreloader` to build your own feed:

<!-- excerpt: custom-feed -->
```dart
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
```

`showControls: false` renders only the video, for example on a page that is
still preloading off screen.

## Customization

Pass a theme, icons, strings, or builders to `ChorkiPlayer`. Any field you
leave out keeps its default.

<!-- excerpt: theming -->
```dart
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
```

- `ChorkiPlayerTheme` sets colors, sizes, and text styles.
- `ChorkiPlayerIcons` replaces the built-in icons.
- `ChorkiPlayerStrings` localizes user-facing text.
- `ChorkiPlayerBuilders` fully replaces parts of the UI, such as the loading,
  error, or seek bar widgets.

## Controller, settings, and media options

<!-- excerpt: controller -->
```dart
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
```

The controller exposes `ValueListenable`s: `value` (position, duration,
buffering, and errors), `videoTracks`, `selectedVideoTrack` (null means Auto),
`audioTracks`, `selectedAudioTrackId`, `speed`, `fit`, `pipStatus`, and
`isAdPlaying`.

When you build a feed with `ChorkiPlayerSurface`, call
`controller.attach(videoController)` / `detach(...)` yourself and pass
`chorkiController:` to the surface. `ChorkiVideoPreloader.load(uri, options:)`
accepts the same `ChorkiMediaOptions`.

You can customize the settings UI through the theme
(`settingsSheetBackgroundColor`, `settingsTextStyle`, `settingsSelectedColor`,
`settingsButton*`), icons, strings (`quality`, `auto`, `audio`,
`normalSpeed`, `fit`, `fill`, `videoFit`, `pictureInPicture`), and builders
(`settingsButtonBuilder`, `settingsSheetBuilder`, `qualityLabelBuilder`).

### Picture-in-picture (Android only)

<!-- excerpt: pip -->
```dart
await controller.enterPip(); // now
await controller.setAutoPip(true); // when the user presses Home
```

PiP shrinks the whole app, not just the player. While
`controller.pipStatus.value == ChorkiPipStatus.enabled`, render only the player.
The player hides its own controls automatically. Enable PiP on your activity
in `AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity"
    android:supportsPictureInPicture="true"
    android:resizeableActivity="true" ... >
```

### Platform support

| Feature | Android | iOS |
|---|---|---|
| Quality selection (HLS/DASH) | ✓ | ✓ (HLS) |
| Audio track selection | ✓ | ✓ |
| Speed, fit/fill, headers, start position | ✓ | ✓ |
| Back-buffer size | ✓ | n/a |
| Keep screen on | default | ✓ |
| Picture-in-picture | ✓ | ✗ |
| DRM (Widevine / FairPlay) | ✗ | ✗ |
| Offline downloads | ✗ | ✗ |

The player is built on `video_player`, which has no DRM and no iOS PiP API.

## Android

Video streaming requires the internet permission in your app's
`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## Ads (Google IMA)

Ad UX: break positions are read from the campaign VMAP and drawn as ticks on the
seek bar (upcoming ticks use `theme.adMarkerColor`, played ones
`adMarkerPlayedColor`). During the 5 seconds before a break an "Ad starts in N"
pill appears above the seek bar; tapping it starts the ad immediately. Customize
with `ChorkiPlayerTheme.adMarker*` / `adCountdown*`,
`ChorkiPlayerStrings.adCountdown`, or replace the pill with
`ChorkiPlayerBuilders.adCountdownBuilder`. If the VMAP cannot be fetched, ads
still play but markers and the countdown are not shown.

Ads are opt-in. Pass a `ChorkiAdConfig` to `ChorkiPlayer` via `ads:`. The ad
campaign is not configured in Dart code. The reel API response can include
`data.ad_campaign`, an object with `id`, `title`, and `url`. The `url` is a
VMAP XML document that IMA loads directly, and the VMAP defines the pre-,
mid-, and post-roll breaks.

- **No campaign, no ads.** A reel without `data.ad_campaign` plays normally.
- **Break timing lives in the VMAP.** `ChorkiAdConfig` has no roll settings.
  To change where ads play, change the campaign's VMAP.
- While an ad plays, the content surface is hidden and the video is paused.
  Playback resumes when the ad break ends.

<!-- excerpt: ads -->
```dart
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
```

| `ChorkiAdConfig` field   | Default     | Purpose                                                    |
| ------------------------ | ----------- | ---------------------------------------------------------- |
| `enabled`                | `true`      | Turns ads on or off for this player                        |
| `progressInterval`       | `200 ms`    | How often content progress is reported to IMA (drives mid-roll timing) |
| `enablePreloading`       | `true`      | Preloads ad media for smoother breaks                      |
| `loadTimeout`            | `8 s`       | Shows and plays content if no ad has started by then (`null` disables) |
| `onAdEvent`              | `null`      | Called for each IMA `AdEvent`                              |
| `onAdError`              | `null`      | Called with a message when an ad fails to load or play     |

The seek bar marks each mid-roll. A custom seek bar gets the same marks as
`ChorkiSeekBarState.adMarkers` (`ChorkiAdMarker`: `id`, `fraction` 0..1 of
the content, `played`):

<!-- excerpt: ads-markers -->
```dart
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
```

### Platform setup checklist

- [ ] **Android**
  - [ ] `INTERNET` and `ACCESS_NETWORK_STATE` permissions in
        `android/app/src/main/AndroidManifest.xml`:

    ```xml
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    ```

  - [ ] Core library desugaring enabled in `android/app/build.gradle(.kts)`:

    ```groovy
    android {
        compileOptions {
            coreLibraryDesugaringEnabled true
        }
    }

    dependencies {
        coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.5'
    }
    ```

  - [ ] `minSdkVersion 24` or higher.
- [ ] **iOS**
  - [ ] Deployment target of 13.0 or higher, set in `ios/Podfile`
        (`platform :ios, '13.0'`) and in the Xcode project.

## Errors, diagnostics and network settings

Failures are typed: `ChorkiPlayerError` has a `code` (`noInternet`,
`timeout`, `unauthorized`, `forbidden`, `notFound`, `badRequest`, `server`,
`malformedResponse`, `noVideoUrl`, `videoLoad`, `playback`, `unknown`), a
`stage` (`route`, `load`, `playback`) and `isTransient`. Transient errors are
retried silently twice before the error view shows; permanent ones (a 404, a
byte without a video) show at once. Viewers can always tap Retry.
`ChorkiPlayerBuilders.errorViewBuilder` receives the error, and
`error.message(strings)` gives the localized text.

The SDK never logs. Errors it recovers from internally (a quality switch the
platform rejected, a failed IMA call, an analytics sink that threw) go to
`ChorkiDiagnostics.onError`:

<!-- excerpt: diagnostics -->
```dart
// Errors the player recovers from internally (it never logs).
ChorkiDiagnostics.onError = (error, stack, context) =>
    recordError(error, stack, context);
```

Route lookups use their own HTTP client. Set headers (for example an auth
token that changes) and timeouts once at startup with
`ChorkiPlayer.configure(network: ChorkiNetworkConfig(headersProvider: ...))`.
VMAP ad requests never get these headers.

## Analytics (Matomo)

The player reports detailed viewing analytics: what was watched (impressions,
plays, pauses, seeks, watched time and segments, quartiles, completions,
loops), quality of experience (startup time, queue wait, rebuffering,
errors, retries, quality switches), IMA ads (breaks, starts, quartiles,
skips, clicks, errors) and player UI (speed, long-press boost, audio track,
fit, PiP, volume, settings).

Events go to one or more **sinks**. `MatomoAnalyticsSink` is built in; you can
add your own (Firebase, your API) by implementing `ChorkiAnalyticsSink`.

<!-- excerpt: analytics -->
```dart
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
```

For a feed, put the config on the shared controller
(`ChorkiPlayerController(analytics: ...)`) and give every page its own
`metadata` (`feedIndex` helps). Only the page on screen reports: a preloading
page sends nothing; swiping away ends its session (`sessionEnd`, reason
`swipedAway`) and the next page's session starts.

### What is sent to Matomo

- **Media Analytics** (premium plugin): an `impression` (`ma_st=0`) when an
  item is shown, then a heartbeat every 10 s while playing and on pause, seek,
  completion and session end, with `ma_id` (one per view), `ma_ti`, `ma_re`,
  `ma_mt=video`, `ma_pn`, `ma_st` (seconds actually played), `ma_ps`, `ma_le`,
  `ma_ttp`, `ma_w`/`ma_h` and `ma_se` (newly watched 5 s segments).
- **Events** for everything else, with categories `Video`, `Video QoE`,
  `Video Ads` and `Video Player`, e.g. `Video QoE / rebuffer / <title> / 1.5`.
- Every request carries `ca=1` (never a page view), `cdt` (the event time, so
  queued requests keep their time), the visitor `_id`, `uid` and your mapped
  `dimensionN` values.
- Requests are sent in bulk (`POST matomo.php`), retried with backoff while
  offline and flushed when the app goes to the background. Pass a
  `ChorkiAnalyticsStorage` (`MatomoConfig.storage`) backed by e.g.
  `shared_preferences` to keep the visitor id and unsent requests across
  launches; the default keeps them in memory.

Without the Media Analytics plugin, set `mediaAnalytics: false`: impressions
are then sent as events too. Set `ChorkiAnalyticsConfig.consentGranted` to
false until the viewer agrees; nothing is tracked, reported or buffered
meanwhile. Revoking it ends the current view and clears the Matomo queue
(`ChorkiAnalyticsSink.onConsentRevoked`).

### Events and their data

Each event's `data` keys, generated from `ChorkiAnalyticsSchema` (`?` means
optional; use the `ChorkiAnalyticsKeys` constants in your own sinks). Ad
events also carry the *ad context* (`breakIndex`, `adCampaignId`?,
`adCampaignTitle`?) and, when IMA provides them, the ad details (`adId`,
`adTitle`, `adSystem`, `advertiser`, `adDurationMs`, `skippable`,
`podPosition`, `podTotal`).

<!-- analytics-schema:start (generated by test/guardrails) -->
| Event | Category | Data keys |
|---|---|---|
| `impression` | playback | `loopCount`? |
| `play` | playback | `timeToPlayMs`, `loopCount`? |
| `pause` | playback | – |
| `resume` | playback | – |
| `seek` | playback | `fromMs`, `toMs`, `source` |
| `heartbeat` | playback | `trigger`, `newSegments` |
| `quartile` | playback | `percent` |
| `complete` | playback | – |
| `loop` | playback | `loopCount` |
| `sessionEnd` | playback | `reason`, `dwellMs`, `watchedPercent`, `maxPositionMs`, `rebufferCount`, `rebufferMs`, `pauseCount`, `seekCount`, `loopCount`, `errorCount` |
| `loadStart` | qoe | – |
| `firstFrame` | qoe | `startupMs`, `queueWaitMs`?, `initMs`?, `preloaded` |
| `bufferStart` | qoe | `afterSeek` |
| `bufferEnd` | qoe | `durationMs` |
| `error` | qoe | `code`, `stage`, `transient`, `willRetry`, `statusCode`?, `detail`? |
| `retry` | qoe | `attempt`, `auto` |
| `qualityChange` | qoe | `fromHeight`?, `toHeight`?, `bitrate`?, `label`?, `auto` |
| `abandon` | qoe | `waitedMs`, `reason`, `abandonStage`, `errorCount` |
| `adBreakStart` | ad | `breakKind`, *ad context* |
| `adStart` | ad | *ad context* |
| `adQuartile` | ad | `percent`, *ad context* |
| `adComplete` | ad | *ad context* |
| `adSkip` | ad | *ad context* |
| `adClick` | ad | *ad context* |
| `adPause` | ad | *ad context* |
| `adResume` | ad | *ad context* |
| `adError` | ad | `message`, *ad context* |
| `adBreakEnd` | ad | `durationMs`, `interrupted`?, *ad context* |
| `speedChange` | ux | `from`, `to` |
| `speedBoostStart` | ux | `speed` |
| `speedBoostEnd` | ux | `durationMs` |
| `audioTrackChange` | ux | `fromTrack`?, `toTrack` |
| `fitChange` | ux | `fit` |
| `pipChange` | ux | `status` |
| `volumeChange` | ux | `from`, `to`, `muted` |
| `settingsOpen` | ux | – |
<!-- analytics-schema:end -->

### Inside the Chorki app

The app already runs `matomo_tracker` (screen views) and has Matomo reports
built on its own names. To keep one visitor and the same reports:

```dart
final matomo = MatomoAnalyticsSink(
  MatomoConfig(
    url: settings.analytics_matomo_url!,
    siteId: int.parse(settings.analytics_matomo_site_id!),
    // Same visitor as the app's screen views.
    visitorIdProvider: () => MatomoTracker.instance.visitor.id,
    // MediaVideo / play / pause / finished, e_v = position.
    naming: MatomoNaming.chorkiLegacy,
    playerName: 'ShortsPlayer',
    // dimension1 user id, 2 subscription, 3 app version, 4/5 cast output.
    dimensionIds: MatomoConfig.chorkiAppDimensions,
    mediaSize: MatomoMediaSize.viewport, // ma_w/ma_h = screen, as the app does
  ),
);
matomo
  ..userId = user.id
  ..setUserProperty('userId', user.id)
  ..setUserProperty('subscription', subscribed ? 'Subscribed' : 'Non-Subscribed')
  ..setUserProperty('appVersion', appVersion);

ChorkiPlayer(
  route: byte.routeUri,
  metadata: ChorkiMediaMetadata(
    contentId: byte.id,
    title: byte.title,
    pageUrl: '$frontendUrl${byte.routeUri}',
    contentType: 'byte',
  ),
  analytics: ChorkiAnalyticsConfig(sinks: [matomo]),
);
```

Viewers who leave before the first frame are reported as `abandon`
("exit before video start"), with how long they waited and whether the video
had loaded.

Watched time only grows while the video really plays: not while paused,
buffering, scrubbing or during an ad. Each loop of a looping byte counts as a
new play (`newSessionOnLoop`, default true).

## Example

See the [`example/`](example/) app for a complete runnable sample. It is a
test catalog for video shapes: Chorki API routes, bundled test patterns (odd
ratios, a rotated clip, anamorphic pixels), public MP4/HLS streams, and
Wikimedia Commons clips from 32:9 down to 28 pixels wide. Each video can be
shown full screen, in a 16:9 or 9:16 box, or with `sizeToVideo` in a list.

## License

MIT — see [LICENSE](LICENSE)
