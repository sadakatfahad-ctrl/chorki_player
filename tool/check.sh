#!/usr/bin/env bash
# The quality gate. CI runs the full gate; the pre-commit hook and the Claude
# Code Stop hook run --quick.
#
#   tool/check.sh            full gate
#   tool/check.sh --quick    format + analyze + guardrails (seconds)
#   tool/check.sh --mutation full gate + mutation smoke run (slow)
set -euo pipefail
cd "$(dirname "$0")/.."

mode="${1:-full}"
step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "format"
dart format --output=none --set-exit-if-changed lib test tool example/lib

step "analyze (package)"
flutter analyze --fatal-infos

step "guardrails"
flutter test --reporter=failures-only test/guardrails

if [[ "$mode" == "--quick" ]]; then
  printf '\n\033[32mquick gate passed\033[0m\n'
  exit 0
fi

step "tests + coverage"
flutter test --coverage --reporter=failures-only
dart run tool/coverage_gate.dart

if true; then
  step "scenario coverage"
  dart run tool/scenarios_report.dart
fi

step "api docs (dart doc --dry-run)"
# Fails on any dartdoc warning except the README's task-list checkboxes
# ("- [ ]"), which dartdoc reads as a reference.
docs="$(dart doc --dry-run 2>&1)" || { echo "$docs" | tail -n 20; exit 1; }
warnings="$(grep -E '^\s*warning:' <<<"$docs" | grep -vF 'unresolved doc reference [ ]' || true)"
if [[ -n "$warnings" ]]; then echo "$warnings"; exit 1; fi
echo "no dartdoc warnings"

step "analyze (example)"
(cd example && flutter analyze --fatal-infos)

step "tests (example)"
# Hermetic: widget tests have no video plugin and no network, so loads fail
# fast; the tests check the catalog, the feed's preloading and the layouts.
(cd example && flutter test --reporter=failures-only)

step "publish dry run"
# Exit code 65 means warnings only (e.g. uncommitted files); fail on errors.
set +e
out="$(dart pub publish --dry-run 2>&1)"; code=$?
set -e
echo "$out" | tail -n 5
if [[ $code -ne 0 && $code -ne 65 ]]; then exit $code; fi

if [[ "$mode" == "--mutation" ]]; then
  step "mutation smoke"
  dart run tool/mutation_smoke.dart
fi

printf '\n\033[32mfull gate passed\033[0m\n'
