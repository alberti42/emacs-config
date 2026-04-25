# markdown-ts-mode: ATX heading marker whitespace not hidden — PR in preparation

**Status (2026-04-25)**: bug confirmed locally; minimal fix applied to
a patched copy at `local/markdown-ts-mode.el`, loaded ahead of the
bundled file via `:load-path` in the `markdown-ts-mode` `use-package`
block in `markdown-config.el`. The runtime workaround that previously
sat in `markdown-config--markdown-ts-mode-setup` (a custom
`atx_heading` treesit fontifier extending invisibility forward through
trailing whitespace) has been removed — the patched local copy fixes
the issue at source. Upstream report not yet filed.

## TL;DR

When `markdown-ts-hide-markup` is on, `markdown-ts--fontify-delimiter`
sets the `invisible` text property on the `atx_h[1-6]_marker` node
range — i.e., only the `#` characters themselves. The single space
that separates the marker from the heading text is left visible,
which leaves the heading title offset by one column instead of
sitting flush at column 0 where the user expects when "hide markup"
is in effect. Fix: use a heading-specific fontifier that extends the
invisible region forward through any trailing whitespace, and route
the six `atx_h[1-6]_marker` captures through it instead of the
generic delimiter fontifier.

## Affected scope

- **Emacs core** `lisp/textmodes/markdown-ts-mode.el` — confirmed
  broken (Emacs 31.0.50, prerelease).
