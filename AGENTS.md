# Emacs Config: Agent Guide (AGENTS.md)

This directory is an Emacs configuration intended to be symlinked into
`~/.config/emacs/` (or wherever `user-emacs-directory` points). The canonical
source lives in this dotfiles repo; `init.el` is a thin entrypoint that locates
the *real* directory and loads the rest.

Use this document as the operating manual when making changes with an automated
agent (LLM) or when you want to understand the configuration structure.

## Goals and Non-Goals

Goals:

- Keep `init.el` small, readable, and stable.
- Put behavior into small, single-purpose modules.
- Be robust when `init.el` is symlinked (load modules from the real path).
- Prefer explicit, predictable defaults over heavy abstractions.
- Support both GUI Emacs and terminal Emacs (TTY), with a strong TTY baseline.

Non-goals:

- This is not a full distribution (Doom/Spacemacs). Avoid introducing a large
  framework unless explicitly requested.
- `custom.el` is not treated as a source-of-truth. Prefer code changes.

## Repository Layout

Key files:

- `early-init.el`
  - Loaded by Emacs before the package system and GUI init.
  - Sets `load-prefer-newer t` so Emacs always uses source files newer than their byte-compiled counterparts.
  - Loads `env-config.el` via `(unless (daemonp) ...)` so PATH and other env vars are set before `straight.el` runs. Skipped in daemon mode because the launcher already set up the environment.
  - Sets the default GUI font via `set-face-attribute` (family, height, weight). TTY frames ignore font face attributes, so no GUI guard is needed.

- `init.el`
  - User entrypoint.
  - Sets basic, early globals (no backups/autosaves, menu bar off, etc.).
  - Loads `emacs-config-core.el`.
  - Loads optional local modules via `emacs-config-load-module`.

- `emacs-config-core.el`
  - Bootstrapping and wiring.
  - Computes `emacs-config-dir` (real directory even when symlinked).
  - Defines `emacs-config-load-module` (safe local module loader).
  - Redirects Customize writes to `custom.el` (but does not auto-load it).
  - Bootstraps `straight.el` and installs/enables `use-package`.

- `custom.el`
  - Written by Emacs Customize UI.
  - Not auto-loaded.

Local modules loaded from `init.el` (via `emacs-config-load-module`):

