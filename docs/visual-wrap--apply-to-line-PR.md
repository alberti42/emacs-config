# visual-wrap-prefix-mode: invisible prefix characters reserve column space — PR in preparation

**Status (2026-04-25)**: bug confirmed locally; minimal fix applied to
a patched copy at `local/visual-wrap.el`, loaded ahead of the bundled
file via a dedicated `use-package visual-wrap` block in `init.el` (with
`:demand t`). The runtime workaround that previously sat in
`markdown-config--markdown-ts-mode-setup` (a custom `jit-lock` cleanup
function stripping `min-width` and `wrap-prefix` from heading lines)
has been removed — the patched local copy fixes the issue at source.
Upstream report not yet filed.

## TL;DR

When a major mode hides leading markup via the `invisible` text
property (e.g. `markdown-ts-mode` with `markdown-ts-hide-markup` on
hides the `#` markers of an ATX heading), `visual-wrap-prefix-mode`
still reserves column-width *as if the markers were visible*. The
visible content is pushed N columns to the right, where N is the
number of hidden prefix characters — a level-3 heading appears
indented by 4 columns, level-5 by 6, etc. Root cause:
`visual-wrap--content-prefix` uses `(string-width prefix)` as a lower
bound on the prefix's column width, and `string-width` does not
consult `buffer-invisibility-spec`. Fix: short-circuit
`visual-wrap--content-prefix` to return `nil` when the prefix is
entirely invisible per the buffer's spec.

## Affected scope

- **Emacs core** `lisp/visual-wrap.el` — confirmed broken (Emacs
  31.0.50, prerelease). Mode introduced in Emacs 30.
- Affects every major mode that hides leading markup matching
  `adaptive-fill-regexp` (which includes `#`, `>`, `*`, `-`, `+`,
  `;`, etc.). Concrete examples observed:
  - `markdown-ts-mode` with `markdown-ts-hide-markup` on (ATX
    headings).
  - Any custom mode that adds an `invisible` property to a leading
    bullet/comment/quote marker.

PR target: Emacs core only, via `M-x report-emacs-bug`.

## Root cause

`visual-wrap--apply-to-line` reserves a `min-width` display spec sized
to the prefix's column-width:

```elisp
(when (numberp next-line-prefix)
  (add-display-text-property
   (point) (min (+ (point) (length first-line-prefix))
                 (pos-eol))
   'min-width `((,next-line-prefix . width))))
```

`next-line-prefix` (an integer column count) comes from
`visual-wrap--content-prefix`:

```elisp
(max (string-width prefix)
     (ceiling (string-pixel-width prefix (current-buffer))
              (string-pixel-width avg-space (current-buffer))))
```

`string-pixel-width` measures via `buffer-text-pixel-size` in a work
buffer set up by `work-buffer--prepare-pixelwise`. That helper copies
`face-remapping-alist`, `char-property-alias-alist` and
`default-text-properties` from the source buffer, but **not**
`buffer-invisibility-spec`. So in the work buffer the spec is at its
default (`t` — everything `invisible` is invisible) and the pixel
measurement may already treat the hidden prefix as zero-width. But
`string-width` is purely character-based — it returns
`(length prefix)` for ASCII text — and the `max` keeps that as the
floor. Result: `min-width` reserves N columns for N invisible
characters, padding the line to push the visible content rightward.

Downstream, the same `next-line-prefix` is used as the `:align-to`
target of the `wrap-prefix` `(space …)` spec, so any continuation
lines also align to the over-reserved column.

## Reproduction recipe

```
emacs -Q
M-x text-mode
M-x visual-wrap-prefix-mode
;; Insert a heading-like prefix that adaptive-fill-regexp matches:
### Heading text
;; Hide the `### ` markers via the invisible property:
M-: (let ((inhibit-read-only t))
      (put-text-property (line-beginning-position)
                         (+ (line-beginning-position) 4)
                         'invisible 'demo))
