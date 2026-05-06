# lsp-core.el

Shared LSP infrastructure used by every `lsp-*-config.el` module: client
core, diagnostics, and UI overlays. The snippet engine that lsp-mode
uses to expand server-returned placeholders is configured separately in
`yasnippet-config.el` — see `docs/modules/yasnippet-config.md`.

## External packages

- `lsp-mode` — the LSP client.
- `lsp-diagnostics` — *not* a separate package; ships inside `lsp-mode`. We
  declare it via `use-package :straight nil :after lsp-mode` purely to force
  `require` so its faces (e.g. `lsp-flycheck-info-unnecessary` for "unused"
  diagnostics) are defined before any server can reference them. Without
  this, early diagnostics trigger "Invalid face reference" warnings.
- `flycheck` — diagnostics frontend (left-fringe indicators).
- `lsp-ui` — sideline hints, doc child frames.

## Cross-module touchpoints

- Loaded by every language module (`lsp-python-config.el`,
  `lsp-rust-config.el`, …) — they all assume the keymap prefix and
  completion provider choice set here.
- **`yasnippet-config.el`** — must be loaded before this module; lsp-mode
  hands snippet completions to yasnippet at runtime.
- **`completions/corfu.el`** + **`completions/cape.el`** are the actual
  completion frontend; this is signalled to lsp-mode via
  `lsp-completion-provider :none` (without it, lsp-mode tries to set up
  company-mode and prints a warning).
- **`which-key`**: `lsp-enable-which-key-integration` is added to
  `lsp-mode-hook` so the `C-c l` prefix shows the popup.

## Completion in LSP buffers — yasnippet + LSP merged super-CAPF

`lsp-completion-mode-hook` runs
`emacs-config--lsp-completion-merge-snippets`, which replaces the bare
`lsp-completion-at-point` entry that lsp-mode just prepended with a
single merged CAPF:

```elisp
(cape-capf-properties
 (cape-capf-super
  (cape-capf-prefix-length #'yasnippet-capf 3)
  (cape-capf-buster #'lsp-completion-at-point))
 :exclusive 'no)
```

What each layer does:

- `cape-capf-super` merges yasnippet keys with LSP candidates into
  one popup. They share identifier-shaped bounds, so the merge is safe.
- `cape-capf-prefix-length 3` keeps yasnippet quiet on 1–2 char input,
  where the much larger LSP candidate list dominates anyway.
- `cape-capf-buster` invalidates LSP's prefix cache between
  keystrokes — necessary because LSP returns context-sensitive
  candidates that must be re-fetched as the prefix changes.
