# Behaviour scenarios

Each `*.yaml` file here is one executable spec of what the analytics engine
reports for a viewing timeline. `scenario_runner_test.dart` runs every file
against the real `ChorkiAnalyticsSession` with a fake clock and a fake video,
and checks the exact events (and, optionally, the Matomo requests).

**Rules:**
- Every `ChorkiAnalyticsEventType` must appear in at least one scenario's
  `expect.events` (enforced).
- A behaviour change comes with a scenario.
- A bug fix comes with a scenario named after the bug, with
  `description: "regression: ..."`, and with a mutant in `tool/mutants.yaml`
  that re-introduces it.
- Expected values come from the requirement, not from copying the current
  output. If they disagree, find out which one is wrong.

## Format

```yaml
name: feed_swipe_away            # unique, snake_case
description: one sentence         # shown as the test name
given:
  duration: 20s                   # media duration
  analytics: {segmentLength: 5s, newSessionOnLoop: true, consentGranted: true, enabled: true}
  metadata: {contentId: c1, title: Title}
  matomo: {naming: chorkiLegacy, mediaAnalytics: true}
  throwingSink: false             # add a sink that throws on every event
steps:
  - bind                          # follow the fake video
  - value: {initialized: true, playing: false, buffering: false, position: 0s,
            completed: false, volume: 1.0, speed: 1.0, error: null}
  - activate                      # on screen / deactivate: swipedAway|disposed|sourceChanged|looped
  - advance: 300ms                # move the clock only
  - play: {to: 7s, step: 500ms}   # real playback: clock and position move together
  - wrap: 200ms                   # a looping video jumps back to 0.2 s
  - seek: {to: 15s, source: scrub}
  - heartbeat                     # a timed heartbeat
  - scrubStart / scrubCancel / loadStart / loadRunning / loaded / settingsOpen
  - error: {code: videoLoad, stage: load, statusCode: 503, willRetry: true}
  - retry: {attempt: 1, auto: true}
  - consent: false                # / enabled: false
  - adBreakStart / adBreakEnd
  - ad: {type: adStart, data: {adId: a1}}
  - speedChange: {from: 1.0, to: 1.5}
  - boostStart: 2.0 / boostEnd
  - quality: {from: 1080, to: 720, bitrate: 2500000, label: 720p}
  - audio: {from: en, to: bn}
  - fit: fill / pip: enabled
  - appHidden                     # the app goes to the background
expect:
  mode: exact                     # exact (default): these events and no others
                                  # subsequence: in this order, others allowed
  events:
    - impression: {$session: $a}  # $a binds a view id; a new alias must be a new id
    - play: {timeToPlayMs: 300}
    - sessionEnd: {watchedPercent: ">=30", dwellMs: "~7300", detail: absent, label: $any}
  never: [pause]                  # must not appear at all
  matomo:                         # requests, in order, as a subsequence
    - {ma_id: view1, ma_st: "0", e_c: absent}
  diagnostics: [analytics.sink]   # ChorkiDiagnostics contexts, exactly
```

Pseudo-keys: `$session` (view id), `$position` and `$watched` (seconds).
Matchers: a literal, `">=N"`, `"<=N"`, `">N"`, `"<N"`, `"~N"` (within 1),
`absent`, `$any`. View ids are `view1`, `view2`, ... in creation order.

When a scenario fails, the test output lists the actual events and Matomo
requests, ready to compare with the expectation.
