# yasnippet-config.el

Snippet expansion engine. Originally pulled in for `lsp-mode` (which
relies on yasnippet to turn LSP placeholder strings like
`"fn(${1:arg1}, ${2:arg2})"` into interactive tab-stops); also drives
the snippet libraries under `yasnippets/` for non-LSP editing modes.
Loaded from `init.el` immediately before `lsp-core.el` because lsp-mode
consumes the engine at completion time.

## External packages

- `yasnippet` — snippet engine. `yas-global-mode` is enabled; snippet
  root is set to `yasnippets/` under the config root.

## Cross-module touchpoints

- **`lsp-core.el`** — every `lsp-*-config.el` module assumes yasnippet
  is loaded so LSP completion candidates expand interactively. If this
  module fails to load, lsp-mode degrades gracefully but server
  placeholders show up as literal text.
- **AUCTeX (`latex-config.el`)** — AUCTeX's major mode is `LaTeX-mode`,
  which does *not* derive from `latex-mode`. A `LaTeX-mode-hook`
  activates the built-in `latex-mode` snippet directory via
  `yas-activate-extra-mode` so a single snippet folder serves both
  modes.

## Invariants — do not change without reading

### `yas-alias-to-yas/prefix-p` must be set in `:init`, not `:config`

Yasnippet keeps the legacy `yas/*` command names as live `defalias`
entries pointing at the modern `yas-*` symbols. They are not declared
obsolete, so they clutter `M-x` completion. The package exposes
`yas-alias-to-yas/prefix-p` to suppress them entirely, but the
docstring is explicit: *it must be set to nil before loading yasnippet
to take effect*. Hence the `setq` lives in the `use-package :init`
block, not `:config`. Don't move it.

## Yasnippet directory layout — easy to break

Snippet root is `<config>/yasnippets/`. Two rules that *will* silently
break snippet discovery if violated:

1. **No yasnippet control files in the root** (`.yas-parents`,
   `.yas-make-groups`, `.yas-metadata`). If any are present, yasnippet
   treats the root as a single mode-specific directory (for a mode named
   `"yasnippets"`) and refuses to scan subdirectories — every per-mode
   folder becomes invisible.

2. **Folder names must exactly match the major-mode symbol; case
   matters**. AUCTeX uses `LaTeX-mode` (capital L, capital T), the
   built-in mode is `latex-mode`. They are different directories.
   Use `yas-activate-extra-mode` to bridge naming gaps; the file
   does this for AUCTeX:
   - `LaTeX-mode-hook` activates `latex-mode` snippets.

   For Markdown the snippet directory is named `markdown-ts-mode/`
   (matching the only Markdown major mode this config installs); no
   bridge is needed.
