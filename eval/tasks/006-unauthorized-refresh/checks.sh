source "$EVAL_ROOT/eval/lib/checks.sh"
run_common_checks
if grep -B3 "onUnauthorized;" lib/src/network/chorki_network_config.dart | grep -q "///" && grep -q "onUnauthorized" CHANGELOG.md
then pass documented; else fail documented; fi
