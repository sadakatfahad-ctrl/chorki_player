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
  with `Either<Failure, ByteDataEntity>` results.
- **HTTP/2 networking** via Dio with sane timeouts.
- **`VideoPreloader`** helper for building custom shorts/feeds experiences.
- **Google IMA ads** — pre-, mid-, and post-roll ads from the reel's
  `data.ad_campaign` VMAP, with event and error callbacks.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  chorki_player: ^1.2.0
```

## Usage

```dart
import 'package:chorki_player/chorki_player.dart';

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

### Playback UX options

```dart
ChorkiPlayer(
  route: byteRoute,
  showSeekBar: true,        // shorts-style scrub bar (default)
  seekBarBottomOffset: 0,   // lift the scrub bar N px above the bottom edge (default 0)
  enableGestures: true,     // full gesture stack (default)
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

### Reusable widgets for custom feeds

`ChorkiPlayerSurface`, `ShortsSeekBar`, and `PlayerGestureOverlay` are all
exported and take a `VideoPlayerController` you own — combine them with
`VideoPreloader` to build your own feed:

```dart
final preloader = VideoPreloader();
final controller = await preloader.load(Uri.parse(videoUrl));
// On success you own the controller — dispose it with
// preloader.disposeQuietly(controller) when done.

ChorkiPlayerSurface(
  controller: controller,
  onTogglePlayPause: () { /* ... */ },
  overlayButton: IconButton(
    icon: const Icon(Icons.more_horiz),
    onPressed: () { /* ... */ },
  ),
);
```

## Customization

Pass a theme, icons, strings, or builders to `ChorkiPlayer`. Any field you
leave out keeps its default.

```dart
ChorkiPlayer(
  route: byteRoute,
  theme: const ChorkiPlayerTheme(
    seekBarPlayedColor: Colors.red,
    seekBarBufferedColor: Colors.grey,
    seekBarBaseColor: Colors.white12,
  ),
  icons: const ChorkiPlayerIcons(
    play: Icons.play_circle_outline,
  ),
  strings: const ChorkiPlayerStrings(
    retry: 'Try again',
    genericError: 'Could not play this video',
  ),
  builders: ChorkiPlayerBuilders(
    loadingBuilder: (context) => const Center(child: Text('Loading...')),
  ),
)
```

- `ChorkiPlayerTheme` sets colors, sizes, and text styles.
- `ChorkiPlayerIcons` replaces the built-in icons.
- `ChorkiPlayerStrings` localizes user-facing text.
- `ChorkiPlayerBuilders` fully replaces parts of the UI, such as the loading,
  error, or seek bar widgets.

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

```dart
import 'package:flutter/foundation.dart';
import 'package:chorki_player/chorki_player.dart';

ChorkiPlayer(
  route: byteRoute,
  autoPlay: true,
  ads: ChorkiAdConfig(
    enabled: true,
    progressInterval: const Duration(milliseconds: 200),
    enablePreloading: true,
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
| `onAdEvent`              | `null`      | Called for each IMA `AdEvent`                              |
| `onAdError`              | `null`      | Called with a message when an ad fails to load or play     |

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

## Example

See the [`example/`](example/) app for a complete runnable sample.

## License

MIT — see [LICENSE](LICENSE)
