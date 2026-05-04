# Dired font-locking: why dir names paint lazily, and how we fix it

## Symptom

On opening a dired buffer, directory names (and the names of "generic" files
without a recognized type) appear in the **default face** instead of
`diredfl-dir-name` blue. Moving point onto a line repaints that line — and
its neighbour — in the expected colors. Pressing `g` (`revert-buffer`)
repaints everything in one shot.

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

When the buffer is first visited, the relevant sequence is:

1. `dired-mode` runs and configures `font-lock-defaults` to **plain**
   `dired-font-lock-keywords`.
2. `dired-readin` inserts the listing and sets `dired-filename` text
   properties on the filenames.
3. `dired-mode-hook` fires. With `add-hook` LIFO, the order is
   `nerd-icons-dired-mode` → `diredfl-mode`.
4. `diredfl-mode` calls `font-lock-refresh-defaults`. That toggles
   `font-lock-mode` off/on, which re-installs the keyword set but **defers
   actual painting to the next redisplay** through jit-lock.
5. On next redisplay jit-lock fontifies the visible region. Some lines'
   anchored matcher gets a nil from `dired-move-to-filename` (timing/edge
   case around when the property is observable to font-lock), so the inner
   sub-rule is skipped: the `d` in the permissions column is colored, but
   the dir name keeps the default face.

When point moves, jit-lock's *contextual* refontification re-runs the
keywords on a chunk around point (default `jit-lock-context-fontify`
window). By then properties are stable, the anchored matcher succeeds, and
the line turns blue. The chunk straddles adjacent lines too — that's why
the neighbour repaints alongside.

`g` works because `dired-revert` reinserts the listing while
`font-lock-mode` is already correctly configured to use diredfl's keywords.
Post-readin fontification then runs over a fully-prepared buffer in one
pass.

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
