# markdown-config.el

Markdown reading and authoring. Configures `markdown-ts-mode`
(tree-sitter backed, bundled with Emacs 31) and adds wiki-link
support, link-following, and markup hiding for inline links on top
of the bundled rules.

External packages: `grip-mode` (MELPA). `markdown-ts-mode` is
built-in; we carry a patched copy at `local/markdown-ts-mode.el`
loaded ahead of the bundled file via `:load-path` (see
"Link rendering" prerequisite below). No `markdown-mode`
configuration block exists in this file.

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
  2. `[label](path)` via the treesit helper above.
  3. Bare URL at point via `thing-at-point 'url`.
  4. Otherwise `user-error "No link at point"`.

## Keybindings

| Key         | Command                                  |
| ----------- | ---------------------------------------- |
| `C-c C-o`   | `markdown-config-follow-link-at-point`   |
| `C-c C-c g` | `grip-mode`                              |
| `mouse-1` / `mouse-2` on a wiki link or inline link | `markdown-config-follow-link-at-point` |

## Link rendering (markdown-ts-mode only)

`markdown-ts-mode-hook` runs
`markdown-config--markdown-ts-mode-setup`, which closes two gaps in
the bundled mode.

> **Prerequisite — patched `markdown-ts-mode.el`.** Both gaps below
> assume the inline grammar can actually see complete `inline_link`
> constructs. The upstream Emacs 31 file uses `:range-fn
> #'treesit-range-fn-exclude-children` for the `markdown-inline`
> embedding, which fragments the parser's view across anonymous
> tokens (`[`, `]`, `(`, `)`, `<`, `>`, `.`, `/`, …) emitted by the
> `markdown` block grammar inside `(inline)`. Without the fix, the
> bundled `(inline_link (link_text) @link)` rule never matches and
> inline-link work in this module silently does nothing. We carry a
> patched copy of `markdown-ts-mode.el` in `local/`, loaded ahead of
> the bundled file via the `:load-path` directive in the
> `use-package` block; the patch is one line — drop the `:range-fn`.
> See `docs/markdown-ts-mode-fragment-link-bug-PR-in-preparation.md`
> for the upstream report. Once the fix lands in a stable Emacs
> release we can delete `local/markdown-ts-mode.el` and the
> `:load-path` line.

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

### Performance

- Wiki links: one bounded single-line regex (`\[\[[^]\n]+\]\]`) per
  visible window via `jit-lock`. Not measurable.
- Inline links: a tree-sitter query reusing nodes the parser already
  built. No extra parse, no buffer scan.

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

### Inline links are detected via treesit, not regex

For `[label](path)` we walk up to the `inline_link` ancestor and read
the `link_destination` child. This handles nested brackets and
escaped parens correctly; a regex-based detector would mis-match.
The grammar node names are stable — don't paraphrase them.

The pointy-bracket form `[label](<url with spaces>)` returns
`<url with spaces>` from `treesit-node-text` — angle brackets included.
`markdown-config--inline-link-destination-at-point` strips one matched
`<…>` pair before returning, so the follower sees a plain path.

### Inline-link hiding reuses `markdown-ts--fontify-delimiter`

The treesit rule we append uses the bundled (internal,
double-underscore) function so face + invisibility behave identically
to the rest of the mode. If a future Emacs version renames that
function, our rule has to follow. The risk is low (the symbol has
been stable since Emacs 30.x); the alternative would be to inline a
copy of the function, which then drifts from upstream.

### `local/markdown-ts-mode.el` is load-bearing for inline links

Inline-link work in this module — bundled `link` face on `[label]`,
our `markdown-config-inline-link-extras` rule (hiding **and**
click-to-follow), and the dispatcher's treesit branch — all depend
on `markdown-inline` seeing complete `inline_link` constructs. The bundled Emacs 31 file does not allow
this (see "Link rendering" prerequisite above). The local copy in
`local/markdown-ts-mode.el` carries a one-line patch (drop
`:range-fn #'treesit-range-fn-exclude-children` from the
`markdown-inline` embedding) and is preferred at load time via
`:load-path` in the `markdown-ts-mode` `use-package` block.

If `local/markdown-ts-mode.el` is deleted or the `:load-path` is
removed before the upstream fix ships in a release, inline-link
fontification, hiding, and `C-c C-o` will all silently regress.
Wiki links keep working — they're regex-only — but you'll see the
asymmetric breakage and likely chase the wrong layer.

When the upstream fix lands in a stable Emacs release: delete
`local/markdown-ts-mode.el`, remove `:load-path` from the
`use-package` block, and update
`docs/markdown-ts-mode-fragment-link-bug-PR-in-preparation.md`.

### `:bind` and `:load-path` in the `markdown-ts-mode` block

`markdown-ts-mode` is built-in (`:straight nil`). use-package's
`:bind` defers loading correctly for built-ins via autoload
registration. Don't replace it with an `eval-after-load` form
unless you have a specific reason — `:bind` is the canonical
pattern in this repo.

`:load-path` is a `lambda` that prepends `<emacs-config-dir>/local/`
to `load-path`, so the patched `local/markdown-ts-mode.el` is
loaded ahead of the bundled file (see "Link rendering"
prerequisite). Don't drop it without first deleting
`local/markdown-ts-mode.el` and confirming the upstream fix is
present in the running Emacs.

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
