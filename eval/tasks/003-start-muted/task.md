# Start muted

Feeds in the Chorki app autoplay, and many viewers scroll with the sound off.

Add `ChorkiPlayer(muted: false)` (both constructors). When true, the video
starts with volume 0. Changing it on a mounted player applies at once.
Turning it off restores volume 1. The initial mute is not a viewer
action, so it must not produce a `volumeChange` analytics event; a later
change does.

Use the `add-player-option` skill. Follow CLAUDE.md's definition of done.
