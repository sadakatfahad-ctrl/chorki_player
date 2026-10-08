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

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  chorki_player: ^1.1.0
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

## Example

See the [`example/`](example/) app for a complete runnable sample.

## License

MIT — see [LICENSE](LICENSE)
