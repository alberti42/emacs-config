# Commit 3 — Make IGNORE-LINE-AT-END stop at the top of TO's line

> `src/xdisp.c` and `test/src/xdisp-tests.el` · general primitive fix
> Commit: *window-text-pixel-size: stop IGNORE-LINE-AT-END at the top of TO's line*

This is the one genuine bug in a **shared C primitive**, and the commit worth
upstreaming on its own merits. It ships with an ERT regression test.

## Background: how pixel-scroll measures backward

To scroll up, `pixel-scroll-precision-scroll-up-page` asks how many pixels of
content sit just above the current `window-start`:

```elisp
(window-text-pixel-size nil (cons start (- delta)) start nil nil nil t)
;;                            └ FROM = (POS . negative offset)  └ TO = POS
;;                                                          IGNORE_LINE_AT_END ┘
```

The cons-`FROM`-with-negative-offset form is the **backward** measurement: it
walks up from `start` by `delta` pixels and returns the pixel span from there up
to `TO` (= `start`), plus the buffer position it started from. With the 7th
argument (`IGNORE_LINE_AT_END`) non-nil it returns the height of the lines
*strictly above* `TO`'s display line. pixel-scroll uses that span to decide the
new `window-start` and `vscroll`. It is the **only** in-tree caller that passes
`IGNORE_LINE_AT_END` non-nil.

## Bug

`IGNORE_LINE_AT_END` is documented to *"not add the height of the screen line
that includes TO to the returned height"* — the measurement is meant to stop at
the **top of `TO`'s display line** and report only the lines above it. It did
not stop there: it stopped at `TO` itself, so anything drawn *above* `TO`
**within that same screen line** was still counted — an overlay before-string
that starts at `TO`, or an after-string that ends at `TO`. Such a string belongs
to `TO`'s screen line, which the option is supposed to drop whole, so counting
it made the height too large. Concretely, with `window-start` on a before-string
image, a backward measurement that should be ~14 px returned ~214 px (the whole
image line).

Consequence: `scroll-up-page` set `vscroll` to ~the image height in one step,
parking the view deep inside the image; the next step re-measured the same way
and **re-snapped**, so the image was traversed twice with a visible jump
between — the "lurch" / "can't reach the top" of bug#64252. The
markdown-ts `"\n " + image` *after*-string is the worst case.

## Root cause

How did the old code get the height? It moved the iterator forward to `END` and
read `it.current_y` (the y at the line `END` lands on), with a correction block
for one awkward case: a **display property** at `END` is one atomic element, so
`move_it_to` *overshoots* (`IT_CHARPOS (it) > end`); an existing block notices
that, backs off to `end - 1`, and re-measures — so the display property is
correctly excluded.

A **before/after-string** anchored at `END` does **not** overshoot:
`move_it_to` stops *exactly* at `END` (`IT_CHARPOS (it) == end`) having already
folded the string's rows into `it.current_y`. So it slips past the overshoot
guard and is counted. This was confirmed with instrumentation:

```
display property at END:  end=1751 charpos=1752  (overshoot → handled)   height 14  ✓
before-string at END:     end=1726 charpos=1726  (no overshoot → counted) height 214 ✗
```

The deeper observation: the function was **measuring into `END`'s line and then
trying to subtract the boundary contribution back out** — first via the
overshoot/`doff` dance, and (in an earlier version of this fix) via an explicit
scan of the overlays at `END`. But the iterator already computes each display
line's top as it walks; the height we want is just *the top of `END`'s own
line*, recalled rather than recomputed. A string displayed at `END` belongs to
`END`'s line, so stopping at that line's top excludes it automatically — no
detection, no subtraction.

## Fix

Split the measurement on `IGNORE_LINE_AT_END`. The `IGNORE_LINE_AT_END` path
becomes a **single** line-by-line descent of the span that stops at the top of
`END`'s display line and reads the height from there — it *is* the measurement,
so the span is walked only once:

```c
int top_of_end_line_y = 0;
if (!NILP (ignore_line_at_end))
  {
    while (IT_CHARPOS (it) < end && it.current_y < max_y)
      {
        int prev_top = it.current_y;
        ptrdiff_t prev_pos = IT_CHARPOS (it);
        int prev_vpos = it.vpos;
        move_it_to (&it, -1, -1, -1, it.vpos + 1, MOVE_TO_VPOS);
        if (IT_CHARPOS (it) == prev_pos && it.vpos == prev_vpos)
          break;                                /* no progress (e.g. ZV) */
        if (IT_CHARPOS (it) > end)
          { it.current_y = prev_top; break; }   /* END interior to this line */
      }
    top_of_end_line_y = it.current_y;
    x = it.current_x;
  }
else
  {
    /* …unchanged stock path: x = move_it_to (&it, end, …) plus the
       overshoot/back-off block… */
  }
…
if (!NILP (ignore_line_at_end))
  y = top_of_end_line_y - WINDOW_TAB_LINE_HEIGHT (w) - WINDOW_HEADER_LINE_HEIGHT (w);
```

