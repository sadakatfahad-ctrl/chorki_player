# Refactor: extract the retry policy

The player's state (`lib/src/presentation/chorki_player_state.dart`, a
`part` of `chorki_player_widget.dart`) is over the size limit and mixes many
jobs. Extract the silent-retry policy (`_autoRetryDelays`,
`_autoRetries`, `_retryTimer`, `_onLoadFailed`'s scheduling,
`_resetRetries`) into `lib/src/presentation/player/retry_policy.dart` as a
small class with its own unit tests (using a fake timer / `fake_async`).

Behaviour must not change at all: every existing test and scenario passes
unchanged, and the public API snapshot does not change. Lock in the smaller
file-size baseline.
