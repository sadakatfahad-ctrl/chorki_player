## 1.4.0

- New `ChorkiPlayer.url(videoUrl, posterUrl:, adTagUrl:)`: plays a URL
  directly, without a Chorki API route. `VideoPreloader` (and so
  `ChorkiPlayer.url`) accepts `asset:` URIs for bundled files.
- Fix: when the platform never finished creating the player, the load hung
  forever and `initTimeout` never fired; the player now shows its error view.
- The example app is now a test catalog for video shapes (see
  `example/README.md`).
- New `ChorkiPlayer.sizeToVideo` (opt-in): the player takes the video's
  aspect ratio instead of filling its parent, so it works in a `Column` or
  `ListView`. `placeholderAspectRatio` (default 16:9) applies until the video
  loads.
- New `ChorkiAdConfig.loadTimeout` (default 8 s, `null` disables): if IMA
  never starts an ad or reports an error, content is shown and played and
  `onAdError` receives `Ad load timed out`.
- Fix: a slow response for a previous route could replace the current one and
  play the wrong video after a fast route change.
- Fix: the error view overflowed in very short players (e.g. a 12.5:1 video
  with `sizeToVideo`); below 160 px it now shows one scaled-down line with an
  icon-only retry button.
- Fix: the "Video failed to play" error view now has a retry button. A custom
  `errorBuilder` now receives a non-null `onRetry` for playback failures too.
- Fix: removing the gesture overlay during a long-press (ad break, controller
  swap) left the video stuck at the boosted speed.
- Fix: entering PiP mid-scrub left the video paused; the controls now stay
  mounted offstage in PiP so gestures finish normally.
- Fix: `ChorkiPlayerSurface` given a controller that was not yet initialized
  stayed black; it now picks up the video size when initialization finishes.
- The poster now uses the same fit as the video, so there is no visible jump
  when playback starts.
- The package never writes to the console. Fire-and-forget futures (playback,
  IMA ads manager, ad progress timer, PiP delegate, video load) are now
  guarded so failures cannot surface as unhandled exceptions.
- `avoid_print` is an analyzer error, and `test/no_logging_test.dart` fails
  if `lib/` gains any print/debugPrint/developer.log usage. Native logs from
  the underlying plugins (ExoPlayer/AVPlayer, IMA SDK) are outside the
  package's control.

## 1.3.0

- Fix: tapping the center play badge while paused did nothing; the badge now
  lets taps through to the gesture layer so playback resumes.
- **Requires Flutter 3.44 / Dart 3.12** (`video_player` ^2.14.1).
- New `ChorkiPlayerController`: play, pause, and seek (forward/back by
  `seekStep`); speed (kept across reloads); fit/fill; quality selection
  (`selectQuality`, where null means Auto); audio track selection; Android
  picture-in-picture (`enterPip`, `setAutoPip`); and `retry`. It exposes
  `ValueListenable`s for the video value, tracks, speed, fit, `pipStatus`,
  and `isAdPlaying`. Pass it with `ChorkiPlayer(controller:)`.
- New settings bottom sheet (`showChorkiSettings`, `ChorkiSettingsSheet`),
  opened by a gear button on the player (`showSettingsButton`). It covers
  Quality, Audio, Speed (`speedOptions`), Video size, and Picture-in-picture.
- New `ChorkiMediaOptions` (`ChorkiPlayer.mediaOptions`,
  `VideoPreloader.load(options:)`): `httpHeaders`, `startPosition`,
  `backBuffer`, `allowBackgroundPlayback`, `mixWithOthers`, `keepScreenOn`,
  and `viewType`.
- `ChorkiPlayerSurface`: new `chorkiController`, `showSettingsButton`,
  `speedOptions`, and `fit` parameters. It renders the video only while in PiP.
- Theme: `settingsButtonColor`, `settingsButtonBackgroundColor`,
  `settingsSheetBackgroundColor`, `settingsTextStyle`,
  `settingsSecondaryTextStyle`, and `settingsSelectedColor`. Icons:
  `settings`, `quality`, `audio`, `speed`, `fit`, `pip`, `check`, and `back`.
  Strings: `settings`, `quality`, `auto`, `audio`, `normalSpeed`, `fit`,
  `fill`, `videoFit`, and `pictureInPicture`. Builders:
  `settingsButtonBuilder`, `settingsSheetBuilder`, and `qualityLabelBuilder`.
- Re-exports `VideoTrack`, `VideoAudioTrack`, and `VideoViewType`.
- New dependency: `floating` (Android PiP).

## 1.2.0

- Ad break markers on the seek bar and an "Ad starts in N" countdown pill
  (tap to start the ad now). The SDK fetches the campaign VMAP to learn break
  times; if the fetch fails, ads still play without markers or countdown.
  Theme: `adMarker*`, `adCountdown*`. Strings: `adCountdown`, `adStartNowHint`.
  Builder: `adCountdownBuilder`.
- Fix: ad events arriving after dispose no longer throw.

- Added Google IMA ads support via `interactive_media_ads`. Pass a
  `ChorkiAdConfig` to `ChorkiPlayer` with `ads:`. Ads come from the reel API
  response's `data.ad_campaign` (`id`, `title`, `url`); reels without a
  campaign play without ads.
  - The campaign `url` is a VMAP document that IMA loads directly, so the VMAP
    defines the pre-, mid-, and post-roll breaks.
  - `ChorkiAdConfig` exposes `enabled`, `progressInterval`,
    `enablePreloading`, `onAdEvent`, and `onAdError`.
  - The content surface is hidden while an ad plays.
- Added `ByteDataEntity.adCampaign` (`AdCampaignEntity?`) and an `adTagUrl`
  getter that returns the campaign `url`.

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
