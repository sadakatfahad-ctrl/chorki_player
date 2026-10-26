# Chorki Player example

A test catalog for checking how the player handles different video shapes.

Run it with `flutter run` from this folder. Pick a video, then switch the
layout at the top of the player page:

- **Fill**: the player fills the screen.
- **16:9 box** / **9:16 box**: the player sits in a fixed box (white outline).
- **Size to video**: `ChorkiPlayer(sizeToVideo: true)` inside a `ListView`.

The line under the switch shows the expected shape next to the size the
platform reports. The FIT/FILL button toggles letterbox and crop.

## Sources

| Group | What it covers |
| --- | --- |
| Chorki API | The staging routes, with ads and a 5 s start position. |
| Generated test patterns | Bundled in `assets/videos/`: 1:3, 3:1, 5:7, 13:5, 17:11, 2.37:1, a portrait clip stored sideways with a rotation flag, and an anamorphic 16:9 clip. Each has a red border (cropping), a circle (must stay round) and a TOP marker (rotation). |
| Public test streams | Flutter's sample MP4, Apple BipBop HLS (4:3 and multi-quality 16:9), Mux HLS, Tears of Steel HLS (2.24:1, multi-quality) and MOV (2.4:1). |
| Wikimedia Commons (360p MOV) | Real clips in 9:16, 1:1, 4:5, 9:19.5, 32:9, 4:1, about 12:1 and about 1:12. MPEG-4 Part 2, which iOS and Android both support. |
| Wikimedia Commons (WebM) | The same clips at up to 1080p. **Android only**: iOS can't decode WebM. |

Not yet played on a device. Check these first: the rotated and anamorphic
patterns (does TOP stay up, does the circle stay round?), and the tiny
Commons copies (28×360, 640×54, 640×52), which may be below some hardware
decoders' minimum size.

The catalog lives in `lib/test_videos.dart`; add an entry there to test
another video. Commons clips are CC or public domain (credit shown on the
player page). Public servers can change or rate-limit: Wikimedia answers
HTTP 429 to heavy automated traffic.

## Regenerating the test patterns

```sh
brew install ffmpeg        # ffmpeg 7+ (for -display_rotation)
pip install pillow
python3 tool/generate_test_patterns.py
```
