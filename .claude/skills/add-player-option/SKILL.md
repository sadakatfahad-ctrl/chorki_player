---
name: add-player-option
description: Add a new option to ChorkiPlayer / ChorkiPlayer.url (a constructor parameter) end to end in chorki_player. Use for any new player setting, callback or builder.
---

# Add a ChorkiPlayer option

1. **Both constructors.** Add the parameter to `ChorkiPlayer(...)` and
   `ChorkiPlayer.url(...)` in `lib/src/presentation/chorki_player_widget.dart`
   with a sensible default that keeps today's behaviour. Document the field
   with `///`: what it does, its default, and any interaction (preload, ads,
   shared controller).
2. **Updates.** Handle a changed value in `didUpdateWidget`. A feed rebuilds
   pages with new values; check whether the option must apply live or only
   on the next load.
3. **Shared controller.** Per-view state never goes on
   `ChorkiPlayerController`. A controller-level default needs a controller
   constructor parameter with the widget value winning.
4. **No new magic numbers.** Use `static const` or documented parameter
   defaults. No `DateTime.now()`; inject a clock if you need time.
5. **Errors.** Platform calls go through `fireAndReport` / `guardAsync`
   (`lib/src/core/guard.dart`). Never use an empty catch.
6. **Analytics.** If the viewer can change it, record it (see the
   `add-analytics-event` skill).
7. **Tests.** Add a widget test in `test/chorki_player_widget_test.dart`,
   using `ChorkiServices.overrideForTesting` and the fakes in `test/fakes/`.
   It must fail without the change; check that.
8. **Docs.** Add or extend a README excerpt in `example/lib/readme/*.dart`
   (`// #region` / `// #endregion`), copy it verbatim into README.md with the
   `<!-- excerpt: name -->` tag, and add a CHANGELOG `### Added` line naming
   the parameter.
9. **API snapshot.** `UPDATE_GOLDENS=1 flutter test test/guardrails`, then
   review the `public_api.txt` diff. Only the intended lines may change.
10. Run `tool/check.sh` and report its tail.

The widget file is over the size limit (ratchet). Put new logic in a helper
under `lib/src/presentation/player/` rather than growing it.
