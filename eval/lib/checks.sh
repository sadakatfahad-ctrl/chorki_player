# Shared objective checks for eval tasks. Source it from a task's checks.sh,
# which runs inside the task worktree. Each check prints `PASS <id>` or
# `FAIL <id> <reason>`.
set -u
BASE_REF="${BASE_REF:-HEAD}"
# Let `git diff` see files the agent created (intent-to-add, no content staged).
git add -A -N . >/dev/null 2>&1 || true

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1 ${2:-}"; }

added_lines() { git diff "$BASE_REF" --unified=0 -- "$@" | grep '^+' | grep -v '^+++' || true; }

check_gate_quick() {
  if tool/check.sh --quick >/tmp/eval_quick.log 2>&1; then pass gate_quick
  else fail gate_quick "see /tmp/eval_quick.log"; fi
}

check_tests() {
  if flutter test --reporter=failures-only >/tmp/eval_tests.log 2>&1; then pass tests
  else fail tests "see /tmp/eval_tests.log"; fi
}

check_hidden_tests() {
  if [ -z "$(find test/eval_hidden -name '*_test.dart' 2>/dev/null)" ]; then
    pass hidden_tests; return
  fi
  if flutter test --reporter=failures-only test/eval_hidden >/tmp/eval_hidden.log 2>&1
  then pass hidden_tests; else fail hidden_tests "see /tmp/eval_hidden.log"; fi
}

check_no_new_allow() {
  if added_lines lib test | grep -q 'guardrail:allow'; then fail no_new_allow
  else pass no_new_allow; fi
}

check_no_wall_clock() {
  if added_lines lib | grep -Eq 'DateTime\.now|Random(\.secure)?\('; then
    fail no_wall_clock
  else pass no_wall_clock; fi
}

check_changelog() {
  if git diff --quiet "$BASE_REF" -- lib; then pass changelog; return; fi
  if git diff --quiet "$BASE_REF" -- CHANGELOG.md; then fail changelog "lib changed, CHANGELOG did not"
  else pass changelog; fi
}

check_made_changes() {
  # test/eval_hidden is the harness's copy of the held-out tests, not the
  # agent's work: an idle run must still score 0.
  if git diff --quiet "$BASE_REF" -- lib test example/lib README.md CHANGELOG.md tool \
    ':!test/eval_hidden'
  then fail made_changes "nothing changed"; else pass made_changes; fi
}

run_common_checks() {
  check_made_changes
  check_gate_quick
  check_tests
  check_hidden_tests
  check_no_new_allow
  check_no_wall_clock
  check_changelog
}
