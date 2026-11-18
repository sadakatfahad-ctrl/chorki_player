# chorki_player: working agreement

A Flutter SDK that resolves Chorki byte routes and plays them (feeds,
gestures, settings, IMA ads, PiP, analytics with a built-in Matomo sink).
Published to pub.dev; the Chorki app depends on it. Treat every public
symbol as a contract.

## Definition of done (every change)

1. `tool/check.sh` passes. Paste its tail in your summary or PR.
2. Behaviour change → a test or a scenario (`test/scenarios/*.yaml`) that
   **fails without the change**. Check this; don't assume it.
3. Bug fix → a regression scenario/test named after the bug **and** a mutant
   in `tool/mutants.yaml` that re-introduces it;
   `dart run tool/mutation_smoke.dart <id>` must say `killed`.
4. Public API change → intended diff in
   `test/guardrails/goldens/public_api.txt` (`UPDATE_GOLDENS=1 flutter test
   test/guardrails`), and every changed symbol named in `CHANGELOG.md`.
5. Docs: `///` on new public members, README snippets edited in
   `example/lib/readme/` and copied verbatim, CHANGELOG under
   `## <version>` / `### Added|Changed|Deprecated|Removed|Fixed|Security`.
6. Report honestly: what was verified, what was not, what failed.

## Commands

| What | Command |
|---|---|
| Quick gate (format, analyze, guardrails) | `tool/check.sh --quick` |
| Full gate (+ tests, coverage, scenarios, example, publish dry run) | `tool/check.sh` |
| Mutation smoke (do tests catch bugs?) | `dart run tool/mutation_smoke.dart [filter]` (do not edit files while it runs) |
| Scenario coverage matrix | `dart run tool/scenarios_report.dart` |
| Re-record goldens/baselines after an intended change | `UPDATE_GOLDENS=1 flutter test test/guardrails` |
| Raise coverage floors | `flutter test --coverage && dart run tool/coverage_gate.dart --update` |
| AI implementation evals | `eval/run.sh <task>` (see `eval/README.md`) |
| Seed an eval task's starting state | `python3 eval/lib/seed_patch.py ...` (see `eval/README.md`) |
| Build the playbook PDF | `tool/build_pdf.sh docs/guardrails/guardrails_evals_playbook.html` |

## Architecture and layering (enforced by `test/guardrails/code_rules_test.dart`)

```
lib/chorki_player.dart            public barrel (the only API hosts see)
lib/chorki_player_testing.dart    conformance suites + fakes for hosts
lib/src/
  core/        diagnostics, clock, ids, guard, result, services (no UI)
  errors/      ChorkiPlayerError (typed) + network exceptions
  network/     ApiClient (Dio, HTTP/2), ChorkiNetworkConfig
  domain/      entities, repository interfaces, use cases (pure Dart)
  data/        data sources, models, repository impl
  controllers/ ChorkiPlayerController, preloader, load scheduler
  analytics/   session engine, schema, sinks (core knows no Matomo)
    matomo/    the Matomo sink, request builder, config, naming
  ads/         IMA layer, VMAP, ad timeline
  presentation/ ChorkiPlayer widget (+ its state part), bloc, widgets
    player/    retry policy, source, loading/video views, analytics binding
  theme/ media/ pip/ helpers/
```

- `domain/` imports no `data/`, `presentation/` or Flutter UI.
- `analytics/` (core) never imports `analytics/matomo/`; analytics never
  imports `presentation/`.
- The player never uses the app's `GetIt.instance`; its object graph is
  `ChorkiServices` (`lib/src/core/services.dart`).
- `lib/` never imports test-only packages; `lib/src` never imports the
  barrels.

## Conventions (each has a guardrail)

- **No silent catches.** A `catch` must rethrow, convert/forward the error,
  catch a narrow `on SomeType`, or call
  `ChorkiDiagnostics.report(e, st, 'area.action')`. Fire-and-forget futures
  use `fireAndReport(action, 'context')` (`lib/src/core/guard.dart`).
  A deliberate exception needs `// guardrail:allow swallowed_error - <reason>`.
- **No logging** in `lib/` (no `print`, `debugPrint`, `dart:developer`).
  Hosts get errors through `ChorkiDiagnostics.onError`.
- **Determinism.** Never call `DateTime.now()` or `Random()` outside
  `lib/src/core/clock.dart` / `ids.dart`; take a `ChorkiClock` /
  `ChorkiIdGenerator`.
- **No magic durations** in method bodies: name them (`static const`).
- **Typed errors.** User-visible failures are `ChorkiPlayerError` with a
  `ChorkiErrorCode`; only transient ones are retried silently. Never show a
  server's raw message to viewers; use `ChorkiPlayerStrings`.
- **Analytics payloads** follow `ChorkiAnalyticsSchema`
  (`lib/src/analytics/chorki_analytics_schema.dart`). Use the
  `ChorkiAnalyticsKeys` constants, never string literals. Each enum value's
  doc has a `Data:` line listing exactly its keys. The README table is
  generated. The session asserts payloads in debug.
- **Naming.** Every public type starts with `Chorki`.
- **Public API changes** are additive in minor versions. To remove or rename
  something, deprecate it with
  `@Deprecated('Use X. Removed in 2.0.0.')`, keep it working, and list it
  under `### Deprecated`.
- **Size.** A `lib/` file may have 350 code lines (comments don't count). Split
  rather than add an allowlist entry.
- **Tests.** Every `lib/src` file is referenced by a test. Every controller
  command and session `record*` method is called in a test. Coverage floors
  only rise (`tool/coverage_baseline.json`).

## Ratchets

`test/guardrails/baselines.json` holds today's accepted violations for
backlogs being paid down (dartdoc, file size, ...). Counts may only go
**down**. When a count drops, the test fails until you lock it in with
`UPDATE_GOLDENS=1`. Never use `GUARDRAIL_RECORD=1` to hide new violations;
it exists only for recording a brand-new rule.

## Recipes

- New analytics event: the `add-analytics-event` skill
  (`.claude/skills/add-analytics-event/SKILL.md`).
- New `ChorkiPlayer` option: the `add-player-option` skill.
- Reviewing a diff: the `chorki-reviewer` agent
  (`.claude/agents/chorki-reviewer.md`) grades against
  `eval/rubric/common.yaml`.

## Gotchas

- Tests run with `ChorkiVideoLoadScheduler.resetForTesting` before each test
  (`test/flutter_test_config.dart`). The same config **fails any test in which
  the SDK reports an unexpected `ChorkiDiagnostics` error**. A test that
  expects reports declares them with `captureDiagnostics()`
  (`test/support/diagnostics.dart`) and asserts on the contexts.
- Widget tests swap `VideoPlayerPlatform.instance` /
  `InteractiveMediaAdsPlatform.instance` for the fakes in `test/fakes/`.
  Inject routes with `ChorkiServices.overrideForTesting(repository: ...)`.
- `ChorkiPlayerController` is shared by a feed; per-view state belongs in the
  widget or the analytics session, never in the controller.
- 1.6.0 is unreleased: its analytics API may still change without
  deprecation. Anything released in 1.5.0 or earlier may not.
