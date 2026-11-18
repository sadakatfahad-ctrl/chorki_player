# Bug: "loop count keeps growing after swiping back"

From the analytics team:

> In the Bytes feed, `sessionEnd.loopCount` is wrong for a byte we come back
> to. Watch a byte until it loops once, swipe to the next, swipe back,
> watch 2 s, swipe away: that last `sessionEnd` says `loopCount: 1`. That
> view never looped. It should be 0.

Find the cause and fix it. Follow CLAUDE.md's definition of done for a bug
fix: a regression scenario and a mutant that re-introduces the bug.
