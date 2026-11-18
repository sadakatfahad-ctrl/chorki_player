#!/usr/bin/env bash
# Reference "agent" for seeded tasks whose answer is today's tree: undoes the
# task's baseline.patch (restores the docs, the refactor, the fix). Run with
#   eval/run.sh <task> --agent script:eval/selftest/reverse_seed.sh
# It should score 1.0; `--agent none` should score 0. If not, the task's
# checks do not measure what the task asks.
set -euo pipefail
git apply -R "$TASK_DIR/baseline.patch"