- `env-config.el`: shell environment import for non-daemon GUI Emacs. When `(not (daemonp))`, parses `export KEY='VALUE'` lines from `$XDG_CACHE_HOME/zsh/interactive-shell-env.sh` and `$XDG_CONFIG_HOME/envs/LanguageTools.sh`, sets them via `setenv` (updates `exec-path` for PATH), and sets `COLORTERM=truecolor` + `TERM=xterm-256color`. Skipped when running as a daemon (the launcher already set up the environment). Loaded from `early-init.el` so PATH is correct before `straight.el` and any package lookups run.
- `treesitter-config.el`: tree-sitter grammar bootstrap. Checks `(treesit-available-p)` and installs missing grammars from `treesit-language-source-alist` (e.g. JSON) at load time.
- `ui-config.el`: UI chrome (menu/tool/scroll bars), window dividers, frame chrome, fonts, frame centering, TTY mode-line separator, truncation/continuation glyphs.
- `auto-revert-config.el`: file-system watcher that silently reverts clean buffers on external change and prompts when there are unsaved edits. Watches the parent **directory** (not the file itself) so that atomic writes via `rename(2)` are detected. Handles `renamed` events by updating `buffer-file-name` and re-attaching the watcher to the new path; handles `deleted` events by emitting a warning and tearing down the watcher.
- `buffer-kill-config.el`: smart kill-buffer behaviour — suppresses the "Buffer modified; kill anyway?" prompt when the buffer content is identical to the file on disk (edits were made and then fully undone). Hooks into `kill-buffer-query-functions` and clears the modified flag before the prompt fires.
- `mac-clipboard.el`: macOS TTY clipboard sync — wires kill-ring writes to `pbcopy`; deliberately omits the paste direction to avoid spawning a `pbpaste` subprocess on every `C-y`.
- `mac-pseudo-daemon-config.el`: keeps a hidden GUI frame alive on macOS so the Dock icon and menu bar stay functional after closing the last visible frame. (Currently **commented out** in `init.el`; kept but not loaded.)
- `recentf-config.el`: recently visited files list, persisted under `$XDG_CACHE_HOME/emacs/`.
- `treesitter-config.el`: tree-sitter grammar bootstrap. Checks `(treesit-available-p)` and automatically installs missing grammars from `treesit-language-source-alist` (JSON, YAML, TOML, Markdown) at load time. Uses `major-mode-remap-alist` to promote `-ts-mode` variants. Provides `treesitter-config-reinstall-grammars` for manual updates.
- `completion.el`: completion orchestration (styles + minibuffer UI + in-buffer completion).
- `nerd-icons-config.el`: Nerd Fonts icon integrations (used by Corfu kind-icon, Treemacs, etc.).
- `soft-wrap.el`: `soft-wrap-mode` (buffer-local minor mode) and `global-soft-wrap-mode` for visual-only soft wrapping. Used by text/Markdown configs.
- `syntaxes.el`: loads per-major-mode settings from `syntaxes/`.
- `csi-u-keys.el`: terminal key decoding for CSI-u sequences. Adds explicit decoders for Backspace variants (`S-backspace`, `C-backspace`, `C-S-backspace`), Ctrl+Tab (`\e[9;5u`), and Shift+Enter (`\e[13;2u`). Requires the application to opt in to CSI-u mode via `printf '\e[>4;1m'` (sent from zsh on startup); without this, tmux and terminals correctly fall back to legacy encoding.
- `dired-config.el`: Dired customizations (`dired-narrow`).
- `terminal-config.el`: terminal emulator settings — sets `xterm-256color` for `term` and `eshell`, sets `ESHELL` env var to `shell-file-name`, advises `term-handle-exit` to close the window when the process exits, and configures `vterm` (fast libvterm-backed terminal). Binds `C-@` (= C-SPC) and `C-M-m` in `vterm-mode-map` using `vterm-send-string` with raw bytes (`\C-@` and `\e\r`) instead of `vterm-send-key`, which re-encodes keys through the C module and produces CSI-u sequences when an app like Claude Code has enabled that mode. `C-SPC` cannot be used as the bind key — Emacs resolves it to `set-mark-command` from `global-map` before `vterm-mode-map` is consulted; `C-@` must be used instead. Also binds `C-g` to forward BEL so terminal apps receive it. Implements `ev` editor integration: `ev-open-file` (registered in `vterm-eval-cmds`) opens a file and binds `C-c C-c` to `ev-done`, which writes a semaphore file to unblock the shell-side `ev` script without involving the Emacs server.
- `magit-config.el`: Magit Git porcelain + Forge (GitHub/GitLab) integration. Includes `vdiff` and a local patched copy of `vdiff-magit` for side-by-side diffs; `e`/`E` in Magit buffers open vdiff instead of Ediff. Disables line numbers in `git-commit-mode` and `git-rebase-mode` buffers.
- `project-config.el`: project.el settings — sets `project-vc-merge-submodules nil` so git submodules are treated as independent project roots rather than merged into the parent repo.
- `search-config.el`: prefer ripgrep for project/xref search; isearch edge-triggered context scrolling (scrolls the minimum amount to keep `search-recenter-context-lines` of context visible when the match lands within `search-recenter-edge-threshold` lines of the window edge).
- `navigation-config.el`: cursor position jump history via `better-jumper`. Provides forward/backward jump list (`C-c [` / `C-c ]`), similar to Vim's C-o/C-i. Integrates automatically with xref/LSP jumps. NOTE (2026-03-24): `better-jumper.el` emits native compiler warnings for missing `declare-function` for `ring-*`, `evil-visual-state-p`, `get-current-persp`, and `safe-persp-name`. These are harmless (ring is always loaded; the others are optional integrations guarded by `fboundp`). TODO: file a PR upstream with `declare-function` declarations if we keep this package.
- `treemacs-config.el`: project file tree (Treemacs), TTY-friendly.
- `lsp-core.el`: shared LSP configuration (`lsp-mode`, `lsp-ui`, `yasnippet`).
- `lsp-python-config.el`: Python LSP via `lsp-pyright` (configured for basedpyright).
- `lsp-web-config.el`: JS/TS LSP (`typescript-mode`, built-in `js`).
- `lsp-json-config.el`: JSON LSP via `vscode-json-language-server` with SchemaStore auto-detection.
- `lsp-ltex-plus-config.el`: LTEX+ grammar/spell checks via `lsp-ltex-plus` (Markdown, LaTeX, plain text, Org, reStructuredText).
- `lsp-swift-config.el`: Swift LSP via `lsp-sourcekit` (SourceKit-LSP). Locates the server via `PATH` or `xcrun -f sourcekit-lsp` on macOS.
- `git-gutter-config.el`: VCS gutter indicators in both TTY and GUI frames. Loads a local copy of `git-gutter.el` (patched fork, kept in-repo until changes land upstream) via `:straight nil` + `:load-path emacs-config-dir`.
- `scroll-config.el`: scroll parameters and `ultra-scroll` for pixel-precise GUI scrolling.
- `windows-config.el`: window navigation, resizing, joining, and swapping — parallels tmux pane operations. `C-c <arrow>` navigates between Emacs windows and falls through to `tmux select-pane` at the edge. `C-c C-<arrow>` resizes (moves the shared border in the arrow direction, tmux convention). `C-c S-<arrow>` joins the current window as a split adjacent to the neighbour in that direction. `C-c M-<arrow>` swaps buffers with an adjacent window. Resize bindings support `repeat-mode` for repeated presses. `C-c <left>` and `C-c <right>` are explicitly unbound from `markdown-mode-map` in `syntaxes/markdown.el` to prevent `markdown-promote`/`markdown-demote` from shadowing the global navigation bindings; those commands are rebound to `C-c M-<` / `C-c M->`.
- `theme-harmonize.el`: synchronizes package faces with the active theme after every theme change. Sets `line-number` background (TTY only, via `theme-harmonize-tty-line-number`) to match the terminal emulator's padding color. Propagates the `line-number` background to git-gutter faces so the gutter column blends uniformly. Sets the background of `compilation-error`, `compilation-warning`, and `compilation-info` to match `line-number` so flymake left-margin indicators blend with the gutter column. Also propagates the `line-number` background to the `margin` face (guarded by `(facep 'margin)`) — this face is introduced by a pending Emacs patch (bug#80693) that allows customizing the margin background color; the guard makes the block a no-op on unpatched builds. Hooks into `enable-theme-functions` (Emacs 29+).
- `themes-config.el`: theme loading pipeline — loads `theme-harmonize` and `zac-theme-autodetection` via `use-package` (`:straight nil`, `:load-path emacs-config-dir`), sets `theme-harmonize-tty-line-number` and `zac-load-theme-callback`, installs and configures `modus-themes`, then loads `zac-theme-autodetection` last.
- `zac-theme-autodetection.el`: watches the OS appearance state file written by `zsh-appearance-control`; invokes `zac-load-theme-callback` (user-supplied callback). Contains no theme or color choices itself. Loaded via `use-package` (`:straight nil`) with `zac-load-theme-callback` set in `:init` so the watcher picks it up on first application.

Local package overrides (`local/`):

- `local/vdiff-magit.el`: local patched copy of the unmaintained `vdiff-magit` package. Fixes two Magit API breakages: `magit-get-revision-buffer` removed (replaced by `magit--get-blob-buffer`); `magit-find-file-index-noselect` dropped its second argument. Loaded via `:straight nil` with `:load-path`. TODO: file a PR upstream if the project shows signs of life.

Packages configured directly in `init.el` (not extracted into modules):

- `cl-lib` (built-in): Common Lisp compatibility helpers.
- `which-key` (built-in, Emacs 30+): display available keybindings in popup.
- `vim-file-locals`: parse Vim modelines/file-local settings.
- `mac-clipboard.el` (macOS TTY only): sync kill ring write direction with system clipboard (local module, no external package). Loaded conditionally in `init.el`.
- `xclip` (Linux TTY only): sync kill ring with system clipboard.
- `inheritenv`: provides tools (`inheritenv` macro, `inheritenv-add-advice`) to allow temp buffers to inherit buffer-local `process-environment` and `exec-path`. Loaded before LSP so packages that wrap it (e.g. rustic) work correctly.
- `multiple-cursors`: Sublime Text-style multiple cursors (`C->` / `C-<`).
- `tmux-tandem`: tmux open-file bridge — opens files in Emacs from tmux via IPC (Emacs 29+).
- `mouse` (built-in, TTY only): `xterm-mouse-mode` + mouse wheel bindings for terminal frames.
- `lua-mode`: major mode for Lua.
- `ssh-config-mode`: major mode for `~/.ssh/config`.

Per-major-mode settings (`syntaxes/`):

- `syntaxes.el` loads every `*.el` file in the `syntaxes/` directory.
- Each file should be small and self-contained (typically one hook form).
- Each file may be toggled by setting a single variable at the top of the file,
  e.g. `emacs-config-syntaxes-enable-markdown`.
- Syntax toggles default to enabled (`t`). To disable a syntax module, set its
  `emacs-config-syntaxes-enable-...` variable to `nil` in that syntax file.

Current syntax modules:

- `syntaxes/js.el`: JS/TS indentation settings.
- `syntaxes/json.el`: JSON indentation (supports `js-json-mode`, `json-mode`, `json-ts-mode`).
- `syntaxes/markdown.el`: Markdown settings. Unbinds `C-c <left>`/`C-c <right>` from `markdown-mode-map` and rebinds `markdown-promote`/`markdown-demote` to `C-c M-<` / `C-c M->`.
- `syntaxes/python.el`: Python indentation settings.
- `syntaxes/sh.el`: Shell script indentation (`sh-basic-offset 2`).
- `syntaxes/text.el`: visual soft wrap at 100 columns for `text-mode`.
- `syntaxes/yaml.el`: YAML indentation settings.
- `syntaxes/swift.el`: Swift indentation (`swift-mode:basic-offset 4`).
- `syntaxes/dired.el`: disables line numbers in Dired mode.
- `syntaxes/agent-shell.el`: disables line numbers in `agent-shell-mode`.

Wrapping:

- `soft-wrap.el` provides `soft-wrap-mode` (buffer-local) and `global-soft-wrap-mode` for visual-only wrapping. The target column is controlled via `soft-wrap-default-width` (defcustom) or `fill-column`. `soft-wrap--debug-dump` is an internal helper for debugging.
- Wrap-at-column is implemented with a window right margin (no newlines inserted). The left margin is preserved so TTY gutters (e.g. git-gutter) keep working.
- Continuation indentation uses built-in `visual-wrap-prefix-mode` (Emacs 30+). No external packages required.

Completion submodules (loaded by `completion.el`):

- `completions/styles.el`: baseline completion styles and category overrides.
- `completions/orderless.el`: Orderless matching (command-palette style).
- `completions/minibuffer-vertico.el`: Vertico minibuffer UI (preferred).
- `completions/minibuffer-icomplete.el`: Icomplete/Fido minibuffer UI (fallback).
- `completions/corfu.el`: Corfu in-buffer completion UI (with TTY support).
- `completions/cape.el`: extra CAPF sources via Cape.
- `completions/marginalia.el`: minibuffer annotations.
- `completions/consult.el`: Consult commands + xref UI.

Notes:

- `completion.el` exposes toggles you can set before it loads:
  - `emacs-config-completions-enable-marginalia`
  - `emacs-config-completions-enable-consult`

## Boot Sequence (Mental Model)

1. Emacs loads `init.el` from `user-emacs-directory`.
2. `init.el` resolves its *true* location (works through symlinks).
3. `init.el` loads `emacs-config-core.el`.
4. `emacs-config-core.el`:
   - sets `emacs-config-dir`
   - defines `emacs-config-load-module`
   - configures `custom-file` to `custom.el`
   - bootstraps `straight.el` and enables `use-package`
5. Back in `init.el`, packages and modules are configured.
6. Optional modules are loaded with warnings on failure (no hard crash unless
   the failure is in core wiring).

## Package Management

This config uses:

- `straight.el` as the package manager.
- `use-package` as the configuration macro.

Conventions:

- Prefer `use-package` for third-party packages.
- Use `:straight nil` for built-in packages.
- Modules should be loadable on their own once `emacs-config-core.el` has run.
- Keep package pinning/versioning decisions explicit if introduced.

Notes:

- Bootstrapping downloads `straight.el` from GitHub the first time.
- If you are modifying this config in an offline environment, avoid adding new
  packages that require immediate downloads, unless you also provide an
  offline-friendly path.

## Customize (`custom.el`)

`emacs-config-core.el` sets:

- `custom-file` => `custom.el` (in this directory)

and intentionally does **not** load it automatically.

Implications:

- Do not add hand-edits to `custom.el` as part of a feature. Prefer editing
  `init.el` or a module.
- If you need a Customize setting to take effect, either:
  - implement it in code, or
  - explicitly load `custom-file` (but that is a design change; do it only when
    requested).

## Local Module Pattern

When adding or editing modules, match the existing style:

- File header uses lexical binding:

  ```elisp
  ;;; my-module.el --- One-line description -*- lexical-binding: t; -*-
  ```

- End with:

  ```elisp
  (provide 'my-module)
  ;;; my-module.el ends here
  ```

- Keep a module narrowly focused.
- Prefer `emacs-config-load-module` from `init.el` for optional behavior.
  It emits a warning instead of aborting startup.

`emacs-config-load-module` expects a file named after the module symbol, e.g.:

- `(emacs-config-load-module 'completion "...")` loads `completion.el`.

It also accepts a string path relative to `emacs-config-dir`, which allows
subdirectories:

- `(emacs-config-load-module "completions/minibuffer-vertico" "...")` loads
  `completions/minibuffer-vertico.el`.

## Platform / Frame-Type Specific Behavior

TTY vs GUI:

- Clipboard helpers are conditional:
  - macOS terminal Emacs uses `mac-clipboard.el` (local module wrapping `pbcopy`) to sync clipboard writes.
  - Linux terminal Emacs uses `xclip` package.
- `git-gutter-config.el` loads a local patched `git-gutter.el` and runs in both TTY and GUI frames.
- Mouse wheel support in TTY is enabled via built-in `mouse` / `xterm-mouse-mode`.

macOS / Linux:

- Theme auto-detection (`zac-theme-autodetection.el`) reads a state file written
  by an external tool and uses file notification APIs when available.
- `mac-pseudo-daemon-config.el` (macOS only): keeps a hidden GUI frame alive so
  the Dock icon and menu bar stay functional when no visible frame exists.

## External Dependencies (Non-ELisp)

These modules expect external programs on `PATH`:

- Python LSP (`lsp-python-config.el`):
  - `basedpyright` (configured via `lsp-pyright-langserver-command`)

- JS/TS LSP (`lsp-web-config.el`):
  - `typescript-language-server`
  - `tsserver` (typically from `typescript` npm package)

- JSON LSP (`lsp-json-config.el`):
  - `vscode-json-language-server` (from `vscode-langservers-extracted` npm package)

- LTEX+ (`lsp-ltex-plus-config.el`):
  - `ltex-ls-plus` (Java-based server)

- Swift LSP (`lsp-swift-config.el`):
  - `sourcekit-lsp` (ships with the Swift toolchain; on macOS located via `xcrun`)

If any of these are missing, Emacs may still start but language features will
not work; the intent is graceful degradation.

## Theme Auto-Detection

`zac-theme-autodetection.el` integrates with:

- `zsh-appearance-control` (external)

It watches an `appearance` file that contains:

- `"1"` => dark
- `"0"` => light

Paths:

- `$ZAC_CACHE_DIR/appearance` if `ZAC_CACHE_DIR` is set
- else `$XDG_CACHE_HOME/zac/appearance`
- else `~/.cache/zac/appearance`

Current theme setup (via `themes-config.el`):

- `modus-themes` package is installed and configured (italic/bold constructs, mixed fonts).
- Theme variant selection: `modus-operandi` (light) / `modus-vivendi-tinted` (dark), set via
  `zac-load-theme-callback` in `themes-config.el`.
- `catppuccin-theme` is installed but disabled (commented out).
- Line-number background is overridden to match WezTerm's Catppuccin padding color
  (`#eff1f5` Latte / `#303446` Frappe), set via `theme-harmonize-tty-line-number` in
  `themes-config.el`.

Design choice:

- `zac-theme-autodetection.el` is a generic module: no color or theme choices live inside it.
- Theme selection (`zac-load-theme-callback`) is set in the `:init` block of `use-package zac-theme-autodetection` in `themes-config.el`, so it is always set before the package activates.
- Line-number colors are set via `theme-harmonize-tty-line-number` in `themes-config.el`.
- `theme-harmonize-theme` fires automatically via `enable-theme-functions` inside `load-theme`,
  handling line-number overrides, git-gutter propagation, and flymake margin indicator
  background synchronization without an explicit call.

## LTEX+ Module Notes

`lsp-ltex-plus-config.el` contains non-trivial glue code to:

- ensure `_ltex.*` commands are executed against the LTEX+ workspace (buffers
  may have multiple LSP workspaces, e.g. TeX + LTEX+)
- trigger a one-shot check on open so diagnostics appear immediately
- handle `emacs --daemon` / `emacsclient` where buffers can persist
- nudge Flymake rendering when diagnostics timing is awkward

If you change this module, preserve those invariants unless explicitly
requested.

### `my--lsp-ltex-plus-execute-code-action` — invariants (do not regress)

**No diagnostics guard.** Do NOT add a guard like
`(when (seq-empty-p diagnostics) (user-error "No diagnostics at point"))`.
LTEX+ generates code actions from its own server-side cache, not from the
`context.diagnostics` field in the codeAction request. After applying a
correction, LTEX+ briefly sends `publishDiagnostics []` before republishing
fresh ones, so the client diagnostic list is transiently empty. A guard during
this window makes the command appear permanently broken.

**Capture workspace at invocation; pass it through all callbacks.** Do NOT
re-fetch the workspace inside `dispatch-code-actions` or its async callback.
After `_ltex.checkDocument` completes, the workspace status can briefly
fluctuate, causing `my--lsp-ltex-plus--initialized-workspace` to return nil
and dispatch to silently do nothing.

**Wrap `lsp--execute-code-action` in `(with-lsp-workspace ws ...)`.** The
action-execution callback runs outside any workspace binding; without this,
`workspace/applyEdit` or `workspace/executeCommand` can target the wrong
attached server.

## Common Tasks

Add a new optional module:

1. Create `my-feature.el` following the module pattern.
2. In `init.el`, add:

   ```elisp
   (emacs-config-load-module
    'my-feature
    "Could not load my-feature.el; <feature> is disabled.")
   ```

3. Prefer to keep the module self-contained with its `use-package` declarations.

Add a new package:

- Use `use-package` in the relevant module.
- Avoid adding packages directly in `init.el` unless it is truly core.

Move configuration from `init.el` into a module:

- Keep `init.el` as a readable table-of-contents.
- Put the logic behind an `emacs-config-load-module` call.

## Validation / Smoke Tests

The most useful checks after changes:

- Interactive startup with debug:
  - `emacs --debug-init`

- Batch load (useful for CI-like smoke checks):
  - `emacs --batch --quick -l init.el --eval "(message \"init loaded\")"`

Notes:

- First-time runs may download packages via straight.
- Some features only activate in terminal frames or in specific major modes.

## Agent Rules (How to Work in This Repo)

When acting as an automated agent editing this configuration:

- Preserve the symlink-aware loading design. Do not introduce hard-coded
  absolute paths outside of `emacs-config-dir` unless there is a strong reason.
- Keep `init.el` compact. Prefer adding/changing local modules.
- Avoid editing `custom.el` unless the user explicitly asks.
- Prefer graceful degradation: optional modules should fail with warnings, not
  break startup.
- Keep Elisp style consistent:
  - `lexical-binding: t`
  - minimal, purposeful comments
  - `provide` at the end of each module
