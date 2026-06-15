# markdown-config.el

Markdown reading and authoring. Configures `markdown-ts-mode`
(tree-sitter backed, bundled with Emacs 31) and adds wiki-link
support, link-following, and markup hiding for inline links — including
inline links inside table cells, which the grammar leaves unparsed — on
top of the bundled rules.

External packages: `markdown-preview-mode` (MELPA). `markdown-ts-mode`
is built-in and used as-is (no vendored copy). No `markdown-mode`
configuration block exists in this file.

> **Preview — two options, both bound in `markdown-ts-mode-map` and both
> exporting through `markdown-command` (pointed at
> `pandoc --from=gfm --to=html5`; pandoc must be on `PATH`).** Note
> `C-c C-c` is `markdown-ts-toggle-checkbox` in markdown-ts-mode (a
> command, not a prefix), so the preview keys can't use it — unlike classic
> markdown-mode, which puts preview on `C-c C-c p` / `C-c C-c l`. The p/l
> mnemonics are kept under the `C-c C-x` extended-command prefix instead.
>
> - `C-c C-x l` → `markdown-live-preview-mode` (ships with the markdown-mode
>   package): renders in a window via eww, no browser or external server. A
>   `display-buffer-alist` entry pins that output to the right and reuses
>   it on re-export; it matches the preview's buffer-local
>   `markdown-live-preview-source-buffer` (not the bare `*eww*` name) so
>   ordinary eww windows are unaffected, and relies on
>   `markdown-split-window-direction` staying `any` (its default) so the
>   preview routes through `display-buffer`.
> - `C-c C-x p` → `markdown-preview-mode` (package): serves the rendered
>   HTML over a local websocket + http server to a browser, wraps the body
>   in `<article class="markdown-body">`, and styles it with the light
>   github-markdown-css (classic black-on-white; the auto variant rendered
>   GitHub's dark theme under OS dark mode) plus a small `data:` URI that
>   centers and pads the column. **Caveat patched here:** the package's
>   minor-mode body forcibly runs `(markdown-mode)` unless the major mode is
>   already markdown-mode/gfm-mode, which would yank a markdown-ts-mode
>   buffer out of tree-sitter. An `:around` advice
>   (`markdown-config--mpm-preserve-major-mode`) stubs the `markdown-mode`
>   *function* to `ignore` for the duration of the toggle, so that one call
>   no-ops while the real major mode is untouched. The advice is
>   **unconditional** — it must NOT be guarded by `(derived-mode-p
>   'markdown-mode)`, because markdown-ts-mode declares markdown-mode as an
>   extra parent (Emacs 30 `derived-mode-extra-parents`), making that
>   predicate non-nil in markdown-ts-mode buffers. The package's idle timer +
>   after-save re-export have no major-mode guard, so live preview still
>   works in markdown-ts-mode.
>
> Both replaced `grip-mode`, which scrapes GitHub's full page chrome and,
> being unmaintained since 4.6.2 (Sept 2022), now renders unstyled.

> **`markdown-mode` is still installed**, but only as a transitive
> dependency of `lsp-mode` (`lsp-mode.el` does
> `(require 'markdown-mode)` at the top because it renders LSP hover
> popups via markdown-mode). It is not configured here, no hooks fire,
> none of its custom variables are tuned, and `M-x markdown-mode` is
> not advertised as a workflow. If you want it as a real escape hatch,
> consult git history for the previous configuration block.

## File routing

`.md` and `.markdown` are routed directly to `markdown-ts-mode` via
`:mode` in this file's `use-package` block. There is no
`markdown-mode → markdown-ts-mode` entry in
`major-mode-remap-alist` (since `markdown-mode` is not installed),
and no `gfm-mode` mapping (README.md is handled the same as any
other `.md`).

## Link helpers

- `markdown-config--follow-wiki-link` — resolves an Obsidian-style name
  relative to the current buffer; `.md`/`.markdown` open via
  `find-file`, other files open `dired` with point on the target,
  missing paths signal `user-error`. **Never creates empty files.**
- `markdown-config--follow-local-link` — same rules for `[label](path)`
  destinations. Returns `t` when handled (local) and `nil` for full URLs
  so the caller can fall back to `browse-url`.
- `markdown-config--inline-link-destination-at-point` — walks up to
  the `inline_link` ancestor of the node at point, reads the
  `link_destination` child's text, and **strips a leading `<` and
  trailing `>`** from CommonMark's pointy-bracket form
  (`[label](<url with spaces>)`). Returns nil when not on a link.
- `markdown-config-follow-link-at-point` — dispatcher bound on
  `markdown-ts-mode-map` and on `markdown-config--link-keymap`
  (used by both wiki-link and inline-link mouse text properties).
  Cond order:
  1. `[[wiki]]` / `[[wiki|label]]` via `thing-at-point-looking-at` and
     `markdown-config--wiki-link-regexp` (the grammar does **not**
     expose wiki links — see invariant below).
  2. `[label](path)` via the treesit helper above (paragraphs).
  3. `[label](path)` via `thing-at-point-looking-at` and
     `markdown-config--inline-link-regexp` — a regex fallback for
     contexts with no `inline_link` node, chiefly **table cells** (see
     "Inline links inside tables" below). Group 2 is stripped of
     pointy-brackets before following, so `[label](<url>)` works too.
  4. Bare URL at point via `thing-at-point 'url`.
  5. Otherwise `user-error "No link at point"`.

## Keybindings

| Key         | Command                                  |
| ----------- | ---------------------------------------- |
| `C-c C-o`   | `markdown-config-follow-link-at-point`   |
| `C-c C-x l` | `markdown-live-preview-mode`             |
| `C-c C-x p` | `markdown-preview-mode`                  |
| `mouse-1` / `mouse-2` on a wiki link or inline link | `markdown-config-follow-link-at-point` |

## Link rendering (markdown-ts-mode only)

`markdown-ts-mode-hook` runs
`markdown-config--markdown-ts-mode-setup`, which closes two gaps in
the bundled mode.

### Wiki links — font-lock keyword

The grammar does not expose `[[name]]` / `[[name|alias]]`, so neither
face nor markup hiding nor click apply out of the box. A **single
font-lock keyword** layered on top of the tree-sitter rules handles
all three:

1. Splits the inner content on `|` to identify the visible label
   (alias when present, name otherwise).
2. Restricts match data to the label range so
   `markdown-config-wiki-link-face` (inherits from the built-in
   `link` face) applies to that range only.
3. Adds `mouse-face`, `keymap`, and `help-echo` text properties so
   `mouse-1` / `mouse-2` follow the link via the existing dispatcher
   (the keymap binds `[follow-link]` to `mouse-face` so
   `mouse-1-click-follows-link` activates).
4. When `markdown-ts-hide-markup` is non-nil, marks the surrounding
   markup (`[[name|` prefix and `]]` suffix) `invisible` against the
   `markdown-ts--markup` invisibility spec — the same spec used by
   the bundled mode's other hidden markup.
   `markdown-ts-toggle-hide-markup` calls `font-lock-flush`, which
   re-runs the matcher with the new value of `markdown-ts-hide-markup`.

### Inline links — treesit rule extension

`[label](url)` IS a grammar node. The bundled mode applies `link`
face to the label and `font-lock-string-face` to the URL, but two
things are missing:

1. The brackets, parens, URL, and optional title aren't hidden when
   `markdown-ts-hide-markup` is on — only headings, code spans,
   emphasis, and a few other constructs are.
2. The label has no clickability — no `mouse-face`, no `keymap`,
   no `help-echo`. `mouse-1` / `mouse-2` do nothing useful.

We close both gaps by appending **one** tree-sitter font-lock rule
that runs four queries against the `markdown-inline` parser:

- `(inline_link [ "[" "]" "(" ")" ] @markdown-ts--fontify-delimiter)`
- `(inline_link (link_destination)  @markdown-ts--fontify-delimiter)`
- `(inline_link (link_title)        @markdown-ts--fontify-delimiter)`
- `(inline_link (link_text)         @markdown-config--inline-link-text-fontify)`

The first three reuse the bundled `markdown-ts--fontify-delimiter`,
which applies face AND invisibility against `markdown-ts--markup`
— so toggle and refontification behave exactly like the rest of
the mode's hidden markup. With hide-markup on, the brackets, parens,
URL, and title disappear; the label remains.

The fourth runs `markdown-config--inline-link-text-fontify` over
the label. That fontifier doesn't apply a face (the bundled rule
already gives the label `link` face); it only attaches text
properties: `mouse-face 'highlight`, `keymap
markdown-config--link-keymap`, and a `help-echo` of the form
`"Link → <destination>"` with angle brackets stripped.
`markdown-config--link-keymap` is the **same** keymap used for
wiki-link labels, so all link clicks across the buffer route
through the same `markdown-config-follow-link-at-point` dispatcher.

