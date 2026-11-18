#!/usr/bin/env bash
# Claude Code Stop hook: Claude may not finish while the quick gate fails.
# Runs only when Dart files changed (git), and blocks once per stop attempt
# (stop_hook_active) so it can never loop forever.
input="$(cat)"
if [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = "true" ]; then
  exit 0
fi
cd "$(dirname "$0")/../.." || exit 0
if [ -z "$(git status --porcelain -- '*.dart' '*.yaml' CHANGELOG.md README.md 2>/dev/null)" ]; then
  exit 0
fi
if out="$(tool/check.sh --quick 2>&1)"; then
  exit 0
fi
reason="tool/check.sh --quick failed. Fix it before finishing (see CLAUDE.md, Definition of done):
$(tail -n 40 <<<"$out")"
jq -n --arg r "$reason" '{decision: "block", reason: $r}'
