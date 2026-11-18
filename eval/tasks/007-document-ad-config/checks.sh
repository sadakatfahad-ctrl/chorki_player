source "$EVAL_ROOT/eval/lib/checks.sh"
check_made_changes
check_gate_quick
check_tests
check_no_new_allow
if python3 -c "import json,sys;d=json.load(open('test/guardrails/baselines.json')).get('dartdoc',{});sys.exit(1 if any(k.endswith(('chorki_ad_config.dart','ad_timeline.dart')) for k in d) else 0)"
then pass dartdoc_zero; else fail dartdoc_zero; fi
if grep -q "<!-- excerpt: ads-markers -->" README.md; then pass excerpt; else fail excerpt; fi
if added_lines lib | grep -vE '^\+\s*(///|//|$)' | grep -q .; then fail lib_logic_unchanged; else pass lib_logic_unchanged; fi