The feature symbol (`markdown-config-inline-link-extras`) is merged
into `treesit-font-lock-feature-list` at level 3 so it activates at
the default `treesit-font-lock-level`.
`treesit-font-lock-recompute-features` is called once after the
buffer-local settings are extended.

### Inline links inside tables — font-lock keyword

The treesit rule above only fires where the `markdown-inline` parser
runs. The grammar parses **table-cell** content as raw block-level
tokens and does **not** route it through `markdown-inline`, so a cell
like `| [DESCRIPTION](DESCRIPTION) | … |` exposes no `inline_link`
node — `treesitter-explore` shows `(pipe_table_cell [ . _ . ] ( . _ . ))`,
where a paragraph shows `(inline … (inline_link …))`. The treesit
rule therefore renders nothing inside tables.

`markdown-config--table-inline-link-fontify` closes this gap with the
same parser-agnostic mechanism as wiki links: a `re-search-forward`
font-lock keyword over `markdown-config--inline-link-regexp`. It scans
the whole buffer, but **every effect is gated on
`markdown-config--in-table-cell-p`** (which walks up the `markdown`
block tree looking for a `pipe_table` ancestor). For each match:

1. The label gets `link` face, `mouse-face`, `keymap`
   (`markdown-config--link-keymap` — the shared one), and a
   `help-echo`, so it is clickable via the same dispatcher.
