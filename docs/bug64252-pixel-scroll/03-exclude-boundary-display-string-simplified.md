# Commit 3, in plain English — the tall-line measurement bug

*This is the friendly companion to
[`03-exclude-boundary-display-string.md`](03-exclude-boundary-display-string.md),
which has the full technical detail. Here the goal is just to make the problem
genuinely clear: what used to happen, what goes wrong, and how to see it for
yourself on a stock Emacs.*

## The one-sentence version

When you smooth-scroll up past a line that carries a tall image, the view
glides *through* the image fine — but the moment it should reveal the ordinary
line just above the image, it lurches back down onto the image instead. The
cause: a routine asked for the height of that ordinary line accidentally adds
the image's height to it, so pixel-scroll over-corrects.

## Vocabulary — the words that actually trip you up

The arithmetic in all of this is trivial. *All* the difficulty is knowing **what
kind of thing** each name refers to. There are only three kinds:

- **Buffer position** — a character offset ("character #1500"). Says *which
  character*; nothing about pixels.
- **Horizontal pixels (x)** — distance *across* a line.
- **Vertical pixels (y)** — distance *down* the window. y grows **downward**;
  y = 0 is the top of the window.

Tag every name below with one of those three and the code reads itself:

- **`window-start`** — a *buffer position*: the first character painted at the
  **top of the window**. It names where the visible region begins. `(window-start)`
  returns it; scrolling changes it.
- **`vscroll`** — *vertical pixels*: a fine offset layered on top of
  `window-start` — "having put `window-start` at the top, now hide this many
  pixels off the top." It's what lets a wheel gesture move 7 px instead of a
  whole line.
- **a line's top / bottom / height** — every displayed line occupies a vertical
  band: its **top** is the upper y, its **bottom** the lower y, its **height** the
  difference. "`window-start`'s line top" = the upper edge of the line that
  `window-start` sits in (≈ the top edge of the window).
