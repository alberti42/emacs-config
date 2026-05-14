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
- `sideline` — generic inline-annotation framework, hooked to
  `flycheck-mode` so it activates wherever flycheck does.
- `sideline-flycheck` — sideline backend rendering flycheck diagnostics
  at end of line ("this is wrong").
- `sideline-lsp` — sideline backend rendering LSP code actions per line
  ("do this to fix it"), queried directly from `lsp-mode`.

`lsp-ui` is no longer used. Sideline replaces `lsp-ui-sideline`; the
on-demand hover popup `lsp-ui-doc-glance` was removed because ElDoc
(echo area) plus `C-c l h h` (`lsp-describe-thing-at-point`) covered
the same workflow.

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

## Completion in LSP buffers — `lsp-completion-at-point` wrapped

`lsp-completion-mode-hook` runs `emacs-config--lsp-completion-setup`,
which replaces the bare `lsp-completion-at-point` entry that
lsp-mode just prepended with a wrapped form:

```elisp
(cape-capf-properties
 (cape-capf-buster #'lsp-completion-at-point)
 :exclusive 'no)
```

What each layer does:

- `cape-capf-buster` invalidates LSP's prefix cache between
  keystrokes. This effectively overrides the server's
  `isIncomplete: false` hint and treats every response as
  `isIncomplete: true` — a deliberately conservative choice that
  guards against server bugs (e.g. servers reporting "complete" when
  they truncated their list) and against single-keystroke context
  changes (crossing `.`, string boundaries, scope) where the cached
  candidate list is no longer correct. See the comment in
  `lsp-core.el` for the full rationale and how to revert if you
  want to honor `isIncomplete: false`.
- `cape-capf-properties :exclusive 'no` lets the chain fall through
  to subsequent CAPFs (`cape-file` inside path strings, `cape-tex`
  after `\`, prose super, …) when LSP returns no candidates. This
  replaces the older `:filter-return cape-nonexclusive` advice on
  `lsp-completion-at-point` — exclusivity now lives next to the
  CAPF that needs it instead of being injected via advice.

**Snippets are intentionally not merged into this CAPF.** A previous
iteration wrapped both `yasnippet-capf` and `lsp-completion-at-point`
in `cape-capf-super` so they shared one popup, but the workflow
("auto-popup must show snippet keys as I type") didn't justify the
complexity (3-char gates, syntax-table widening for `-`,
predicate-based prefix filtering, mode-derivation gotchas in
Emacs 30+ for `python-ts-mode` vs `python-mode`). Snippets are now
inserted on demand via `C-c y` (`yas-insert-snippet`) — see
`docs/modules/yasnippet-config.md`.

## Hover info and inline annotations — independent display systems

| System              | What it shows                                  | When it shows                      |
| ------------------- | ---------------------------------------------- | ---------------------------------- |
| ElDoc (echo area)   | symbol signature only (`lsp-eldoc-render-all nil`) | always, on cursor move         |
| sideline-flycheck   | diagnostics from flycheck                      | inline, right of each diagnostic line |
| sideline-lsp        | code actions offered by the LSP server         | inline, right of current line      |
| full hover docs     | full hover documentation buffer                | **on demand** via `C-c l h h` (`lsp-describe-thing-at-point`) |

Diagnostics flow: LSP server → lsp-mode → flycheck → `sideline-flycheck`.
Code actions flow: LSP server → lsp-mode → `sideline-lsp` directly (per
line), bypassing flycheck — flycheck has no concept of "fixes", only
errors. The two are separate packages because the `sideline` ecosystem
treats them as distinct backends; `lsp-ui-sideline` previously bundled
both into one package.

## Key bindings

| Key            | Action                                             |
| -------------- | -------------------------------------------------- |
| `C-c l`        | LSP keymap prefix                                  |
| `C-c l h h`    | `lsp-describe-thing-at-point` — full hover docs    |

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

### No automatic hover popup

The `lsp-ui-doc` child-frame is no longer wired up — `lsp-ui` is not
installed. Hover information is split across:

- **ElDoc** (echo area): one-line signature, follows the cursor.
- **`C-c l h h`** (`lsp-describe-thing-at-point`): full docs in a help
  buffer, on demand.

If you find yourself wanting an at-point floating popup again, re-add
`lsp-ui` and bind `lsp-ui-doc-glance` to a key — but consider whether
the echo area + help buffer combination already covers the workflow.

### Session file `~/.config/emacs/.lsp-session-v1` is intentionally bypassed

`lsp-guess-root-without-session t` makes lsp-mode rely on `project.el`
exclusively. The session file is never read or written, so it stops
growing. Don't re-enable it — there's no benefit and the cache becomes
stale across `project.el` root changes.

### Commented-out fork `alberti42/fork-lsp-mode` is no longer needed

The `:straight (... :branch "integrated" ... )` recipe at lines 11–16
references a personal fork that carried several patches. All of them
have since been merged upstream:

- Kind-First JSON-RPC routing (prevents protocol deadlocks when
  server-initiated requests collide with client IDs).
- Diagnostic codes exposed via `flycheck-error-id` — upstream lsp-mode
  now passes `:id code?` to `flycheck-error-new` inside
  `lsp-diagnostics--flycheck-start`.
- Two further critical patches in the same series.

Safe to delete the commented `:straight` recipe.