2. When `markdown-ts-hide-markup` is non-nil, the surrounding `[` and
   `](url)` are blanked with a **width-preserving** `display`
   `(space :width N)` — **not** `invisible`.

> **Why `display`-space and not `invisible` here.** Table columns are
> aligned by raw character count. `invisible` collapses the markup to
> zero width, which shifts everything after it and misaligns the table.
> `(space :width N)` (N = the markup's character length) blanks the
> markup while reserving exactly its original width, so the cell keeps
> its column count and the table stays aligned. `display` is added to
> `font-lock-extra-managed-props` so toggling hide-markup off cleanly
> removes it and reveals the URL.

The paragraph/table split is purely by the `markdown-config--in-table-cell-p`
gate: paragraph links never reach this matcher's body, so prose keeps
the bundled `invisible` collapse (no reserved gap — correct for prose),
and only table links reserve width. No per-link configuration.

### Performance

- Wiki links: one bounded single-line regex (`\[\[[^]\n]+\]\]`) per
  visible window via `jit-lock`. Not measurable.
- Inline links (paragraphs): a tree-sitter query reusing nodes the
  parser already built. No extra parse, no buffer scan.
- Inline links (tables): one bounded single-line regex per visible
  window via `jit-lock`, plus a cheap `pipe_table` ancestor check per
  match. Like wiki links, not measurable.

The reasons `markdown-mode` is slow on large files do not apply here:

- No `markdown-fontify-code-blocks-natively` (a whole secondary major
  mode booted per fenced block).
- No `markdown-syntax-propertize` pass.
- No multiline regex keywords scanning the buffer.

### Why not extend the tree-sitter grammar instead?

For wiki links specifically: forking `tree-sitter-markdown` to add a
`wiki_link` node would mean owning merge conflicts forever, building
the parser `.so` on every machine, and isolating us from the rest of
the tree-sitter ecosystem (Helix, nvim-treesitter, GitHub) which
wouldn't see our node. The regex cost is invisible; the grammar cost
is structural and ongoing.

## Invariants — do not change without reading

### Wiki links are detected by regex, not tree-sitter

`tree-sitter-markdown` (both the upstream master and our `split_parser`
branch) does **not** expose `[[name]]` as a node type. Two places
match wiki links by regex:

1. The dispatcher (`markdown-config-follow-link-at-point`) uses
   `markdown-config--wiki-link-regexp` to pick the link out of the
   text around point.
2. The font-lock matcher (`markdown-config--wiki-link-fontify`) uses
   the equivalent regex inside `re-search-forward` to fontify and add
   click behavior.

Don't rewrite either branch as a treesit query — the grammar will
silently return no nodes. See "Why not extend the tree-sitter grammar
instead?" above.

### Inline links are detected via treesit, not regex — except in tables

For `[label](path)` **in paragraphs** we walk up to the `inline_link`
ancestor and read the `link_destination` child. This handles nested
brackets and escaped parens correctly; a regex-based detector would
mis-match. The grammar node names are stable — don't paraphrase them.

The pointy-bracket form `[label](<url with spaces>)` returns
`<url with spaces>` from `treesit-node-text` — angle brackets included.
`markdown-config--inline-link-destination-at-point` strips one matched
`<…>` pair before returning, so the follower sees a plain path.

**Tables are the exception.** Inside a `pipe_table` there is no
`inline_link` node (the grammar keeps cell content out of the
`markdown-inline` parser), so the treesit detector returns nil and both
rendering and following fall back to `markdown-config--inline-link-regexp`.
That regex's group 2 matches either `<url>` (which may contain `)`) or a
bare URL stopping at the first `)`; `markdown-config--strip-pointy-brackets`
removes the angle brackets on follow. Don't try to make the table path
use treesit — there is nothing to query. See "Inline links inside
tables" above.

### Inline-link hiding reuses `markdown-ts--fontify-delimiter`

The treesit rule we append uses the bundled (internal,
double-underscore) function so face + invisibility behave identically
to the rest of the mode. If a future Emacs version renames that
function, our rule has to follow. The risk is low (the symbol has
been stable since Emacs 30.x); the alternative would be to inline a
copy of the function, which then drifts from upstream.

### Inline-link fontification relies on the `markdown-inline` grammar

Inline-link work in this module — bundled `link` face on `[label]`,
our `markdown-config-inline-link-extras` rule (hiding **and**
click-to-follow), and the dispatcher's treesit branch — all depend
on `markdown-inline` seeing complete `inline_link` constructs. Early
Emacs 31 builds fragmented that view (the `markdown-inline` embedding
used `:range-fn #'treesit-range-fn-exclude-children`, so `inline_link`
never assembled); this was fixed upstream and the bundled mode now
assembles inline links correctly. If a future regression breaks
inline-link fontification/hiding/`C-c C-o` while wiki links (regex
only) keep working, suspect the `markdown-inline` range setup rather
than this module.

### `:bind` in the `markdown-ts-mode` block

`markdown-ts-mode` is built-in (`:straight nil`). use-package's
`:bind` defers loading correctly for built-ins via autoload
registration. Don't replace it with an `eval-after-load` form
unless you have a specific reason — `:bind` is the canonical
pattern in this repo.

## Cross-module touchpoints

- `treesitter-config.el` provides the `split_parser` grammar pair
  (`markdown` + `markdown-inline`). Removing either entry breaks this
  module. There is no `markdown-mode → markdown-ts-mode` remap — file
  routing is via `:mode` in this file.
- `syntaxes/markdown.el` sets `fill-column 100` for `markdown-ts-mode`;
  `text-mode-hook` triggers `soft-wrap-mode` (because
  `markdown-ts-mode` derives from `text-mode`).
- `lsp-ltex-plus-config.el` may attach to `markdown-ts-mode` for
  grammar checking — orthogonal to this module.
