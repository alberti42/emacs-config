# Git-gutter TTY: visual-line wrapping and beyond-EOB gutter fill

This note documents two separate fixes made to improve `git-gutter` in terminal
Emacs.

---

## Part 1 — Visual-line continuation rows

### Symptom

On a single *buffer line* displayed as multiple *visual lines* (soft-wrap),
the TTY git-gutter indicator (`▐`) appeared only on the first visual row. The
continuation rows showed the buffer background instead of the gutter background.

### Root cause: overlay placement

Git-gutter places zero-length overlays at each buffer line start with a
`before-string` that puts a sign in the left margin.  A zero-length overlay
only fires at one point; it has no way to inject content on continuation rows.

Attempts to enumerate visual row starts with `vertical-motion` are unreliable:
`vertical-motion` lands at the last character of the current screen row, not
the start of the next one, and `visual-wrap-prefix-mode` shifts row boundaries
in ways `vertical-motion` does not account for.

### Fix: `wrap-prefix` on a spanning overlay

The `wrap-prefix` overlay property is fired by the Emacs display engine at the
start of every continuation row for the overlay's extent.  By making the
overlay span from `bol` to `eol` (instead of being zero-length), and setting
`wrap-prefix` to the same margin string as `before-string`, the sign appears on
every visual row of a hunk line with a single overlay.

**Changes to `git-gutter.el`:**

`git-gutter:wrap-prefix-for-sign` — removed the `(stringp existing)` guard;
always returns a wrap-prefix string, prepending the gutter sign to any existing
`wrap-prefix` text property (from `visual-wrap-prefix-mode`):

```elisp
(defun git-gutter:wrap-prefix-for-sign (sign pos)
  (let ((existing (get-text-property pos 'wrap-prefix)))
    (concat (git-gutter:before-string sign) (or existing ""))))
```

`git-gutter:put-signs` — overlay spans `pos` to `eol` in TTY + visual-line
mode, so `wrap-prefix` fires on every continuation row:

```elisp
(let* ((eol (when (and git-gutter:visual-line (not (display-graphic-p)))
              (save-excursion (goto-char pos) (line-end-position))))
       (ov (make-overlay pos (or eol pos)))
       (gutter-sign (git-gutter:before-string sign)))
  (overlay-put ov 'before-string gutter-sign)
  (when eol
    (overlay-put ov 'wrap-prefix (git-gutter:wrap-prefix-for-sign sign pos)))
  (overlay-put ov 'git-gutter t))
```

`view-set-overlays` and `view-for-unchanged` — removed the `move-fn` selection;
both always walk with `forward-line`.  Visual row enumeration is no longer
needed because the display engine handles continuation rows via `wrap-prefix`.
`git-gutter:next-visual-line` was removed entirely.

### Design rationale

The gutter sign repeats on every visual row of a hunk line, consistent with how
Emacs presents visual lines:

- `display-line-numbers`: shows the number on the first row, blank on
  continuations.
- `visual-wrap-prefix-mode`: repeats the indentation prefix on every
  continuation row.
- git-gutter (after fix): repeats `▐` on every visual row — the change spans
  the entire visible extent of the logical line.

---

## Part 2 — Beyond-end-of-buffer gutter strip

### Symptom

The left-margin column (gutter) had the correct background on rows with buffer
content, but showed the raw terminal background on all rows beyond the end of
the buffer.

### Root cause: two separate issues

**A. `extend_face_to_end_of_line` not called for beyond-EOB rows**

In `display_line` (`xdisp.c`), when `get_next_display_element` returns false
(iterator at ZV), the code sets `row->ends_at_zv_p = true` and calls
`extend_face_to_end_of_line` only for RTL rows or rows with a remapped default
face.  For normal LTR rows with the default face, `extend_face_to_end_of_line`
was skipped — so the left margin was never filled for those rows.

**B. `extend_face_to_end_of_line` did not fill the left margin with the right color**

Even when called, the function did not fill the left-margin area with the gutter
background.

### Fix: patch `xdisp.c`

Two changes to `display_line` in `xdisp.c`:

**1. Call `extend_face_to_end_of_line` for any row with a left margin**

```c
if (row->reversed_p
    || lookup_basic_face (it->w, it->f, DEFAULT_FACE_ID) != DEFAULT_FACE_ID
    || WINDOW_LEFT_MARGIN_WIDTH (it->w) > 0)
  extend_face_to_end_of_line (it);
```

**2. Fill empty left-margin columns using the `line-number` face**

In `extend_face_to_end_of_line` (TTY path), when the left margin has fewer
glyphs than its declared width, fill the remaining columns with the `line-number`
face:

```c
int margin_fill_face_id =
    merge_faces (it->w, Qline_number, 0, DEFAULT_FACE_ID);

if (WINDOW_LEFT_MARGIN_WIDTH (it->w) > 0
    && it->glyph_row->used[LEFT_MARGIN_AREA] < WINDOW_LEFT_MARGIN_WIDTH (it->w)
    && !it->glyph_row->mode_line_p
    && (face->background != FRAME_BACKGROUND_PIXEL (f)
        || FACE_FROM_ID (f, margin_fill_face_id)->background
           != FRAME_BACKGROUND_PIXEL (f)))
  { /* fill left margin with margin_fill_face_id */ }
```

### Why `line-number` face and not a separate variable

`display-line-numbers` fills every screen row (including beyond-EOB) via
`maybe_produce_line_number`, which runs inside the C display loop and actively
produces glyphs with the `line-number` face.  Git-gutter, being Lisp overlays
tied to buffer positions, cannot do the same — beyond-EOB rows have no buffer
positions, so no overlay fires there.

The `line-number` face is already the semantic owner of "gutter column
background": users set its background to match the terminal border color
(e.g. WezTerm's Catppuccin padding), which is exactly the color needed to fill
empty beyond-EOB margin cells.  Using `line-number` here is automatic and
requires no user-visible variable — if the user has not customized the face, its
background equals the frame background and the fill is a no-op.

A dedicated `left-margin-face` variable was considered and implemented
initially, but discarded: the `line-number` face already carries the correct
semantic and value, so a separate variable would just be redundant configuration.

### Effect on `theme-harmonize.el`

No change needed.  `theme-harmonize.el` already sets the `line-number`
background to match the terminal border color.  The Emacs patch picks that up
automatically for beyond-EOB rows.

---

## Appendix: key debug snippets

Count visual rows for the current buffer line:

```elisp
(count-screen-lines (line-beginning-position) (line-end-position) t)
```

List git-gutter overlay starts on the current buffer line:

```elisp
(let* ((bol (line-beginning-position))
       (eol (line-end-position)))
  (sort (delete-dups
         (cl-loop for ov in (overlays-in bol eol)
                  when (overlay-get ov 'git-gutter)
                  collect (overlay-start ov)))
        #'<))
```

Inspect what a git-gutter overlay draws in the margin:

```elisp
(let* ((p (point))
       (ovs (seq-filter (lambda (ov) (overlay-get ov 'git-gutter))
                        (overlays-in p (min (1+ p) (point-max))))))
  (mapcar (lambda (ov)
            (let* ((bs (overlay-get ov 'before-string))
                   (disp (and (stringp bs) (get-text-property 0 'display bs))))
              (list :start (overlay-start ov)
                    :before-string bs
                    :display disp)))
          ovs))
```

Inspect wrap indentation applied via text properties:

```elisp
(list (get-text-property (point) 'wrap-prefix)
      (get-text-property (point) 'line-prefix))
```
