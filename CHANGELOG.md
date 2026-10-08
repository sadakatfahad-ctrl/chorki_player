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
