# markdown-ts-mode: upstream submission candidates

Defects and gaps in the bundled `markdown-ts-mode` that this configuration
currently works around locally, and that belong upstream rather than in
`markdown-config.el`. Opinionated local policy is deliberately excluded (see
"Not candidates" at the end).

## Where these go

Both places, and the two are not alternatives:

- **The Emacs bug tracker** (`M-x report-emacs-bug`, which mails
  `bug-gnu-emacs`) is where a fix must be filed. `markdown-ts-mode` is
  `lisp/textmodes/markdown-ts-mode.el` in Emacs core, so debbugs is the only
  place a patch can land and be tracked to a commit.
- **A lab issue** at <https://github.com/LionyxML/markdown-ts-mode-lab/issues>
  is where the maintainers prefer the discussion to happen, and it is how the
  mode's own history is kept. Their `patches.md` tracks every submission with
  its debbugs link, and closed lab issues carry the number in the title —
  `#55 … (bug#81524)`, `#35 … (bug#81195)`, `#60 … (bug#81771)`.

Order: **lab issue first**, offering the patch, then debbugs once the
maintainers have weighed in.

That is the opposite of what the bug-numbered lab issues suggest at a glance,
so the reasoning matters. Every lab issue carrying a `bug#NNNNN` was opened by
a maintainer — Rahul Martim Juliato (LionyxML, the `Maintainer:` header) or
Stéphane Marks (shipmints, co-maintainer, though the file header does not name
him). [#26](https://github.com/LionyxML/markdown-ts-mode-lab/issues/26)
recording "@shipmints already submitted a patch" to debbugs is therefore a
maintainer filing into their own patch queue, not a model for an outside
contributor. The genuinely outside reports —
[#51](https://github.com/LionyxML/markdown-ts-mode-lab/issues/51),
[#57](https://github.com/LionyxML/markdown-ts-mode-lab/issues/57),
[#59](https://github.com/LionyxML/markdown-ts-mode-lab/issues/59) — are plain
reports with no patch and no bug number, and the maintainers route things to
debbugs from there.

Two further reasons to ask before filing:

- The maintainers said outright that they want discussion in the lab repo
  because email threads are harder to follow.
- `patches.md` carries an unsubmitted **"Improve link handling in
  'markdown-ts-mode'"** entry. Its stated contents (reference links, autolinks,
  link-reference-definition fontification) are already in master, so the file
  looks stale — but a link-handling patch sitting in their queue is adjacent
  enough to items 1 and 2 that it is worth one question rather than a
  surprise collision.

Once they agree, debbugs is still where the fix has to land: `markdown-ts-mode`
is `lisp/textmodes/markdown-ts-mode.el` in Emacs core, so only a bug there can
carry a patch to a commit, and the lab issue then gets `(bug#NNNNN)` appended
to its title the way the maintainers' own do. Nothing is ever "reposted": a
debbugs bug is a mail thread, so a revised patch is a reply to
`NNNNN@debbugs.gnu.org` on the same bug.

Grammar-level problems are the exception: they cannot be fixed in the mode at
all, so they belong to `tree-sitter-markdown`, tracked in the lab repo at
[issue #5](https://github.com/LionyxML/markdown-ts-mode-lab/issues/5).

One formatting note: the drafts here are written GitHub-flavoured, and debbugs
is plain-text email, so flatten any table before sending that copy.

## Status of this list

Checked against upstream `origin/master` at `ab1d6868ed3` (2026-09-03); the
installed build carries the same `markdown-ts-mode` bar one unrelated one-line
fix (`5919ac3fac6`, bare-URL `mailto:` prefix). All 59 lab issues (open and
closed) were fetched and grepped: **none of the items below is already filed.**
Three are adjacent to existing issues and should cross-reference them.

"Verified live" means reproduced in `emacs -Q --batch` against the installed
build. Reproducers for the two background items are in
`docs/markdown-ts-mode/background-artifacts-repro.el`.

When filing, unwrap the prose to one line per paragraph — GitHub and the Emacs
bug tracker soft-wrap, and hard wraps render badly.

---

## Mode-fixable — file against Emacs

### 1. Link destinations are used verbatim, never unwrapped or percent-decoded

*Verified live. No existing issue. **Drafted** —
`01-destination-brackets (draft).md`, with reproducer and tested patch.*

`[a](<my file.md>)` hands `find-file` the literal `<my file.md>`;
`[a](my%20file.md)` hands it `my%20file.md`. Both create an empty buffer
instead of opening the file. There is no bracket-stripping or `url-unhex`
anywhere in the file. CommonMark *requires* the `<…>` form when a destination
contains spaces, so this is the documented spelling failing.

The same root cause has a third symptom, which is the one to cite for severity:
a **bracketed URL** goes to `find-file` rather than `browse-url`. The scheme
test in `markdown-ts--make-link-button` runs on the still-bracketed string, so
it never matches `\`[a-z]+:` and the destination falls through to the local-file
branch — `[a](<https://ex.com/x?a=1&b=2>)` opens a buffer visiting a nonsense
relative path, and saving it would create the file.

Fix: strip a matched `<…>` pair at the top of `markdown-ts--make-link-button`
(so the scheme test sees `https:`, which also fixes the bracketed URL) and at
`markdown-ts--fontify-image`'s extraction. Local equivalent, minus the
decoding half: `markdown-config--normalize-link-path`.

### 2. The same raw text breaks image rendering

*Verified live. No existing issue. **Drafted separately** —
`02-destination-percent-encoding (draft).md`. Split from item 1 because
unbracketing is CommonMark syntax with no trade-off, while decoding is a URI
reading the spec does not ask for: it needs a user option and cannot resolve a
name literally containing `%25`. The image symptom appears under both.*

`markdown-ts--fontify-image` resolves the destination with
`(expand-file-name (treesit-node-text dest t))`, so a bracketed or
`%20`-encoded path fails the `file-exists-p` guard and the image silently
never renders.

Same root cause as #1 — one shared helper fixes both, and they should be filed
together. Read from the source rather than reproduced: the batch harness
renders no image at all (a valid control also fails, apparently an
outline-overlay artifact), so this path is not testable headless.

### 3. `link_title` is not hidden under `markdown-ts-hide-markup`

*Verified live. No existing issue. Low severity — cosmetic, and only affects
documents that use link titles.*

The brackets, parens and `link_destination` of an `inline_link` all get
`invisible 'markdown-ts--markup`; `link_title` only gets a face. With
hide-markup on, this source

```
See [label](https://ex.com "the title") and [plain](https://ex.com) here.

[lab]: https://ex.com "ref title"
```

renders as

```
See label "the title" and plain here.

lab "ref title"
```

where it should render as `See label and plain here.` / `lab`.

Why this is a defect and not a preference:

- Two identical constructs render differently — `[label](url "title")` keeps
  visible text that `[plain](url)` does not, purely because metadata is
  attached, while the URL is hidden in both.
- CommonMark makes the title the HTML `title` attribute, i.e. a tooltip. No
  renderer displays it inline, so showing it contradicts what hide-markup is
  for. The same argument applies to the destination, which upstream already
  hides, so "keep it visible while editing" is not a coherent counter-position.
- Upstream gives `link_title` the *same* face as the destination
  (`@markdown-ts-link-destination`), i.e. classifies it as destination-category
  markup — and hides the destination. That reads as an oversight.

Two sites, not one: `link_reference_definition` has the same gap
(`markdown-ts--fontify-link-ref-label` hides the brackets and colon,
`markdown-ts--fontify-link-ref-destination` hides the URL, the title survives).

Fix: route both `(inline_link (link_title))` and
`(link_reference_definition (link_title))` through
`markdown-ts--fontify-delimiter`. Not quite a one-liner: the whitespace between
`link_destination` and `link_title` belongs to neither node, so hiding only the
title leaves a stray space behind (`label  and` with two spaces). The fix has
to cover the inter-node whitespace as well — or hide the whole `( … )` span.

### 4. No inline rendering inside pipe-table cells

*Verified live. No existing issue; adjacent to #42.*

In a table cell, `[lnk](t.md)` gets no button and no markup hiding, and
`**bold**` / `` `code` `` get no faces:

```
| [lnk]     label: face=(markdown-ts-table-cell markdown-ts-table) button=no  dest-invisible=nil
Para [lnk]  label: face=…                                          button=YES dest-invisible=markdown-ts--markup
```

Cause is the range rule, not the grammar: `((inline) @markdown-inline)` embeds
a local inline parser on host `(inline)` nodes only, and a `pipe_table_cell` is
not one. (The *global* `markdown-inline` parser does see the construct, which
is why a whole-buffer query finds `inline_link` inside a row — a different
parser instance from the ones font-lock uses.)

Fix: extend the range rules to cover table cells. Worth raising in the same
report: hiding markup inside a cell with plain `invisible` collapses it to zero
width and misaligns the table, so cells need width-preserving hiding — the
local workaround uses a `(space :width N)` `display` property. This also
interacts with
[#42, table prettification under hide-markup](https://github.com/LionyxML/markdown-ts-mode-lab/issues/42).

Highest-impact item: an upstream fix removes the local table workaround
entirely.

### 5. An `html_block`'s trailing newline keeps the block face while its text loses it

*Verified live. No existing issue; same family as #31.*

```
#1 html_block: text-face=font-lock-comment-face  newline-face=markdown-ts-html-block
```

Two layers with mismatched extents:

- `((html_block) @markdown-ts-html-block)` faces the whole node, its trailing
  newline included.
- The mode also embeds the HTML grammar over that same node
  (`:embed html :host markdown … '((html_block) @html)`), and `html-ts-mode`
  faces the `comment` node — which covers `<!-- … -->` but *not* the newline —
  and **replaces** rather than combines.

So the newline is the only character still showing the block face. Give
`markdown-ts-html-block` a background with `:extend t` and a row of HTML
comments renders with its text on the default background and the rest of the
row running to the window edge in the block colour. Reproducer: example 1 in
`docs/markdown-ts-mode/background-artifacts-repro.el`.

This is the mode's own layering, not the grammar — a block node carrying its
own newline is conventional.

Cross-reference
[#31 "Wrong html colors"](https://github.com/LionyxML/markdown-ts-mode-lab/issues/31):
same base-face-not-overridden family, different mechanism (there an `ERROR`
node leaves `html-ts-mode`'s queries nothing to match, so a whole closing tag
keeps the block face). A fix that makes the two layers agree on extent and
combination would likely cover both.

Two fixes are possible, and the report should present both rather than assume
one:

- **Stop applying `markdown-ts-html-block` to the trailing newline.** Simple,
  and it makes the row consistent. Cost: a `markdown-ts-html-block`
  background can then never fill a row.
- **Have the embedded HTML faces combine with the block face rather than
  replace it.** The comment text keeps the block background and gains a
  comment foreground; the newline already matches. Keeps the face usable for
  what it is for.

Whichever is chosen, flag that the first must **not** be generalized to block
faces at large: a fenced code block *needs* its trailing newline faced, since
that is what extends the background across the full row, and
`markdown-ts-code-block`'s docstring documents background usage as intended.

### 6. Inline images break pixel-precision scrolling

*No existing issue.*

`markdown-ts--fontify-image` attaches the image as an `after-string` prefixed
with `"\n"`. An after-string has no buffer position, so that newline creates a
phantom display line `pixel-scroll-precision-mode` cannot anchor `window-start`
to, and scrolling jumps by a whole image height — the bug#64252 family.

Fix direction, as used locally for embeds: put the image in a `display`
property on a single buffer position and hide the remaining markup, so
`window-start` has nowhere to park. A wide `display` span is nearly as bad as
the after-string, because `window-start` can land deep inside it.

### 7. Fence lines leave a stray blank row while editing

*Enhancement — needs a design pitch, not a bug report. No existing issue.*

Whole-line fence collapse exists in `markdown-ts-view-mode` only. In an
editable buffer with `markdown-ts-hide-markup` on, only the delimiter *text* is
marked invisible, so the line's newline stays live and every hidden fence
leaves an empty row.

The in-code comment in `markdown-ts--fontify-delimiter` says editing buffers
were skipped deliberately, over hide-markup UX hazards (point movement,
backspace across invisible regions). So this has to be pitched as an answer to
that objection rather than as an oversight: collapse the line with an overlay
`display` of `""` and let stock `reveal-mode` open the fence point is on for
editing. Only `display` + a `reveal-toggle-invisible` function is both fully
collapsing and revealable — a plain `invisible` overlay is invisible to
`reveal-mode`, and ellipsis-`invisible` renders a literal `…` on the row.

---

## Grammar — file against `tree-sitter-markdown`, lower priority

### 8. `indented_code_block` absorbs trailing blank lines

*Verified live. No existing issue; belongs on lab #5.*

The node range swallows the blank lines that follow the block:

```
indented_code_block range 27..61 = "    indented code\n    more code\n\n\n"
```

CommonMark is explicit that blank lines *following* an indented code block are
not part of it, so the grammar deviates from the spec and the mode faithfully
faces the range it is handed — the code-block background leaks onto the empty
lines below. Reproducer: example 2 in `docs/markdown-ts-mode/background-artifacts-repro.el`.

Lower priority because it is not directly fixable in the mode. Add it to
[lab #5, the grammar issue tracker](https://github.com/LionyxML/markdown-ts-mode-lab/issues/5).

A mitigation is available in the mode meanwhile, and is worth mentioning so
"the grammar's fault" is not read as "nothing can be done": replace the plain
`@markdown-ts-indented-code-block` face capture with a fontifier that clamps
the face to the last non-blank line.

---

## Not candidates

- **Revealing non-Markdown link targets in `dired`** — local policy, not a
  defect. Upstream's `find-file`-for-everything is a defensible default.
- **Wiki links and `![[embeds]]`** — Obsidian flavour, outside upstream's
  CommonMark + GFM scope. Kept in `markdown-obsidian.el`.
- **`markdown-ts-table-fill-cells`** — a missing feature, not a defect, so not
  a bug report. But
  [#41 "Pipe table wrap/unwrap cell text"](https://github.com/LionyxML/markdown-ts-mode-lab/issues/41)
  is an open request for exactly this, including the unwrap direction this
  implementation does not have. Offering the implementation there is the
  natural move.
- **`my/md-recreate-inline-parser-at-point`** — the maintainer's debug helper
  implies a stale-inline-parser bug, but bug#81019 and bug#81195 have landed
  since. Needs a fresh reproducer before filing anything.
- **Background bugs already reported** — the two items in
  `docs/markdown-ts-mode/background-artifacts-repro.el` were sent to the maintainers on
  2026-06-14 with no reply. Both still reproduce, and they are items 5 and 8
  above; filing them properly (Emacs for 5, the grammar tracker for 8) is the
  way to unstick them. Item 5's original framing is probably why it drew no
  reply: `markdown-ts-html-block` carries no background by default and no
  built-in theme gives it one, so the artifact only *shows* once you set one.
  The mismatched extents underneath are real regardless, and that is what the
  report should lead with.

## Related open issues worth tracking

Not ours to file, but they bear on local configuration:

- [#39 "Refine URIs as buttons behavior"](https://github.com/LionyxML/markdown-ts-mode-lab/issues/39)
  — `button-map` takes `RET` ahead of `markdown-ts-mode-map`, which is annoying
  when editing a URL. Proposes a user option to gate `push-button` on
  `markdown-ts-hide-markup`. `markdown-config--link-keymap` deliberately
  mirrors the button gestures (`RET`, `mouse-1`, `mouse-2`) for the links that
  never become buttons, so it should follow whatever upstream settles on.
- [#42 "Prettify pipe tables when hiding markup"](https://github.com/LionyxML/markdown-ts-mode-lab/issues/42)
  — overlay-based table prettification; overlaps the width-preservation
  question in item 4.
