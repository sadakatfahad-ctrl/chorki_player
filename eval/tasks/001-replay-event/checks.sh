source "$EVAL_ROOT/eval/lib/checks.sh"
run_common_checks
if grep -q "ChorkiAnalyticsEventType.replay => const \[" lib/src/analytics/chorki_analytics_schema.dart \
  && grep -A2 "ChorkiAnalyticsEventType.replay => const \[" lib/src/analytics/chorki_analytics_schema.dart | grep -q "fromMs"
then pass schema_entry; else fail schema_entry; fi
added="$(git diff "$BASE_REF" --name-only --diff-filter=A -- test/scenarios)"
if [ -n "$added" ] && grep -l "replay" $added >/dev/null 2>&1
then pass scenario_added; else fail scenario_added; fi
if grep -q "ChorkiAnalyticsEventType.replay =>" lib/src/analytics/matomo/matomo_request_builder.dart
then pass matomo_mapped; else fail matomo_mapped; fi
