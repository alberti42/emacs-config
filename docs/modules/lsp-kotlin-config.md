# lsp-kotlin-config.el

Kotlin LSP via `kotlin-ts-mode` and JetBrains' official `kotlin-lsp`. The
lsp-mode-bundled fwcd client is disabled outright, so `kotlin-lsp` is the
only server that can attach.

## External packages

- `kotlin-ts-mode` — tree-sitter-based major mode for `.kt` and `.kts`.

## External binaries

| Binary                     | Source                                                          | Role                       |
| -------------------------- | --------------------------------------------------------------- | -------------------------- |
| `kotlin-lsp`               | `brew install JetBrains/utils/kotlin-lsp`                       | the only server            |

`kotlin-lsp` must be on PATH. There is no fallback: the fwcd
`kotlin-language-server` client is disabled (see below), so a machine
without `kotlin-lsp` gets no Kotlin LSP at all.

## Cross-module touchpoints

- **`lsp-core.el`** — base LSP infrastructure (`lsp-deferred`, etc.).
- **`treesitter-config.el`** — provides the Kotlin grammar, tracking
  `master`. Current `kotlin-ts-mode` queries the external-scanner
  interpolation nodes (`interpolation_*_start`/`_end`) added in `55622a4`
  (2026-04-11, "Multi-dollar string interpolation" #260), so the grammar
  must be at or after that commit or treesit disables the `string`
  font-lock feature (`treesit-font-lock-rules-mismatch`). Don't re-pin to
  an older commit — see the inline comment in `treesitter-config.el`.
- **`apheleia-config.el`** — registers `ktlint` for `kotlin-ts-mode`
  buffers (auto-format on save).

## How the client setup works

lsp-mode's built-in `lsp-kotlin.el` registers a `kotlin-ls` client backed
by fwcd's `kotlin-language-server` (priority −1). This module disables
that client by adding it to `lsp-disabled-clients`, then registers its own
`jetbrains-kotlin-lsp` client (priority 0):

| Server                      | Client ID              | Status                          |
| --------------------------- | ---------------------- | ------------------------------- |
| JetBrains kotlin-lsp        | `jetbrains-kotlin-lsp` | active (this module)            |
| fwcd kotlin-language-server | `kotlin-ls`            | disabled via `lsp-disabled-clients` |

```elisp
(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-disabled-clients 'kotlin-ls))
```

With `kotlin-ls` disabled, lsp-mode never considers it, so
`jetbrains-kotlin-lsp` is the only Kotlin client that can attach — there is
no automatic fallback. The `:priority 0` is therefore moot but kept for
clarity of intent.

The JetBrains registration runs inside
`(with-eval-after-load 'lsp-kotlin ...)`, which also guarantees the
built-in `kotlin-ls` is on the registry (and already disabled) by the time
this runs.

## Invariants — do not change without reading

### JetBrains `kotlin-lsp` is required for Kotlin 2.2+

fwcd's `kotlin-language-server` (latest release 1.3.13 as of writing)
bundles the Kotlin 2.1.0 compiler. It rejects metadata from projects
built with Kotlin 2.2+ — symptoms are `INCOMPATIBLE_CLASS` errors on the
stdlib that cascade into `UNRESOLVED_REFERENCE` for everything. The
JetBrains server tracks current Kotlin and is the only working option
for modern projects — which is why the fwcd `kotlin-ls` client is disabled
outright rather than kept as a fallback.

If you ever need fwcd back (a project locked to Kotlin ≤ 2.1 on a machine
without `kotlin-lsp`), remove the `lsp-disabled-clients` entry rather than
lowering the JetBrains client's priority.

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
