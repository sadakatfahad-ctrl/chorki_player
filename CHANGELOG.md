## 1.6.0

### Added

- New analytics: `ChorkiPlayer(metadata:, analytics:)` and
  `ChorkiPlayerController(analytics:)` report detailed viewing events to
  one or more `ChorkiAnalyticsSink`s:
  - Playback: impression, play (time to play), pause, resume, seek (with
    its source: double tap, scrub, seek bar, ad skip-ahead, API), heartbeat
    with watched segments, 25/50/75/100% quartiles, complete, loop, and a
    session end with dwell time, watched %, rebuffer, pause, seek and loop
    totals.
  - QoE: load start, first frame (startup time, queue wait, init time),
    rebuffering with durations, errors by stage, auto and manual retries,
    quality changes.
  - Ads: break start/end (pre/mid/post-roll, duration), ad start, quartiles,
    complete, skip, click, pause/resume, errors and the load timeout, with
    the campaign id/title.
  - UX: speed changes, long-press boost, audio track, fit, PiP, volume and
    mute, settings opened.
  - Watched time counts only real playback (not while paused, buffering,
    scrubbing or during ads). In a feed only the page on screen reports.
- New `MatomoAnalyticsSink`: Matomo Media Analytics (`ma_*`) heartbeats plus
  Matomo Events and Custom Dimensions, sent in bulk with an offline queue,
  backoff, back-dated `cdt` and a flush when the app goes to the background.
  Pluggable `ChorkiAnalyticsStorage` for a persistent visitor id.
- New `CallbackAnalyticsSink` and `MemoryAnalyticsSink`.
- `abandon` event: the view ended before the first frame (exit before video
  start), with the wait, the stage (`loading` / `ready`) and the error count.
- Chorki app compatibility: `MatomoConfig.visitorIdProvider` (share the app's
  `matomo_tracker` visitor), `MatomoNaming.chorkiLegacy` (`MediaVideo` /
  `play` / `pause` / `finished`), `MatomoConfig.chorkiAppDimensions`,
  `MatomoMediaSize.viewport`, and `ChorkiMediaMetadata.pageUrl` /
  `referrerUrl` (`url` / `urlref`).
- Typed errors: `ChorkiPlayerError` with `ChorkiErrorCode` (`noInternet`,
  `timeout`, `unauthorized`, `forbidden`, `notFound`, `badRequest`,
  `server`, `malformedResponse`, `noVideoUrl`, `videoLoad`, `playback`,
  `unknown`), `ChorkiErrorStage` and `isTransient`.
  `ChorkiPlayerBuilders.errorViewBuilder` receives it.
- `ChorkiDiagnostics.onError` (a `ChorkiErrorHandler`): every error the
  player recovers from internally (a rejected quality switch, a failed IMA
  call, a throwing analytics sink, ...) is reported there instead of being
  silently dropped. The SDK still never logs.
- `ChorkiNetworkConfig` and `ChorkiPlayer.configure(network:)`: headers, an
  async `headersProvider` (auth tokens), timeouts and HTTP/2 for route
  lookups. VMAP requests never get these headers.
- `ChorkiVideoPreloader.loadResult` returns a `ChorkiVideoLoadResult` with
  the reason a load failed (`timeout` vs `videoLoad`).
- `package:chorki_player/chorki_player_testing.dart`: conformance suites for
  your own `ChorkiAnalyticsSink`, `ChorkiAnalyticsStorage`, `MatomoTransport`
  and `ChorkiPipDelegate` (`analyticsSinkConformance`, ...), plus
  `ChorkiFakeClock`, `sequentialIds` and `sampleAnalyticsEvent`. No
  `flutter_test` dependency. `ChorkiClock` and `ChorkiIdGenerator` are
  exported.
- `ChorkiVideoLoadScheduler.configure` sets the app-wide load limits.
- `VideoPlayerController` and `VideoPlayerValue` are exported, so builders
  and `ChorkiPlayerSurface` work without depending on `video_player`.
- `ChorkiAnalyticsSchema`, `ChorkiAnalyticsKeys`, `ChorkiAnalyticsField` and
  `ChorkiAnalyticsValueType`: the typed description of every event's `data`
  (also generated into the README). The player checks each payload against
  it in debug builds.
- `ChorkiAnalyticsConfig.clock` / `idGenerator` (deterministic tests) and
  `ChorkiAnalyticsSink.onConsentRevoked` (`MatomoAnalyticsSink` and
  `MemoryAnalyticsSink` drop what they buffered).
- A `heartbeat` with `trigger: background` when the app goes to the
  background, followed by a flush of every sink.
- `ChorkiSeekBarState.adMarkers`: a custom `seekBarBuilder` can draw the
  mid-roll `ChorkiAdMarker`s like the built-in seek bar does.
- `==` and `hashCode` on `ChorkiPlayerTheme`, `ChorkiPlayerIcons` and
  `ChorkiPlayerStrings` (rebuilding with an equal theme is a no-op compare).
- Dartdoc for `ChorkiAdConfig`, `ChorkiAdMarker`, `ChorkiPlayerIcons`,
  `ChorkiPlayerStrings`, `ChorkiSeekBarState`, `ChorkiGestureKind`,
  `ChorkiGestureFeedback` and `defaultAdCountdown`.

### Changed

- Every public type and member has dartdoc (`public_member_api_docs` is on).
- `ChorkiPlayerController.setAdPlaying` is `@internal` (only the player's ad
  layer calls it).
