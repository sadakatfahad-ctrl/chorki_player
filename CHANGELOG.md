## 1.1.0

- **Breaking:** removed all fullscreen features:
  - `showChorkiFullscreen` and `ChorkiFullscreenPage`.
  - `enableFullscreen` on `ChorkiPlayer`.
  - `ChorkiPlayerIcons.fullscreen` and `ChorkiPlayerIcons.exitFullscreen`.
  - `ChorkiPlayerStrings.fullscreen` and `ChorkiPlayerStrings.exitFullscreen`.
  - `ChorkiPlayerBuilders.fullscreenButtonBuilder`.
  - `ChorkiPlayerTheme.fullscreenTransitionDuration`.
  - The `wakelock_plus` dependency.

## 1.0.1

- Add `seekBarBottomOffset` to `ChorkiPlayer`, `ChorkiPlayerSurface`, and
  `showChorkiFullscreen` (since removed) to raise the shorts-style seek bar
  above the bottom edge. Defaults to 0, so existing layouts are unchanged.

## 1.0.0

- **Breaking:** new theme, icon, string, and builder parameters on
  `ChorkiPlayer`, `ShortsSeekBar`, `PlayerGestureOverlay`, and
  `showChorkiFullscreen`. Pass `ChorkiPlayerTheme`, `ChorkiPlayerIcons`,
  `ChorkiPlayerStrings`, and `ChorkiPlayerBuilders` to customize the UI.
- **Breaking:** `ShortsSlot` has been removed. Build feed items with
  `ChorkiPlayerSurface` and `VideoPreloader` directly.
- **Breaking:** the seek bar's buffered range is now the contiguous range
  at the playhead, not the total buffered amount.
- Fix a stale-load race when the route changes while a previous load is
  still in flight.
- Fix the mid-playback error state so playback failures render the error
  view instead of freezing.
- Fix fullscreen orientation and wakelock leaks, and clarify controller
  ownership between the player and fullscreen route.
- Fix gesture callbacks firing during dispose.
- Fix `ShortsSeekBar` calling `play()` on a controller it is disposing.
- Fix an unhandled error when the preloader initialization times out.
- Raw error text is no longer shown to users; localized messages from
  `ChorkiPlayerStrings` are used instead.

## 0.3.0

- **Shorts-style scrub bar** (`ShortsSeekBar`): thin always-visible bar that
  expands with a thumb and time bubble while dragging, buffered-range tint,
  tap-to-seek, haptic ticks every 5s of scrubbed time, pause-while-scrubbing
  with auto-resume, and throttled live seeking.
- **Premium gesture stack** (`PlayerGestureOverlay`): double-tap sides to
  seek ±10s with ripple overlay, horizontal-drag scrubbing with a target-time
  HUD (one screen width ≈ 90s), long-press for 2× speed, and single-tap
  play/pause. Vertical drags remain free for `PageView` feeds.
- **Aspect-aware fullscreen** (`showChorkiFullscreen` / `ChorkiFullscreenPage`):
  landscape videos rotate to an edge-to-edge landscape experience; portrait
  videos fill the screen in immersive mode without rotating. Reuses the same
  video controller (no reload/re-buffer), keeps the screen awake via
  `wakelock_plus`, and restores orientation/system UI on exit.
- New `ChorkiPlayer` options: `showSeekBar`, `enableGestures`,
  `enableFullscreen`, `doubleTapSeek`, `longPressSpeed`.
- Extracted `ChorkiPlayerSurface` (video + gestures + seek bar + play/
  buffering indicators) for reuse in custom feeds and the fullscreen route.
- Buffering spinner during playback stalls; play badge hides while gesture
  HUDs are active.
- Performance: the player widget no longer rebuilds the whole subtree every
  playback tick (value-driven builders scoped to the surface).
- Exported `formatClock` / `formatDelta` time helpers.

## 0.2.0

- Bump `flutter_bloc` to `^9.1.1` (breaking dependency change for downstream apps on flutter_bloc 8.x).
- Fix the example iOS app for modern Xcode: raise `IPHONEOS_DEPLOYMENT_TARGET` to 15.0 across the Runner project and Pods, and pin `platform :ios, '15.0'` in the Podfile.

## 0.1.1

- Remove emojis from the README.

## 0.1.0

- Initial release.
- `ChorkiPlayer` widget: resolves a Chorki byte route and plays it with
  `video_player` (poster while buffering, tap to play/pause, error view with
  retry, looping and auto-play options).
- Clean-architecture data layer: Dio (HTTP/2) client, repository and usecase
  with `dartz` `Either` results and typed failures.
- `VideoPreloader` for initializing/disposing video controllers safely.
- `ShortsSlot` value type for feed-style integrations.
- GetIt dependency graph via `initChorkiPlayer()`.
