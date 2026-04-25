# markdown-config.el

Markdown reading and authoring. Configures both `markdown-ts-mode`
(primary, daily) and `markdown-mode` (escape hatch) in a single file.

External packages: `markdown-mode` (MELPA), `grip-mode` (MELPA).
`markdown-ts-mode` is built into Emacs 31.

## Dual-mode design

`markdown-ts-mode` is the daily driver, routed via the
`major-mode-remap-alist` entry `(markdown-mode . markdown-ts-mode)` in
`treesitter-config.el`. It is fast on large files where `markdown-mode`
stalls Emacs.

`markdown-mode` is intentionally **kept installed and fully configured**.
Reach it via `M-x markdown-mode`. It retains:

- A patched wiki-link follower (fixes upstream's extension-doubling and
  space→dash mangling).
- A custom local-link follower wired through
  `markdown-follow-link-functions`.
- Markup hiding on entry.
- `grip-mode` on `markdown-mode-command-map` (`C-c C-c g`).

The `markdown-mode` block exists because `markdown-ts-mode` does not yet
cover note-taking workflows (notably wiki-link follow at point). When
parity is reached, the block can be dropped — but **not unilaterally**.

## Shared link helpers

Both modes call into the same helpers, kept at the top of the file:

- `markdown-config--follow-wiki-link` — resolves an Obsidian-style name
  relative to the current buffer; `.md`/`.markdown` open via
  `find-file`, other files open `dired` with point on the target,
  missing paths signal `user-error`. **Never creates empty files.**
- `markdown-config--follow-local-link` — same rules for `[label](path)`
  destinations. Returns `t` when handled (local) and `nil` for full URLs
  so callers can fall back to `browse-url`. Used both as a member of
  `markdown-follow-link-functions` and as a direct call from the
  ts-mode dispatcher.
- `markdown-config-follow-link-at-point` — ts-mode-only dispatcher.
  Cond order:
  1. `[[wiki]]` / `[[wiki|label]]` via `thing-at-point-looking-at` and
     `markdown-config--wiki-link-regexp` (the grammar does **not**
     expose wiki links — see invariant below).
  2. `[label](path)` via treesit, walking up to the `inline_link`
     ancestor and reading the `link_destination` child.
  3. Bare URL at point via `thing-at-point 'url`.
  4. Otherwise `user-error "No link at point"`.

## Keybindings

| Mode               | Key         | Command                                  |
| ------------------ | ----------- | ---------------------------------------- |
| `markdown-ts-mode` | `C-c C-o`   | `markdown-config-follow-link-at-point`   |
| `markdown-ts-mode` | `C-c C-c g` | `grip-mode`                              |
| `markdown-ts-mode` | `mouse-1` / `mouse-2` on a wiki link | `markdown-config-follow-link-at-point` |
| `markdown-mode`    | `C-c C-o`   | (native, calls patched wiki/link logic)  |
| `markdown-mode`    | `C-c C-c g` | `grip-mode` (via `markdown-mode-command-map`) |

## Wiki-link fontification (markdown-ts-mode only)

The grammar gap means `[[name]]` / `[[name|alias]]` would otherwise
appear as plain text. We add visual recognition with a **single
font-lock keyword** layered on top of the tree-sitter rules. No grammar
fork, no syntax-propertize pass.

What the matcher does for each match:

1. Splits the inner content on `|` to identify the visible label
   (alias when present, name otherwise).
2. Restricts match data to the label range so the
   `markdown-config-wiki-link-face` applies to it only — face inherits
   from the built-in `link` face.
3. Adds `mouse-face`, `keymap`, and `help-echo` text properties so
   `mouse-1` / `mouse-2` follow the link via the existing dispatcher
   (the keymap binds `[follow-link]` to `mouse-face` so
   `mouse-1-click-follows-link` activates).
4. Marks the surrounding markup (`[[name|` prefix and `]]` suffix)
   `invisible` with the symbol `markdown-ts-hide`.

The `markdown-ts-hide` symbol is `markdown-ts-mode`'s own invisibility
spec; toggling `M-x markdown-ts-toggle-hide-markup` adds/removes that
symbol from `buffer-invisibility-spec`, which automatically shows or
hides our markup ranges. We therefore set the `invisible` property
unconditionally — visibility is controlled by the spec, not by the
property's presence.

### Performance

Cost is **one bounded single-line regex** (`\[\[[^]\n]+\]\]`) per
visible window via `jit-lock`. Not measurable. The reasons
`markdown-mode` is slow on large files do not apply here:

- No `markdown-fontify-code-blocks-natively` (a whole secondary major
  mode booted per fenced block).
- No `markdown-syntax-propertize` pass.
- No multiline regex keywords scanning the buffer.

### Why not extend the tree-sitter grammar instead?

Considered and rejected. Forking `tree-sitter-markdown` to add a
`wiki_link` node would mean owning merge conflicts forever, building
the parser `.so` on every machine, and isolating us from the rest of
the tree-sitter ecosystem (Helix, nvim-treesitter, GitHub) which
wouldn't see our node. The regex cost is invisible; the grammar cost
is structural and ongoing.

## Invariants — do not change without reading

### Wiki links are detected by regex, not tree-sitter

`tree-sitter-markdown` (both the upstream master and our `split_parser`
branch) does **not** expose `[[name]]` as a node type. The dispatcher
matches them with `markdown-config--wiki-link-regexp`. Don't rewrite
this branch as a treesit query — it will silently return nil.

### Inline links are detected via treesit, not regex

For `[label](path)` we walk up to the `inline_link` ancestor and read
the `link_destination` child. This handles nested brackets and
escaped parens correctly; a regex-based detector would mis-match.
The grammar node names are stable — don't paraphrase them.

### `markdown-mode` is preserved on purpose

The `use-package markdown-mode` block, the `:override` advice, and the
`markdown-follow-link-functions` hook all **stay**. Daily traffic goes
to `markdown-ts-mode` via the `major-mode-remap-alist` entry, but the
escape hatch must keep its fixes active. Do not consolidate to a single
mode without explicit user agreement.

### `grip-mode` is bound twice on purpose

`markdown-mode` puts it on `markdown-mode-command-map`'s `g` (the
package-native command-prefix convention; resulting chord is
`C-c C-c g`). `markdown-ts-mode` has no command map, so the chord is
defined directly on `markdown-ts-mode-map`. Both reach the same key
sequence; the bindings are **not** redundant.

### `:bind` in the `markdown-ts-mode` block

`markdown-ts-mode` is built-in (`:straight nil`). use-package's `:bind`
defers loading correctly for built-ins via autoload registration.
Don't replace it with an `eval-after-load` form unless you have a
specific reason — `:bind` is the canonical pattern in this repo.

## Cross-module touchpoints

- `treesitter-config.el` provides the `markdown-mode → markdown-ts-mode`
  remap and the `split_parser` grammar pair. Removing either breaks
  this module.
- `syntaxes/markdown.el` sets `fill-column 100` for both modes;
  `text-mode-hook` triggers `soft-wrap-mode` (because
  `markdown-ts-mode` derives from `text-mode`).
- `lsp-ltex-plus-config.el` may attach to either mode for grammar
  checking — orthogonal to this module.
