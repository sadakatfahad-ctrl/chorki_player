#!/usr/bin/env bash
# Reference "agent" for feature tasks: applies a known-good implementation
# from eval/selftest/reference/<task>.patch (made by implementing the task in
# a worktree at the baseline and saving `git diff`). Run with
#   eval/run.sh <task> --agent script:eval/selftest/reference_patch.sh
# It should score 1.0. Regenerate the patch when it stops applying.
set -euo pipefail
git apply "$ROOT/eval/selftest/reference/$(basename "$TASK_DIR").patch"
