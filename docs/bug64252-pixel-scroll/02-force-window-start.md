# Commit 2 — Force the window start in pixel-scroll-precision page scrolling

> `lisp/pixel-scroll.el` · mode-only fix
> Commit: *Force the window start in pixel-scroll-precision page scrolling*

## Problem

`pixel-scroll-precision-scroll-up-page` and `-scroll-down-page` set the window
start with **`NOFORCE` non-nil** whenever a `vscroll` remained. `NOFORCE` tells
redisplay it may *disregard* the requested start if honouring it would leave
point invisible, and choose its own start instead.

Across a display line **taller than the scroll step** (an image, or an
after-string image) the requested start plus `vscroll` genuinely cannot keep
point visible, so redisplay threw the start away and **jumped the window to the
buffer edge** — the scroll lurched and could not reach the top (bug#64252,
"Problem #2" in the investigation).

There was a second instance of the same root cause **at the very top of the
buffer**: when the backward measurement could no longer advance,
`-scroll-up-page` signalled `beginning-of-buffer` *without setting the window
start at all*, leaving the previous, non-forced start in place. With point on a
line too tall to fit at the buffer's start, redisplay then recomputed the start
to keep point visible, yanking the view back down so the top could never be
reached.

## Fix

1. **Force the start** (`set-window-start … nil`, i.e. `NOFORCE` nil) on both
   page functions. Redisplay then honours the start and keeps the `vscroll`
   (preserved via `set-window-vscroll`'s `PRESERVE-VSCROLL` argument).

2. **Force the start at the top too**, before signalling `beginning-of-buffer`:

   ```elisp
   (when (or (not position) (eq position start))
     (set-window-start nil start nil)          ; <- added
     (signal 'beginning-of-buffer nil))
   ```

3. **Keep the hand-rolled point repositioning** that rides point at the window
   **edge** when it would scroll off-screen (the `(unless
   (pos-visible-in-window-p (point)) …)` blocks, plus the bottom-edge target
   computed via `posn-at-x-y` at the top of `-scroll-up-page`). See the
   regression note below — this is the crucial subtlety.

Net change versus the prior (pre-fix) code is essentially just
`NOFORCE → FORCE` on `set-window-start` plus the top-of-buffer force; the point
motion is unchanged.

## Regression that this commit was corrected for (important)

The **first** version of this commit also *deleted* the manual point
repositioning, on the theory that a forced start makes redisplay reposition an
off-screen point by itself. That theory was wrong in a damaging way:

- `force_start` **does** reposition an off-screen point — but to the **middle**
  of the window (a recenter).
- The hand-rolled motion instead pins point to the window **edge**, so point
  rides the boundary as the window scrolls past it.

With the point motion removed, the cursor **teleported to mid-window** the
instant it would scroll off an edge — a regression that only showed up after
rebuilding (no config change), exactly matching the user's report.

It was missed initially because every bug#64252 reproduction had point either
*on the tall image* (partially visible, so `force_start` left it alone) or
*parked far from the scrolled region*, and the traces watched
`window-start`/`vscroll` while collapsing point-unchanged rows — so point's
**row** in ordinary text was never plotted. An A/B confirmed it:

```
pre-fix point motion:  ws=16 pt=16 row=0  ws=17 pt=17 row=0 …   rides the edge
force_start only:      ws=16 pt=32 row=16                        jumps to middle
```

The committed version keeps the point motion; its message says so explicitly.

**Lesson:** when changing scroll/point code, test the **point row** trajectory
in plain text, and verify interactively (batch `redisplay t` does not reproduce
the interactive point-visibility recenter).

## Verification

With the fix loaded (reload `lisp/pixel-scroll.el`, no rebuild needed for the
Lisp commits):

- **Edge-riding:** scrolling so point leaves an edge keeps it at `row 0`
  (top) / last row (bottom), never mid-window.
- **Lurch / reach-top:** scrolling up onto a tall line snaps `vscroll` once and
  crawls through; the window reaches `ws=1` and stays (repeated
  `beginning-of-buffer`), no bounce.
- **No oscillation** between the image line and the line below it.

## Why `NOFORCE` was there originally

Forcing the start runs redisplay's `force_start` path on every scroll step,
which fires `window-scroll-functions` each step (the `NOFORCE` path did not).
That is the likely reason the original author chose `NOFORCE`; it is a possible
perf/behaviour consideration to note when upstreaming, but the lurch it caused
is the worse problem.