The `move_it_to` to `END` and its overshoot back-off now run **only** on the
non-`IGNORE_LINE_AT_END` (forward) path, which is otherwise stock upstream. The
descent runs on the live iterator (no `SAVE_IT`/`RESTORE_IT` copy and no second
pass), so the span is traversed once instead of twice. The sole caller of the
backward `IGNORE_LINE_AT_END` form (pixel-scroll) uses only the height and the
start position, so the returned width is just the x reached at `END`'s line
rather than a separate max-width walk.

> An intermediate version of this fix kept the stock `move_it_to (&it, end, …)`
> for the width and ran the descent *in addition*, on a `SAVE_IT` copy — correct,
> and behaviorally identical, but it walked the span twice (measurably slower:
> ~52 vs ~43 µs/call in a tight benchmark). Folding the height into the one walk
> removes the redundancy.

### What "`END`'s display line" means — the two cases

The loop stops at the first display line whose start position reaches `END`, and
takes that line's top:

- **A line starts exactly at `END`** → use its top. This is the boundary-string
  case: a before-string anchored at `END` opens a fresh display line *at* `END`
  (likewise an after-string whose overlay ends at `END`), so the string's rows
  sit at/below the stop and are excluded. It is also the ordinary case where
  `END` is a normal line start.
- **No line starts exactly at `END`** (the step overshoots, `IT_CHARPOS > end`)
  → `END` is interior to the line we just left (e.g. `END` is a bare newline),
  so that line's top is the answer. This keeps the no-overlay result
  **byte-identical** to the old code for every position pixel-scroll actually
  produces.

`MOVE_TO_VPOS` advances one *screen* row at a time (the idiom `move_it_to (it,
-1, -1, -1, it->vpos + 1, MOVE_TO_VPOS)` taken from `move_it_by_lines`), so
wrapped lines and image rows are each one step.

## Why recall, not rescan

An earlier version of this fix detected the boundary string explicitly —
`Foverlays_in` around `END`, matching a before-string whose overlay starts at
`END` or an after-string whose overlay ends at `END`, then taking the overshoot
back-off path and zeroing `max_ascent`/`max_descent` so the `doff` term wasn't
inflated by the string. It worked (same ERT pass, identical scroll), but it
*reconstructed*, from raw overlay geometry, a fact the iterator had already
computed while walking to `END` — and it had to special-case zero-length
overlays (which `get-char-property` cannot see) and the `doff` inflation. The
line-stepping version throws none of that away: it reuses the per-line height
the iterator accumulates, so the string never enters the measurement to begin
with. Verified equivalent to the overlay-scan version: identical batch numbers
at every realistic scroll delta and a byte-identical live scroll trajectory
through a 300 px after-string image.

## A failed approach worth not repeating

An even earlier attempt re-seeded the iterator at the new `START` in the
backward (`vertical_offset < 0`) block. That **regressed** the display-property
case (made it include the image too), because the original code already excludes
a display property correctly; re-seeding unified the two wrongly. The right fix
is confined to the `IGNORE_LINE_AT_END` height, leaving the overshoot path
untouched.

## Regression test

`test/src/xdisp-tests.el`,
`xdisp-tests--window-text-pixel-size-backward-boundary-string`:

It measures a one-pixel backward span ending at a position `TO`, first with no
overlay, then with a tall before-string and then a tall after-string anchored
at `TO` (zero-length overlay), asserting the height is **unchanged**:

```elisp
(let ((ov (make-overlay to to)))
  (overlay-put ov 'before-string "X\nY\nZ\n")
  (should (equal (nth 1 (window-text-pixel-size nil (cons to -1) to nil nil nil t))
                 h-plain))
  (delete-overlay ov))
```

With the fix the boundary string is excluded (`h == h-plain`); without it the
string's height leaks in, so the `equal` fails (`:form (equal 4 1)` on the
unpatched build) — the test genuinely catches the regression. Runs in batch:

```sh
./src/emacs -Q --batch -l ert -l test/src/xdisp-tests.el \
  --eval '(ert-run-tests-batch-and-exit "backward-boundary-string")'
```

## Why this is the upstreamable commit

`window_text_pixel_size` is the C backend of the public
`window-text-pixel-size` (and `buffer-text-pixel-size`). The fix is correct for
**any** caller of the backward `IGNORE_LINE_AT_END` form, independent of
pixel-scroll — even though pixel-scroll is effectively the only in-tree caller
of that form today. Fix + ERT test in one self-contained commit.
