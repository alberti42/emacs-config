;;; init.el -*- lexical-binding: t; tab-width: 2; -*-

;; Disable bidirectional text reordering for better performance.
(setq-default bidi-display-reordering 'left-to-right
              bidi-paragraph-direction 'left-to-right)
;; Inhibit the Bidirectional Parentheses Algorithm.
(setq bidi-inhibit-bpa t)

;; Defer fontification while typing; highlighting catches up on idle.
;; In practice, we will never notice the delay, but scrolling and
;; typing may feel smoother.
(setq redisplay-skip-fontification-on-input t)

;; Increase subprocess read buffer from 64KB to 4MB.  LSP servers like
;; rust-analyzer or clangd routinely send multi-megabyte responses;
;; this reduces the number of read() calls Emacs has to make.
(setq read-process-output-max (* 4 1024 1024))

(setq backup-inhibited t)         ; disable backup
(setq make-backup-files nil)      ; stop creating ~ files
(setq auto-save-default nil)      ; disable auto-save completely (no #…# files)
(setq create-lockfiles nil)       ; stop lock files (.#filename)
(setq vc-follow-symlinks t)       ; do not ask confirmation before following symbolic links

;; Unbind C-x C-c (save-buffers-kill-terminal): too easy to hit by accident.
;; Use M-x save-buffers-kill-terminal (or M-x kill-emacs) as an alternative
(global-unset-key (kbd "C-x C-c"))

;; Add reference to Emacs C source files
(let ((src "~/Documents/Programming/Others/fork-emacs"))
  (when (file-directory-p src)
    (setq source-directory src)))

;; Emacs supports per-file settings embedded directly in source files,
;; either as a first-line header (e.g., -*- coding: utf-8-unix -*-) or
;; a footer block:
;;
;;   Local Variables:
;;   buffer-file-coding-system: utf-8-unix
;;   End:
;;g
;; Emacs applies such settings silently if the variable declares
;; itself safe via a safe-local-variable property (e.g., a predicate
;; like #'stringp). Since buffer-file-coding-system lacks that
;; property, Emacs prompts for confirmation instead. This entry is a
;; workaround: it pre-approves this specific pair so Emacs skips the
;; prompt.
(setq safe-local-variable-values
      '((elisp-lint-indent-specs (git-gutter:awhen . 1))
        (buffer-file-coding-system . utf-8-unix)))

;; Bootstrap
;; Keep init.el compact; details live in emacs-config-core.el.
(let ((init-path (or load-file-name
                     user-init-file
                     (expand-file-name "init.el" user-emacs-directory))))
  (load (expand-file-name
         "emacs-config-core"
         (file-name-directory (file-truename init-path)))
        nil 'nomessage))

;; UI chrome, fonts, frame setup, and TTY mode-line separator.
(emacs-config-load-module
 'ui-config
 "Could not load ui-config.el; UI settings are disabled.")

;; Centered startup splash buffer (GUI only, no file args).
(emacs-config-load-module
 'welcome-config
 "Could not load welcome-config.el; startup splash is disabled.")

;; Built-ins
;; cl-lib: Common Lisp compatibility helpers used by many packages.
(use-package cl-lib
  :straight nil) ; use built-in cl-lib (Emacs 24+), don't fetch via straight

;; Smart auto-revert: silently revert clean buffers on external change,
;; prompt when the buffer has unsaved local edits.
(emacs-config-load-module
 'auto-revert-config
 "Could not load auto-revert-config.el; smart auto-revert is disabled.")

;; Suppress the kill prompt when the buffer content matches the file on disk
;; (i.e., edits were made and then fully undone).
(emacs-config-load-module
 'buffer-kill-config
 "Could not load buffer-kill-config.el; kill-buffer prompt suppression is disabled.")

;; UI & Convenience
;; which-key: display available keybindings in popup.
(use-package which-key
  :straight nil  ; use built-in which-key (Emacs 30+), don't fetch via straight
  :config
  (setq which-key-idle-delay 1.0)
  (which-key-mode 1))

;; vundo: visual undo tree, navigate undo history as a tree diagram.
(use-package vundo
  :straight t
  :bind ("C-x u" . vundo))

;; macOS pseudo-daemon
;; Keep Dock icon + menu functional after closing the last GUI frame when using
;; Emacs in server/daemon-style workflows.
;; (emacs-config-load-module
;;   'mac-pseudo-daemon-config
;;   "Could not load mac-pseudo-daemon-config.el; macOS pseudo-daemon behavior is disabled.")

;; electric-pair-mode: auto-close brackets, parens, and quotes.
(electric-pair-mode 0)

;; Accept y/n instead of typing yes/no in full.
(setq use-short-answers t)

;; Save minibuffer history
(savehist-mode 1)

;; Recently visited files
(emacs-config-load-module
 'recentf-config
 "Could not load recentf-config.el; recent files list is disabled.")

;; Project management (submodule-aware root detection)
(emacs-config-load-module
 'project-config
 "Could not load project-config.el; project root detection uses default behavior.")

;; Fast project search (prefer ripgrep)
(emacs-config-load-module
 'search-config
 "Could not load search-config.el; using default project search backend.")

;; Completion system (minibuffer + in-buffer)
(emacs-config-load-module
 'completion
 "Could not load completion.el; using default completion behavior.")

;; Nerd icons (Nerd Fonts)
(emacs-config-load-module
 'nerd-icons-config
 "Could not load nerd-icons-config.el; nerd icons are disabled.")

;; Line numbers
(setq display-line-numbers-type t) ; (t displays absolute line numbers; alternatives: 'relative or 'visual)
;; Non-nil keeps current line absolute while others are relative.
(setq display-line-numbers-current-absolute t)
;; Fix the gutter to a constant width so it never reflows mid-scroll.
;; display-line-numbers-width is buffer-local, so setq-default is required.
;; Without a fixed value, Emacs recomputes the width on every redisplay from the
;; last visible line number (not the total buffer size), causing the gutter to
;; jump whenever scrolling causes the last visible line to cross a power-of-10
;; boundary.  A fixed value of 4 is treated as a minimum: for buffers exceeding
;; 9999 lines Emacs still expands the width automatically.  This mimics neovim,
;; which also reserves a fixed 4 digits by default.
(setq-default display-line-numbers-width 4)
;; Reserve 1 column for the git-gutter indicator in all buffers so the layout
;; never shifts when switching between VC and non-VC buffers.
(setq-default left-margin-width 1)
;; display-line-numbers mode is enabled in all buffers where
(global-display-line-numbers-mode 1)
;; Disable line numbers and suppress horizontal wheel scroll in terminal/shell
;; buffers.  Hscroll is suppressed via a buffer-local flag rather than by
;; setting `truncate-lines' to nil: the latter would cause Emacs to reserve the
;; last column for the continuation glyph, making vterm's prompt overflow by one
;; character because it reports the full window width to the child process.
(dolist (hook '(shell-mode-hook eshell-mode-hook term-mode-hook vterm-mode-hook ghostel-mode-hook))
  (add-hook hook (lambda ()
                   (display-line-numbers-mode -1)
                   (setq-local scroll-config-suppress-hscroll t))))

;; Terminal emulators (term, eshell, vterm)
(emacs-config-load-module
 'terminal-config
 "Could not load terminal-config.el; terminal settings are disabled.")

;; Wrapping helpers (soft wrap, visual only)
(use-package soft-wrap
  :straight nil
  :load-path emacs-config-dir
  :commands (soft-wrap-mode global-soft-wrap-mode)
  :custom
  (soft-wrap-load-diagnostics nil))

;; Tree-sitter grammars (auto-install missing ones)
(emacs-config-load-module
 'treesitter-config
 "Could not load treesitter-config.el; tree-sitter grammar bootstrap is disabled.")

;; Per-syntax indentation settings
(emacs-config-load-module
 'syntaxes
 "Could not load syntaxes.el; per-syntax settings are disabled.")

;; Terminal key decoding (CSI u).
(emacs-config-load-module
 'csi-u-keys
 "Could not load csi-u-keys.el; CSI-u key decoding is disabled.")

;; vim-file-locals: parse Vim modelines/file-local settings in files.
(use-package vim-file-locals
  :straight (vim-file-locals
             :type git
             :host github
             :repo "abougouffa/emacs-vim-file-locals")
  ;; Enable globally after startup; it adds `vim-file-locals-apply` to
  ;; `find-file-hook` for newly opened files.
  :hook (after-init . vim-file-locals-mode))

;; Clipboard
(setq select-enable-clipboard t)

;; Before overwriting the clipboard with a kill, save its current
;; content into the kill ring so M-y can still retrieve it.
(setq save-interprogram-paste-before-kill t)

;; macOS: sync kill ring → clipboard via pbcopy (TTY and GUI).
(when (eq system-type 'darwin)
  (emacs-config-load-module
   'mac-clipboard
   "Could not load mac-clipboard.el; macOS clipboard sync is disabled."))

;; Linux: sync clipboard via xclip; also enable X11 primary selection.
;; (declare-function xclip-mode "xclip")
;; (when (eq system-type 'gnu/linux)
;;   (use-package xclip
;;     :if (not window-system)
;;     :config
;;     (setq select-enable-primary t)
;;     (xclip-mode 1)))

;; General-purpose interactive utilities (insert-uuid, copy-buffer-file-name, …)
(emacs-config-load-module
 'utils
 "Could not load utils.el; utility commands are disabled.")

;; Dired and file manager
(emacs-config-load-module
 'dired-config
 "Could not load dired-config.el; dired customizations are disabled.")

;; Window navigation (C-c <arrow>) and resizing (C-c C-<arrow>)
;; Match tmux's repeat-time default (500ms) for consistent feel.
(setq repeat-exit-timeout 0.5)
(emacs-config-load-module
 'windows-config
 "Could not load windows-config.el; windmove and window resizing are disabled.")

;;;; -- Development tools ------------------------------------------------------

;; multiple-cursors: Sublime Text-style multiple cursors.
(use-package multiple-cursors
  :bind (("C->" . mc/mark-next-like-this)
         ("C-<" . mc/mark-previous-like-this)))

;; magit: Git porcelain, forge (GitHub/GitLab), and nerd-icons integration.
(emacs-config-load-module
 'magit-config
 "Could not load magit-config.el; Magit is disabled.")

;; Project tree (TTY-friendly)
(emacs-config-load-module
 'treemacs-config
 "Could not load treemacs-config.el; Treemacs is disabled.")

;; inheritenv: propagate buffer-local `process-environment' and `exec-path'
;; from the caller buffer into commands that internally pop to a fresh
;; buffer (and therefore lose the caller's buffer-locals) before spawning.
;; `inheritenv-add-advice' wraps a command so that, at spawn time, it copies
;; the caller buffer's env into the target buffer.
;;
;; Precedence note.  Some target buffers (notably agent-shell, which calls
;; `hack-dir-local-variables-non-file-buffer' on its own buffer right after
;; creation) re-apply dir-locals AFTER inheritenv has already snapshotted
;; the caller env.  Because the dir-local hook (`pyenv--apply-dir-local')
;; sets buffer-local `process-environment'/`exec-path' explicitly, its
;; values OVERRIDE whatever was inherited.  Net result: if the project has
;; a `.dir-locals.el' with `pyenv-version', it wins over an interactive
;; `pyenv-activate-buffer' done in the caller buffer.  Everything else on
;; this list (shells, terminals, generic project.el spawners) does NOT
;; re-apply dir-locals, so the inherited env is what spawns see.
(use-package inheritenv
  :config
  (dolist (cmd '(shell
                 eshell
                 term
                 vterm
                 ghostel
                 async-shell-command
                 compile
                 project-shell
                 project-eshell
                 project-async-shell-command
                 project-compile
                 agent-shell
                 agent-shell-google-start-gemini
                 agent-shell-anthropic-start-claude-code
                 agent-shell-opencode-start-agent))
    (inheritenv-add-advice cmd)))

(emacs-config-load-module
 'apheleia-config
 "Could not load apheleia-config.el; formatters are disabled.")

;; Buffer-local pyenv activation (PYENV_VERSION per buffer).
(emacs-config-load-module
 'pyenv-config
 "Could not load pyenv-config.el; per-buffer pyenv activation is disabled.")

;;; VCS gutter

(emacs-config-load-module
 'git-gutter-config
 "Could not load git-gutter-tty.el; VCS gutter is disabled.")

;;;; -- LSP clients ------------------------------------------------------------

;; LSP modules
(emacs-config-load-module
 'lsp-core
 "Could not load lsp-core.el; LSP is disabled.")

(emacs-config-load-module
 'lsp-python-config
 "Could not load lsp-python-config.el; Python LSP is disabled.")

(emacs-config-load-module
 'lsp-elisp-config
 "Could not load lsp-elisp-config.el; Elisp LSP is disabled.")

(emacs-config-load-module
 'lsp-web-config
 "Could not load lsp-web-config.el; TypeScript/JavaScript LSP is disabled.")

(emacs-config-load-module
 'lsp-json-config
 "Could not load lsp-json-config.el; JSON LSP is disabled.")

(emacs-config-load-module
 'lsp-ltex-plus-config
 "Could not load lsp-ltex-plus-config.el; LTEX+ is disabled.")

;; (emacs-config-load-module
;;  'lsp-ltex-plus-config-old
;;  "Could not load lsp-ltex-plus-config.el; LTEX+ is disabled.")

;; (emacs-config-load-module
;;  'harper-config
;;  "Could not load harper-config.el; Harper is disabled.")

(emacs-config-load-module
 'lsp-swift-config
 "Could not load lsp-swift-config.el; Swift LSP is disabled.")

(emacs-config-load-module
 'lsp-rust-config
 "Could not load lsp-rust-config.el; Rust LSP is disabled.")

(emacs-config-load-module
 'lsp-kotlin-config
 "Could not load lsp-kotlin-config.el; Kotlin LSP is disabled.")

(emacs-config-load-module
 'lsp-c-config
 "Could not load lsp-c-config.el; C/C++ LSP is disabled.")

(emacs-config-load-module
 'lsp-tex-config
 "Could not load lsp-tex-config.el; TeX/LaTeX LSP is disabled.")

;;;; -------------------------------------------------------------------------

;; Editing
(emacs-config-load-module
 'latex-config
 "Could not load latex-config.el; AUCTeX is disabled.")

;; Markdown reading/authoring (olivetti, obsidian vault, grip-mode preview)
(emacs-config-load-module
 'markdown-config
 "Could not load markdown-config.el; Markdown enhancements are disabled.")

;; Org mode (LaTeX preview, Python babel, literate notebooks)
(emacs-config-load-module
 'org-config
 "Could not load org-config.el; Org mode enhancements are disabled.")

;; lua-mode: major mode for editing Lua.
(use-package lua-mode)

;; ssh-config-mode: major mode for ~/.ssh/config.
(use-package ssh-config-mode)

;; swift-mode: major mode for Swift.
(use-package swift-mode)

;; AI agent shell (Claude Code, Gemini CLI, etc. via ACP)
(emacs-config-load-module
 'agent-shell-config
 "Could not load agent-shell-config.el; agent-shell is disabled.")

;; Themes
;; Load order within themes-config: theme-harmonize → load-theme → zac-theme-autodetection.
;; See themes-config.el for the rationale.
(emacs-config-load-module
 'themes-config
 "Could not load themes-config.el; theme and appearance settings are disabled.")

;; Terminal UX
;; Mouse support in terminal Emacs.
;; `xterm-mouse-mode` enables mouse events in terminal emulators that support it.
(use-package mouse
  :straight nil
  :if (not window-system)
  :preface
  (defun emacs-config--scroll-down-1 ()
    (interactive)
    (scroll-down 1))

  (defun emacs-config--scroll-up-1 ()
    (interactive)
    (scroll-up 1))
  :config
  (xterm-mouse-mode 1)
  ;; Wheel events in terminals are usually mouse-4/mouse-5.
  ;; Keep wheel-up/wheel-down bindings too (some builds/terminals use them).
  (global-set-key [mouse-4] #'emacs-config--scroll-down-1)
  (global-set-key [mouse-5] #'emacs-config--scroll-up-1)
  (global-set-key [wheel-up] #'emacs-config--scroll-down-1)
  (global-set-key [wheel-down] #'emacs-config--scroll-up-1))

;; Cursor navigation (smart Home/End)
(emacs-config-load-module
 'navigation-config
 "Could not load navigation-config.el; smart Home/End keys are disabled.")

;; Scrolling
(emacs-config-load-module
 'scroll-config
 "Could not load scroll-config.el; scrolling settings are disabled.")

;; tmux open-file bridge: open files in Emacs from tmux via IPC.
;; Requires Emacs 29+ for server-after-make-frame-hook.
(use-package tmux-tandem
  :if (>= emacs-major-version 29)
  :straight (tmux-tandem
             :type git
             :host github
             :repo "alberti42/emacs-tmux-tandem")
  :config
  (tmux-tandem-enable))
