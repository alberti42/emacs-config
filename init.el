;;; init.el -*- lexical-binding: t; tab-width: 2; -*-


(setq backup-inhibited t)    ; disable backup
(setq make-backup-files nil) ; stop creating ~ files
(setq auto-save-default nil) ; disable auto-save completely (no #…# files)
(setq create-lockfiles nil)  ; stop lock files (.#filename)
(setq vc-follow-symlinks t)  ; do not ask confirmation before following symbolic links

;; Add reference to Emacs C source files
(let ((src "~/Documents/Programming/Others/fork-emacs"))
  (when (file-directory-p src)
    (setq source-directory src)))

;; Emacs supports per-file settings embedded directly in source files,
;; either as a first-line header (e.g. -*- coding: utf-8-unix -*-) or
;; a footer block:
;;
;;   Local Variables:
;;   buffer-file-coding-system: utf-8-unix
;;   End:
;;
;; Emacs applies such settings silently if the variable declares
;; itself safe via a safe-local-variable property (e.g. a predicate
;; like #'stringp). Since buffer-file-coding-system lacks that
;; property, Emacs prompts for confirmation instead. This entry is a
;; workaround: it pre-approves this specific pair so Emacs skips the
;; prompt.
(add-to-list 'safe-local-variable-values '(buffer-file-coding-system . utf-8-unix))

;; Bootstrap
;; Keep init.el compact; details live in emacs-config-core.el.
(let ((init-path (or load-file-name
                   user-init-file
                   (expand-file-name "init.el" user-emacs-directory))))
  (load (expand-file-name
          "emacs-config-core"
          (file-name-directory (file-truename init-path)))
    nil 'nomessage))

;; GUI chrome, fonts, frame setup, and TTY mode-line separator.
(emacs-config-load-module
  'gui-config
  "Could not load gui-config.el; GUI/frame settings are disabled.")

;; Built-ins
;; cl-lib: Common Lisp compatibility helpers used by many packages.
(use-package cl-lib
  :straight nil) ; use built-in cl-lib (Emacs 24+), don't fetch via straight

;; Smart auto-revert: silently revert clean buffers on external change,
;; prompt when the buffer has unsaved local edits.
(emacs-config-load-module
  'auto-revert-config
  "Could not load auto-revert-config.el; smart auto-revert is disabled.")

;; Suppress kill prompt when the buffer content matches the file on disk
;; (i.e. edits were made and then fully undone).
(emacs-config-load-module
  'buffer-kill-config
  "Could not load buffer-kill-config.el; kill-buffer prompt suppression is disabled.")

;; UI & Convenience
;; which-key: display available keybindings in popup.
(use-package which-key
  :straight nil  ; use built-in which-key (Emacs 30+), don't fetch via straight
  :config
  (setq which-key-idle-delay 0.200)
  (which-key-mode 1))

;; vundo: visual undo tree, navigate undo history as a tree diagram.
(use-package vundo
  :straight t
  :bind ("C-x u" . vundo))

;; macOS pseudo-daemon
;; Keep Dock icon + menu functional after closing the last GUI frame when using
;; emacs in server/daemon style workflows.
;; (emacs-config-load-module
;;   'mac-pseudo-daemon-config
;;   "Could not load mac-pseudo-daemon-config.el; macOS pseudo-daemon behavior is disabled.")

;; electric-pair-mode: auto-close brackets, parens, quotes.
(electric-pair-mode 1)

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
;; If this option is non-nil, ‘display-line-numbers-width’ is set up
;; from the start to a width necessary to display all line numbers in
;; the buffer.
(setq display-line-numbers-width-start t)
;; display-line-numbers mode is enabled in all buffers where
(global-display-line-numbers-mode 1)
;; Disable line numbers in terminal/shell buffers.
(dolist (hook '(shell-mode-hook eshell-mode-hook term-mode-hook vterm-mode-hook))
  (add-hook hook (lambda () (display-line-numbers-mode -1))))

;; Terminal emulators (term, eshell, vterm)
(emacs-config-load-module
  'terminal-config
  "Could not load terminal-config.el; terminal settings are disabled.")

;; Wrapping helpers (soft wrap, visual only)
(use-package soft-wrap
  :straight nil
  :load-path emacs-config-dir
  :commands (soft-wrap-enable soft-wrap-disable))

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

;; Copy the current buffer's file path to the kill ring.
(defun copy-buffer-file-name ()
  "Copy the absolute path of the current buffer's file to the kill ring.
When called from the minibuffer, resolves the buffer that was active
before entering it.  Does nothing if the buffer does not visit a file."
  (interactive)
  (if-let* ((name (buffer-file-name (window-buffer (minibuffer-selected-window)))))
      (progn (kill-new name) (message "%s" name))
    (message "Buffer has no file name")))

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

;; Development
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

;; LSP modules
(emacs-config-load-module
  'lsp-core
  "Could not load lsp-core.el; LSP is disabled.")

(emacs-config-load-module
  'lsp-python
  "Could not load lsp-python.el; Python LSP is disabled.")

(emacs-config-load-module
  'lsp-web
  "Could not load lsp-web.el; TypeScript/JavaScript LSP is disabled.")

(emacs-config-load-module
  'lsp-json
  "Could not load lsp-json.el; JSON LSP is disabled.")

(emacs-config-load-module
  'lsp-ltex-plus-config
  "Could not load lsp-ltex-plus-config.el; LTEX+ is disabled.")

;; VCS gutter (TTY)
(emacs-config-load-module
  'git-gutter-tty
  "Could not load git-gutter-tty.el; VCS gutter is disabled.")

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

;; Languages
;; lua-mode: major mode for editing Lua.
(use-package lua-mode)

;; ssh-config-mode: major mode for ~/.ssh/config.
(use-package ssh-config-mode)

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