- **END** — **not** "end of buffer." It's the bottom position of *this one
  measurement* — the buffer position the measurement stops at. In our case
  **END = `window-start`**. (In the C code it's the variable `end`; same thing.)
- **`ignore-line-at-end`** — a flag on the measurement. When on, it stops at the
  **top** of END's line instead of its bottom — i.e. it counts only the lines
  *strictly above* END's line, not END's own line. (Its docstring promises
  exactly this: *"do not add the height of the screen line that includes
  END."*) We turn it on because we want the height of what sits *above* the
  current top line, not the top line itself. The bug below is simply that the
  old code did not keep that promise.

## How smooth scrolling positions the page

To show a buffer, Emacs uses two numbers:

- **`window-start`** — the buffer position of the first character at the top of
  the window.
- **`vscroll`** — a pixel offset applied on top: "having placed `window-start`
  at the top, hide this many pixels off the top." It's what lets a wheel gesture
  move by 7 pixels instead of a whole line.

`pixel-scroll-precision-mode` deliberately keeps **`vscroll` as small as
possible**: it puts `window-start` at the buffer position *closest to* the top
of what's visible and uses `vscroll` only for the leftover pixels. Hold onto
this — it's why the bug appears exactly where it does.

So one wheel-up event does one of two things:

- **a vscroll nudge** — `window-start` stays put, `vscroll` just drops by a few
  pixels (cheap, nothing is measured); or
- **a line change** — `vscroll` has run out, so `window-start` has to move up to
  an earlier buffer position. *This* is the only case that measures, and the
  only case that can go wrong.

## The measurement (only on a line change)

When `window-start` must move up, the mode asks: **"how tall is the line
immediately above the current top?"** — so it knows how far to move and how much
`vscroll` to set. It asks `window-text-pixel-size` in its *backward* form:

```elisp
;; height of the span ending at the current top (START), going back DELTA px
(window-text-pixel-size nil (cons start (- delta)) start nil nil nil t)
```

Under the hood that height is just a **difference between two buffer
positions**: find where the previous line starts, and measure the pixels from
there up to `START`. For ordinary lines it's exactly one line's height.

(Historical aside: this backward form and its `ignore-line-at-end` flag were
both added to Emacs in December 2021 *solely* to power this one pixel-scroll
function — and it's still their only user. That's why a bug in them could sit
unnoticed for years: only one place ever exercises this path, and only when a
tall image happens to land on the top line.)

## That call, argument by argument

`window-text-pixel-size` is a general function with several modes depending on
how you *shape* its arguments — its elisp docstring covers all of them. Only one
shape concerns us, so here is just that one, decoded. The signature is:

```elisp
(window-text-pixel-size WINDOW FROM TO X-LIMIT Y-LIMIT MODE-LINES IGNORE-LINE-AT-END)
;; our call:
(window-text-pixel-size nil    (cons start (- delta))
                                     start  nil     nil     nil        t)
```

- **WINDOW = `nil`** — use the selected window.
- **FROM = `(cons start (- delta))`** — *this cons shape is the crux.* A plain
  position would mean "start measuring exactly there." The cons `(POS . OFFSET)`
  instead means "go to POS, then shift `OFFSET` pixels *first*, and measure from
  there." Our `OFFSET` is `(- delta)` — negative, so **move up `delta` pixels**
  before measuring. FROM is therefore "the point `delta` pixels above `start`."
- **TO = `start`** (= `window-start`) — measure *up to* the current top. This is
  the **END** from the vocabulary. So the span runs from "`delta` px above the
  top" down to "the top."
- **X-LIMIT = `nil`** — don't cap (or compute toward) a width limit.
- **Y-LIMIT = `nil`** — don't cap the height.
- **MODE-LINES = `nil`** — don't add mode-line / header-line / tab-line heights.
- **IGNORE-LINE-AT-END = `t`** — stop at the **top** of END's line; count only
  what's strictly above it (see vocabulary). This is the argument the whole bug
  hinges on.

What it returns, *for this cons-FROM shape*, is a three-element list
`(WIDTH HEIGHT POSITION)`:

- **WIDTH** — *horizontal pixels*; we ignore it.
- **HEIGHT** — *vertical pixels*: the span we asked for (how far the top will
  rise). **This is the number the bug corrupts.**
- **POSITION** — a *buffer position*: the character the "up `delta` pixels" walk
  landed on. pixel-scroll uses it directly as the new `window-start`.

(That third value, POSITION, only exists *because* FROM was a cons. With a plain
FROM the function returns just `(WIDTH . HEIGHT)` — a two-element cons, no
position. The cons-FROM is what both shifts the start *and* reports where it
landed.)

## What goes wrong — a worked example

Take a line that carries a markdown-style inline image: the image is an overlay
**after-string** (`"\n " + image`), so it renders *below* the line's own text.
With a 14px text line and a 300px image, the display reads top-to-bottom:

```
line 19 text          14px
[ image ]            300px      ← after-string, anchored at E19 (end of line 19)
line 20 text
```

Scroll up toward this from below. Because the mode keeps `vscroll` small, once
the image reaches the top it parks **`window-start` at the image's anchor
`E19`** and slides `vscroll` *through* the image:

```
window-start = E19,  vscroll = 300 … 200 … 100 … 0     ← pure vscroll nudges, smooth
```

Every one of those is a vscroll nudge — nothing measured, no problem. When
`vscroll` reaches **0**, the image's top sits exactly at the window top, and the
only thing still above the window is line 19's 14px of **text**.

Now one more wheel-up (say 5px). `vscroll` is already 0 — nothing left to nudge
— so `window-start` **must move up**, from `E19` to the start of line 19
(`S19`). That's the line-change path, so it measures "the line above `E19`":

- it should be just **line 19's text = 14px**;
- but the image is anchored *exactly at `E19`*, the boundary the measurement
  walks up to, so the routine paints the image too and returns **14 + 300 =
  314px**.

Feed each into the scroll arithmetic (`vscroll = height − scrolled`):

| | height | new `window-start` | `vscroll` | what shows at the top |
|---|---|---|---|---|
| correct | 14 | S19 | 14 − 5 = **9** | bottom 5px of line-19 text ✓ |
| buggy | 314 | S19 | 314 − 5 = **309** | 14 + 295 → back *inside* the image ✗ |

So instead of revealing 5px of line-19 text, the oversized `vscroll = 309` drops
you 295px back down into the image — the **lurch**. The next wheel-up repeats it,
so you can never climb past the image.

The essence in one line: **a line's start position normally marks the top pixel
of that line — but once an image is anchored at that boundary, the
"previous-line height" measurement swallows the image, even though the image
belongs to the line you're sitting on, not to the line above.**

Two things worth keeping straight:

- **Only the step that *leaves* the anchored boundary misbehaves.** `S19 → S18`,
  `S18 → S17`, … each measure up to a plain line start with nothing anchored on
  it, and are perfectly correct. The single poisoned moment is `E19 → S19`.
- **Before-string and after-string are the same bug, symmetric.** A before-string
  is drawn at its overlay's *start*, an after-string at its overlay's *end* — so
  whenever either anchor is the boundary, the string is drawn *at* the boundary,
  regardless of the range the overlay spans. The markdown-ts case only *looks*
  lopsided because its leading `"\n "` pushes the image visually below the text;
  the anchor is still the boundary. That's why the fix treats them alike: a
  before-string whose overlay *starts* at the boundary, or an after-string whose
  overlay *ends* at it.
- **It isn't really about images.** Any overlay string taller than a normal line
  over-counts — several rows of text, or text enlarged with a face `:height`,
  not just an image. We use an image here because it's the most vivid case (and
  the one that actually bit us); the regression test below deliberately uses a
  plain three-line string to prove the bug is general. What's over-counted is
  simply the string's own height, whatever made it tall.

## Why "overshoot" is the heart of it

The old code already handles a *display-property* image correctly, and seeing
**why** pinpoints exactly what it misses.

To reach a buffer position, the display walker has to actually *draw* whatever is
there. A `display` property **replaces** a stretch of characters with one
indivisible image, so the positions hidden under that image have no spot of their
own to stop on. Ask the walker to reach one of them and it has to draw the whole
image and land *past* it — on the next line. (You can watch the same thing with
the cursor: press the right-arrow through an image and it jumps from just-before
to just-after; it can never sit *inside*.) "Landed past where I asked" is the
tell, and the old code — Eli Zaretskii's 2018 fix — watches for it: when it sees
the overshoot, it steps back to just before the image and leaves it out.

An overlay before/after-string is the **opposite kind** of thing. It *adds* an
extra string at the boundary and replaces nothing, so the boundary position still
has its own spot. The walker stops *exactly* there — no landing past, no tell —
even though it has already drawn the tall string on the way down. So the old
"did we land too far?" check never fires, and the string's height rides along
uncaught.

That single asymmetry is the entire bug: **replace** (the walk overshoots, the
2018 code catches it) versus **add** (the walk doesn't overshoot, so nothing
catches it). The 2018 code excludes what the boundary line *replaces*; this fix
excludes what it *adds*; together they drop the whole boundary line — which is
all `ignore-line-at-end` ever promised.

## Why the old code got it wrong (one paragraph)

Remember the promise: with `ignore-line-at-end` on, the measurement must stop at
the **top** of END's line and leave that whole line out. The old code instead
got the height by walking *to* the boundary and reading off how far
down it had travelled — then patching up the one case it knew about (the
overshoot above). The deeper problem is that the code was measuring *into* the
boundary line and then subtracting afterwards at all. The display engine already
records where each line begins, so the height wanted is just the top of the
boundary line, recalled rather than recomputed.

## Can you reproduce it on a stock Emacs? Yes.

This is a bug in the stock C function `window_text_pixel_size`, so any unpatched
Emacs shows it — you do **not** need any of this repo's pixel-scroll changes.
Here is the smallest reproduction; it runs in batch, no GUI required. Paste it
into a file or run it inline against a stock `emacs`:

```elisp
;; Measure a one-line-tall slice ending at line 4, with nothing special there,
;; then again with a 3-line string glued onto that exact spot.  The string is
;; displayed AT line 4, so it must NOT change "the slice above line 4".
(with-temp-buffer
  (dotimes (i 8) (insert (format "line %d\n" i)))
  (switch-to-buffer (current-buffer))
  (let* ((to (save-excursion (goto-char (point-min)) (forward-line 4) (point)))
         (plain (nth 1 (window-text-pixel-size nil (cons to -1) to nil nil nil t))))
    (let ((ov (make-overlay to to)))
      (overlay-put ov 'before-string "X\nY\nZ\n")
      (princ (format "plain=%s  with-tall-string=%s\n"
                     plain
                     (nth 1 (window-text-pixel-size nil (cons to -1)
                                                    to nil nil nil t)))))))
```

```sh
emacs -Q --batch --eval "$(cat that-file.el)"     # or -l that-file.el
```

**Confirmed results** (run during this work):

| build | output | meaning |
|-------|--------|---------|
| **unpatched** | `plain=1  with-tall-string=4` | the 3-line string leaked into the "above" slice (1 → 4) — **bug** |
| **patched**   | `plain=1  with-tall-string=1` | the boundary string is excluded — **fixed** |

(The numbers are in character-cell units in batch; in a real GUI frame they're
the pixel equivalents — e.g. with the 300px image of the worked example above, a
slice that should measure **14 px** comes back as **314 px**.)

The project's regression test is exactly this comparison. On the unpatched
binary it fails, naming the wrong value outright:

```
FAILED  xdisp-tests--window-text-pixel-size-backward-boundary-string
   (should (equal … h-plain)) :form (equal 4 1) :value nil
```

### Seeing the *visible* lurch (interactive, stock)

If you want to watch the symptom rather than the measurement, on a stock GUI
Emacs:

1. `M-x pixel-scroll-precision-mode`
2. Open any long buffer and, on some line partway down, attach a tall image via
   an overlay after-string (the markdown-ts idiom):
   ```elisp
   (let ((ov (make-overlay (line-end-position) (line-end-position))))
     (overlay-put ov 'after-string
                  (concat "\n " (propertize " " 'display
                                            (create-image "/path/to/some.png")))))
   ```
3. Scroll **up** with the trackpad so that image rises toward the top of the
   window. Instead of gliding past, the view jumps onto the image and snaps
   back — you can't smoothly carry it off the top.

(Stock Emacs additionally has the separate "can't reach the very top" lurch that
commits 1–2 address; the snap/re-traversal over the image is this commit's bug.)

## The fix in a nutshell

The height the code wants — "everything above END's line" — is something the
display engine already computes as it walks the buffer: the top position of each
display line. So instead of measuring *into* END's line and then subtracting the
boundary string back out, `window_text_pixel_size` now steps down toward END one
display line at a time and stops at the **top of END's own line**. A string
shown at END belongs to END's line, so stopping at that line's top leaves it out
automatically — no scanning for overlays, no special-casing. Full details and
the diff are in the [technical companion](03-exclude-boundary-display-string.md).

## Why not just measure to END and subtract the string?

The obvious quick fix is to keep the old "walk all the way to END" measurement —
which gives the inflated 314 px — and then subtract the 300 px the string added.
It works, but it's the wrong shape, for two reasons:

- **You'd have to hunt for the string first.** To subtract its height you must
  first recognise that there *is* something at END, and exactly which kind: a
  before-string whose overlay *starts* at END, an after-string whose overlay
  *ends* at END, or a zero-length overlay (which the ordinary
  `get-char-property` lookups can't even see) — and a `display` *property* is
  yet another case again. Each needs its own handling. That is the brittle
  "scan every overlay at END" code we deliberately threw out.
- **You'd be recomputing a number Emacs already had.** On its way down, the
  display engine passes the top of END's line — at that instant it already knows
  the height of everything above END's line, which is the exact number we want.
  The subtract route throws that away, deliberately overshoots into END's line,
  and then reconstructs the part it overshot. Stopping at the top of END's line
  instead just *reads back* the number that was already there.

So the fix isn't "measure, then correct" — it's "stop before there is anything
to correct." No string detection, no height recomputation, and nothing for an
unforeseen overlay shape to slip through.