- **LionyxML's MELPA package**
  (https://github.com/LionyxML/markdown-ts-mode) — different code
  base; status not investigated for this issue.

PR target: Emacs core only, via `M-x report-emacs-bug`.

## Root cause

The bundled `markdown-ts--fontify-delimiter`:

```elisp
(defun markdown-ts--fontify-delimiter (node override start end &rest _)
  "Fontify delimiter NODE and optionally hide its markup."
  (treesit-fontify-with-override
   (treesit-node-start node) (treesit-node-end node)
   'markdown-ts-delimiter override start end)
  (when markdown-ts-hide-markup
    (put-text-property (treesit-node-start node) (treesit-node-end node)
                       'invisible 'markdown-ts--markup)))
```

is registered against six ATX marker captures:

```elisp
:language 'markdown
:feature 'heading
:override 'prepend
'((atx_h1_marker) @markdown-ts--fontify-delimiter
  (atx_h2_marker) @markdown-ts--fontify-delimiter
  ...
  (atx_h6_marker) @markdown-ts--fontify-delimiter)
```

The tree-sitter-markdown grammar emits `atx_h*_marker` for the `#`
characters only — the whitespace between the marker and the heading
text is **not** part of the marker node. So the `put-text-property`
above hides the `#`s and stops; the trailing space is left visible.

For a level-3 heading `### List of contents`, the rendered line is
the literal space (column 0) followed by `List of contents` (starting
at column 1). The user sees a one-column offset that grows by one
per level only when also paired with the `visual-wrap-prefix-mode`
column-reservation bug (separate PR), so without `visual-wrap-prefix-mode`
the offset is a stable +1 regardless of level.

This same fontifier is used for many other delimiter constructs
(block quote markers, fenced code block delimiters, emphasis
delimiters, …), where there is *no* trailing whitespace to worry
about. Modifying it in place would incorrectly affect those
constructs. The right fix is a heading-specific variant.

## Reproduction recipe

```
emacs -Q
M-x markdown-ts-mode
### Heading text
M-: (setq-local markdown-ts-hide-markup t)
M-: (markdown-ts--set-hide-markup t)
;; expected: "Heading text" sits at column 0.
;; actual:   "Heading text" sits at column 1.
M-: (get-text-property (line-beginning-position) 'invisible)
;; => markdown-ts--markup       ← marker '###' is hidden, good
M-: (get-text-property (+ (line-beginning-position) 3) 'invisible)
;; => nil                       ← the space between marker and title is NOT hidden
```

The third character (`#` at column 2) is invisible; the fourth
(the space) is not. So the visible portion of the line begins with a
literal space, indenting the title by one column.

## Evidence — node structure

```elisp
(treesit-node-children
 (treesit-parent-until
  (treesit-node-at (line-beginning-position) 'markdown)
  (lambda (n) (string= (treesit-node-type n) "atx_heading"))
  t))
;; => ((atx_h3_marker BEG END) (inline BEG' END'))
```

`END` (end of the marker node) and `BEG'` (start of the inline
content) are *not* equal — there's exactly one whitespace character
between them, and that character is not part of either node, so no
fontifier covers it.

## Proposed patch

```diff
--- a/lisp/textmodes/markdown-ts-mode.el
+++ b/lisp/textmodes/markdown-ts-mode.el
@@ -168,6 +168,27 @@ markdown-ts--fontify-delimiter
     (put-text-property (treesit-node-start node) (treesit-node-end node)
                        'invisible 'markdown-ts--markup)))

+(defun markdown-ts--fontify-atx-marker (node override start end &rest _)
+  "Fontify an ATX heading marker NODE and hide its markup.
+
+Like `markdown-ts--fontify-delimiter', but when
+`markdown-ts-hide-markup' is on, also hides the whitespace separating
+the marker from the heading text — without that, the heading title
+ends up indented by one column rather than sitting flush with the
+left edge where the user expects it.
+
+OVERRIDE, START, and END are passed through to
+`treesit-fontify-with-override'."
+  (treesit-fontify-with-override
+   (treesit-node-start node) (treesit-node-end node)
+   'markdown-ts-delimiter override start end)
+  (when markdown-ts-hide-markup
+    (save-excursion
+      (goto-char (treesit-node-end node))
+      (skip-chars-forward " \t")
+      (put-text-property (treesit-node-start node) (point)
+                         'invisible 'markdown-ts--markup))))
+
 (defvar markdown-ts--treesit-settings
   (treesit-font-lock-rules
    :language 'markdown-inline
@@ -189,12 +210,12 @@ markdown-ts--treesit-settings
    :language 'markdown
    :feature 'heading
    :override 'prepend
-   '((atx_h1_marker) @markdown-ts--fontify-delimiter
-     (atx_h2_marker) @markdown-ts--fontify-delimiter
-     (atx_h3_marker) @markdown-ts--fontify-delimiter
-     (atx_h4_marker) @markdown-ts--fontify-delimiter
-     (atx_h5_marker) @markdown-ts--fontify-delimiter
-     (atx_h6_marker) @markdown-ts--fontify-delimiter)
+   '((atx_h1_marker) @markdown-ts--fontify-atx-marker
+     (atx_h2_marker) @markdown-ts--fontify-atx-marker
+     (atx_h3_marker) @markdown-ts--fontify-atx-marker
+     (atx_h4_marker) @markdown-ts--fontify-atx-marker
+     (atx_h5_marker) @markdown-ts--fontify-atx-marker
+     (atx_h6_marker) @markdown-ts--fontify-atx-marker)

    :language 'markdown
    :feature 'paragraph
```

Notes for the maintainer:

- The `markdown-ts-delimiter` face continues to apply to *only* the
  marker node range (the `treesit-fontify-with-override` call is
  unchanged) — only the `invisible` property is extended through
  trailing whitespace. The face range stays accurate; the
  invisibility range matches what users expect from "hide markup".
- All non-heading delimiter captures (block quote markers, fenced
  code block delimiters, emphasis delimiters, info strings,
  block continuations, code span delimiters) keep routing through
  the original `markdown-ts--fontify-delimiter`. None of them have a
  trailing-whitespace concern, so they are intentionally untouched.
- `skip-chars-forward " \t"` matches the standard ATX-heading lexer
  contract (one or more space/tab characters between marker and
  text). It does not cross a newline, so an empty heading
  (`###` followed immediately by EOL) is handled correctly — the
  invisible region simply ends at the marker.

## Local fix in this repo

We carry a patched copy of `markdown-ts-mode.el` at
`local/markdown-ts-mode.el`, identical to the upstream Emacs 31 file
plus the new `markdown-ts--fontify-atx-marker` helper and the routing
update for the six marker captures. The `markdown-ts-mode`
`use-package` block in `markdown-config.el` prepends
`<emacs-config-dir>/local/` to `load-path` via `:load-path`, so the
patched copy is loaded ahead of the bundled file. The runtime
workaround that previously lived in
`markdown-config--markdown-ts-mode-setup` (a custom `atx_heading`
fontifier registered as `markdown-config-heading-extras`) has been
removed.

When the upstream fix lands in a stable Emacs release: delete
`local/markdown-ts-mode.el`, remove `:load-path` from the
`use-package` block in `markdown-config.el` (only if no other local
markdown patches remain), update this note's status line.

## How to file the report

Emacs uses email-based contribution to debbugs.gnu.org, not GitHub
PRs.

```
M-x report-emacs-bug
```

Subject suggestion:

> `markdown-ts-mode: ATX heading marker whitespace not hidden when markdown-ts-hide-markup is on`

Body should include:

1. The reproduction recipe (above) — keeps it actionable.
2. The `get-text-property` evidence on the post-marker space —
   pinpoints the gap as "the marker node range stops at the last `#`,
   and no fontifier covers the trailing whitespace".
3. The note that all *other* delimiter constructs are intentionally
   untouched — answers the maintainer's first instinct ("why a new
   function instead of modifying `markdown-ts--fontify-delimiter`?").
4. The patch — under the ~15-line FSF threshold; no copyright
   assignment required.
5. A pointer to the closely-related visual-wrap PR (file the two
   together if both are filed in the same window — they compose:
   without the visual-wrap fix, this fix alone still leaves headings
   indented by `(length marker) + 1` columns when
   `visual-wrap-prefix-mode` is active; without this fix, the
   visual-wrap fix doesn't trigger at all because the visible
   trailing space defeats the "fully-invisible prefix" predicate).

Once filed, link the debbugs URL here and update the **Status** line
at the top.
