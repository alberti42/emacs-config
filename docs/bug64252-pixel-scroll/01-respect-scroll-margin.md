# Commit 1 — Respect `scroll-margin` in `pixel-scroll-precision-mode`

> `lisp/pixel-scroll.el` · +137 lines · mode-only feature
> (SHA at time of writing: `44e8ce0`)

## Problem

`pixel-scroll-precision-mode` drags point toward the window edge while
scrolling so that redisplay won't recenter the view. With a **non-zero
`scroll-margin`**, redisplay then immediately re-imposes the margin and pulls
`window-start` back — which reads as the text *snapping back* during a slow
smooth scroll. It is worst:

- near the buffer edges, where the margin cannot be honoured at all, and
- across inline images taller than the margin can fit, where the view
  oscillates.

`scroll-margin` exists for **cursor movement** (keeping context around point as
you move by line/word/search), not for wheel scrolling. So the fix is to take
it out of the way *only while the wheel is moving* and put it back once
scrolling stops.

(Historically this repo worked around the conflict in the user's config by
advising the scroll commands to zero `scroll-margin`. This commit moves that
behaviour into the mode itself, so a non-zero `scroll-margin` no longer fights
smooth scrolling out of the box.)

## What the commit adds

### Defcustoms

|Variable                                            |Default|Meaning                                                 |
|----------------------------------------------------|-------|--------------------------------------------------------|
|`pixel-scroll-precision-reposition-point`           |`t`    |After a gesture settles, move point back so it honours  |
|                                                    |       |`scroll-margin`.                                        |
|`pixel-scroll-precision-hide-cursor-while-scrolling`|`nil`  |Hide the cursor while it is pinned at the edge during a |
|                                                    |       |gesture.                                                |
|`pixel-scroll-precision-settle-delay`               |`0.18` |Seconds of idle after the last scroll event before the  |
|                                                    |       |gesture is considered finished and `scroll-margin` is   |
|                                                    |       |restored. A defcustom because the right value depends on|
|                                                    |       |what the user considers an acceptable pause for a slow  |
|                                                    |       |continuous scroll.                                      |

### Mechanism

- **`pixel-scroll-precision--begin-gesture`** is called by every scroll entry
  point (`-scroll-up`, `-scroll-down`). On the first event of a gesture it
  saves the buffer's `scroll-margin` (and whether it was buffer-local) into
  `pixel-scroll-precision--saved-margin` and sets `scroll-margin` to `0`
  buffer-locally. It records the window in
  `pixel-scroll-precision--gesture-windows` and **(re)arms a single idle
  timer** (`pixel-scroll-precision--settle-timer`) for
  `pixel-scroll-precision-settle-delay`. Because the timer is cancelled and
  re-armed on *every* event, it only fires once scrolling — including any
  momentum tail — has actually stopped.

- **`pixel-scroll-precision--settle`** runs when that timer fires: for each
  window scrolled since the last settle it restores `scroll-margin` (or kills
  the local variable if it was not buffer-local before), optionally repositions
  point to honour the margin (`--reposition-point`), and reveals the cursor if
  it had been hidden.

- **`pixel-scroll-precision--reposition-point`** moves point *inward* so it sits
  at least `margin` whole rows from either edge — but targets `margin + 1` rows,
  because a non-zero `vscroll` clips the boundary line and resting exactly
  `margin` rows in can still leave fewer than `margin` *whole* lines, which
  would make redisplay recenter.

- **`pixel-scroll-precision--point-pinned-p`** reports whether point is within
  `margin` rows of an edge — used to decide whether to hide the cursor.

The value is set buffer-locally and the timer is re-armed on every scroll
event, so `scroll-margin` cannot get stuck at `0` in normal use.

## Gotcha / known limitation

`--reposition-point` is gated on `margin > 0`. With `scroll-margin` equal to
`0`, it is a no-op — point is left wherever the scroll put it. This is by
design (there is no margin to honour), but it means the edge-case where point
sits on a tall line at a buffer edge is *not* smoothed by this commit; that is
handled (for the window) by commit 2. With a non-zero `scroll-margin` the
reposition runs and the edge case does not arise.

## Why a defcustom for the settle delay

`0.18 s` is a compromise: long enough to span the gap between discrete
trackpad events in a slow drag (so the margin is not restored mid-gesture),
short enough that point settles promptly once you stop. The acceptable value
is subjective and input-device dependent, hence a user option rather than a
constant.

## Relationship to the other commits

This commit is an independent behaviour layer. Commits 2 and 3 fix the actual
lurch/snap bugs; this one removes the `scroll-margin`-vs-smooth-scroll
friction and provides the settle/reposition infrastructure the mode now relies
on instead of external advice.
