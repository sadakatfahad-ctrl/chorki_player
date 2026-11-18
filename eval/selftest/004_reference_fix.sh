# Reference solution for task 004, used to prove the harness scores a correct
# fix as passing (run from the task worktree).
set -e
python3 - <<'PY'
import pathlib
p = pathlib.Path("lib/src/analytics/chorki_analytics_session.dart")
s = p.read_text()
s = s.replace("    _firstFrameAt = null;\n    _lastSeekAt = null;\n    _pauseCount = 0;",
              "    _firstFrameAt = null;\n    _lastSeekAt = null;\n    _loopCount = 0;\n    _pauseCount = 0;", 1)
p.write_text(s)
m = pathlib.Path("tool/mutants.yaml")
m.write_text(m.read_text() + '''- id: session.loopCountLeaks
  why: the loop count of a swiped-away view leaked into the next one
  file: lib/src/analytics/chorki_analytics_session.dart
  find: "    _loopCount = 0;\\n    _pauseCount = 0;"
  replace: "    _pauseCount = 0;"
  tests: [test/scenarios]
''')
pathlib.Path("test/scenarios/033_loop_count_after_swipe.yaml").write_text('''name: loop_count_after_swipe
description: "regression: a revisited view inherited the previous view's loopCount"
given: {duration: 10s}
steps:
  - bind
  - value: {initialized: true}
  - activate
  - play: {to: 9.8s}
  - wrap
  - deactivate: swipedAway
  - activate
  - play: {to: 2s}
  - deactivate: swipedAway
expect:
  mode: subsequence
  events:
    - sessionEnd: {reason: swipedAway, loopCount: 1}
    - impression: {$session: $c}
    - sessionEnd: {reason: swipedAway, loopCount: 0, $session: $c}
''')
c = pathlib.Path("CHANGELOG.md")
s = c.read_text()
s = s.replace("### Fixed\n\n", "### Fixed\n\n- The loop count no longer leaks into a revisited view.\n", 1)
c.write_text(s)
PY
