# markdown-ts-mode inline-link fontification bug — PR in preparation

**Status (2026-04-25)**: bug confirmed locally; one-line fix verified
on a patched copy of `markdown-ts-mode.el` (live in
`local/markdown-ts-mode.el`, loaded ahead of the bundled file via
`:load-path` in the `markdown-ts-mode` `use-package` block). The
runtime workaround that previously sat in
`markdown-config--markdown-ts-mode-setup` (overriding
`treesit-range-settings`) has been removed — the patched local copy
fixes the issue at source. Upstream report not yet filed.

## TL;DR

In Emacs 31's bundled `markdown-ts-mode`, standard inline links
`[label](url)` and `[label](<url with spaces>)` get **no
fontification** — neither the bundled `link` face nor markup hiding
applies — and `treesit-parent-until` from a position inside the link
finds no `inline_link` ancestor. Root cause: the embedded-grammar
range setup uses `:range-fn #'treesit-range-fn-exclude-children`,
which fragments the `markdown-inline` parser's view of the buffer so
`inline_link` constructs never get assembled. Fix: drop the
`:range-fn` line.

## Affected scope

- **Emacs core** `lisp/textmodes/markdown-ts-mode.el` — confirmed
  broken (Emacs 31.0.50, prerelease).
- **LionyxML's MELPA package**
  (https://github.com/LionyxML/markdown-ts-mode) — **not affected**;
  that version doesn't use embedded grammars at all (no
  `treesit-range-rules`, no `:range-fn`, much simpler implementation,
  no multi-language code-block fontification). The bug was introduced
  during/after upstreaming when the embedded-grammar machinery was
  added.

PR target: Emacs core only, via `M-x report-emacs-bug`. Do not file
on LionyxML's GitHub repo — different code, different scope.

## Root cause

`markdown-ts-mode` embeds the `markdown-inline` parser inside the
`markdown` host grammar's `(inline)` nodes:

```elisp
(treesit-range-rules
 :embed 'markdown-inline
 :host  'markdown
 :range-fn #'treesit-range-fn-exclude-children
 '((inline) @markdown-inline))
```

`treesit-range-fn-exclude-children` excludes **all** children of the
host node — both named and anonymous. The `markdown` block grammar
emits the literal characters `[`, `]`, `(`, `)`, `<`, `>`, `.`, `/`
as anonymous children of `(inline)` (they're the structural tokens
that delimit inline-link syntax). With those positions excluded,
`markdown-inline` receives **disjoint fragments** of the inline
content and never assembles them into a complete `inline_link`.

Downstream, the bundled font-lock rules

```elisp
(inline_link (link_text) @link)
(inline_link (link_destination) @font-lock-string-face)
```

never match — they're effectively dead code under the current range
setup.

Wiki links (`[[…]]`) are unaffected for two reasons: `markdown-ts-mode`
has no wiki-link support to begin with, and our config handles them
with a regex-based font-lock keyword that bypasses the parser
entirely.

## Reproduction recipe

