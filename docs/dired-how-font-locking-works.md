# Dired font-locking: why dir names paint lazily, and how we fix it

## Symptom

On opening a dired buffer, directory names (and the names of "generic" files
without a recognized type) appear in the **default face** instead of
`diredfl-dir-name` blue. Moving point onto a line repaints that line — and
its neighbour — in the expected colors. Pressing `g` (`revert-buffer`)
repaints everything in one shot.

The same family of bug also surfaces with `nerd-icons-dired`'s icons: the
upstream `(propertize string 'display string)` wrapper around the overlay
`after-string` produces "colorless icons until first redisplay event"
unless overridden — see the comment block in `dired-config.el` at
`nerd-icons-dired--add-overlay`. Both phenomena point at the same root
cause; the dir-name half is just easier to notice because diredfl colors
many more elements than built-in dired does.

Icons sit on a different track: `nerd-icons-dired` builds them as overlay
`after-string`s with the face baked into the propertized string returned by
`nerd-icons-icon-for-file` / `…-for-dir`. Files mapped to a specific icon
face (e.g. PDF → `nerd-icons-red`) look colored from frame zero; files that
fall through to a default-faced icon look "uncolored" but are working
correctly. The buggy half is the buffer-text font-locking, not the icons.

## How it's wired

Two layers contribute font-lock keywords:

1. Built-in `dired-font-lock-keywords` (in `dired.el`): header line, marks,
   deletion flag, symlinks.
2. `diredfl-font-lock-keywords-1` (in `diredfl/diredfl.el`): permission
   bits, sizes, dates, `diredfl-dir-name`, `diredfl-file-name`,
   ignored/compressed names, etc.

`diredfl-mode` stuffs its keywords into `font-lock-defaults` and calls
`font-lock-refresh-defaults` — that's all.

The directory-name rule is an **anchored highlighter**:

```elisp
(list (concat dired-re-maybe-mark dired-re-inode-size "\\(d\\)[^:]")
      '(1 diredfl-dir-priv t)
      '(".+" (dired-move-to-filename) nil (0 diredfl-dir-name t)))
```

The outer matcher catches the `d` in the permission column. The inner
matcher (`".+"`) is run **after** `(dired-move-to-filename)` jumps point onto
the actual filename. `dired-move-to-filename` resolves the filename column
by reading the `dired-filename` text property set during `dired-readin`.

## Root cause

The bug is upstream of both diredfl and nerd-icons-dired. It predates
diredfl in this config (the icon-color workaround on
`nerd-icons-dired--add-overlay` was already needed before diredfl was
added).

When the buffer is first visited:

1. `dired-mode` runs and configures `font-lock-defaults`.
2. `dired-readin` inserts the listing **into a buffer that is not yet
   displayed**, then attaches text properties (`dired-filename`,
   `mouse-face`, `help-echo`).
3. `dired-mode-hook` fires (icons get added, diredfl keywords get
   installed) — still no display.
4. The buffer is finally shown. Jit-lock fontifies a chunk around point
   on the first redisplay; lines outside that chunk are left for
   on-demand fontification when something pulls them in (point motion,
   scroll, an overlay change).

The diredfl rule that paints directory names is an anchored highlighter:

```elisp
(list (concat dired-re-maybe-mark dired-re-inode-size "\\(d\\)[^:]")
      '(1 diredfl-dir-priv t)
      '(".+" (dired-move-to-filename) nil (0 diredfl-dir-name t)))
```

When jit-lock does run on a line, the `(dired-move-to-filename)` PRE-MATCH
form locates the filename column and the inner `.+` paints it. That works
fine on lines jit-lock actually fontifies. The problem is jit-lock not
running on most of the lines on first display.

Why does point motion paint a line *and* its neighbour? Jit-lock's
contextual refontification works in chunks of `jit-lock-chunk-size`
characters (default 1500), which on a typical dired listing spans a few
adjacent lines.

Why does `g` paint everything? `dired-revert` reinserts the listing into a
buffer that is **already on-screen**, so the post-readin fontification
sees a fresh visible region with all properties in place and paints it in
one pass. The asymmetry is in the bootstrapping of the buffer's first
display, not in anything diredfl or nerd-icons-dired do.

## Fix (in `dired-config.el`)

Force a full re-fontification at the end of `dired-after-readin-hook`,
after `nerd-icons-dired--refresh` has placed its overlays:

```elisp
(defun dired-config--fontify-after-readin ()
  "Eagerly refontify the dired buffer after readin completes."
  (font-lock-flush)
  (font-lock-ensure))

(add-hook 'dired-after-readin-hook #'dired-config--fontify-after-readin 90)
```

Depth `90` puts this after `nerd-icons-dired--refresh` (added at default
depth 0), so overlays are in place first and font-lock runs over a fully
prepared buffer. `font-lock-flush` invalidates fontification across the
buffer; `font-lock-ensure` paints synchronously instead of waiting for
redisplay.

## Diagnostic snippets

If dir names still don't paint after the fix, the next thing to check is
whether `dired-move-to-filename` is finding them at fontification time:

```elisp
;; Eval in a misbehaving dired buffer with point at line N's start:
(save-excursion (dired-move-to-filename))
;; nil → the `dired-filename' property is missing on this line.
;; integer → the property is set; the issue is elsewhere.
```

To watch jit-lock chunking in action:

```elisp
(setq jit-lock-chunk-size 200)   ;; default 1500; smaller = more visible chunks
```
