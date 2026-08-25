# Emacs Config: Agent Guide (AGENTS.md)

This directory is an Emacs configuration intended to be symlinked into
`~/.config/emacs/` (or wherever `user-emacs-directory` points). The canonical
source lives in this dotfiles repo; `init.el` is a thin entrypoint that locates
the *real* directory and loads the rest.

Use this document as the operating manual when making changes with an automated
agent (LLM) or when you want to understand the configuration structure.

## Filesystem Layout (canonical source vs. symlink)

- The **canonical source** of every Emacs config file lives in this dotfiles
  repo: `/Users/andrea/google-drive/dotfiles/.config/emacs/`. Edit files here.
- `~/.config/emacs/init.el` is a **symlink** to
  `/Users/andrea/google-drive/dotfiles/.config/emacs/init.el` (via the
  `~/.config/dotfiles` → repo symlink). All the other config files
  (`early-init.el`, `*-config.el`, `local/`, `syntaxes/`, `completions/`,
  `docs/`, …) live alongside it in this repo directory.
- **`straight.el` still installs into `~/.config/emacs/straight/`** (its
  clones under `straight/repos/` and byte-compiled builds under
  `straight/build/`) — that tree is *not* in the dotfiles repo and is not
  symlinked back. Look there for third-party package sources.

## Probing the live Emacs for paths / values

When you need to locate a library, resolve a variable, or check runtime state,
probe the running Emacs directly with `emacsclient` instead of guessing. This
is the fastest way to find the real on-disk path of an installed package:

```sh
# Where is a feature/library actually loaded from?
emacsclient -e '(find-library-name "magit")'
emacsclient -e '(locate-library "consult")'

# Resolve a variable / evaluate arbitrary Elisp
emacsclient -e 'straight-base-dir'
emacsclient -e '(expand-file-name "straight/build" user-emacs-directory)'
emacsclient -e 'emacs-config-dir'
```

If no daemon/server is running, fall back to a batch eval:

```sh
emacs --batch --quick -l init.el --eval '(princ (find-library-name "magit"))'
```

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
  - Defines `emacs-config-cache-dir` / `emacs-config-cache-file` — the single place that decides where this config's machine-local state goes (`$XDG_CACHE_HOME/emacs/`, never the git worktree `user-emacs-directory` points at). Any module persisting a package's state file (`recentf-save-file`, `org-id-locations-file`, `treemacs-persist-file`, …) goes through `emacs-config-cache-file`, which also creates the directory.
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

