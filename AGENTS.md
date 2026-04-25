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
  - Makes `fixed-pitch` inherit from `default` so any package that routes code/tables through `fixed-pitch` (mu4e body, `mixed-pitch-mode`, certain theme "mixed-fonts" modes) stays in the same mono font as the rest of the editor. Contains a prominent warning: if `default` is ever switched to a proportional font, this line must be replaced with an explicit mono `:family` / `:height` or tables and src blocks will lose fixed-width rendering.
  - Adds a `set-fontset-font` mapping for Unicode block `#x2010–#x27bf` (General Punctuation, Arrows, Mathematical Operators, Box Drawing, etc.) to `Menlo`, preventing macOS from falling back to proportional fonts like Calibri for characters such as `→` and `—` — which otherwise push org table columns out of alignment.

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

> **How to read this list**: each entry describes the module's purpose, the
> external packages it installs, and any cross-module dependencies — enough
> to route work to the right file. When an entry ends with **→
> `docs/modules/<name>.md`**, that file holds invariants, gotchas, and
> workarounds you must read before modifying the module. Entries without a
> pointer are simple enough that the source comments are sufficient. These
> docs are read on demand (no auto-load) so most conversations pay no
> context cost for them.

- `env-config.el`: shell environment import for non-daemon GUI Emacs. When `(not (daemonp))`, parses `export KEY='VALUE'` lines from `$XDG_CACHE_HOME/zsh/interactive-shell-env.sh` and `$XDG_CONFIG_HOME/envs/LanguageTools.sh`, sets them via `setenv` (updates `exec-path` for PATH), and sets `COLORTERM=truecolor` + `TERM=xterm-256color`. Skipped when running as a daemon (the launcher already set up the environment). Loaded from `early-init.el` so PATH is correct before `straight.el` and any package lookups run.
- `ui-config.el`: UI chrome (menu/tool/scroll bars), window dividers, frame chrome, fonts, frame centering, TTY mode-line separator, truncation/continuation glyphs. On macOS GUI, sets `ns-alternate-modifier` to `meta` and `ns-right-alternate-modifier` to `none` so the right Option key is handed to macOS for character composition (e.g. `⌥u u` → `ü`, `⌥s` → `ß`), while the left Option remains Meta for Emacs. TTY composition is the terminal emulator's responsibility.
- `welcome-config.el`: GUI-only startup splash with a centered logo (from `goodies/`) and "Welcome to Emacs!" title. Activated from both `emacs-startup-hook` (direct launches) and `server-after-make-frame-hook` (emacsclient against daemon); shown only when nothing has been opened. `M-x show-welcome-buffer` resurfaces it. Sets `inhibit-startup-screen t`. → `docs/modules/welcome-config.md`
- `auto-revert-config.el`: file-system watcher that silently reverts clean buffers on external change and prompts when there are unsaved edits. Watches the parent **directory** (not the file itself) so that atomic writes via `rename(2)` are detected. Handles `renamed` events by updating `buffer-file-name` and re-attaching the watcher to the new path; handles `deleted` events by emitting a warning and tearing down the watcher.
- `buffers-config.el`: general hub for buffer interaction — anything that shapes how the user lists, navigates, or manages the lifecycle of buffers. Currently contains: (1) `ibuffer` setup, replacing `list-buffers` (`C-x C-b`, via `[remap list-buffers]`) with `ibuffer` grouped by `project.el` root via `ibuffer-project` (`ibuffer-hook` regenerates the groups on every invocation so new projects appear automatically) and decorated with `nerd-icons-ibuffer` (reuses the same Nerd Font configured in `nerd-icons-config.el`, no second icon-font system); `ibuffer-expert t` and `ibuffer-show-empty-filter-groups nil` keep the listing terse. (2) Smart kill-buffer behaviour — suppresses the "Buffer modified; kill anyway?" prompt when the buffer content is identical to the file on disk (edits were made and then fully undone) by hooking into `kill-buffer-query-functions` and clearing the modified flag before the prompt fires. New buffer-related behaviours should land here rather than in standalone modules.
- `mac-clipboard.el`: macOS TTY clipboard sync — wires kill-ring writes to `pbcopy`; deliberately omits the paste direction to avoid spawning a `pbpaste` subprocess on every `C-y`.
- `mac-pseudo-daemon-config.el`: keeps a hidden GUI frame alive on macOS so the Dock icon and menu bar stay functional after closing the last visible frame. (Currently **commented out** in `init.el`; kept but not loaded.)
- `recentf-config.el`: recently visited files list, persisted under `$XDG_CACHE_HOME/emacs/`.
- `treesitter-config.el`: tree-sitter grammar bootstrap. Checks `(treesit-available-p)` and automatically installs missing grammars from `treesit-language-source-alist` (JSON, YAML, TOML, Markdown, Kotlin, …) at load time. Uses `major-mode-remap-alist` to promote `-ts-mode` variants for JSON, YAML, and TOML. Markdown is intentionally NOT remapped to `markdown-ts-mode` because `markdown-mode` has richer features (markup hiding, wiki links, obsidian integration) that `markdown-ts-mode` does not support. Provides `treesitter-config-reinstall-grammars` for manual updates.
- `completion.el`: completion orchestration (styles + minibuffer UI + in-buffer completion).
- `nerd-icons-config.el`: core Nerd Fonts setup — installs the `nerd-icons` library and configures the icon font ("Symbols Nerd Font Mono", a standalone icon-only font with correct monospace metrics, recommended by the package author). In GUI frames, calls `set-fontset-font` to map the Private Use Area (`#xe000–#xffff`) to that font, preventing fallback to fonts with wrong glyph metrics (which causes horizontal truncation of icons). Per-consumer integrations (`nerd-icons-ibuffer`, `nerd-icons-dired`, Corfu kind-icon, Treemacs, etc.) live in their respective modules (`buffers-config.el`, `dired-config.el`, …), not here.
- `soft-wrap.el`: `soft-wrap-mode` (buffer-local minor mode), `global-soft-wrap-mode`, and `soft-wrap-set-width` for visual-only soft wrapping. Used by text/Markdown configs. Optional diagnostics live in `soft-wrap-diagnostic.el` (debug routines kept separate to minimize load), loaded when `soft-wrap-load-diagnostics` is non-nil.
- `syntaxes.el`: loads per-major-mode settings from `syntaxes/`.
- `csi-u-keys.el`: terminal key decoding for CSI-u sequences. Adds explicit decoders for Backspace variants (`S-backspace`, `C-backspace`, `C-S-backspace`), Ctrl+Tab (`\e[9;5u`), and Shift+Enter (`\e[13;2u`). Requires the application to opt in to CSI-u mode via `printf '\e[>4;1m'` (sent from zsh on startup); without this, tmux and terminals correctly fall back to legacy encoding.
- `dired-config.el`: Dired customizations. Reuses a single Dired buffer when navigating (`dired-kill-when-opening-new-dired-buffer`), enables `dired-dwim-target`, moves deletions to trash. Loads `dired-x` with `dired-omit-mode` on by default (hides dotfiles via regex `\`[.][^.]`, excluding `.`/`..`), toggled with `.` (overriding the default `dired-clean-directory` binding). Installs `dired-narrow` (bound to `/`). Adds `O` for `dired-open-with` (open via OS / reveal in file manager), and `,` followed by `a/A/m/M/b/B/e/E` for Yazi-style sorting. Visual enhancements: `diredfl` for richer font-locking (distinct faces for size/date/permissions/directories/symlinks/executables/compressed files, works in TTY) and `nerd-icons-dired` for icon glyphs at the start of each line.
- `terminal-config.el`: terminal emulator settings for `term` and `eshell`. Installs `vterm` (libvterm) and `ghostel` (libghostty-vt-backed; ~2× faster, adds Kitty keyboard protocol, OSC 8 hyperlinks, mouse passthrough, auto shell integration). Implements `ev` blocking-`$EDITOR` integration. Exposes `C-b` so `windows-config.el`'s `tmux-map` works in terminal buffers. → `docs/modules/terminal-config.md`
- `magit-config.el`: Magit Git porcelain + Forge (GitHub/GitLab) integration. Includes `vdiff` and a local patched copy of `vdiff-magit` for side-by-side diffs; `e`/`E` in Magit buffers open vdiff instead of Ediff. Disables line numbers in `git-commit-mode` and `git-rebase-mode` buffers.
- `project-config.el`: project.el settings — sets `project-vc-merge-submodules nil` so git submodules are treated as independent project roots rather than merged into the parent repo.
- `search-config.el`: prefer ripgrep for project/xref search.
- `navigation-config.el`: smart Home/End keys (first press goes to line start/end, repeated press toggles to first/last non-whitespace character). xref back/forward navigation is provided by the built-in `xref-go-back` (`M-,`) and `xref-go-forward` (`C-M-,`).
- `treemacs-config.el`: project file tree (Treemacs), TTY-friendly.
- `lsp-core.el`: shared LSP infrastructure used by every `lsp-*-config.el`. Installs `lsp-mode`, `lsp-ui`, `flycheck` (left-fringe indicators), `yasnippet` (snippet expansion engine for LSP completions), and force-requires `lsp-diagnostics` so its faces are defined before any server uses them. Hands completion off to corfu+cape (`lsp-completion-provider :none`). `C-c l` keymap prefix; `C-c l h g` for `lsp-ui-doc-glance`. → `docs/modules/lsp-core.md`
- `apheleia-config.el`: Formatter configuration via `apheleia`. Automatically formats buffers on save without moving point. Configures `ruff` (isort + format) for Python and `ktlint` for Kotlin (`kotlin-mode`, `kotlin-ts-mode`).
- `pyenv-config.el`: per-buffer pyenv version selection. No external package — `pyenv-mode` is deliberately avoided (would duplicate `env-config.el`'s shim setup and force global scope). Adds two override paths on top of pyenv's default shim behavior: dir-local `pyenv-version` for project overrides not committed as `.python-version`, and `M-x pyenv-activate-buffer` for ad-hoc picks. Both perform a full buffer-local `pyenv activate` equivalent. → `docs/modules/pyenv-config.md`
- `lsp-python-config.el`: Python LSP via `lsp-pyright` (configured for **basedpyright**, not pyright). Activates in `python-mode` / `python-ts-mode` and inside org-babel Python src blocks opened with `C-c '`. Disables `ruff-lsp` and `ruff` lsp clients to prevent overlap. Depends on `lsp-core.el`, `org-config.el`'s `org-src-*` settings, and `my/unique-file-path` from `utils.el`. → `docs/modules/lsp-python-config.md`
- `lsp-elisp-config.el`: Experimental Elisp LSP configuration (currently disabled/irrelevant).
- `lsp-c-config.el`: C/C++ LSP configuration via `lsp-clangd`.
- `lsp-web-config.el`: JS/TS LSP (`typescript-mode`, built-in `js`).
- `lsp-json-config.el`: JSON LSP via `vscode-json-language-server` with SchemaStore auto-detection.
- `lsp-ltex-plus-config.el`: User configuration and activation for the `lsp-ltex-plus` package — a minimal `lsp-mode` client for `ltex-ls-plus` (Markdown, LaTeX, Org, HTML, etc.) that replaces the heavy `lsp-ltex` with a transparent implementation using proactive configuration pushing. Managed via a local repository for development.
- `harper-config.el`: Grammar checker configuration via `harper-ls` and Eglot. Currently commented out; used for comparing with LTEX+.
- `latex-config.el`: LaTeX specific editing configuration and PDF viewer integration.
- `lsp-tex-config.el`: LaTeX LSP configuration via `texlab`.
- `org-config.el`: Org mode plus inline LaTeX previewing and Python babel. Installs Org from **tecosaur's fork** (custom straight recipe with synthesized `org-version.el`) for karthink's live `org-latex-preview` (auto-preview, dvisvgm SVG, live updates — not yet upstream), and `org-appear` for emphasis-marker auto-toggling. Tunes `C-c '` (`org-edit-special`) with `org-src-*` settings that `lsp-python-config.el` depends on. Pre-emptively purges stale `.fmt` cache files after TeX Live upgrades. Python babel defaults are minimal (`:results output :exports both`) — matplotlib setup belongs in per-file blocks or yasnippets. → `docs/modules/org-config.md`
- `jupyter-config.el`: emacs-jupyter for remote kernels via the Jupyter Server protocol (HTTP/WebSockets). Registers `jupyter-python` as an Org-babel language with optimized defaults (e.g., `:results output` to capture stdout). Includes an automated workaround to fetch prebuilt `zmq` dynamic modules on macOS (Apple Silicon) and Linux, bypassing local build/link failures.
- `code-cells-config.el`: Spyder/VSCode-style `# %%` code cells in plain `.py`/`.jl`/`.R` files via the `code-cells` package. Provides cell-aware navigation (`M-n`/`M-p`) and evaluation (`C-c C-c`); `code-cells-mode-maybe` auto-activates only in buffers that contain cell markers, so plain files without `# %%` lines are unaffected. When `emacs-jupyter` is loaded too, redirects `jupyter-eval-line-or-region` to `code-cells-eval` via `[remap]` — operates at the command-symbol level (not the key level), so it catches whatever key jupyter binds to its line-region eval (present or future) without enumerating keys or fighting keymap-priority order. The remap is wrapped in `with-eval-after-load 'jupyter`, so disabling jupyter-config doesn't break code-cells.
- `markdown-config.el`: Markdown reading and authoring experience. Installs `markdown-mode` with `markdown-enable-wiki-links t` and `markdown-wiki-link-alias-first nil` (so wiki links use `[[url|label]]` order, not `[[label|url]]`); enables `markdown-hide-markup` on mode entry (which is a superset of URL hiding — hides brackets, asterisks, URLs, etc.). Custom link-following logic (symmetric for both wiki links and standard `[label](path)` links): Markdown targets open with `find-file`; non-Markdown local files open `dired` with the cursor on the file; missing files signal a `user-error` with the resolved path; full URLs open in the browser unchanged. The default `markdown-follow-wiki-link` is replaced via `:override` advice (`markdown-config--follow-wiki-link`) to avoid its bugs (appending the buffer extension to the link name, replacing spaces with dashes). Standard links are intercepted via `markdown-follow-link-functions` (`markdown-config--follow-local-link`). Includes a disabled `obsidian` block (wrapped in `(when nil ...)`) for Obsidian vault integration — currently disabled due to bugs. Installs `grip-mode` for live GitHub-flavored Markdown preview in a browser (bound to `C-c C-c g`). Visual line wrapping is handled by `syntaxes/markdown.el` via `soft-wrap-mode`.
- `lsp-swift-config.el`: Swift LSP via `lsp-sourcekit` (SourceKit-LSP). Locates the server via `PATH` or `xcrun -f sourcekit-lsp` on macOS.
- `lsp-rust-config.el`: Rust LSP via `rustic-mode` + `rust-analyzer` (lsp-mode built-in `lsp-rust`). Enables `rustfmt` on save.
- `lsp-kotlin-config.el`: Kotlin LSP via `kotlin-ts-mode` + JetBrains' official `kotlin-lsp`. Requires `kotlin-lsp` on `PATH` (`brew install JetBrains/utils/kotlin-lsp`). Registers a `jetbrains-kotlin-lsp` client (priority 0) that invokes `kotlin-lsp --stdio`, shadowing lsp-mode's built-in `kotlin-ls` client (priority -1) which is backed by fwcd's `kotlin-language-server` — the fwcd server's latest release (1.3.13) bundles Kotlin 2.1.0 and rejects metadata from projects built with Kotlin 2.2+ (INCOMPATIBLE_CLASS cascading into UNRESOLVED_REFERENCE on stdlib). The built-in client is left registered as a fallback for machines that only have fwcd installed.
- `git-gutter-config.el`: VCS gutter indicators in both TTY and GUI frames. Loads a local copy of `git-gutter.el` (patched fork, kept in-repo until changes land upstream) via `:straight nil` + `:load-path emacs-config-dir`.
- `scroll-config.el`: scroll parameters and `ultra-scroll` for pixel-precise GUI scrolling. Also implements smart horizontal wheel scrolling via `scroll-config-horizontal` (bound to `wheel-left`/`wheel-right` at all speed tiers), which suppresses hscroll when it would have no visible effect. The suppression predicate `scroll-config--hscroll-applicable-p` checks (a) a buffer-local opt-out `scroll-config-suppress-hscroll` (set by terminal/shell mode hooks in `init.el`, because terminal emulators re-wrap content to the window width, so hscroll has nothing to reveal), (b) `truncate-lines`, and (c) `truncate-partial-width-windows` semantics. The hscroll opt-out is decoupled from `truncate-lines` because terminal emulators require the full window width reported to the child process — setting `truncate-lines` nil there would cost the last column to the continuation glyph and make the shell prompt overflow by one character.
- `windows-config.el`: window navigation, splitting, resizing, joining, reflowing, swapping, send-buffer, deletion, and zoom — parallels tmux pane operations. Defines `tmux-map` on `C-b` (shadowing `backward-char`) as the pane prefix; `C-b <arrow>` falls through to `tmux select-pane` at the frame edge when running inside tmux. Built on `windmove`, `winner-mode`, and `repeat-mode`; no external packages. Also rebinds `C-x 1` / `C-x 2` / `C-x 3` / `C-x m`. → `docs/modules/windows-config.md`
- `themes-config.el`: theme orchestration. Installs `modus-themes` (variants: `modus-operandi` light, `modus-vivendi-tinted` dark) and configures palette overrides. Wires `theme-harmonize` (face-sync library, this repo) and `zac-theme-autodetection` (OS-appearance watcher, in `local/`). Theme is selected by `zac-load-theme-callback` based on the OS appearance state file. Load order is intentional: theme-harmonize → modus-themes config → zac-theme-autodetection. → `docs/modules/themes-config.md`
- `theme-harmonize.el`: face-synchronization library hooked on `enable-theme-functions` and `after-make-frame-functions`. Drives a single line-number background color across `line-number`, `margin`, `fringe`, `header-line`, `flycheck-fringe-*`, and `git-gutter:*` so the gutter column blends uniformly in both TTY and GUI. Configured via `theme-harmonize-line-number-bg` (`:light`/`:dark` plist) and `theme-harmonize-git-gutter-colors`, both set in `themes-config.el`. → `docs/modules/themes-config.md` (combined with themes-config)
- `agent-shell-config.el`: Agent shell configuration (environment and mode integration).
- `utils.el`: Generic Emacs Lisp utility functions for the configuration.

Local package overrides (`local/`):

- `local/vdiff-magit.el`: local patched copy of the unmaintained `vdiff-magit` package. Fixes two Magit API breakages: `magit-get-revision-buffer` removed (replaced by `magit--get-blob-buffer`); `magit-find-file-index-noselect` dropped its second argument. Loaded via `:straight nil` with `:load-path`. TODO: file a PR upstream if the project shows signs of life.
- `local/zac-theme-autodetection.el`: watches the OS appearance state file written by `zsh-appearance-control`; invokes `zac-load-theme-callback` (user-supplied callback). Contains no theme or color choices itself. Loaded via `use-package` (`:straight nil`) with `zac-load-theme-callback` set in `:init` so the watcher picks it up on first application.


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
- `syntaxes/latex.el`: LaTeX syntax enhancements. Defines custom faces for braces (`{ }`) and brackets (`[ ]`), and implements high-speed, context-aware number highlighting that only activates within AUCTeX math environments (detected via text properties). Sets `fill-column` to 100.
- `syntaxes/markdown.el`: Overrides `fill-column` to 100 for Markdown buffers (supports `markdown-mode`, `gfm-mode`, and `markdown-ts-mode`). `soft-wrap-mode` is inherited from `text-mode-hook` (via `syntaxes/text.el`). Package-level configuration lives in `markdown-config.el`.
- `syntaxes/python.el`: Python indentation settings.
- `syntaxes/sh.el`: Shell script indentation (`sh-basic-offset 2`).
- `syntaxes/text.el`: visual soft wrap at 100 columns for `text-mode`.
- `syntaxes/yaml.el`: YAML indentation settings.
- `syntaxes/swift.el`: Swift indentation (`swift-mode:basic-offset 4`).
- `syntaxes/dired.el`: disables line numbers in Dired mode.
- `syntaxes/elisp.el`: Elisp settings, sets `fill-column` to 80.
- `syntaxes/magit.el`: Magit display settings, enables `visual-line-mode` and disables line numbers in Magit buffers.
- `syntaxes/agent-shell.el`: disables line numbers in `agent-shell-mode`.

Wrapping:

- `soft-wrap.el` provides `soft-wrap-mode` (buffer-local), `global-soft-wrap-mode`, and `soft-wrap-set-width` for visual-only wrapping. The target column is controlled via `soft-wrap-default-width` (defcustom) or `fill-column` (read dynamically when nil).
- Wrap-at-column is implemented with a window right margin (no newlines inserted). The left margin is always preserved so TTY gutters (e.g. git-gutter) keep working.
- Continuation indentation uses built-in `visual-wrap-prefix-mode` (Emacs 30+). No external packages required.
- `soft-wrap-diagnostic.el` provides debugging tools (`soft-wrap-debug-dump`, `soft-wrap-diagnose`, `soft-wrap-trace-start/stop`). Loaded only when `soft-wrap-load-diagnostics` is non-nil.

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

- LTEX+ (`lsp-ltex-plus.el`):
  - `ltex-ls-plus` (Java-based server)

- Swift LSP (`lsp-swift-config.el`):
  - `sourcekit-lsp` (ships with the Swift toolchain; on macOS located via `xcrun`)

- Rust LSP (`lsp-rust-config.el`):
  - `rust-analyzer` (via `rustup component add rust-analyzer`)

- Kotlin LSP (`lsp-kotlin-config.el`):
  - `kotlin-lsp` (via `brew install JetBrains/utils/kotlin-lsp`) — JetBrains' official server; required for projects targeting Kotlin 2.2+
  - fallback: `kotlin-language-server` (fwcd, via `brew install kotlin-language-server`) — only handles Kotlin ≤2.1

- emacs-jupyter (`jupyter-config.el`): Requires a reachable Jupyter Server (local or remote via SSH tunnel). The `zmq` dynamic module is automatically downloaded from upstream releases on first use to bypass build issues.

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

`lsp-ltex-plus.el` provides a streamlined `lsp-mode` client with these key characteristics:

- **Add-on Design**: Registered with `:add-on? t` and `:priority -1` to run alongside primary servers (e.g., `texlab`).
- **Proactive Configuration**: Pushes the full `ltex.*` settings namespace on server initialization and after any dictionary updates, ensuring the server is always in sync with Emacs variables.
- **Kind-First Routing**: Relies on the `lsp-core.el` patch to handle bi-directional JSON-RPC traffic (like `workspace/configuration` requests) without deadlocks.
- **Simplified Actions**: Uses standard `lsp-mode` `:action-handlers` for `_ltex.*` commands, bypassing complex manual dispatch logic.

### Dictionary and Action Invariants

- **No diagnostics guard**: Do NOT add a guard like `(when (seq-empty-p diagnostics) ...)` to code actions. LTEX+ generates actions from its own cache; diagnostics may be transiently empty while the server re-checks the document.
- **Persistence**: Words added via code actions are persisted to `lsp-ltex-plus-dictionary-file` in a plist format compatible with the original `lsp-ltex-plus` package.

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
