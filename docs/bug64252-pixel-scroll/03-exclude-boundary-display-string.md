# Commit 3 — Exclude a display string anchored at window-start from backward span

> `src/xdisp.c` (+44/−2) and `test/src/xdisp-tests.el` (+30) · general primitive fix
> (SHA at time of writing: `06eca78`)

This is the one genuine bug in a **shared C primitive**, and the commit worth
upstreaming on its own merits. It ships with an ERT regression test.

## Background: how pixel-scroll measures backward

To scroll up, `pixel-scroll-precision-scroll-up-page` asks how many pixels of
content sit just above the current `window-start`:

```elisp
(window-text-pixel-size nil (cons start (- delta)) start nil nil nil t)
;;                            └ FROM = (POS . negative offset)  └ TO = POS
```

The cons-`FROM`-with-negative-offset form is the **backward** measurement: it
walks up from `start` by `delta` pixels and returns the pixel span from there up
to `TO` (= `start`), plus the buffer position it started from. pixel-scroll uses
that span to decide the new `window-start` and `vscroll`.

## Bug

When `start` (= `TO`) sits on a line whose **leading display string** is tall,
the backward measurement counts that string's height as part of the span
*above* `TO`, even though the string is displayed **at** `TO` (inside the
window), not above it. Concretely, with point/`window-start` on a
before-string image, a backward measurement of ~14 px returned ~214 px (the
whole image line).

Consequence: `scroll-up-page` set `vscroll` to ~the image height in one step,
parking the view deep inside the image; the next step re-measured the same way
and **re-snapped**, so the image was traversed twice with a visible jump
between — the "lurch" / "can't reach the top" of bug#64252. The
markdown-ts `"\n " + image` *after*-string is the worst case (it adds a second
tall phantom line).

## Root cause — the discriminator

The function already handles a **display property** at `TO`: such a property is
one atomic element, so `move_it_to` *overshoots* (`IT_CHARPOS (it) > end`), and
an existing block backs off to `end - 1` and accounts for it manually — so the
display property is correctly excluded.

A **before/after-string** anchored at `TO` does **not** overshoot:
`move_it_to` stops *exactly* at `END` (`IT_CHARPOS (it) == end`) having already
folded the string's height into `it.current_y`. So it slips past the
overshoot guard and is counted. This was confirmed with instrumentation:

```
display property at END:  end=1751 charpos=1752  (overshoot → handled)   height 14  ✓
before-string at END:     end=1726 charpos=1726  (no overshoot → counted) height 214 ✗
```

## Fix

In `window_text_pixel_size`, after the forward `move_it_to` to `END`, when it
stopped exactly at `END`, scan the overlays around `END` for a boundary string
and, if present, take the **same back-off path** the overshoot case uses:

```c
bool string_at_end = false;
if (IT_CHARPOS (it) == end)
  {
    Lisp_Object ovs = Foverlays_in (make_fixnum (max (BEGV, end - 1)),
                                    make_fixnum (min (ZV, end + 1)));
    for (; CONSP (ovs); ovs = XCDR (ovs))
      {
        Lisp_Object ov = XCAR (ovs);
        if ((XFIXNUM (Foverlay_start (ov)) == end
             && !NILP (Foverlay_get (ov, Qbefore_string)))
            || (XFIXNUM (Foverlay_end (ov)) == end
                && !NILP (Foverlay_get (ov, Qafter_string))))
          { string_at_end = true; break; }
      }
  }
if (IT_CHARPOS (it) > end || string_at_end)   /* was: IT_CHARPOS (it) > end */
  { … existing back-off (end--, RESTORE_IT, re-measure) … }
```

Two non-obvious details:

1. **`Foverlays_in`, not `get-char-property`.** These strings commonly live on
   **zero-length** overlays (`make-overlay P P`), which `get-char-property`
   cannot see (an empty overlay covers no position). `overlays-in` does
   include empty overlays located at the range bounds.

2. **Reset `max_ascent`/`max_descent` before the re-measure** in the
   string-at-end case:

   ```c
   if (string_at_end)
     it.max_ascent = it.max_descent = 0;
   ```

   The back-off block's `doff` term ("height of the previous line") is computed
   from `max (it.max_ascent, it.ascent) + max (it.max_descent, it.descent)`.
   After `RESTORE_IT`, those still carried the tall string's dimensions (e.g.
   100/100), so `doff` came out as the *image* height (200) instead of the real
   previous line (14) — which made the after-string fix look like a no-op until
   this reset was added.

## The anchoring conditions, precisely

- **before-string:** displayed before its overlay's *start*; it leaks into the
  span when `overlay-start == END`.
- **after-string:** displayed after its overlay's *end*; it leaks in when
  `overlay-end == END` (the after-string's own charpos is `END`, so reaching
  `END` renders it).

(A first attempt checked `overlay-end == END-1` for the after-string — that is
the *legitimate first-snap* measurement from the line below, where the 214 px
height is correct; checking `== END` is what isolates the re-snap.)

## A failed approach worth not repeating

An earlier attempt re-seeded the iterator at the new `START` in the backward
(`vertical_offset < 0`) block. That **regressed** the display-property case
(made it include the image too) because the original code already excludes a
display property correctly; re-seeding unified the two wrongly. The right fix
is the narrow `END`-boundary exclusion above.

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

With the fix the boundary string is excluded (`h == h-plain`, 14); without it
the string's height leaks in (~56), so the `equal` fails — the test genuinely
catches the regression. Runs in batch:

```sh
./src/emacs -Q --batch -l ert -l test/src/xdisp-tests.el \
  --eval '(ert-run-tests-batch-and-exit "backward-boundary-string")'
```

## Why this is the upstreamable commit

`window_text_pixel_size` is the C backend of the public
`window-text-pixel-size` (and `buffer-text-pixel-size`). The fix is correct for
**any** caller of the backward form, independent of pixel-scroll — even though
pixel-scroll is effectively the only in-tree caller of that form today. Fix +
ERT test in one self-contained commit.
