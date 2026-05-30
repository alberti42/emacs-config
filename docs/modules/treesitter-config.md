# treesitter-config.el

Tree-sitter grammar bootstrap and major-mode remapping for Emacs 29+.

External packages: none — built entirely on the bundled `treesit`.

## What it does

1. Checks `treesit-available-p`; warns and exits if Emacs was built
   without tree-sitter support.
2. Populates `treesit-language-source-alist` with the grammars we use.
3. Walks the alist on load and runs `treesit-install-language-grammar`
   for any missing grammar, suppressing the install confirmation prompt.
4. Sets `major-mode-remap-alist` so opening a file routes to the
   `-ts-mode` variant where one is desired.
5. Exposes `treesitter-config-reinstall-grammars` for manual updates.

## Cross-module touchpoints

- **`lsp-kotlin-config.el`** depends on the Kotlin grammar tracked here.
  See the invariants section below.
- **`markdown-config.el`** configures `markdown-ts-mode` directly via
  `:mode` on `\\.md\\'` and `\\.markdown\\'`. There is no longer a
  `markdown-mode` block, and no remap entries are needed for it. See
  `docs/modules/markdown-config.md`.

## Grammars installed

| Language          | Source                                                                   | Notes                                                                  |
| ----------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| `json`            | `tree-sitter/tree-sitter-json`                                           |                                                                        |
| `yaml`            | `ikatyang/tree-sitter-yaml`                                              |                                                                        |
| `toml`            | `tree-sitter-grammars/tree-sitter-toml`                                  |                                                                        |
| `elisp`           | `Wilfred/tree-sitter-elisp`                                              |                                                                        |
| `typescript`      | `tree-sitter/tree-sitter-typescript` (subdir `typescript/src`)           | shared repo with `tsx`                                                 |
| `tsx`             | `tree-sitter/tree-sitter-typescript` (subdir `tsx/src`)                  | same                                                                   |
| `bash`            | `tree-sitter/tree-sitter-bash`                                           |                                                                        |
| `zsh`             | `tree-sitter-grammars/tree-sitter-zsh`                                   | dedicated grammar; remapped to `bash-ts-mode` (no `zsh-ts-mode` exists) |
| `python`          | `tree-sitter/tree-sitter-python`                                         |                                                                        |
| `kotlin`          | `fwcd/tree-sitter-kotlin` (master)                                       | see invariants                                                         |
| `markdown`        | `tree-sitter-grammars/tree-sitter-markdown`, **branch `split_parser`**, subdir `tree-sitter-markdown/src` | needs `markdown-inline` too                |
| `markdown-inline` | same repo + branch, subdir `tree-sitter-markdown-inline/src`             | required by `markdown` for inline parsing                              |

## Major-mode remap

| Source mode        | Target mode          | Note                                                              |
| ------------------ | -------------------- | ----------------------------------------------------------------- |
| `json-mode`        | `json-ts-mode`       |                                                                   |
| `js-json-mode`     | `json-ts-mode`       |                                                                   |
| `yaml-mode`        | `yaml-ts-mode`       |                                                                   |
| `toml-mode`        | `toml-ts-mode`       |                                                                   |
| `typescript-mode`  | `typescript-ts-mode` |                                                                   |
| `tsx-mode`         | `tsx-ts-mode`        |                                                                   |
| `sh-mode`          | `bash-ts-mode`       |                                                                   |
| `zsh-mode`         | `bash-ts-mode`       | no `zsh-ts-mode`; bash mode handles it                            |
| `python-mode`      | `python-ts-mode`     |                                                                   |
| (markdown)         | `markdown-ts-mode`   | routed via `:mode` in `markdown-config.el`, not via remap-alist   |

## Public API

- `M-x treesitter-config-reinstall-grammars` — force-reinstall every
  grammar in `treesit-language-source-alist`. Useful when a grammar has
  been updated upstream.

## Invariants — do not change without reading

### Kotlin grammar tracks `master` (do not re-pin to an old commit)

```elisp
(kotlin "https://github.com/fwcd/tree-sitter-kotlin")
```

This was previously pinned at `57170e50` to stay before the
external-scanner interpolation tokens added by `55622a4` (2026-04-11,
"Multi-dollar string interpolation" #260). That pin is now **inverted**:
current `kotlin-ts-mode` (the `string` feature) queries the
`interpolation_identifier_start` / `interpolation_expression_start` /
`interpolation_expression_end` nodes that *only* the post-`55622a4`
grammar provides. Pinning to the old grammar makes those node types
absent, so treesit can't compile the `string` feature and disables it
entirely (`treesit-font-lock-rules-mismatch`).

So: don't re-pin to a pre-`55622a4` commit. If you ever do pin (for
reproducibility), pick a commit at or after `55622a4` that still has
those three nodes, and re-test font-lock on a `.kt` file with string
interpolations (`"hello $name"` and `"sum: ${a+b}"`) before merging.

`lsp-kotlin-config.md` references this grammar dependency from the
cross-module side.

### Markdown needs the `split_parser` branch *and* both grammars

`tree-sitter-markdown`'s default branch ships a single combined grammar
that handles both block- and inline-level constructs. `markdown-ts-mode`
(both the bundled Emacs 31 version and the LionyxML MELPA package)
needs the *split* version: a block-level `markdown` grammar plus an
inline `markdown-inline` grammar, sourced from the `split_parser`
branch with two different subdirs.

If you remove either entry, font-lock fails (the bundled mode silently
falls back to no highlighting). If you point at the master branch,
queries fail at install time because the grammar shape doesn't match.

### Bootstrap loop suppresses `y-or-n-p` via `cl-letf`

```elisp
(cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
  (treesit-install-language-grammar lang))
```

`treesit-install-language-grammar` asks "Install language grammar for
LANG? " on first install. We rebind `y-or-n-p` to always return `t`
*locally* (the binding is undone when the form exits) so the bootstrap
runs unattended on a fresh machine. Don't replace this with a
`(setq treesit-language-source-alist ...)` and a manual install hook —
the suppression is what makes startup non-interactive.

### Each install wrapped in `condition-case`

A single grammar that fails to compile (e.g. missing `gcc`, network
issue, repo moved) emits a warning via `display-warning` and the loop
continues. Don't replace this with a bare call — partial failures are
expected (an offline/laptop install) and shouldn't break Emacs startup
for every other language.

### `zsh-mode → bash-ts-mode`

There is no `zsh-ts-mode`. The bash grammar handles enough zsh syntax
for editing purposes (font-lock, indentation). The dedicated `zsh`
grammar is installed because some other tooling may consume it directly,
but the mode mapping itself goes to bash.

### Markdown is `markdown-ts-mode`-only

There is no `markdown-mode` block in this config and no
`(markdown-mode . markdown-ts-mode)` entry in `major-mode-remap-alist`.
`.md` and `.markdown` are routed straight to `markdown-ts-mode` via
`:mode` in `markdown-config.el`. The previous dual-mode setup (with
`markdown-mode` as an escape hatch) was removed once `markdown-ts-mode`
reached feature parity for note-taking workflows. See
`markdown-config.md`.
