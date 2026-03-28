# Git-gutter TTY + visual-line wrapping: investigation and fix

This note documents a debugging session about `git-gutter` in terminal Emacs, specifically when `git-gutter:visual-line` is enabled and the buffer is soft-wrapped (narrow window / `visual-line-mode`).

The user-visible symptom was:

- On a single *buffer line* that is displayed as multiple *visual lines* (screen rows), the TTY git-gutter indicator (a vertical bar `▐` in the margin, configured as `"▐"`) appears *interrupted* on the wrapped continuation row.
- Where the bar is interrupted, the left margin shows the *buffer background* instead of the gutter background (because nothing is being rendered there).

The initial hypothesis was "soft wrap creates a continuation row that does not inherit git-gutter's background". Over the course of the investigation, we proved that the root cause is *overlay placement*, not face propagation.


## Environment and relevant configuration

### Emacs

- Emacs version: `31.0.50`

### Repository setup

The user moved `git-gutter.el` into this Emacs config repo so it can be loaded without `straight.el` recompilation friction:

- `git-gutter-tty.el` uses `use-package` with `:straight nil` and `:load-path emacs-config-dir`.

`git-gutter-tty.el` (relevant excerpt):

```elisp
(use-package git-gutter
  :if (not window-system)
  :straight nil
  :load-path emacs-config-dir
  :config
  (setq git-gutter:update-interval 0.5)
  (setq git-gutter:modified-sign "▐")
  (setq git-gutter:added-sign "▐")
  (setq git-gutter:deleted-sign "▐")
  (setq git-gutter:visual-line t)
  (setq git-gutter:window-width 1)
  (setq git-gutter:separator-sign " ")
  (setq git-gutter:always-show-separator t)
  (setq git-gutter:unchanged-sign " ")
  (global-git-gutter-mode 1))
```

### Gutter rendering mechanism

In TTY, `git-gutter` renders by attaching a `before-string` to zero-length overlays, and uses a `display` property to place text in the left margin:

```elisp
(defun git-gutter:before-string (sign)
  (let ((gutter-sep (concat sign (git-gutter:gutter-seperator))))
    (propertize " " 'display `((margin left-margin) ,gutter-sep))))

