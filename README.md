# Emacs Configuration

A personal Emacs configuration built around a modular design, with solid support for
both GUI and terminal (TTY) Emacs.

## Features

**Completion**
- [Vertico](https://github.com/minad/vertico) — vertical minibuffer UI
- [Corfu](https://github.com/minad/corfu) + [Cape](https://github.com/minad/cape) — in-buffer completion with TTY support
- [Orderless](https://github.com/oantolin/orderless) — flexible, command-palette-style matching
- [Consult](https://github.com/minad/consult) + [Marginalia](https://github.com/minad/marginalia) — enhanced search and annotations

**Language support (LSP)**
- Python via [basedpyright](https://github.com/DetachHead/basedpyright)
- TypeScript / JavaScript via `typescript-language-server`
- JSON via `vscode-json-language-server` with SchemaStore auto-detection
- Grammar and spell checking via [LTEX+](https://github.com/ltex-plus/ltex-ls-plus) (Markdown, LaTeX, Org, plain text)
- Snippet expansion via [yasnippet](https://github.com/joaotavora/yasnippet) (enabled in LSP buffers)

**Git**
- [Magit](https://magit.vc/) with [Forge](https://magit.vc/manual/forge/) (GitHub/GitLab)
- Git gutter indicators in both TTY and GUI frames

**UI**
- [Modus Themes](https://protesilaos.com/emacs/modus-themes) with automatic dark/light switching
- [Treemacs](https://github.com/Alexander-Miller/treemacs) file tree (TTY-friendly)
- [Nerd Fonts](https://www.nerdfonts.com/) icons via `nerd-icons`
- Relative line numbers with absolute current line
- Pixel-precise scrolling in GUI (`ultra-scroll`)
- Frameless window style on macOS GUI

**Editor**
- Multiple cursors (`C->` / `C-<`)
- Soft visual wrapping for prose and Markdown
- Dired with preview and narrowing
- Vim modeline support
- CSI-u terminal key decoding for richer key bindings in TTY
- tmux open-file bridge via [tmux-tandem](https://github.com/alberti42/emacs-tmux-tandem) (open files in Emacs from tmux)

## Requirements

- Emacs 30+
- [Nerd Fonts](https://www.nerdfonts.com/) installed (for icons in GUI)
- External LSP servers on `PATH` as needed:
  - `basedpyright` (Python)
  - `typescript-language-server` (TypeScript/JavaScript)
  - `vscode-json-language-server` from `vscode-langservers-extracted` (JSON)
  - `ltex-ls-plus` (grammar/spell checking)
- `ripgrep` for fast project search
- macOS or Linux (tested on both)

## Installation

Clone and symlink into your Emacs config directory:

```sh
git clone https://github.com/alberti42/emacs-config ~/.config/emacs
```

Or symlink if you manage it as part of a larger dotfiles repo:

```sh
ln -s /path/to/dotfiles/.config/emacs ~/.config/emacs
```

On first launch, [straight.el](https://github.com/radian-software/straight.el)
will bootstrap itself and download all packages automatically.

## Structure

```
early-init.el            # Pre-GUI init (load-prefer-newer)
init.el                  # Entry point; loads core and all modules
emacs-config-core.el     # Bootstrapping, straight.el, use-package
completion.el            # Completion orchestration
completions/             # Vertico, Corfu, Cape, Orderless, Consult, …
syntaxes/                # Per-language indentation and settings
lsp-core.el              # Shared LSP configuration
lsp-python-config.el            # Python LSP
lsp-web-config.el               # TypeScript / JavaScript LSP
lsp-json-config.el       # JSON LSP (SchemaStore)
lsp-ltex-plus-config.el  # Grammar / spell checking
gui-config.el            # Fonts, frame chrome, window dividers
scroll-config.el         # Scrolling (pixel-precise GUI, TTY mouse)
themes-config.el         # Theme loading (modus-themes + appearance sync)
git-gutter-config.el     # VCS gutter (patched local git-gutter.el, TTY + GUI)
theme-harmonize.el       # Face synchronization after theme changes (git-gutter, flymake, line-number)
magit-config.el          # Magit + Forge
treemacs-config.el       # File tree
soft-wrap.el             # Soft-wrap helpers (margin-based, no external deps)
goodies/                 # Non-Elisp companion files
  eb                     #   Script: blocking open-in-Emacs from ghostel (use as $EDITOR)
  xterm-emacs.terminfo   #   Custom terminfo for 24-bit color in terminals
…
```

Each module is self-contained and loaded with graceful degradation: if a module
fails to load, Emacs still starts and logs a warning.

## Theme auto-switching

Dark/light switching is driven by
[zsh-appearance-control](https://github.com/alberti42/zsh-appearance-control),
which writes a state file read by `zac-theme-autodetection.el`.

The active theme package is [Modus Themes](https://protesilaos.com/emacs/modus-themes) — high-contrast, WCAG AAA compliant:

- Dark  → Modus Vivendi Tinted
- Light → Modus Operandi

## License

MIT — see [LICENSE](LICENSE).
