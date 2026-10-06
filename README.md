# chorki_player

[![pub package](https://img.shields.io/pub/v/chorki_player.svg)](https://pub.dev/packages/chorki_player)

A Flutter plugin that resolves a Chorki byte/short-video route and plays it
out of the box — with built-in data fetching over HTTP/2, poster-while-loading,
tap-to-play/pause, error views with retry, and safe video controller
lifecycle handling.

## Features

- **Drop-in player widget** — give it a route, it plays the video.
- **Poster thumbnail** shown while the video buffers.
- **Looping & auto-play** options.
- **Graceful error handling** — connection failures render an error view
  with a retry button instead of crashing.
- **Clean architecture** — bloc + usecase + repository + Dio datasource,
  with `Either<Failure, ByteDataEntity>` results.
- **HTTP/2 networking** via Dio with sane timeouts.
- **`VideoPreloader`** and **`ShortsSlot`** helpers for building custom
  shorts/feeds experiences.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  chorki_player: ^0.1.0
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

### Building your own feed

Use `VideoPreloader` to initialize controllers without leaking them, and
`ShortsSlot` to model the state of each item in a shorts feed:

```dart
final preloader = VideoPreloader();
final controller = await preloader.load(Uri.parse(videoUrl));
// On success you own the controller — dispose it with
// preloader.disposeQuietly(controller) when done.
```

## Android

Video streaming requires the internet permission in your app's
`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

## Example

See the [`example/`](example/) app for a complete runnable sample.

## License

MIT — see [LICENSE](LICENSE).
