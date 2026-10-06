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
