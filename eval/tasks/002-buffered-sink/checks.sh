source "$EVAL_ROOT/eval/lib/checks.sh"
run_common_checks
if grep -q "ChorkiBufferedAnalyticsSink" test/guardrails/goldens/public_api.txt; then pass exported; else fail exported; fi
