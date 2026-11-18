# Report replays

Product wants to know how often viewers watch a byte again.

Add an analytics event `replay` (category playback). It fires when a viewer
seeks back to the start (less than 1 s) after the video completed in the
same view. Data: `fromMs` (where the seek started, int, required).

Use the `add-analytics-event` skill. Follow CLAUDE.md's definition of done.