- `cape-capf-properties :exclusive 'no` lets the chain fall through
  to subsequent CAPFs (`cape-file` inside path strings, `cape-tex`
  after `\`, prose super, …) when neither inner CAPF has a match.
  This replaces the older `:filter-return cape-nonexclusive` advice
  on `lsp-completion-at-point` — exclusivity now lives next to the
  CAPF that needs it instead of being injected via advice.

Order matters: yasnippet first → snippet keys ranked above LSP
symbols in the popup. With `cape-capf-super` the result is a *merged*
view (not "winner takes all"), so you still see LSP alternatives
alongside the snippet match.

## Hover info — three independent display systems

| System              | What it shows                                  | When it shows           |
| ------------------- | ---------------------------------------------- | ----------------------- |
| ElDoc (echo area)   | symbol signature only (`lsp-eldoc-render-all nil`) | always, on cursor move |
| lsp-ui-sideline     | hover, diagnostics, code-action hints         | inline, right of line   |
| lsp-ui-doc child frame | full hover docs                              | **on demand** via `C-c l h g` (`lsp-ui-doc-glance`) |

The sideline shows hover *in addition* to ElDoc; the duplication is
deliberate so the inline view doesn't disappear when you move past the
symbol. The lsp-ui-doc child frame is **not** shown automatically — both
`lsp-ui-doc-show-with-cursor` and `lsp-ui-doc-show-with-mouse` are
explicitly `nil`.

## Key bindings

| Key            | Action                                             |
| -------------- | -------------------------------------------------- |
| `C-c l`        | LSP keymap prefix                                  |
| `C-c l h g`    | `lsp-ui-doc-glance` — pop the full doc child frame |

## Performance / behavior knobs

| Setting                              | Value      | Why                                           |
| ------------------------------------ | ---------- | --------------------------------------------- |
| `read-process-output-max`            | 4 MB       | larger LSP JSON payloads without stalls       |
| `lsp-diagnostics-provider`           | `:flycheck`| richer display, fringe stays fixed            |
| `lsp-completion-provider`            | `:none`    | hand-off to corfu+cape                        |
| `lsp-headerline-breadcrumb-enable`   | `t`        | breadcrumb in header-line                     |
| `lsp-auto-guess-root`                | `t`        | use `project.el` for workspace root           |
| `lsp-guess-root-without-session`     | `t`        | skip `.lsp-session-v1` (file stops growing)   |
| `flycheck-indication-mode`           | `'left-fringe` | no layout jitter; degrades to TTY        |
| `lsp-eldoc-enable-hover`             | `t`        | hover info to echo area                       |
| `lsp-eldoc-render-all`               | `nil`      | one-line signature, not full docs             |

## Invariants — do not change without reading

### `lsp-completion-provider :none` is required, not optional

Without it, lsp-mode assumes company-mode and tries to wire it up
automatically. Since corfu is the completion frontend here, lsp-mode prints
a warning at startup. `:none` tells lsp-mode "I'll wire completion myself"
— corfu's `cape-capf-*` machinery picks up the LSP CAPF without help.

### `lsp-diagnostics` must be force-required (`:after lsp-mode`)

Diagnostic faces are defined inside `lsp-diagnostics.el` (which ships
inside `lsp-mode`'s repo). If a server sends a diagnostic referencing a
face like `lsp-flycheck-info-unnecessary` *before* `lsp-diagnostics` is
loaded, you get "Invalid face reference" warnings. The
`use-package lsp-diagnostics :straight nil :after lsp-mode` block exists
purely to force `require` at the right time.

### lsp-ui-doc is on-demand only

The child-frame popup is not automatic. If you find this surprising while
moving the cursor over a symbol and seeing nothing, that's by design:
ElDoc gives you the signature in the echo area; `C-c l h g` pops the
full popup. Don't flip `lsp-ui-doc-show-with-cursor` to `t` without
considering the visual noise — the previous decision was that automatic
popup competes with ElDoc and sideline.

### Kind-First Routing patch is currently DISABLED

The block starting at the comment "Patched lsp--parser-on-message to
prioritize 'method' (Kind-First routing)" is wrapped in `(when nil ...)`.
The patch is *defined* but *not active*. It was previously enabled to
prevent protocol deadlocks when server-initiated requests collide with
client IDs (see `docs/lsp-mode-01-collision-resolution.md`). If symptoms
recur (LSP hangs, "Received a response without a matching request"
warnings), re-enable by removing the `(when nil ...)` wrapper.

The earlier `CLAUDE.md` text ("Includes a global surgical patch …
prevents protocol deadlocks") is **stale** — it described the patch as
active.

### Session file `~/.config/emacs/.lsp-session-v1` is intentionally bypassed

`lsp-guess-root-without-session t` makes lsp-mode rely on `project.el`
exclusively. The session file is never read or written, so it stops
growing. Don't re-enable it — there's no benefit and the cache becomes
stale across `project.el` root changes.

### Commented-out fork `alberti42/fork-lsp-mode` is no longer needed

The `:straight (... :branch "show-diagnostic-codes" ... )` recipe at
lines 11–16 references a personal fork that exposed diagnostic codes via
flycheck. Upstream lsp-mode now passes `:id code?` to `flycheck-error-new`
inside `lsp-diagnostics--flycheck-start` (see the comment on the
`flycheck` `use-package` block), so diagnostic codes are natively
available via `flycheck-error-id`. Safe to delete the commented block at
some point.

