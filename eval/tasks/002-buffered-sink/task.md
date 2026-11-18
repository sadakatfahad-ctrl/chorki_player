# A batching callback sink

Hosts that forward analytics to their own backend want fewer calls.

Add a public `ChorkiBufferedAnalyticsSink` (in `lib/src/analytics/`,
exported) with constructor
`ChorkiBufferedAnalyticsSink({required void Function(List<ChorkiAnalyticsEvent>) onBatch, int batchSize = 20})`.
It buffers events and calls `onBatch` when `batchSize` events are waiting
and on `flush()` (with what is waiting, never with an empty list). After
`onConsentRevoked()` buffered events are dropped. It must pass
`analyticsSinkConformance` from `package:chorki_player/chorki_player_testing.dart`.

Follow CLAUDE.md's definition of done.