- `env-config.el`: shell environment import for non-daemon GUI Emacs. Keeps its own `export KEY='VALUE'` parser rather than `utils.el`'s: it runs from `early-init.el`, long before utils.el is loaded, and requiring utils.el there would drag `use-package`, keybindings and advice into the pre-package phase — and its job is to `setenv` into this Emacs, not to return a value. When `(not (daemonp))`, parses `export KEY='VALUE'` lines from `$XDG_CACHE_HOME/zsh/interactive-shell-env.sh` and `$XDG_CONFIG_HOME/envs/LanguageTools.sh`, sets them via `setenv` (updates `exec-path` for PATH), and sets `COLORTERM=truecolor` + `TERM=xterm-256color`. Skipped when running as a daemon (the launcher already set up the environment). Loaded from `early-init.el` so PATH is correct before `straight.el` and any package lookups run.
- `ui-config.el`: visual presentation layer — UI chrome (menu/tool/scroll bars off, no GUI dialogs), bottom-only window dividers, platform-specific frame chrome (macOS rounded undecorated, others undecorated + internal border), display-table glyphs (FULL BLOCK vertical-border, `…`/`↲` for truncation/wrap), TTY mode-line tweak, per-frame centering hooked on both `emacs-startup-hook` and `after-make-frame-functions` so emacsclient GUI frames also get it. macOS: right Option goes to system character composition, left Option stays Meta. TTY emoji opt-in via `icons-tty-emoji` (provided by an emacs-plus patch). → `docs/modules/ui-config.md`
- `welcome-config.el`: GUI-only startup splash with a centered logo (from `goodies/`) and "Welcome to Emacs!" title. Activated from both `emacs-startup-hook` (direct launches) and `server-after-make-frame-hook` (emacsclient against daemon); shown only when nothing has been opened. `M-x show-welcome-buffer` resurfaces it. Sets `inhibit-startup-screen t`. → `docs/modules/welcome-config.md`
- `warning-toast.el`: surfaces `display-warning` messages (level `warning-toast-min-level` and above; default `:warning`) as a transient auto-dismissing corner popup instead of the easily-missed `*Warnings*` buffer. Built on `popon` (TTY+GUI, fetched from Codeberg) rather than `posframe` (GUI-only). Installs a global minor mode `warning-toast-mode` that adds an `:around` advice on `display-warning`. With `warning-toast-suppress-window` (default t) the redundant `*Warnings*` window auto-pop is suppressed for sub-`:emergency` warnings by let-binding `warning-minimum-level` to `:emergency` during the original call — the entry is still logged to the buffer (logging is gated separately by `warning-minimum-log-level`). Corner/duration/width/face are defcustoms. Motivating case: flycheck's `flycheck-disable-excessive-checker` discards all diagnostics and disables a checker past `flycheck-checker-error-threshold`, announcing it only via a one-shot `lwarn`.
- `auto-revert-config.el`: file-system watcher that silently reverts clean buffers on external change and prompts when there are unsaved edits. Watches the parent **directory** (not the file itself) so that atomic writes via `rename(2)` are detected. Handles `renamed` events by updating `buffer-file-name` and re-attaching the watcher to the new path; handles `deleted` events by emitting a warning and tearing down the watcher.
- `buffers-config.el`: hub for buffer interaction (lifecycle, listing, navigation). New buffer-related behaviours should land here rather than as standalone modules. Currently: `ibuffer` setup with `project.el`-based grouping (`ibuffer-project`) and `nerd-icons-ibuffer` decoration, replacing `list-buffers` via `[remap list-buffers]`; smart kill-buffer that suppresses the "modified; kill anyway?" prompt when buffer content matches disk. → `docs/modules/buffers-config.md`
- `mac-clipboard.el`: macOS TTY clipboard sync — wires kill-ring writes to `pbcopy`; deliberately omits the paste direction to avoid spawning a `pbpaste` subprocess on every `C-y`.
- `mac-pseudo-daemon-config.el`: keeps a hidden GUI frame alive on macOS so the Dock icon and menu bar stay functional after closing the last visible frame. (Currently **commented out** in `init.el`; kept but not loaded.)
- `recentf-config.el`: recently visited files list, persisted under `emacs-config-cache-dir`.
- `bookmark-aux-config.el`: thin consumer/wiring layer for the `bookmark-aux-file` library (`local/bookmark-aux-file.el`). Loads the library, enables `bookmark-aux-file-mode`, and sets `bookmark-aux-file-resolver` so that a **relative** `bookmark-aux-file` set from a project's `.dir-locals.el` resolves against the **project.el root** (one auxiliary file for the whole project, regardless of which subdirectory is open), falling back to `default-directory` outside a project. All project.el coupling lives here, never in the library. Per-project setup is otherwise automatic — the library marks `bookmark-aux-file` a safe local variable, so `.dir-locals.el` (e.g. `((nil . ((bookmark-aux-file . "._aux/bookmarks.eld"))))`) sets it with no further wiring. → `docs/modules/bookmark-aux-file.md`
- `treesitter-config.el`: tree-sitter grammar bootstrap and major-mode remapping for Emacs 29+. Auto-installs missing grammars from `treesit-language-source-alist` at load time (JSON, YAML, TOML, TypeScript/TSX, Bash, zsh, Python, Kotlin, Markdown). Promotes `-ts-mode` variants via `major-mode-remap-alist`. Kotlin grammar is pinned (`57170e50`) due to a font-lock-breaking upstream change. Markdown grammar uses the `split_parser` branch (block + inline). `M-x treesitter-config-reinstall-grammars` for manual updates. → `docs/modules/treesitter-config.md`
- `completion.el`: completion orchestration (styles + minibuffer UI + in-buffer completion).
- `nerd-icons-config.el`: core Nerd Fonts setup — installs the `nerd-icons` library and configures the icon font ("Symbols Nerd Font Mono", a standalone icon-only font with correct monospace metrics, recommended by the package author). In GUI frames, calls `set-fontset-font` to map the Private Use Area (`#xe000–#xffff`) to that font, preventing fallback to fonts with wrong glyph metrics (which causes horizontal truncation of icons). Per-consumer integrations (`nerd-icons-ibuffer`, `nerd-icons-dired`, Corfu kind-icon, Treemacs, etc.) live in their respective modules (`buffers-config.el`, `dired-config.el`, …), not here.
- `soft-wrap.el`: `soft-wrap-mode` (buffer-local minor mode), `global-soft-wrap-mode`, and `soft-wrap-set-width` for visual-only soft wrapping. Used by text/Markdown configs. Optional diagnostics live in `soft-wrap-diagnostic.el` (debug routines kept separate to minimize load), loaded when `soft-wrap-load-diagnostics` is non-nil.
- `syntaxes.el`: loads per-major-mode settings from `syntaxes/`.
- `csi-u-keys.el`: terminal key decoding for CSI-u sequences. Adds explicit decoders for Backspace variants (`S-backspace`, `C-backspace`, `C-S-backspace`), Ctrl+Tab (`\e[9;5u`), and Shift+Enter (`\e[13;2u`). Requires the application to opt in to CSI-u mode via `printf '\e[>4;1m'` (sent from zsh on startup); without this, tmux and terminals correctly fall back to legacy encoding.
- `dired-config.el`: Dired with Yazi-style keybindings, OS file-manager integration, and `diredfl` + `nerd-icons-dired` decoration. Installs `dired-narrow` (`/`), `diredfl`, `nerd-icons-dired`. Single-buffer navigation, trash-on-delete, `dired-omit-mode` on by default. `O` opens via OS default / reveals in file manager; `,` followed by `a/A/m/M/b/B/e/E` for sorting. Requires `gls` on macOS for GNU ls features. → `docs/modules/dired-config.md`
- `terminal-config.el`: terminal emulator settings for `term` and `eshell`. Installs `ghostel` (libghostty-vt-backed; Kitty keyboard protocol, OSC 8 hyperlinks, mouse passthrough, auto shell integration). Implements `eb` ("emacs blocking") `$EDITOR` integration. Exposes `C-b` so `windows-config.el`'s `tmux-map` works in terminal buffers. → `docs/modules/terminal-config.md`
- `magit-config.el`: Magit Git porcelain + Forge (GitHub/GitLab) integration. Includes `vdiff` and a local patched copy of `vdiff-magit` for side-by-side diffs; `e`/`E` in Magit buffers open vdiff instead of Ediff. Disables line numbers in `git-commit-mode` and `git-rebase-mode` buffers.
- `project-config.el`: project.el settings — sets `project-vc-merge-submodules nil` so git submodules are treated as independent project roots rather than merged into the parent repo.
- `search-config.el`: prefer ripgrep for project/xref search.
- `wgrep-config.el`: editable `grep-mode` buffers via `wgrep`, for project-wide find-and-replace driven by `embark-export` from `consult-ripgrep`. Sets `wgrep-auto-save-buffer t`: in `wgrep-mode` `C-x C-s` is rebound to `wgrep-finish-edit` (not `save-buffer`), and that only applies the edits to the visiting buffers — without the auto-save they stay modified-but-unsaved until an explicit `save-some-buffers`, which reads as "wgrep did nothing".
- `navigation-config.el`: smart Home/End keys (first press goes to line start/end, repeated press toggles to first/last non-whitespace character). xref back/forward navigation is provided by the built-in `xref-go-back` (`M-,`) and `xref-go-forward` (`C-M-,`).
- `electric-config.el`: `electric-pair-mode` policy plus a generic region-wrap command. Keeps electric-pair's code-editing value (balance-aware auto-close, type-over, string/comment context) but sets `electric-pair-inhibit-predicate` to suppress the auto-inserted closing partner for quote chars (`"` `'` `` ` ``) on a bare keypress — region-wrap survives because it is a separate branch of `electric-pair-post-self-insert-function` that ignores the predicate. Defines `my/wrap-region-or-self-insert` (wrap the active region with the typed char, else self-insert) for delimiters electric-pair does not treat as pairs; `syntaxes/markdown.el` binds it to `` ` `` and `*`. The optional `max-level` arg (default nil = wrap once, no cycle) enables repeat-cycling: pressing the key again right after a wrap adds one delimiter per side, up to `max-level`. It is passed at the binding site, not a global, since each repeat is a fresh command invocation — `syntaxes/markdown.el` binds `*` via a lambda supplying `3` (cycling `*x*` → `**x**` → `***x***`, i.e. emphasis/strong/both) while `` ` `` keeps the default (no cycle). The wrapped span is tracked across presses via markers in `my/wrap--state`. Not routed through `electric-pair-pairs` on purpose — its entries return `unconditional`, forcing an auto-paired second delimiter no predicate can stop.
- `treemacs-config.el`: project file tree (Treemacs), TTY-friendly.
- `yasnippet-config.el`: snippet expansion engine. Originally pulled in for lsp-mode (LSP servers return placeholder snippets like `my_function(${1:arg1}, ${2:arg2})` that yasnippet expands into interactive tab-stops); also drives the snippet libraries under `yasnippets/`. Sets `yas-snippet-dirs` to `yasnippets/` in this repo, disables the legacy `yas/*` command aliases via `yas-alias-to-yas/prefix-p`, binds `C-c y` to `yas-insert-snippet` for on-demand snippet picking (snippets are deliberately *not* surfaced via auto-popup completion — see the doc for the rationale), and bridges AUCTeX's `LaTeX-mode` to the `latex-mode` snippet folder via `yas-activate-extra-mode`. Loaded before `lsp-core.el` because lsp-mode consumes it at completion time. → `docs/modules/yasnippet-config.md`
- `lsp-core.el`: shared LSP infrastructure used by every `lsp-*-config.el`. Installs `lsp-mode`, `flycheck` (left-fringe indicators), and force-requires `lsp-diagnostics` so its faces are defined before any server uses them. Sideline rendering via the `sideline` framework — `sideline-flycheck` for diagnostics, `sideline-lsp` for code actions (replaces `lsp-ui-sideline`; `lsp-ui` is no longer used). Hands completion off to corfu+cape (`lsp-completion-provider :none`). Depends on `yasnippet-config.el` being loaded first. `C-c l` keymap prefix. → `docs/modules/lsp-core.md`
- `apheleia-config.el`: Formatter configuration via `apheleia`. Automatically formats buffers on save without moving point. Configures `ruff` (isort + format) for Python and `ktlint` for Kotlin (`kotlin-mode`, `kotlin-ts-mode`).
- `compile-config.el`: build workflow on top of built-in `compile`. No external package. Sets `compilation-scroll-output 'first-error` and `compilation-ask-about-save nil`, and binds `C-c c` to `my/compile-dwim` — runs the buffer's `compile-command` in `default-directory` with no minibuffer prompt (prefix arg prompts, to append one-off flags). Per-project builds are declared entirely by a `.dir-locals.el` setting `compile-command`; nothing project-specific belongs in this module. Makefile projects instead get an AUCTeX-style target prompt (`my/compile-make`): `compile-config--make-targets` parses the makefile found by `locate-dominating-file` and offers its rules via `completing-read`, annotated with the `target: ## description` convention, defaulting to the last target built in that directory (else the default goal) and running in the makefile's own directory. `compile-config-make-command` (dir-local-safe, default `"make"`) carries per-project flags. Which of the two `my/compile-dwim` picks is decided by `(local-variable-p 'compile-command)`: a dir-local `compile-command` is an explicit "just run this" and wins over the target prompt. Parsing gotchas: `:=`/`::=`/`:::=` are assignments and must not be read as rules, which needs a `(looking-at ":*=")` check after the colon rather than a single regexp (backtracking over `:+` re-reads `::=` as a double-colon rule); the prompt string deliberately avoids the words in `marginalia-prompt-categories`, since a classified category would let marginalia's `affixation-function` displace the `:annotation-function` carrying the `##` docs. `compilation-read-command` is deliberately left at t globally, because `compile-command`'s `safe-local-variable` predicate only accepts a directory-local string while it is non-nil. Builds are silent while `compile-config-quiet` is non-nil (default): a `display-buffer-alist` entry using `display-buffer-no-window` keeps the running compilation off screen (`compilation-start` passes `allow-no-window`, which is what makes that action effective), and a `compilation-finish-functions` hook pops the buffer up on a non-zero exit and closes a leftover window once a build succeeds. Both paths match `compilation-mode` **exactly**, not derived modes — `grep-mode`/`project-find-regexp` output is the requested result and must keep its window.
- `uv-config.el`: per-buffer activation of uv-managed virtual environments (the pyenv→uv migration replacement, 2026-06-21). No external package. Named envs live under `uv-virtualenvs-dir` (default `$XDG_DATA_HOME/virtualenvs/<name>`). Unlike pyenv there is no CWD-walking shim, so there is no "default layer" — activation is always explicit: dir-local `uv-venv` for per-project auto-activation, and `M-x uv-activate-buffer` for ad-hoc picks. Both perform a buffer-local `source <venv>/bin/activate` equivalent (sets `VIRTUAL_ENV`, prepends `bin/` to PATH/`exec-path`, clears `PYTHONHOME`). Accepts a bare name or an absolute venv path. → `docs/modules/uv-config.md`
- `pyenv-config.el`: per-buffer pyenv version selection. **Superseded by `uv-config.el` and commented out in `init.el`** after the pyenv→uv migration; file kept for reference. → `docs/modules/pyenv-config.md`
- `lsp-python-config.el`: Python LSP via `lsp-pyright` (configured for **basedpyright**, not pyright). Activates in `python-mode` / `python-ts-mode` and inside org-babel Python src blocks opened with `C-c '`. Disables `ruff-lsp` and `ruff` lsp clients to prevent overlap. Depends on `lsp-core.el`, `org-config.el`'s `org-src-*` settings, and `my/unique-file-path` from `utils.el`. → `docs/modules/lsp-python-config.md`
- `lsp-elisp-config.el`: Experimental Elisp LSP configuration (currently disabled/irrelevant).
- `lsp-c-config.el`: C/C++ LSP configuration via `lsp-clangd`.
- `lsp-web-config.el`: JS/TS LSP (`typescript-mode`, built-in `js`).
- `lsp-json-config.el`: JSON LSP via `vscode-json-language-server` with SchemaStore auto-detection.
- `lsp-ltex-plus-config.el`: User configuration and activation for the `lsp-ltex-plus` package — a minimal `lsp-mode` client for `ltex-ls-plus` (Markdown, LaTeX, Org, HTML, etc.) that replaces the heavy `lsp-ltex` with a transparent implementation using proactive configuration pushing. Managed via a local repository for development.
- `harper-config.el`: Grammar checker configuration via `harper-ls` and Eglot. Currently commented out; used for comparing with LTEX+.
- `latex-config.el`: LaTeX specific editing configuration and PDF viewer integration. SyncTeX forward/inverse search and viewer selection (`latex-config-pdf-viewer`: `skim`/`pdf-tools`/`auto`) live here since they are AUCTeX-specific; the Skim revert step reuses `pdf-preview-skim-revert` from `pdf-preview.el` rather than inlining its own `osascript`.
- `pdf-preview.el`: shared, viewer-agnostic "open this PDF" helpers used by `latex-config.el` and `typst-config.el`, so the macOS Skim launch/revert logic and the Skim-vs-pdf-tools-vs-OS-default choice are written once. `pdf-preview-viewer` (defcustom, default `skim`) picks the viewer; `pdf-preview-open` (a `user-error` on a missing file, otherwise dispatches on that choice) is suitable as a `*-preview-function`. `pdf-preview-skim-revert`/`pdf-preview-skim-open` drive Skim via `osascript`/`open` (revert an already-open copy first so a recompiled PDF refreshes even with Skim's file-change watching off; fall back to `browse-url` off macOS). `pdf-preview-skim-open` brings Skim to the foreground (explicit "show me the PDF"), whereas `pdf-preview-skim-revert` stays silent/background so it can be reused mid-edit by LaTeX SyncTeX forward search; `auto` resolves per call to pdf-tools in GUI frames, Skim in TTY frames, OS default elsewhere. Owns *plain* preview only — SyncTeX stays in `latex-config.el`.
- `lsp-tex-config.el`: LaTeX LSP configuration via `texlab`.
- `org-config.el`: Org mode plus inline LaTeX previewing and Python babel, on **built-in Org** (`:straight (org :type built-in)` — not a bare `:straight nil`, since `org-appear` requires `org` and would otherwise rebuild the leftover fork checkout onto `load-path`). Migrated off **tecosaur's (now unmaintained) fork**. In-buffer math is rendered by the homegrown **`org-latex-to-svg`** package (a front-end over the standalone **`latex-to-svg`** engine, both in `~/Documents/Programming/Emacs/`; `org-mode-hook` enables `org-latex-to-svg-mode`). The shared `latex-to-svg` engine is registered and configured centrally in **`latex-to-svg-config.el`** (loaded first in init.el), not here — this file only registers the `org-latex-to-svg` front-end and turns the mode on. The engine compiles each equation once (content-addressed), color- and size-independent, so previews **recolour on OS theme switch and rescale on text zoom straight from cache with no LaTeX recompile** — the fork's ergonomics without the fork. Built-in Org's classic `org-latex-preview` (dvisvgm) stays as a fallback when the mode is off. The earlier stopgap (classic preview + `org-format-latex-options` recolour/rescale hooks) and `org-startup-with-latex-preview` were removed. The full fork-based config is preserved but unloaded in `org-karthink-config.el`. Also sets `org-id-locations-file` (via `emacs-config-cache-file`, so `org-id`'s ID→file map stays out of the worktree): it spans every org file this Emacs knows, so it belongs with org rather than with any one vulpea vault — keeping it in step with vulpea's db is `vulpea-vault/ids.el`. Installs `org-appear` for emphasis-marker auto-toggling. Enables `org-num-mode` from `org-mode-hook`, so section numbers are drawn as overlays instead of living in the heading text — the notes imported from Obsidian carried them literally (`5.4.2. TensorFlow with TensorRT support`), which put the number inside every `[[*Heading]]` link target and broke every link below an inserted section. Tunes `C-c '` (`org-edit-special`) with `org-src-*` settings that `lsp-python-config.el` depends on. Python babel defaults are minimal (`:results output :exports both`) — matplotlib setup belongs in per-file blocks or yasnippets. → `docs/modules/org-config.md`
- `org-karthink-config.el`: **preserved, not loaded.** The previous `org-config.el` that pulled Org from tecosaur's fork (custom straight recipe with synthesized `org-version.el`, stale-`.fmt` purge) for karthink's live preview. Kept for reference / as a basis for a homegrown math-rendering package. Not wired into `init.el`.
- `vulpea-config.el`: note database over the org notes migrated from the Obsidian work vault — **vulpea v2** (standalone; v2 dropped org-roam and owns its own SQLite db). Also the single owner of the settings that key off `:ID:`, since three systems share that one property: `org-id` (`id:` links), `org-attach` (attachment directory) and vulpea (database primary key). **No vault directory is named anywhere in this repository** — a vault becomes known by being opened, `vulpea-vault-history` (savehist) remembers it, and startup resumes its most recent reachable entry; "no vault open" is a supported state. A directory counts as a vault only because its `.dir-locals.el` declares `(vulpea-vault-version . N)`, and everything else a vault can say about itself — attachment store, cache location, folder roles, tag vocabulary, per-folder note templates — is declared there too. The code side of that contract is `vulpea-vault/scheme.el`, the single place holding every variable a vault may set (default, docstring, `safe-local-variable` predicate) and nothing else's business: `vulpea-vault-schema-version` versions exactly that list, so adding a declaration and weighing a bump are adjacent lines; a predicate must be attached before any `.dir-locals.el` naming it is read, which the startup resume does before the other modules load; and one unsafe variable makes Emacs discard a whole dir-locals file (silently, non-interactively), so partial declaration is not a degraded state but a broken one. The consumers (`directories`, `tags`, `create`, and `core` for the two global ones) only read the values. `vulpea-vault/core.el` owns which vault is in use: `vulpea-vault-directory`, `vulpea-vault-apply` (derives the five vault-dependent settings from a root), `vulpea-vault-or-error`, `vulpea-vault-resume` (startup); `M-x vulpea-vault-switch` re-points them live, closing the leaving vault's buffers because `org-attach-id-dir` is a single global with no per-buffer form. **`vulpea-vault/` is written as a package that happens not to be published** — generic mechanism, nothing in it naming a machine or a directory — while `vulpea-config.el` is only this machine's configuration of it (straight recipes, bindings, the module list; `org-id` is not configured here at all — `org-id-locations-file` sits with the rest of org in `org-config.el`); the test for anything added later is *would this be wrong on another machine or for another vault?* Host facts cross through a declared socket, never a hostname inside a module: `git.el` defines `vulpea-vault-git-rollup-environment` for a rollup that has to be handed a credential, and nothing supplies one here — the rollup runs with no SSH agent in its environment (`unset SSH_AUTH_SOCK` in the script), so it signs from a key file and authenticates from an SSH key on disk, and no dialog is reachable from it. One concern per file (`scheme`, `core`, `directories`, `tags`, `create`, `ids` — keeps `org-id` in step with vulpea's db (index hook, `M-x vulpea-vault-update-id-locations`, the lowercase-UUID `org-id-new` override) — `attachments` — the ID-keyed store and the cross-note `attachment:<uuid>/file` syntax — `orphans` — the dangling-link / unreferenced-file / undeclared-tag report — `select`, `switch`, `semantic` — ties the vault's org-semantic index to the switch, see `org-semantic-config.el` — `modified-stamp`, `git` — every save recorded on a Magit work-in-progress ref, folded into one commit every 6 h by `etc/goodies/notes-git-rollup.sh`, driven by an Emacs timer that backs up every vault opened in this Emacs (`vulpea-vault-history` + the active one), each its own git repo — backup is not scoped to the single active vault, since that limit is vulpea's database, not git (a launchd agent would have to name one); the interval is judged from the age of `HEAD`, not measured by the timer, so it survives restarts; `C-c n l` reads both — and the `x-bdsk:` / `pdffile:` / `message:` link types), loaded from here the way `completion.el` loads `completions/`. The tree is produced by `etc/goodies/obsidian-to-org.py`. `C-c n f`/`i`/`b` for find/insert/backlink, `C-c n v` to switch vault, `C-c n d` for Dired on the vault root (`vulpea-vault-dired`, in `directories.el` — the root is the one folder a vault never declares, so it is a command there rather than a role). `vulpea-vault-switch` runs two abnormal hooks — `vulpea-vault-leave-functions` (root being left, after its buffers are closed, before anything is re-pointed) and `vulpea-vault-enter-functions` (new root, once everything is in place) — neither of which runs at startup, since resuming a vault leaves none and a fresh Emacs starts no process it need not. → `docs/modules/vulpea-config.md`
- `org-semantic-config.el`: semantic (embedding) + lexical (BM25) search over a tree of org notes via the user-authored **`org-semantic`** package — one Rust binary driven over a pipe (`org-semantic serve`, JSON-RPC on stdio through `jsonrpc.el`), no database server and no Python. Straight is pointed at the local checkout `~/Documents/Programming/Emacs/org-semantic` (`:local-repo` + `:repo`, with `:files ("lisp/*.el")` since the Lisp is under `lisp/`); the recipe path is written out literally because a use-package recipe is literal data, not an expression. `org-semantic-executable` and `org-semantic-install-directory` are left at their defaults on purpose, so the binary is found the way it is for anyone with no configuration (`~/.config/emacs/org-semantic/`, then PATH); the development build is put in that first place by a symlink, not by a setting, which keeps the real lookup exercised here. Deferred — the process starts on the first search. `C-c n s` find, `C-c n S` find scoped to `default-directory` and below (`org-semantic-find-in-directory`, which prefills the prompt with a `dir:` predicate naming it — editable text, not a hidden argument), `C-c n .` find-at-point, `C-c n R` reindex; `org-semantic-index-mode` is `"both"` and `org-semantic-require-fresh-index` is t (the indexes are kept current automatically, so a stale answer would be the wrong one rather than merely an old one). `org-semantic-config` (the indexing policy) is stated **whole** — it is compared whole, so a setting left out takes its default and a policy disagreeing with the one an index was built under fails the search; everything in it is org-semantic's own default except `:languages`, which names the three the vaults are written in. Which tree is searched is not decided here: a vault declares `(org-semantic-vault-root . t)` in its `.dir-locals.el`, and that is the only thing that finds one — nothing searches the filesystem, and the `.org-semantic` directory is derived data that is never consulted, since a vault may keep its index elsewhere entirely. The vulpea vaults are wired to it in `vulpea-vault/semantic.el`: `close` is sent for the vault being left (one process holds every vault until told otherwise — a ceiling, not a refund), the enter hook only says (when the server already runs) that a vault has no index yet, and `org-semantic-vault-root` is set to the function `vulpea-vault-semantic-vault` (not advice — org-semantic asks the setting for it), so a buffer belonging to no org-semantic vault falls back to the active vulpea vault and `C-c n s` searches the notes from anywhere. That module never loads org-semantic — it acts only when something else already has.
- `jupyter-config.el`: emacs-jupyter for remote kernels via the Jupyter Server protocol (HTTP/WebSockets). Registers `jupyter-python` as an Org-babel language with optimized defaults (e.g., `:results output` to capture stdout). Includes an automated workaround to fetch prebuilt `zmq` dynamic modules on macOS (Apple Silicon) and Linux, bypassing local build/link failures.
- `code-cells-config.el`: Spyder/VSCode-style `# %%` code cells in plain `.py`/`.jl`/`.R` files via the `code-cells` package. Provides cell-aware navigation (`M-n`/`M-p`) and evaluation (`C-c C-c`); `code-cells-mode-maybe` auto-activates only in buffers that contain cell markers, so plain files without `# %%` lines are unaffected. When `emacs-jupyter` is loaded too, redirects `jupyter-eval-line-or-region` to `code-cells-eval` via `[remap]` — operates at the command-symbol level (not the key level), so it catches whatever key jupyter binds to its line-region eval (present or future) without enumerating keys or fighting keymap-priority order. The remap is wrapped in `with-eval-after-load 'jupyter`, so disabling jupyter-config doesn't break code-cells.
- `markdown-config.el`: Markdown reading and authoring. Configures `markdown-ts-mode` (tree-sitter backed, bundled with Emacs 31) directly via `:mode` on `\\.md\\'` and `\\.markdown\\'`; the legacy `markdown-mode` package was removed once ts-mode reached parity for note-taking workflows. Link helpers handle Obsidian-style `[[wiki]]` and standard `[label](path)` links symmetrically: Markdown targets open with `find-file`; non-Markdown local files open `dired` with the cursor on the file; missing files signal `user-error` with the resolved path; full URLs go to the browser. `C-c C-o` runs `markdown-config-follow-link-at-point`, which detects `[[wiki]]` (regex — the grammar doesn't expose wiki links), `[label](path)` (treesit `inline_link`, with angle brackets stripped from the pointy-bracket form), or bare URL at point. Wiki links receive visual fontification via a single font-lock keyword layered on top of the treesit rules: `link`-style face on the visible label, `mouse-1`/`mouse-2` click-to-follow, and label-only rendering (brackets and `name|` prefix marked `invisible` against the bundled `markdown-ts--markup` spec, so `markdown-ts-toggle-hide-markup` toggles them with the rest of the markup). Inline links `[label](url)` get the same label-only collapse via a treesit rule that runs the bundled `markdown-ts--fontify-delimiter` over the brackets/parens/`link_destination`/`link_title` (the bundled mode does not hide them out of the box) plus `mouse-1`/`mouse-2` click-to-follow on the label via a treesit fontifier on `link_text` that attaches the same shared keymap used by wiki-link labels. `markdown-ts-hide-markup t` enables markup hiding by default. No in-Emacs preview package is configured: `markdown-preview-mode` (and classic `markdown-live-preview-mode`, and before them `grip-mode`) all dragged in `markdown-mode` plus a `web-server` recipe workaround and a major-mode-stubbing advice, just to shell out to pandoc — so all of it was removed. Preview is done from a terminal instead (`pandoc --from=gfm --to=html5 file.md -o file.html`, optionally with a watcher like `entr`/`watchexec`). Classic `markdown-mode` is no longer configured or used here at all; it is only installed if another package pulls it in as a dependency (e.g. `rustic`). Visual line wrapping is handled by `syntaxes/markdown.el` via `soft-wrap-mode`. → `docs/modules/markdown-config.md`
- `typst-config.el`: Typst authoring via `typst-ts-mode` (meow_king's tree-sitter mode, `https://codeberg.org/meow_king/typst-ts-mode.git`, Emacs 29+). Registered with `:mode` on `\.typ\'`. The uben0 typst grammar is **not** installed here — it is bootstrapped centrally in `treesitter-config.el` via `treesit-language-source-alist` alongside the other grammars. Sets `typst-ts-enable-raw-blocks-highlight` (fenced code blocks highlighted with the embedded language's grammar; must be set before the first typst buffer opens, which `:custom` guarantees since it runs at load time) and `typst-ts-compile-hide-compilation-buffer-if-success`. Compile/watch/PDF-preview (`C-c C-c`, `C-c C-S-c`, `C-c C-p`, `C-c C-w`) shell out to the `typst` CLI (`brew install typst`); editing/navigation/highlighting work without it. Compiled-PDF preview is delegated to `pdf-preview.el` by setting `typst-ts-preview-function` to `pdf-preview-open`, so it honours `pdf-preview-viewer` (Skim on macOS by default) instead of upstream's `browse-url`. Separately, **live preview** with source↔preview jumping (the SyncTeX-like feature the compiled PDF can't provide) is wired via `typst-preview.el` (havarddj, `github:havarddj/typst-preview.el`) + `websocket`, backed by the `tinymist` server over a websocket: `C-c C-l` toggles `typst-preview-mode` (autostart + open browser), `C-c C-j` runs `typst-preview-send-position`; colours follow OS appearance (`typst-preview-invert-colors "auto"`), browser is `"xwidget"` (in-Emacs webkit; requires an `--with-xwidgets` build — fall back to `"default"` for the system browser otherwise). The `tinymist` binary is needed for live preview only — install via `M-x typst-ts-lsp-download-binary` or `cargo install --git https://github.com/Myriad-Dreamin/tinymist --locked tinymist-cli`. The `*typst-compilation*` buffer is kept out of the window tree via a `display-buffer-no-window` rule on `typst-ts-compilation-mode` (effective because `compilation-start` passes `allow-no-window`), popped up again only on failure by a `compilation-finish-functions` hook — this neutralizes typst-ts-mode's `delete-windows-on` call in its success finish-function, which would otherwise collapse a multi-window layout (source + live preview) down to a single window. Same quiet-build technique as `compile-config.el`, replicated locally because that module matches `compilation-mode` exactly and `typst-ts-compilation-mode` is a derived mode.
- `pdf-tools-config.el`: in-Emacs PDF viewing via `pdf-tools` (vedang's actively maintained line). Uses `pdf-loader-install` so the `epdfinfo` C helper builds on first PDF open, not at startup. Registers `pdf-view-mode` for `%PDF` magic and enables `pdf-view-roll-minor-mode` (continuous scroll across page boundaries, upstream as of v1.3.0; experimental). Disables line numbers in PDF buffers. Requires `poppler` + `automake` for the first-open build (`brew install poppler automake` on macOS).
- `lsp-swift-config.el`: Swift LSP via `lsp-sourcekit` (SourceKit-LSP). Locates the server via `PATH` or `xcrun -f sourcekit-lsp` on macOS.
- `lsp-rust-config.el`: Rust LSP via `rustic-mode` + `rust-analyzer` (lsp-mode built-in `lsp-rust`). Enables `rustfmt` on save.
- `lsp-kotlin-config.el`: Kotlin LSP via `kotlin-ts-mode` + JetBrains' official `kotlin-lsp` (priority 0), the only server that can attach — lsp-mode's built-in fwcd client (`kotlin-ls`) is disabled via `lsp-disabled-clients` rather than kept as a fallback. JetBrains is required for Kotlin 2.2+ — fwcd bundles Kotlin 2.1.0 and chokes on newer metadata. Tree-sitter grammar is pinned in `treesitter-config.el` to avoid an upstream font-lock regression. → `docs/modules/lsp-kotlin-config.md`
- `git-gutter-config.el`: VCS gutter indicators in both TTY and GUI frames. Loads a local copy of `git-gutter.el` (patched fork, kept in-repo until changes land upstream) via `:straight nil` + `:load-path emacs-config-dir`.
- `scroll-config.el`: scroll parameters, pixel-precise vertical scrolling via the built-in `pixel-scroll-precision-mode` (on a locally patched Emacs that suspends `scroll-margin` during a wheel gesture and fixes the tall-inline-image scroll jumps, bug#64252; tuned via `pixel-scroll-precision-reposition-point`/`-settle-delay`/`-hide-cursor-while-scrolling`), and a smart horizontal-scroll handler (`scroll-config-horizontal`, bound to `wheel-left`/`wheel-right` at all speed tiers) that suppresses no-op scrolls in wrapped buffers via `scroll-config-suppress-hscroll` (a buffer-local opt-out set by terminal/shell mode hooks in `init.el`, decoupled from `truncate-lines` so terminal emulators keep their full reported width). Also rebinds `C-v`/`M-v`/`PgUp`/`PgDn` to 10-line steps and disables ctrl+scroll zoom. (`ultra-scroll` was removed — it only existed to work around the now-fixed image jumps.) → `docs/modules/scroll-config.md`
- `windows-config.el`: window navigation, splitting, resizing, joining, reflowing, swapping, send-buffer, deletion, and zoom — parallels tmux pane operations. Defines `tmux-map` on `C-b` (shadowing `backward-char`) as the pane prefix; `C-b <arrow>` falls through to `tmux select-pane` at the frame edge when running inside tmux. Built on `windmove`, `winner-mode`, and `repeat-mode`; no external packages. Also rebinds `C-x 1` / `C-x 2` / `C-x 3` / `C-x m`. → `docs/modules/windows-config.md`
- `themes-config.el`: theme orchestration. Installs `modus-themes` (variants: `modus-operandi` light, `modus-vivendi-tinted` dark) and configures palette overrides. Wires `theme-harmonize` (face-sync library, this repo) and `zac-theme-autodetection` (OS-appearance watcher, in `local/`). Theme is selected by `zac-load-theme-callback` based on the OS appearance state file. Load order is intentional: theme-harmonize → modus-themes config → zac-theme-autodetection. → `docs/modules/themes-config.md`
- `theme-harmonize.el`: face-synchronization library hooked on `enable-theme-functions` and `after-make-frame-functions`. Drives a single line-number background color across `line-number`, `margin`, `fringe`, `header-line`, `flycheck-fringe-*`, and `git-gutter:*` so the gutter column blends uniformly in both TTY and GUI. Also overrides the 16 `ansi-color-*` faces (vector palette) so ghostel, eshell, term, and compilation buffers all share one palette — `term-color-*` and `ghostel-color-*` inherit from `ansi-color-*`, so a single set of overrides covers all the terminal stacks. Configured via `theme-harmonize-line-number-bg`, `theme-harmonize-git-gutter-colors`, and `theme-harmonize-ansi-color-palette` (all `:light`/`:dark` plists), set in `themes-config.el`. → `docs/modules/themes-config.md` (combined with themes-config)
- `agent-shell-setup.el`: `agent-shell` (interactive AI coding agents over ACP). Configures the OpenCode adapter — default model, `--attach <url>` against a long-running `opencode serve` (depends on a personal fork at `~/Documents/Programming/Others/fork-opencode.nosync` whose `acp-attach` branch carries the upstream-rejected feature), `M-RET`/`C-c a` bindings — plus an `agent-shell-cwd-function` that feeds the agent the launching buffer's `default-directory` as its working directory (no dired special-casing — dired buffers use agent-shell's stock file-picking workflow), and an override on `agent-shell-project-buffers` that matches session reuse on the `project.el` root (decoupled from cwd, since the two no longer coincide) so any buffer in a project reuses that project's shell regardless of subdirectory. Also enables the `agent-shell-math-renderer` front-end (SVG math in agent responses); the underlying `latex-to-svg` engine and its global settings live in `latex-to-svg-config.el`, not here. → `docs/modules/agent-shell-setup.md`
- `latex-to-svg-config.el`: single owner of the **`latex-to-svg`** rendering engine (LaTeX→SVG library, content-addressed cache, color/size-independent SVGs tinted+scaled at display). Registers the local-checkout straight recipe and sets the engine's **global** defcustoms (`latex-to-svg-font-scale` — equation size vs the buffer font, `latex-to-svg-render-on-non-graphic`, and `latex-to-svg-appended-preamble` — the shared LaTeX packages: physics/stmaryrd/siunitx/mathtools). These are library-wide, shared by every front-end (`agent-shell-math-renderer`, `org-latex-to-svg`), so they live here rather than inside any one front-end. init.el loads this **before** those front-ends so straight can resolve their `latex-to-svg` `Package-Requires` dependency from the checkout.
- `straight-overview-config.el`: thin wiring layer for the user-authored `straight-overview` package — a read-only overview and dired-style selective-upgrade UI for straight.el-managed packages (`M-x straight-overview` lists which packages are behind upstream with `(commits; time)` behind, then pull/optionally rebuild only the marked ones). The package lives in its own standalone repo at `~/Documents/Programming/Emacs/straight-overview` (MPL-2.0); straight is pointed at the local checkout via the canonical local-development recipe (`:local-repo` + `:repo "alberti42/straight-overview"`). Not yet pushed to GitHub.
- `utils.el`: Generic Emacs Lisp utility functions for the configuration. Among them `my/parse-env-file` / `my/env-file-value`, which read the plain `KEY=VALUE` files the shell sources (`~/.config/envs/*.sh`, secrets kept outside this repo) without running a shell: literal assignments only — `export` optional, one surrounding quote pair stripped, a repeated name keeping the last value as a shell would, nil for an unreadable file — and by design no `$VAR` interpolation, command substitution or continuations. `my/env-file-value` also spares the caller the string-key trap (`alist-get` needs `#'equal`). No caller at present — kept because reading one of those files without a shell is a thing the configuration keeps needing. Also `my/yank-markdown-as-org`, which pipes the top of the kill ring through `pandoc -f gfm-gfm_auto_identifiers -t org --wrap=preserve` and yanks the result, the converted text taking the Markdown's place on the kill ring. The extension is switched off because the gfm reader has it on, which gives every pasted heading a `:CUSTOM_ID:` drawer. A prefix argument adds `--shift-heading-level-by=(org-current-level)`, so a pasted `#` becomes a child of the heading point is in rather than a top-level `*` closing its section. Unbound. `my/org-strip-heading-numbering` then drops section numbers from the converted headings (`2.`, `2)`, `2.1`, `2.1.3)`; a bare number with no separator, as in `1990 in review`, is kept) — run on the Org rather than on the Markdown because pandoc writes a block-internal leading `*` as `,*`, so `^\*+ ` cannot hit anything but a heading, whereas a `#` inside a fenced block is indistinguishable from one. `my/org-blank-line-after-headings` then restores the blank line after each heading that org writes and pandoc omits (a heading at end of buffer is left alone; two headings in a row get separated like anything else).

Local package overrides (`local/`):

- `local/vdiff-magit.el`: local patched copy of the unmaintained `vdiff-magit` package. Fixes two Magit API breakages: `magit-get-revision-buffer` removed (replaced by `magit--get-blob-buffer`); `magit-find-file-index-noselect` dropped its second argument. Loaded via `:straight nil` with `:load-path`. TODO: file a PR upstream if the project shows signs of life.
- `local/zac-theme-autodetection.el`: watches the OS appearance state file written by `zsh-appearance-control`; invokes `zac-load-theme-callback` (user-supplied callback). Contains no theme or color choices itself. Loaded via `use-package` (`:straight nil`) with `zac-load-theme-callback` set in `:init` so the watcher picks it up on first application.
- `local/bookmark-aux-file.el`: standalone library (not a patched copy) adding per-context **auxiliary bookmark files** to stock `bookmark.el` via advice only — no fork. A buffer-local `bookmark-aux-file` names an extra bookmark file; while set, its bookmarks merge with the global ones (auxiliary entries first, so a bare-name `bookmark-get-bookmark` resolves to them; both are always shown — duplicate names are never silently removed, matching stock `bookmark.el`), a set from such a buffer always targets the aux file and never overwrites a same-named *global* bookmark (overwrites an aux entry of that name if present, else creates a new aux one), and saves partition each group back to its own file in plain stock format (the in-memory `baf-file` routing tag is stripped on write). Project-agnostic *mechanism*; all lifecycle/location *policy* lives in the consumer (`bookmark-aux-config.el`). Loaded from there via `emacs-config-load-module`. Candidate for an eventual upstream `bookmark.el` proposal. → `docs/modules/bookmark-aux-file.md`


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
- `applescript-mode`: major mode for AppleScript (font-locking + indentation); auto-registers `.applescript`.

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
- `syntaxes/markdown.el`: Sets `fill-column` to 100 and enables `soft-wrap-mode` in `markdown-ts-mode` buffers. (Soft-wrap is opt-in per derived mode — see `syntaxes/text.el`.) Package-level configuration lives in `markdown-config.el`.
- `syntaxes/python.el`: Python indentation settings.
- `syntaxes/sh.el`: Shell script indentation (`sh-basic-offset 2`).
- `syntaxes/text.el`: visual soft wrap at 72 columns for plain `text-mode` only (guarded with `(eq major-mode 'text-mode)` so derived modes like `markdown-ts-mode`, `yaml-ts-mode`, `org-mode` are unaffected — they opt in from their own syntax files). Skips Git commit buffers (`COMMIT_EDITMSG`/`MERGE_MSG` or `git-commit-mode` minor mode), which use auto-fill at 72.
- `syntaxes/yaml.el`: YAML indentation settings.
- `syntaxes/swift.el`: Swift indentation (`swift-mode:basic-offset 4`).
- `syntaxes/dired.el`: disables line numbers in Dired mode.
- `syntaxes/elisp.el`: Elisp settings, sets `fill-column` to 80.
- `syntaxes/magit.el`: Magit display settings, enables `visual-line-mode` and disables line numbers in Magit buffers.
- `syntaxes/agent-shell.el`: disables line numbers in `agent-shell-mode`.
- `syntaxes/xwidget.el`: disables line numbers in `xwidget-webkit-mode` (the embedded webkit view used by typst-preview).

Wrapping:

- `soft-wrap.el` provides `soft-wrap-mode` (buffer-local), `global-soft-wrap-mode`, and `soft-wrap-set-width` for visual-only wrapping. The target column is controlled via `soft-wrap-default-width` (defcustom) or `fill-column` (read dynamically when nil).
- Wrap-at-column is implemented with a window right margin (no newlines inserted). The left margin is always preserved so TTY gutters (e.g. git-gutter) keep working.
- Continuation indentation uses built-in `visual-wrap-prefix-mode` (Emacs 30+). No external packages required.
- `soft-wrap-diagnostic.el` provides debugging tools (`soft-wrap-debug-dump`, `soft-wrap-diagnose`, `soft-wrap-trace-start/stop`). Loaded only when `soft-wrap-load-diagnostics` is non-nil.

Completion submodules (loaded by `completion.el`):

- `completions/styles.el`: baseline completion styles and category overrides. Also installs an advice on `completion--styles` so per-category override styles fully **replace** the global `completion-styles` instead of being prepended (stock Emacs appends, silently re-introducing orderless as a fallback). → `docs/modules/completions.md`
- `completions/orderless.el`: Orderless matching (command-palette style). Per-category overrides: `file` → `(basic partial-completion)`, `emacs-config-dict` → `(basic)`. → `docs/modules/completions.md`
- `completions/minibuffer-vertico.el`: Vertico minibuffer UI (preferred).
- `completions/minibuffer-icomplete.el`: Icomplete/Fido minibuffer UI (fallback).
- `completions/corfu.el`: Corfu in-buffer completion UI (with TTY support).
- `completions/cape.el`: extra CAPF sources via Cape. Defines `emacs-config-cape-dict-prefix`, an in-memory English-word CAPF for prose buffers (Markdown, Org, plain text, LaTeX) that fires after 3 chars, tags with `:category 'emacs-config-dict`, and replaces upstream `cape-dict` (which shells out to `grep -F -m100` per cache miss and surfaces substring-matched noise like `apron` for `pro`). Also defines `emacs-config-cape-prose`, a `cape-capf-super` of dabbrev (≥3 chars) + the dict CAPF, hooked from each prose syntax file — merged because dict's near-universal hit rate would otherwise leave dabbrev dormant in a flat chain. Snippet keys are *not* in any CAPF chain — see `yasnippet-config.el` for the manual `C-c y` insertion path. → `docs/modules/completions.md`
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

### Local-checkout packages: rebuild after editing (gotcha)

Several packages are developed from **local checkouts** under
`~/Documents/Programming/Emacs/` and pointed at via a straight `:local-repo`
recipe: `latex-to-svg`, `org-latex-to-svg`, `agent-shell-math-renderer`, and
`straight-overview`.

**straight does not pick up edits to a local-repo package automatically.** It
builds (byte-compiles into `straight/build/<pkg>/`) once and then loads that
build; editing the source `.el` in the checkout does **not** change what a new
Emacs session loads. So after committing (or even just saving) a change to one
of these packages you must rebuild it, or the running session and the next
restart keep running the stale byte-compiled version:

- `M-x straight-rebuild-package RET <pkg>` — recompile that package from the
  current checkout, then `(load "<pkg>")` (or restart) to pick it up.
- Or use the `straight-overview` UI (`M-x straight-overview`) to pull/rebuild.
- For a quick *session-only* test you can `(load "/abs/path/to/<pkg>.el")`, but
  that is ephemeral — the persistent `straight/build` copy is unchanged, so a
  restart reverts. Always `straight-rebuild-package` to make an edit stick.

Hot-reloading a change into a **running daemon** (when you can't restart) is
the same two steps via `emacsclient -e`: `straight-rebuild-package` then
`load`. (This bit us once: a fix `load`ed as source into the daemon looked
applied, but the stale `.elc` in `straight/build` still shipped the bug.)

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
  - `kotlin-lsp` (via `brew install JetBrains/utils/kotlin-lsp`) — JetBrains' official server; required for projects targeting Kotlin 2.2+. The only Kotlin server used; the fwcd `kotlin-language-server` client is disabled in `lsp-kotlin-config.el`, so there is no fallback.

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
- **Kind-First Routing**: Relies on the kind-first JSON-RPC dispatch in `lsp-mode` (merged upstream) to handle bi-directional traffic — like `workspace/configuration` requests — without deadlocks.
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