M-: (add-to-invisibility-spec 'demo)
;; Force a refontify so visual-wrap-prefix-function reruns:
M-x font-lock-flush
;; expected: "Heading text" sits at column 0.
;; actual:   "Heading text" sits at column 4.
M-: (get-text-property (line-beginning-position) 'display)
;; => (min-width ((4 . width)))   ← reserves 4 columns for invisible chars
M-: (get-text-property (line-beginning-position) 'wrap-prefix)
;; => (space :align-to (4 . width))
```

## Evidence — observed in markdown-ts-mode

For a markdown buffer with `markdown-ts-hide-markup` on and point at
the start of a `##### 1. Fundamentals` heading line, `text-properties-at`
returns:

```
(wrap-prefix (space :align-to (6 . width))
 display    (min-width ((6 . width)))
 invisible  markdown-ts--markup
 face       (markdown-ts-delimiter markdown-ts-heading-5)
 fontified  t)
```

Both `min-width 6` and `:align-to 6` exactly match the prefix length
(`#####` + space = 6 characters). Toggling `visual-wrap-prefix-mode`
off makes the heading collapse correctly to column 0; toggling it
back on re-introduces the indentation. So the misalignment is
entirely contributed by `visual-wrap-prefix-mode` — the invisibility
spec and the `invisible` text property are doing exactly what they
should.

## Proposed patch

```diff
--- a/lisp/visual-wrap.el
+++ b/lisp/visual-wrap.el
@@ -103,6 +103,22 @@ visual-wrap--display-property-safe-p
                  display)))))

+(defun visual-wrap--prefix-fully-invisible-p (prefix)
+  "Return non-nil if every character in PREFIX is invisible.
+Visibility is checked against the current buffer's
+`buffer-invisibility-spec'.  PREFIX must carry the `invisible' text
+properties it had in its source buffer (which holds when PREFIX comes
+from `match-string' or `buffer-substring')."
+  (and (> (length prefix) 0)
+       (let ((pos 0)
+             (len (length prefix))
+             (all-invisible t))
+         (while (and all-invisible (< pos len))
+           (unless (invisible-p (get-text-property pos 'invisible prefix))
+             (setq all-invisible nil))
+           (setq pos (or (next-single-property-change
+                          pos 'invisible prefix len)
+                         len)))
+         all-invisible)))
+
 (defun visual-wrap--prefix-face (fcp _beg end)
   ;; If the fill-context-prefix already specifies a face, just use that.
   (cond ((get-text-property 0 'face fcp))
@@ -175,6 +191,16 @@ visual-wrap--content-prefix
   (cond
    ((string= prefix "")
     nil)
+   ;; If the prefix is entirely invisible per the buffer's
+   ;; `buffer-invisibility-spec' (e.g. a major mode that hides leading
+   ;; markup, like `markdown-ts-mode' with `markdown-ts-hide-markup'
+   ;; on), treat it as no prefix.  Otherwise the `min-width' display
+   ;; spec set in `visual-wrap--apply-to-line' would reserve column
+   ;; space for characters that aren't actually displayed, pushing the
+   ;; visible content to a column that doesn't match where the user
+   ;; sees the line begin.
+   ((visual-wrap--prefix-fully-invisible-p prefix)
+    nil)
    ((or (and adaptive-fill-first-line-regexp
              (string-match adaptive-fill-first-line-regexp prefix))
         (and comment-start-skip
```

After this change, when the entire prefix is hidden,
`visual-wrap--content-prefix` returns `nil`, the `when-let*` binding
in `visual-wrap--apply-to-line` short-circuits, and neither the
`min-width` display spec nor the `wrap-prefix` is applied to the
line. The visible content sits flush at column 0, matching what the
user sees.

For *partially* invisible prefixes — a hypothetical mode that hides
`###` but not the trailing space, or a quote-plus-heading like
`> ###` where only `###` is hidden — the predicate returns `nil` and
the existing code path runs unchanged. So this patch fixes the
common, observed case (fully-hidden leading markup) without altering
behavior anywhere else. A more thorough fix that prorates `min-width`
to the visible portion of a partially-hidden prefix is possible but
meaningfully larger; see *Known limitation* below.

## Known limitation

The fix only handles the *fully* invisible case. A partially-hidden
prefix (e.g. `> ###` with only `###` hidden) would still over-reserve
column space proportional to the invisible portion. A follow-up could
walk the prefix in chunks, sum the visible width via
`next-single-property-change` + `string-width`, and pass that
adjusted width to `min-width` and `:align-to`. That is a
substantially more invasive change to `visual-wrap--content-prefix`
and `visual-wrap--apply-to-line`, and the partial case is not known
to occur in any shipping mode today, so this PR proposes the minimal
fix and flags partial-invisibility as a follow-up.

## Local fix in this repo

We carry a patched copy of `visual-wrap.el` at `local/visual-wrap.el`,
identical to the upstream Emacs 31 file plus the helper and the new
cond branch above. A dedicated `use-package visual-wrap` block in
`init.el` prepends `<emacs-config-dir>/local/` to `load-path` and
loads the file eagerly (`:demand t`), so the patched copy is in
memory before `soft-wrap.el` invokes `visual-wrap-prefix-mode` (the
mode is autoloaded from the bundled location otherwise; explicit
`require` is required to override).

When the upstream fix lands in a stable Emacs release: delete
`local/visual-wrap.el`, remove the `use-package visual-wrap` block
from `init.el`, update this note's status line.

## How to file the report

Emacs uses email-based contribution to debbugs.gnu.org, not GitHub
PRs.

```
M-x report-emacs-bug
```

Subject suggestion:

> `visual-wrap-prefix-mode: min-width reserves column space for invisible prefix characters`

Body should include:

1. The reproduction recipe (above) — keeps it actionable.
2. The `text-properties-at` evidence from a real markdown-ts-mode
   buffer — distinguishes "visual-wrap is doing this" from "the
   major mode is misconfigured".
3. The note that `string-width` ignores invisibility while
   `string-pixel-width` (via `buffer-text-pixel-size` in a work
   buffer) may already give the correct zero — pinpointing
   `(max (string-width prefix) …)` in `visual-wrap--content-prefix`
   as the floor that breaks the case.
4. The patch — under the ~15-line FSF threshold; no copyright
   assignment required.
5. The known-limitation note about partial invisibility, so the
   maintainer can decide whether to extend the fix or accept the
   minimal version.

Once filed, link the debbugs URL here and update the **Status** line
at the top.
