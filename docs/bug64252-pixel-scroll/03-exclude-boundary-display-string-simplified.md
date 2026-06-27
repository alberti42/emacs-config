# Commit 3, in plain English — the tall-line measurement bug

*This is the friendly companion to
[`03-exclude-boundary-display-string.md`](03-exclude-boundary-display-string.md),
which has the full technical detail. Here the goal is just to make the problem
genuinely clear: what used to happen, what goes wrong, and how to see it for
yourself on a stock Emacs.*

## The one-sentence version

When you smooth-scroll toward a line that is much taller than a normal line —
an inline image, or an image glued on with an overlay "before/after string" —
the view jumps and snaps back instead of gliding, because a low-level
measurement routine **counts the tall thing twice**: once as the line you're
arriving at, and again as if it were sitting in the space *above* that line.

## How smooth scrolling positions the page

To show a buffer, Emacs needs two numbers:

- **`window-start`** — the buffer position of the first character drawn at the
  top of the window.
- **`vscroll`** — a fine pixel offset: "having chosen `window-start`, then nudge
  everything up by this many pixels." It's what lets a wheel gesture move the
  text by 7 pixels instead of a whole line at a time.

`pixel-scroll-precision-mode` is built on these. When you scroll up by, say, 14
pixels, it doesn't just bump `vscroll`; it figures out the *new* `window-start`
a line or two up and sets a small `vscroll` for the leftover pixels. The result
is a smooth glide where the numbers underneath are doing discrete jumps.

## The measurement it leans on

To find that new `window-start`, the mode asks one question: **"starting from
the current top of the window, how many pixels of content are in the 14 pixels
just above it, and where does that span begin?"** It asks with the built-in
function `window-text-pixel-size`, in its *backward* form:

```elisp
;; "measure the span ending at START, going back DELTA pixels"
(window-text-pixel-size nil (cons start (- delta)) start nil nil nil t)
```

Think of it as measuring the slice of text immediately **above** the current
top line. For ordinary text the answer is boring and correct: 14 pixels back is
about one line up.

## What goes wrong

Now put a tall thing right at the top of the window — concretely, the way
markdown-ts shows an inline image: an overlay whose *after-string* is
`"\n " + image`, sitting on a line. That image is **part of that line's
display** — it belongs to the line you're looking at, not to the empty space
above it.

But when the mode measures "the slice above," the buggy routine includes the
image's full height in the answer. So instead of reporting "about 14 pixels (a
normal line) above us," it reports "about 214 pixels above us." The mode
believes there's a wall of content overhead, sets a large `vscroll` to
compensate, and the view **lunges** — and because the very next measurement
makes the same mistake, it **snaps back and re-traverses the same image**. That
back-and-forth is the user-visible bug#64252: the scroll won't glide past a
tall line and, near the buffer edge, can't settle at the top.

The crucial word is *boundary*: the image is exactly **at** the edge of the
measured span (at the line the span ends on). It should count as part of that
line, but the old code folded it into the span above.

## Why the old code got it wrong (one paragraph)

`window-text-pixel-size` already knew about one kind of tall thing at the
boundary: an image attached as a `display` property on a real character. Walking
up to that character "overshoots" it, and there's existing code that notices the
overshoot and backs off, correctly leaving the image out. A *before/after
string*, though, doesn't overshoot — the walk stops exactly on the boundary
position with the string's height already added in. So it slipped past that
existing guard and got counted. The fix teaches the routine to recognise a
before/after string sitting on the boundary and back off the same way it
already did for display-property images.

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
the pixel equivalents — during development the same measurement read **214 px**
where **14 px** was correct.)

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

In `window_text_pixel_size`, after walking up to the boundary, check whether a
before-string (overlay starting there) or after-string (overlay ending there)
is anchored **on** that boundary; if so, exclude its height — exactly the
back-off already used for a display-property image. One extra detail: reset the
iterator's running ascent/descent first, so the "previous line height" it adds
back isn't itself inflated by the tall string. Full details and the diff are in
the [technical companion](03-exclude-boundary-display-string.md).
