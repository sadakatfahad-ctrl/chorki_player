---
name: add-analytics-event
description: Add or change a chorki_player analytics event (a ChorkiAnalyticsEventType value or its data keys). Use whenever the analytics payload, schema, Matomo mapping or event docs change.
---

# Add an analytics event

Every step has a guardrail; skipping one fails `tool/check.sh`.

1. **Schema first.** In `lib/src/analytics/chorki_analytics_schema.dart`:
   add any new key to `ChorkiAnalyticsKeys` (constant name == value, with a
   `///` doc), and the event's fields to `ChorkiAnalyticsSchema.own`
   (required vs `.optional`, the right `ChorkiAnalyticsValueType`).
2. **Enum.** In `lib/src/analytics/chorki_analytics_event.dart`, add the value
   in its category section with a one-line doc and a `Data:` line that lists
   exactly the keys from step 1 in backticks (`Data: none.` when empty).
3. **Emit.** Record it from `ChorkiAnalyticsSession` (a `record*` method, or
   inside `_onValue`) using `_K.<key>`, never string literals. The debug
   assert checks every payload against the schema.
4. **Wire.** Call the recorder from the widget, controller or ad layer that
   knows the fact. Use `ChorkiAnalyticsScope.maybeOf(context)` in player
   widgets, or `_session` in `ChorkiPlayerController`.
5. **Matomo.** Add the case to `MatomoRequestBuilder._describe` (action, name,
   value). Read values with `n(key)` / `s(key)` / `secs(key)`. Decide whether
   it belongs in `MatomoConfig.defaultExcludedEvents`.
6. **Scenario.** Add `test/scenarios/NNN_<name>.yaml` asserting the event and
   its data (and a Matomo request if mapped). See `test/scenarios/README.md`.
   The coverage test fails until one exists.
7. **Recorder test.** If you added a `record*` method, call it in a test
   (`proof_test` checks this).
8. **Docs.** Regenerate the README event table:
   `UPDATE_GOLDENS=1 flutter test test/guardrails`. Add a CHANGELOG line
   naming the event. The API snapshot changes too; review its diff.
9. **Prove it.** Add a mutant to `tool/mutants.yaml` that drops the emit,
   then run `dart run tool/mutation_smoke.dart <id>`: it must be killed.
10. Run `tool/check.sh` and report its tail.

Renaming or removing a key after a release breaks sinks: deprecate in docs,
send both keys for a minor version, and remove in the next major.