```
emacs -Q
M-x markdown-ts-mode
[notes](other.md)
M-x font-lock-ensure
;; With cursor inside the word `notes':
M-: (get-text-property (point) 'face)
;; expected: a face that includes 'link
;; actual:   nil
M-: (treesit-node-string (treesit-node-at (point) 'markdown-inline))
;; expected: an inline_link descendant
;; actual:   "(inline)" with no children
```

## Evidence — parse tree and parser ranges

For a buffer containing `[notes](other.md)\n`, the `markdown` grammar's
named tree is

```
(document (section (paragraph (inline))))
```

with **no named children** inside `(inline)`. All children are
anonymous tokens:

```
type=[ named=nil text="["
type=] named=nil text="]"
type=( named=nil text="("
type=. named=nil text="."
type=) named=nil text=")"
```

The resulting `markdown-inline` parser ranges are fragmented:

```
((2 . 7) (9 . 14) (15 . 17))
```

— excluding positions 1, 8, 14, 17, 18 (the bracket/paren/dot
characters). With those excluded, `markdown-inline` parses its input
as `(inline)` with no children. No `inline_link` recognized.

When the *same* buffer content is fed to `markdown-inline` directly
without range restrictions, it parses correctly:

```
(inline (inline_link (link_text) (link_destination)))
```

So the parser is fine; the range-fn is the problem.

## Reproduced under multiple grammar versions

Tested against `tree-sitter-grammars/tree-sitter-markdown`:

- `v0.4.1` (commit `413285231ce8fa8b11e7074bbe265b48aa7277f9`,
  the version the bundled mode's commentary documents).
- `v0.5.x` HEAD of the `split_parser` branch.

Both versions produce identical fragmentation behavior. Pinning the
grammar does **not** fix the bug. This is a `markdown-ts-mode` issue,
not a grammar regression.

## Attribution and timeline (from `git blame` / `git log`)

Worth including in the report so the maintainer can locate the
relevant work fast and assess fix scope:

- The buggy line was added by **Yuan Fu** in commit
  `6f1e317764dab918d40b08d2e8e9166d42ae6c8d` on 2025-03-11
  (*"Expand markdown-ts-mode and add code block support for
  javascript"*). The commit message specifically lists
  *"Correctly setup markdown_inline with range settings"* as one of
  the goals — so this was a deliberate range-setup change, not
  drive-by editing.
- The helper `treesit-range-fn-exclude-children` was introduced by
  the **same author** two weeks earlier, in commit
  `8a3e19f4b39` on 2025-02-27 (*"Support alternative range function
  for tree-sitter range settings"*). So the API and its first
  consumer were authored by the same person, in the same workstream.
- **`markdown-ts-mode.el` is the only call site of the helper in
  the entire Emacs source tree** (`git grep -l
  treesit-range-fn-exclude-children -- '*.el'` returns only
  `lisp/textmodes/markdown-ts-mode.el` and `lisp/treesit.el`
  itself).

Implications:

- Whatever the right resolution is — drop the line, or replace the
  helper with one that filters `NAMED`-only children — there are no
  other call sites to coordinate with. The fix is contained.
- No automated test in `test/lisp/textmodes/` asserts that
  `[label](url)` ends up with the `link` face, which is plausibly
  why the bug shipped despite review by an experienced contributor:
  the change set looked correct in isolation, and a visual smoke
  test of a markdown buffer can easily miss "no link face" — the
  default `link` face is just an underline + slightly different
  color in many themes, and an unfontified link still renders as
  legible default text.

## Proposed patch

```diff
--- a/lisp/textmodes/markdown-ts-mode.el
+++ b/lisp/textmodes/markdown-ts-mode.el
@@ -334,7 +334,6 @@ (defun markdown-ts--range-settings ()
   (treesit-range-rules
    :embed 'markdown-inline
    :host 'markdown
-   :range-fn #'treesit-range-fn-exclude-children
    '((inline) @markdown-inline)

    :embed #'markdown-ts--convert-code-block-language
```

After this change, `markdown-inline` sees the full `(inline)` host
range and parses correctly. The existing font-lock rules then
activate as designed.

Verified end-to-end with our config: inline-link `link_text` gets the
`link` face, our `markdown-config-inline-link-hiding` rule matches,
and `markdown-config--inline-link-destination-at-point` returns the
expected destination (with `<…>` stripping for the pointy-bracket
form).

## Open question for the maintainer

`treesit-range-fn-exclude-children` excludes *all* children, named
and anonymous. If the original intent was to exclude only named
children (e.g., to skip embedded HTML tags or images that are real
sub-grammars), the right fix may be a new helper such as
`treesit-range-fn-exclude-named-children` rather than dropping
`:range-fn` entirely. Either resolution is functionally equivalent
for `markdown-ts-mode` as shipped today, since `(inline)` has no
named children — only anonymous tokens — but the choice matters for
intent and for future grammar evolution.

## Local fix in this repo

We carry a patched copy of `markdown-ts-mode.el` at
`local/markdown-ts-mode.el`, identical to the upstream Emacs 31
file with the single `:range-fn` line removed. The
`markdown-ts-mode` `use-package` block in `markdown-config.el`
prepends `<emacs-config-dir>/local/` to `load-path` via
`:load-path`, so the patched copy is loaded ahead of the bundled
file. No runtime workaround remains in
`markdown-config--markdown-ts-mode-setup`.

When the upstream fix lands in a stable Emacs release: delete
`local/markdown-ts-mode.el`, remove `:load-path` from the
`use-package` block, update this note's status line, and remove
the corresponding invariant in `docs/modules/markdown-config.md`
(`### local/markdown-ts-mode.el is load-bearing for inline links`).

## How to file the report

Emacs uses email-based contribution to debbugs.gnu.org, not GitHub
PRs.

```
M-x report-emacs-bug
```

Subject suggestion:

> `markdown-ts-mode: inline links not fontified — treesit-range-fn-exclude-children fragments markdown-inline ranges`

Suggested opening line (puts attribution and scope up front so the
maintainer can triage in one sentence):

> Bundled `markdown-ts-mode`'s only call site for
> `treesit-range-fn-exclude-children`, authored by the helper's
> author (Yuan Fu, commits `6f1e317764d` and `8a3e19f4b39`,
> March 2025), has silently broken inline-link fontification since
> then. No other Emacs Lisp file uses the helper, so the fix is
> contained.

Body should include:

1. The reproduction recipe (above) — keeps it actionable.
2. The parse-tree / range evidence — distinguishes parser bug from
   range-setup bug.
3. The note that v0.4.1 and v0.5.x both reproduce — rules out grammar
   regression.
4. The attribution / timeline / single-call-site facts — frames the
   fix as contained.
5. The patch — small enough to qualify as a casual-contributor change
   (under the ~15-line FSF threshold; no copyright assignment
   required).
6. The open question about `exclude-children` semantics — lets the
   maintainer decide whether to introduce a new helper
   (`treesit-range-fn-exclude-named-children`) or just drop the line.
   Worth suggesting: a regression test in
   `test/lisp/textmodes/markdown-ts-mode-tests.el` asserting that
   `(get-text-property POS 'face)` on `[label]` includes `'link`,
   so this can't silently regress again.

Once filed, link the debbugs URL here and update the **Status** line
at the top.
