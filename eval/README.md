# AI implementation evals

Graded tasks that measure whether a future change (by Claude, another agent
or a person) meets this repo's bar. A task holds the prompt, objective
checks, optional held-out tests and a rubric. A run happens in a throwaway
git worktree, so your checkout is never touched.

```
eval/
  run.sh                 runs one task, writes eval/results/<task>-<time>.json
  rubric/common.yaml     criteria and weights every task inherits
  lib/checks.sh          shared objective checks (gate, tests, hidden tests, ...)
  selftest/              reference solutions that prove the harness discriminates
  tasks/NNN-slug/
    task.md              the prompt, written like a real issue
    rubric.yaml          task-specific criteria and weights
    checks.sh            objective checks: prints PASS <id> / FAIL <id> <why>
    hidden/              held-out tests, copied in only after the agent is done
    baseline.patch       optional: seeds a bug or planted code before the run
    planted.json         (review tasks) the problems a review must find
```

## Running

```sh
eval/run.sh 004-loopcount-regression                 # claude -p does the task
eval/run.sh 004-loopcount-regression --judge         # + chorki-reviewer grades the rubric
eval/run.sh 003-start-muted --agent manual --keep    # you do it; keep the worktree
EVAL_BASE=<commit> eval/run.sh ...                   # baseline other than HEAD
```

The baseline is `HEAD`, so **commit before running**: uncommitted work is not
in the worktree. The result JSON has `objective_score` (passed check weights
divided by all check weights), every check with its detail, and the judge's
JSON when `--judge` is set.

## Tasks

| Task | Kind | What it measures |
|---|---|---|
| 001-replay-event | feature | the schema → session → Matomo → scenario → README chain for a new analytics event |
| 002-buffered-sink | feature | a new public sink that passes the conformance suite |
| 003-start-muted | feature | a `ChorkiPlayer` option end to end (both constructors, updates, analytics, README excerpt) |
| 004-loopcount-regression | bug fix | finding a seeded bug from a user report, plus the regression scenario and mutant |
| 005-extract-retry-policy | refactor | behaviour-preserving extraction (tests untouched, API unchanged, file shrank) |
| 006-unauthorized-refresh | feature | a network feature in the right layer, with held-out tests |
| 007-document-ad-config | docs | paying down the dartdoc ratchet and adding a compiled README excerpt |
| 008-review-planted-antipatterns | review | precision and recall on three planted antipatterns |

## Harness self-test (run after changing the harness)

Every seeded task must score 0 with no agent and 1.0 with its reference:

```sh
eval/run.sh 004-loopcount-regression --agent none                                  # expect 0
eval/run.sh 004-loopcount-regression --agent script:eval/selftest/004_reference_fix.sh  # expect 1.0
eval/run.sh 005-extract-retry-policy --agent script:eval/selftest/reverse_seed.sh  # expect 1.0
eval/run.sh 007-document-ad-config --agent script:eval/selftest/reverse_seed.sh    # expect 1.0
eval/run.sh 008-review-planted-antipatterns --agent none                            # expect 0
eval/run.sh 008-review-planted-antipatterns --agent script:eval/selftest/008_perfect_review.sh  # expect 1.0
for t in 001-replay-event 002-buffered-sink 003-start-muted 006-unauthorized-refresh; do
  eval/run.sh $t --agent none                                      # expect 0
  eval/run.sh $t --agent script:eval/selftest/reference_patch.sh   # expect 1.0
done
```

References: `reverse_seed.sh` undoes `baseline.patch` (for tasks whose answer
is today's tree); `reference_patch.sh` applies
`selftest/reference/<task>.patch`, a known-good implementation built in a
worktree at the baseline (`git diff` after `git add -A -N .`). Regenerate a
reference patch when it stops applying.

Last measured on all eight tasks: `--agent none` scores 0.0 and the reference
scores 1.0 for every task.

Uncommitted work has no commit to start from. Snapshot it without touching
your index, refs or stash, and pass it as `EVAL_BASE`:

```sh
export GIT_INDEX_FILE=$(mktemp); git read-tree HEAD; git add -A
snap=$(git commit-tree "$(git write-tree)" -p HEAD -m "eval snapshot"); unset GIT_INDEX_FILE
EVAL_BASE=$snap eval/run.sh 005-extract-retry-policy --agent none
```

## Adding a task

1. Write `task.md` as the issue a developer would file. State the public API
   the held-out tests rely on (names, signatures); nothing else.
2. Put held-out tests in `hidden/`. They are copied to `test/eval_hidden/`
   and excluded from analysis, so they may reference APIs that don't exist
   yet.
3. Write `checks.sh`: `source "$EVAL_ROOT/eval/lib/checks.sh"`, then
   `run_common_checks`, then task checks printing `PASS id` / `FAIL id why`.
   Compare against `$BASE_REF`; new files are visible (intent-to-add).
4. Add weights for the task's ids in `rubric.yaml`.
5. To seed a starting state (a bug put back, docs removed, a refactor
   undone), build it in a scratch directory and generate the patch:
   `python3 eval/lib/seed_patch.py eval/tasks/<task>/baseline.patch --seed
   <dir> <changed files...> --delete <files to remove...>`. Remove the test
   or scenario that would reveal a seeded bug, and seed `baselines.json`
   too if the seeded code breaks a ratchet. Re-run it when the files it
   touches change (`git apply --check` tells you).
6. Add a reference solution (`selftest/`, or `reverse_seed.sh` when the
   answer is today's tree) and check that it scores 1.0 and that
   `--agent none` scores 0. If not, fix the checks, not the reference.
