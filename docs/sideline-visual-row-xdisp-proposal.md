# Per-visual-row margin rendering: proposal for `xdisp.c`

Status: investigation complete; upstream patch not yet written.

## Goal

Render sideline-style annotations (LSP diagnostics, code actions, grammar
hints) in the dedicated `right-margin` column of Emacs windows, with **one
label per visual row** — so that in soft-wrapped prose buffers (e.g. LaTeX
with `soft-wrap-mode`) successive labels stack with uniform 1-row gaps,
regardless of how many visual rows each underlying buffer line occupies.

Motivation: in centered/soft-wrapped prose the text area has no horizontal
slack for `sideline.el`'s default end-of-line `align-to` rendering. The
real `right-margin` column is the natural home for annotations there.
Our patched copy of sideline (`local/sideline.el`) adds a
`sideline-display-area 'right-margin` mode that routes labels through a
`(propertize " " 'display '((margin right-margin) <label>))` carrier.

## What we found

Margin overlays are anchored to **buffer-line geometry**, not visual-row
geometry: an overlay whose `before-string` carries a `(margin
right-margin)` display spec renders at the visual row containing the
overlay's position. Two consequences:

1. If we attach one overlay per buffer line at BOL, the margin label
   appears at visual row 1 of that buffer line; rows 2…N of a wrapped
   buffer line carry no margin content. Visible gaps follow each wrapped
   paragraph proportional to its wrap count.

2. If we attach one overlay per *visual row* — at the buffer position
   that begins each visual row inside a wrapped paragraph — each label
   does land on its own visual row. This was empirically confirmed via
   `right-margin-labels-poc.el` by attaching at `(+ (line-beginning-position) 100)`
   in a wrapped paragraph: the label rendered on the wrapped row, not at
   the paragraph's top.

So **per-row positioning is achievable in principle**.

## Why we couldn't make it work efficiently

Walking visual rows requires the display engine to compute wrap points.
The natural primitive is `vertical-motion`, but it is prohibitively slow
when `set-window-margins` is active (which is exactly our case —
`soft-wrap-mode` uses the right margin to enforce wrap column). Each
`vertical-motion` call goes through the redisplay engine to recompute
display layout under the constrained text width.

With sideline's design — N candidates per render, each candidate walking
visible rows looking for a free slot, render firing on every
`post-command-hook` — vertical-motion is called O(N²) times per
keystroke. Empirically: ~10 iterations/sec, Emacs hangs perceptibly on a
real document. A 500-iteration safety cap fires regularly under load.

`forward-visible-line` (used by sideline's original buffer-line walker)
is fast because it doesn't invoke display computation. But it can't
target visual rows inside a wrapped buffer line.

## What `git-gutter` does instead

`git-gutter` (also used in this config, with a local fork at
`alberti42/fork-git-gutter#fix/visual-line`) renders correctly on every
visual row of wrapped lines, including under `set-window-margins`, with
no perceptible cost. It does this with **no `vertical-motion` calls**:

```elisp
;; git-gutter:put-signs (excerpt)
(let* ((eol (when git-gutter:visual-line
              (save-excursion (goto-char pos) (line-end-position))))
       (ov (make-overlay pos (or eol pos))))  ; span the full buffer line
  (overlay-put ov 'before-string gutter-sign) ; row 1
  (when eol
    (overlay-put ov 'wrap-prefix              ; rows 2+
                 (git-gutter:wrap-prefix-for-sign sign pos))))
```

The trick: a single overlay spans the whole buffer line. `before-string`
puts the sign on visual row 1 (margin display routed via the carrier
character). `wrap-prefix` makes the **same** sign appear on every
continuation row — the display engine, not Lisp, does the per-row
rendering work, and it's fast.

## Why it doesn't directly solve our problem

`wrap-prefix` is a *single* string. It repeats verbatim on every
continuation row. Git-gutter is fine with this — each buffer line has at
most one sign, and it just repeats. Sideline needs **different** labels
on **different** visual rows of the same buffer line. `wrap-prefix`
cannot express that.

## Proposed `xdisp.c` patch

Extend the `wrap-prefix` text/overlay property to accept, in addition to
the current single string / image / stretch-space spec, either:

1. **A lambda** `(lambda (continuation-index) -> string-or-display-spec)`,
   called once per continuation row with the row's 0-based index relative
   to its buffer line; the return value is used as that row's prefix. A
   nil return falls back to the empty prefix.

2. **A vector or list** `[row1-prefix row2-prefix row3-prefix …]`,
   indexed by continuation index. Falls back to the last element (or
   nil) when the line wraps further than the vector's length.

Either form lets a caller render distinct content per continuation row
without computing wrap positions in Lisp.

### Where the change lives

The display engine already knows the continuation index when it's about
to render a continuation row (see `it->continuation_lines_width` and the
prefix-handling block around `handle_line_prefix` in `xdisp.c`). The
patch:

- Consult the property in its new form when rendering each continuation
  row.
- For the lambda form: call into Lisp at that point (once per
  continuation row — cheap, since the engine is already about to lay
  out that row).
- For the vector form: index lookup, no Lisp call.

The hot path stays roughly the same: one extra dispatch per continuation
row, comparable to the current single-string handling.

### Backwards compatibility

The current single-string semantics is preserved for any prefix that
isn't recognised as a lambda or vector. No existing code needs to
change.

## What sideline would look like with the new primitive

One buffer-line-spanning overlay per paragraph, `wrap-prefix` carrying a
vector of `(margin right-margin) <label-N>` display specs for the labels
that belong to that paragraph. The display engine handles placement,
including soft-wrap re-flow on window resize. No `vertical-motion`, no
per-row Lisp overhead. Gaps are exactly 1 visual row by construction —
because each continuation row has its own slot.

## Scope estimate

- C side: ~50–150 lines in `xdisp.c` (property recognition + dispatch),
  plus `etc/NEWS` entry and a couple of paragraphs in `display.texi`.
- Test side: a handful of redisplay tests covering vector, lambda, and
  fallback semantics under wrap.
- Lisp side: a follow-up sideline backend (or sideline replacement)
  rendering through the new primitive — small once the C primitive is
  in place.

Plus the usual upstream-review iteration. Several days of focused work,
not a weekend afternoon.

## Status of the in-tree workaround

`local/sideline.el` carries a buffer-line walker that places one label per
buffer line. Visual gaps in margin = (wrap rows of preceding buffer line)
— variable but visible. Acceptable as a stopgap. Fast, no display-engine
cost beyond what sideline upstream already incurs.

The visual-row walker that motivated this proposal has been reverted; see
git history for `local/sideline.el` if you want to revisit it.
