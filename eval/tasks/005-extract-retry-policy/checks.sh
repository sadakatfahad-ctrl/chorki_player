source "$EVAL_ROOT/eval/lib/checks.sh"
# A behaviour-preserving internal refactor has nothing user-visible to log,
# so the common CHANGELOG check is left out on purpose.
check_made_changes
check_gate_quick
check_tests
check_hidden_tests
check_no_new_allow
check_no_wall_clock
f=lib/src/presentation/player/retry_policy.dart
if [ -f "$f" ] && grep -rlq "retry_policy.dart" test; then pass file_created; else fail file_created; fi
code() { grep -cvE '^\s*(//|\*|$)' "$1"; }
state=lib/src/presentation/chorki_player_state.dart
before="$(git show "$BASE_REF":$state | grep -cvE '^\s*(//|\*|$)')"
after="$(code $state)"
if [ "$after" -lt "$before" ]; then pass widget_shrank; else fail widget_shrank "$before -> $after"; fi
if git diff --quiet "$BASE_REF" -- test/guardrails/goldens/public_api.txt; then pass api_unchanged; else fail api_unchanged; fi
if [ -z "$(git diff "$BASE_REF" --name-only --diff-filter=M -- test ':!test/guardrails/baselines.json')" ]
then pass tests_untouched; else fail tests_untouched; fi
