source "$EVAL_ROOT/eval/lib/checks.sh"
run_common_checks
if grep -rq "muted:" example/lib/readme && grep -q "muted:" README.md; then pass readme_excerpt; else fail readme_excerpt; fi
