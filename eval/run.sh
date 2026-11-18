#!/usr/bin/env bash
# Runs one AI implementation eval task.
#
#   eval/run.sh <task-dir-name> [--agent claude|manual|none|script:<path>]
#               [--judge] [--keep]
#
# EVAL_BASE=<commit> overrides the task's baseline commit (default HEAD).
#
# 1. Creates a git worktree at the task's baseline (HEAD, or the commit in
#    baseline.txt) and applies baseline.patch if present (seeded bugs).
# 2. Runs the agent on task.md (`claude -p`), or waits for you (manual).
# 3. Copies the task's hidden/ tests into test/eval_hidden/.
# 4. Runs checks.sh (objective) and, with --judge, the chorki-reviewer agent
#    (subjective criteria).
# 5. Writes eval/results/<task>-<timestamp>.json with the score.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
export ROOT

task="${1:?usage: eval/run.sh <task> [--agent claude|manual] [--judge] [--keep]}"
shift
agent=claude judge=0 keep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --agent) agent="$2"; shift ;;
    --judge) judge=1 ;;
    --keep) keep=1 ;;
  esac
  shift
done

TASK_DIR="$ROOT/eval/tasks/$task"
export TASK_DIR
[ -f "$TASK_DIR/task.md" ] || { echo "no task $task"; exit 2; }
base="${EVAL_BASE:-$(cat "$TASK_DIR/baseline.txt" 2>/dev/null || git rev-parse HEAD)}"
stamp="$(date +%Y%m%d-%H%M%S)"
WT="$(mktemp -d)/chorki-eval-$task"

git worktree add --detach "$WT" "$base" >/dev/null
cleanup() { [ "$keep" = 1 ] || git worktree remove --force "$WT" >/dev/null 2>&1 || true; }
trap cleanup EXIT

cd "$WT"
if [ -f "$TASK_DIR/baseline.patch" ]; then
  git apply "$TASK_DIR/baseline.patch"
  git -c user.email=eval@local -c user.name=eval commit -qam "eval baseline: $task"
fi
BASE_REF="$(git rev-parse HEAD)"
flutter pub get >/dev/null
(cd example && flutter pub get >/dev/null)

echo "== task $task in $WT"
case "$agent" in
  claude)
    claude -p "$(cat "$TASK_DIR/task.md")" --permission-mode acceptEdits \
      --output-format json > "$WT/.eval_agent.json" || true ;;
  manual)
    echo "Implement the task in $WT, then press Enter."; read -r _ ;;
  none) ;;  # score the untouched baseline (harness self-test)
  script:*)
    bash "$ROOT/${agent#script:}" ;;  # a scripted "agent" (harness self-test)
  *) echo "unknown agent $agent"; exit 2 ;;
esac

mkdir -p test/eval_hidden
if [ -d "$TASK_DIR/hidden" ]; then cp -R "$TASK_DIR/hidden/." test/eval_hidden/; fi

echo "== objective checks"
checks="$(BASE_REF="$BASE_REF" EVAL_ROOT="$ROOT" bash "$TASK_DIR/checks.sh" 2>&1 || true)"
echo "$checks"

judge_json='null'
if [ "$judge" = 1 ]; then
  echo "== judge"
  judge_json="$(claude -p "Use the chorki-reviewer agent to review \`git diff $BASE_REF\` for the task in $TASK_DIR (task.md and rubric.yaml) and $ROOT/eval/rubric/common.yaml. Reply with its JSON only." --output-format text 2>/dev/null | sed -n '/^{/,/^}/p' || echo null)"
fi

mkdir -p "$ROOT/eval/results"
out="$ROOT/eval/results/$task-$stamp.json"
python3 - "$checks" "$TASK_DIR" "$ROOT/eval/rubric/common.yaml" "$judge_json" > "$out" <<'PY'
import json, re, sys
checks, task_dir, common, judge = sys.argv[1:5]
def weights(path):
    w = {}
    try:
        for m in re.finditer(r"- id: (\w+)\s+weight: (\d+)", open(path).read()):
            w[m[1]] = int(m[2])
    except FileNotFoundError:
        pass
    return w
w = {**weights(common), **weights(task_dir + "/rubric.yaml")}
results = {}
for line in checks.splitlines():
    m = re.match(r"(PASS|FAIL) (\w+)(.*)", line)
    if m: results[m[2]] = {"pass": m[1] == "PASS", "detail": m[3].strip()}
total = sum(w.get(k, 1) for k in results)
got = sum(w.get(k, 1) for k, v in results.items() if v["pass"])
# A run that changed nothing scores zero, however clean the untouched tree is.
if results.get("made_changes", {}).get("pass") is False:
    got = 0
print(json.dumps({
    "task": task_dir.rsplit("/", 1)[-1],
    "objective_score": round(got / total, 3) if total else 0,
    "checks": results,
    "judge": json.loads(judge) if judge not in ("", "null") else None,
}, indent=2))
PY
echo "== result: $out"
python3 -c "import json;d=json.load(open('$out'));print('objective score', d['objective_score'])"
