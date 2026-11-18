source "$EVAL_ROOT/eval/lib/checks.sh"
# The hidden scenario is YAML: run it with the scenario runner.
mkdir -p test/scenarios
cp test/eval_hidden/hidden_005_loop_count_resets.yaml test/scenarios/zz_hidden_loop.yaml
if flutter test --reporter=failures-only test/scenarios >/tmp/eval_hidden.log 2>&1
then pass hidden_tests; else fail hidden_tests "see /tmp/eval_hidden.log"; fi
rm -f test/scenarios/zz_hidden_loop.yaml test/eval_hidden/*.yaml
check_made_changes
check_gate_quick
check_tests
check_no_new_allow
check_no_wall_clock
check_changelog
added="$(git diff "$BASE_REF" --name-only --diff-filter=A -- test/scenarios)"
if [ -n "$added" ] && grep -l "loopCount" $added >/dev/null 2>&1
then pass regression_scenario; else fail regression_scenario; fi
new_ids="$(git diff "$BASE_REF" -U0 -- tool/mutants.yaml | sed -n 's/^+- id: //p')"
if [ -n "$new_ids" ] && dart run tool/mutation_smoke.dart "$(head -1 <<<"$new_ids")" >/tmp/eval_mut.log 2>&1
then pass mutant_added; else fail mutant_added "see /tmp/eval_mut.log"; fi