(defun git-gutter:put-signs (sign points)
  (dolist (pos points)
    (let ((ov (make-overlay pos pos))
          (gutter-sign (git-gutter:before-string sign)))
      (overlay-put ov 'before-string gutter-sign)
      (overlay-put ov 'git-gutter t))))
```

Key implication:

- If there is *no overlay* at the start of a given visual row, there is no margin string, so the margin background falls back to the buffer/window background. This produces the "white hole".


## Evidence collected

### 1) The symptom is a missing margin string on continuation rows

The user inspected the left margin at column 0 across consecutive visual rows and saw one entry with `string=nil`, indicating nothing was drawn in the left margin for that row.

This established that the "hole" is explained by absence of any left-margin rendering for that specific visual row.


### 2) The problem is not "left-margin face"

We confirmed that `left-margin` in `((margin left-margin) ...)` is a margin identifier, not a face, so `(facep 'left-margin)` returning nil is normal.

This matters because "just set the `left-margin` face background" is not a direct fix in this setup.


### 3) Root cause: overlays cannot target continuation row starts reliably

The original approach (and the first attempted fix) walked the buffer with `vertical-motion` to find the buffer position of each visual row start, placing one zero-length overlay per row. This is fundamentally unreliable:

- `vertical-motion` lands at the last character of the current screen row, not at the start of the next one.
- `visual-wrap-prefix-mode` (Emacs 30+) adds continuation indentation via `wrap-prefix` *text properties*, which shifts where visual rows begin in a way that `vertical-motion` does not account for.
- Evidence: two overlays were found with the same `y` screen coordinate, meaning the "second" overlay was placed on the first visual row rather than the start of the continuation row.

This is the same problem `display-line-numbers` solves by running *inside the C display loop* (once per screen row, with direct access to `continuation_lines_width`). From Lisp, there is no equivalent hook.


### 4) `wrap-prefix` on a spanning overlay is the correct solution

The key insight: the `wrap-prefix` overlay property is exactly what Emacs uses internally to render content at the start of continuation rows. It is what `visual-wrap-prefix-mode` uses for indentation. We can piggyback on the same mechanism.

**Proof-of-concept tests run (with `git-gutter-mode` disabled to avoid interference):**

Test 1 — does `wrap-prefix` on a non-zero overlay render in the left margin on continuation rows?

```elisp
(let* ((bol (line-beginning-position))
       (eol (line-end-position))
       (ov  (make-overlay bol eol)))
  (overlay-put ov 'wrap-prefix
               (propertize " " 'display
                           `((margin left-margin)
                             ,(propertize " " 'face 'git-gutter:modified))))
  ov)
```

Result: colored blank appeared on the continuation row. Mechanism confirmed.

Test 2 — where is the `wrap-prefix` text property from `visual-wrap-prefix-mode`?

```elisp
(get-text-property (line-beginning-position) 'wrap-prefix)
```

Result: `#("  ;; " ...)` — present at `bol`, same throughout the line. Safe to read once from `bol` and prepend to.

Test 3 — combined gutter blank + existing wrap-prefix:

```elisp
(let* ((bol (line-beginning-position))
       (eol (line-end-position))
       (existing (get-text-property bol 'wrap-prefix))
       (gutter-blank (propertize " " 'display
                                 `((margin left-margin)
                                   ,(propertize " " 'face 'git-gutter:modified))))
       (combined (concat gutter-blank (or existing "")))
       (ov (make-overlay bol eol)))
  (overlay-put ov 'wrap-prefix combined)
  ov)
```

Result: colored blank on continuation row, indentation preserved.

Test 4 — sign on continuation rows (not just blank):

```elisp
(let* ((bol (line-beginning-position))
       (eol (line-end-position))
       (existing (get-text-property bol 'wrap-prefix))
       (sign (propertize "▐ " 'face 'git-gutter:modified))
       (gutter (propertize " " 'display `((margin left-margin) ,sign)))
       (combined (concat gutter (or existing "")))
       (ov (make-overlay bol eol)))
  (overlay-put ov 'before-string
               (propertize " " 'display `((margin left-margin) ,sign)))
  (overlay-put ov 'wrap-prefix combined)
  ov)
```

Result: `▐` on both the first visual row and every continuation row, with correct indentation. Single overlay, no zero-length hack needed.

**Important testing note:** early tests appeared to fail because git-gutter's own zero-length overlay at `bol` was masking the test overlay's `before-string`. Disabling `git-gutter-mode` before testing is essential to get clean results.


## Design rationale

The correct behavior is: the gutter sign repeats on every visual row of a hunk line. This is consistent with how Emacs presents visual lines to the user:

- `display-line-numbers`: shows the number on the first visual row, blank on continuation rows — the non-advancing line number signals "same logical line".
- `visual-wrap-prefix-mode`: repeats the indentation prefix on every continuation row so the text looks like multiple indented lines.
- git-gutter (after fix): repeats `▐` on every visual row — the change spans the entire visible extent of the logical line.


## The fix

Three changes to `git-gutter.el`:

### 1. `git-gutter:wrap-prefix-for-sign`

Removed the `(stringp existing)` guard. The function now always returns a wrap-prefix string, falling back to `""` when no text property exists:

```elisp
(defun git-gutter:wrap-prefix-for-sign (sign pos)
  (let ((existing (get-text-property pos 'wrap-prefix)))
    (concat (git-gutter:before-string sign) (or existing ""))))
```

### 2. `git-gutter:put-signs`

Overlay now spans `pos` to `eol` (instead of zero-length) in TTY + `visual-line` mode, so `wrap-prefix` fires on every continuation row:

```elisp
(let* ((eol (when (and git-gutter:visual-line (not (display-graphic-p)))
              (save-excursion (goto-char pos) (line-end-position))))
       (ov (make-overlay pos (or eol pos))))
  (overlay-put ov 'before-string gutter-sign)
  (when eol
    (overlay-put ov 'wrap-prefix (git-gutter:wrap-prefix-for-sign sign pos))))
```

### 3. `view-set-overlays` and `view-for-unchanged`

Dropped `git-gutter:next-visual-line`; both functions now always walk with `forward-line`. Visual row enumeration is no longer needed — the display engine handles continuation rows via `wrap-prefix`. `git-gutter:next-visual-line` was removed entirely.


## Appendix: key debug snippets used

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

Check whether two buffer positions are on the same screen row:

```elisp
(list (posn-x-y (posn-at-point p0))
      (posn-x-y (posn-at-point p1)))
```

Inspect wrap indentation applied via text properties:

```elisp
(list (get-text-property (point) 'wrap-prefix)
      (get-text-property (point) 'line-prefix))
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
