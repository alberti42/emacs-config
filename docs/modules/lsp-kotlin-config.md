# lsp-kotlin-config.el

Kotlin LSP via `kotlin-ts-mode` and JetBrains' official `kotlin-lsp`,
with the lsp-mode-bundled fwcd client kept as a fallback.

## External packages

- `kotlin-ts-mode` — tree-sitter-based major mode for `.kt` and `.kts`.

## External binaries

| Binary                     | Source                                                          | Role                       |
| -------------------------- | --------------------------------------------------------------- | -------------------------- |
| `kotlin-lsp`               | `brew install JetBrains/utils/kotlin-lsp`                       | primary (Kotlin 2.2+)      |
| `kotlin-language-server`   | `brew install kotlin-language-server` (fwcd)                    | fallback (Kotlin ≤ 2.1)    |

Only the primary needs to be present on most machines. The fallback is
useful only when `kotlin-lsp` is unavailable on the platform.

## Cross-module touchpoints

- **`lsp-core.el`** — base LSP infrastructure (`lsp-deferred`, etc.).
- **`treesitter-config.el`** — provides the Kotlin grammar. **The grammar
  is pinned** to commit `57170e50`. Newer commits (`55622a4` and after,
  2026-04-11, "Multi-dollar string interpolation" #260) replaced the
  literal `"$"` / `"${"` tokens in the `_interpolation` rule with
  external-scanner rules, which breaks `kotlin-ts-mode`'s `string`
  font-lock feature. Don't unpin without re-checking that font-lock still
  works — see the inline comment in `treesitter-config.el`.
- **`apheleia-config.el`** — registers `ktlint` for `kotlin-ts-mode`
  buffers (auto-format on save).

## How the dual-client setup works

lsp-mode's built-in `lsp-kotlin.el` registers a `kotlin-ls` client backed
by fwcd's `kotlin-language-server`, with **priority −1**. This module
registers a second client, `jetbrains-kotlin-lsp`, with **priority 0**:

| Server                | Client ID                | Priority | Source                |
| --------------------- | ------------------------ | -------- | --------------------- |
| JetBrains kotlin-lsp  | `jetbrains-kotlin-lsp`   | 0        | this module           |
| fwcd kotlin-language-server | `kotlin-ls`        | −1       | bundled with lsp-mode |

When both are registered, lsp-mode picks the higher-priority client; if
its launch fails (e.g. the JetBrains binary is missing), it falls back to
the lower-priority one.

The registration runs inside `(with-eval-after-load 'lsp-kotlin ...)` so
that the built-in `kotlin-ls` client is already on the registry before
this one is added.

## Invariants — do not change without reading

### JetBrains `kotlin-lsp` is required for Kotlin 2.2+

fwcd's `kotlin-language-server` (latest release 1.3.13 as of writing)
bundles the Kotlin 2.1.0 compiler. It rejects metadata from projects
built with Kotlin 2.2+ — symptoms are `INCOMPATIBLE_CLASS` errors on the
stdlib that cascade into `UNRESOLVED_REFERENCE` for everything. The
JetBrains server tracks current Kotlin and is the only working option
for modern projects.

Don't drop the JetBrains client and rely on the fwcd fallback unless the
project is locked to Kotlin ≤ 2.1.

### `:major-modes '(kotlin-mode kotlin-ts-mode)`

Both are listed even though the `:mode` association only routes to
`kotlin-ts-mode`. If a user manually invokes `M-x kotlin-mode` (the
non-tree-sitter mode from the `kotlin-mode` package), LSP should still
attach. Don't trim this to just `kotlin-ts-mode`.

### `:initialized-fn` pushes the `kotlin` configuration section

```elisp
(lambda (workspace)
  (with-lsp-workspace workspace
    (lsp--set-configuration (lsp-configuration-section "kotlin"))))
```

Without this, the server starts with built-in defaults and any
`lsp-kotlin-*` settings (defined upstream by lsp-mode for the fwcd client)
are not pushed. The `kotlin` section is the LSP-configuration namespace
both servers consume.
