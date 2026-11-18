# Contributing

Read `CLAUDE.md` first: it holds the architecture, conventions and the
definition of done (for people and for AI agents alike).

## Setup

```sh
flutter pub get && (cd example && flutter pub get)
tool/install_hooks.sh      # optional: quick gate before every commit
```

## The gate

| Command | When |
|---|---|
| `tool/check.sh --quick` | Before every commit (the hook runs it): format, analyze `--fatal-infos`, guardrails. |
| `tool/check.sh` | Before a PR (CI runs it): + all tests with coverage floors, scenario coverage, example analysis, publish dry run. |
| `tool/check.sh --mutation` | After touching analytics, the Matomo sink, errors or retries (CI runs it nightly). |

What the guardrails check (`test/guardrails/`): swallowed errors, layering,
wall clock and randomness, magic durations, file size, analytics key
literals, the public API snapshot, dartdoc coverage, the deprecation policy,
that every file and controller command is exercised by tests, the CHANGELOG
format and version, README snippets that compile, and the analytics schema
against the enum docs, Matomo mapping, README table and scenarios.

Backlogs being paid down are in `test/guardrails/baselines.json`. Those
counts may only go down.

## Evals

- `test/scenarios/*.yaml`: behaviour specs of the analytics engine (see its
  README).
- `package:chorki_player/chorki_player_testing.dart`: conformance suites for
  host implementations.
- `eval/`: graded AI implementation tasks (see `eval/README.md`).

The whole system (layers, full cycle, templates, a port table for other
stacks) is explained in `docs/guardrails/guardrails_evals_playbook.html`.
Build the PDF with `tool/build_pdf.sh docs/guardrails/guardrails_evals_playbook.html`.

## Releasing

1. Move `## Unreleased` to `## x.y.z` and set `version: x.y.z` in
   `pubspec.yaml` (the docs guardrail checks they match).
2. `tool/check.sh --mutation` passes.
3. Commit, tag `vx.y.z` and push the tag. Every release is tagged.
4. `dart pub publish`.

## Regenerating the analytics guide PDF

The HTML source is `docs/analytics/matomo_analytics.html`; the PDF is
gitignored. To regenerate it:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --no-pdf-header-footer \
  --print-to-pdf=docs/analytics/ChorkiPlayer_Matomo_Analytics.pdf \
  docs/analytics/matomo_analytics.html
```