- The player keeps its own services (`ChorkiServices`) instead of
  registering in the app's `GetIt.instance`, so an app resetting or scoping
  GetIt no longer breaks it.
- Route failures are typed. Permanent ones (401/403/404/4xx, a malformed
  response, no video URL) are no longer retried silently; the error view
  still offers Retry. The error view shows the localized
  `ChorkiPlayerStrings.noInternet` / `serverError` / `genericError` instead
  of the server's raw message.
- `ChorkiAnalyticsSession.recordError` takes the `ChorkiPlayerError`; the
  `error` event carries `code`, `stage`, `transient`, `statusCode` and
  `detail`.
- Analytics payload keys are unambiguous: `heartbeat.trigger` (was
  `reason`), `abandon.abandonStage` (was `stage`), `audioTrackChange`
  `fromTrack` / `toTrack` (were `from` / `to`). Event `data` is unmodifiable.
- Analytics consent and `enabled` are view boundaries: turning them on starts
  a fresh view (with its impression); turning them off ends the view without
  counting anything in between.
- `watchedPercent` counts the time actually covered (not touched 5 s
  buckets); segments end exactly at the video's end; `firstFrame` and the
  loop count are per view; replaying after the end reports quartiles again.
- `MatomoAnalyticsSink` treats a throwing transport as a failed send (backoff,
  reported), restores a damaged saved queue entry by entry within
  `maxQueueLength`, never sends a request twice when the app goes to the
  background before the saved queue was restored, and reports recovered
  errors to `ChorkiDiagnostics`.
- `ChorkiVideoPreloader.load` takes `onStarted`. `ChorkiPlayerController.attach`
  takes `analytics`.
- Stricter analyzer settings (strict casts / inference / raw types and more
  lints) and guardrail tests in `test/guardrails/` that check the source for
  swallowed errors, layering, wall-clock use, file size, magic durations, the
  public API snapshot, dartdoc coverage, the deprecation policy, test
  coverage of every file, and CHANGELOG / README consistency.

### Fixed

- An IMA ads manager that loaded after its player was disposed was never
  destroyed.
- `ChorkiPlayerController` cancels its PiP status probes on dispose.
- VMAP schedules reuse one HTTP client instead of creating one per request.
- `ChorkiShortsSeekBar` ends a drag cut off by a controller swap or disposal
  (analytics no longer treat the next pause as part of a scrub).
- A custom `seekBarBuilder`'s seeks are clamped to the video before they are
  reported (a seek past the end was reported as such).
- Route responses with any 2xx status (202, 206, ...) are successes; only
  200, 201 and 204 were.

### Deprecated

- `PlayerGestureOverlay`, `ShortsSeekBar`, `VideoPreloader`,
  `VideoLoadScheduler` and `FloatingPipDelegate`: renamed to
  `ChorkiGestureOverlay`, `ChorkiShortsSeekBar`, `ChorkiVideoPreloader`,
  `ChorkiVideoLoadScheduler` and `ChorkiFloatingPipDelegate` (every public
  type now has the `Chorki` prefix). The old names are aliases.
- `ByteDataEntity` and `AdCampaignEntity`: internal types that appear in no
  public API.
- `getIt` and `initChorkiPlayer`: the player no longer uses GetIt.
- `ChorkiPlayerBuilders.errorBuilder`: use `errorViewBuilder`.
- Assigning `ChorkiVideoLoadScheduler.instance` (setter `instance`): use
  `ChorkiVideoLoadScheduler.configure(maxConcurrent:)` at startup.

### Removed

- The `dartz` dependency.

## 1.5.0

- New `ChorkiPlayer.preload` (opt-in, both constructors) for feeds that build
  the next byte ahead of time, e.g. `preload: index != current` in a
  `PageView` with `allowImplicitScrolling: true`. A preloading player fetches
  the route, initializes and buffers the video, and shows its first frame. It
  does not play, show controls, or request ads, and it leaves `controller`
  unattached, so one controller can serve a whole feed. Turning `preload` off
  plays at once (with `autoPlay`) and starts the ads. Turning it back on
  pauses and rewinds to the start. A byte that failed while preloading
  retries when it becomes active.
- Feeds survive flaky networks and fast swiping:
  - Silent auto-retry: a failed route fetch, a video init failure or a
    playback error retries after 1s and 3s, showing the poster, before the
    error view. A playback error resumes from where it stopped. Retry and a
    byte becoming active start a fresh round.
  - A preloading byte never shows the error view (it no longer flashes in
    mid-swipe).
  - New `VideoLoadScheduler`: at most two players are created at a time,
    the visible byte first. A page swiped past before its turn never creates
    a player. New loads briefly wait for disposals in progress to free their
    decoders. `VideoPreloader.load` takes `isHighPriority` and `isCancelled`.
  - Resolved routes are cached for 5 minutes (LRU, 50 entries). Requests for
    the same route share one fetch, and a retry after a video failure
    bypasses the cache.
  - Route GETs whose connection drops before a response (a refused, reset
    or stale HTTP/2 connection, a GOAWAY) are retried twice, after 300ms and
    900ms. Timeouts are left to the player's retry, so a dead network still
    fails fast.
- New `ChorkiPlayerSurface.showControls` (default `true`): `false` shows only
  the video.
- `ChorkiPlayerController.isAdPlaying` now belongs to the attached video: it
  resets when a different video is attached or the video is detached.
- Fix: with one controller shared by several players, disposing or reloading
  a player that was not attached cleared the attached player's `isAdPlaying`.
- Fix: changing `ChorkiPlayer.controller` while a video was still loading
  detached another player's video from the old controller.

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
