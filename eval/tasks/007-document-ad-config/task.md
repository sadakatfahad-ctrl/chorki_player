# Docs: ads configuration

`ChorkiAdConfig` and `ChorkiAdMarker` have undocumented public members
(see `test/guardrails/baselines.json`, rule `dartdoc`). Document every one:
what it does, its default, and how it interacts with preload and the load
timeout. Then add a README excerpt `ads-markers` (in `example/lib/readme/`)
that shows building a custom seek bar with `ChorkiAdMarker`s, and lock in
the smaller dartdoc baseline. No behaviour change.
