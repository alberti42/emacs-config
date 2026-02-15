;;; init.el -*- lexical-binding: t; -*-

(setq backup-inhibited t) ; disable backup
(setq make-backup-files nil) ; stop creating ~ files
(setq auto-save-default nil) ; disable auto-save completely (no #…# files)
(setq create-lockfiles nil) ; stop lock files (.#filename)
(menu-bar-mode -1) ; turn off menu bar
(setq vc-follow-symlinks t) ; do not ask confirmation before following symbolic links

;; Bootstrap
;; Keep init.el compact; details live in emacs-config-core.el.
(let ((init-path (or load-file-name
                     user-init-file
                     (expand-file-name "init.el" user-emacs-directory))))
  (load (expand-file-name
         "emacs-config-core"
         (file-name-directory (file-truename init-path)))
        nil 'nomessage))

;; Built-ins
;; cl-lib: Common Lisp compatibility helpers used by many packages.
(use-package cl-lib
  :straight nil) ; use built-in cl-lib (Emacs 24+), don't fetch via straight

;; UI & Convenience
;; which-key: display available keybindings in popup.
(use-package which-key
  :straight nil  ; use built-in which-key (Emacs 30+), don't fetch via straight
  :config
  (which-key-mode 1))

;; Save minibuffer history
(savehist-mode 1)

;; Editing Defaults
;; Use spaces for indentation (never literal \t)
(setq-default indent-tabs-mode nil)
;; Configure indentation defaults
(setq-default tab-width 4)
(setq-default standard-indent 4)

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
;; Always sync kill ring <-> system clipboard
(setq select-enable-clipboard t)
(setq select-enable-primary t)   ; use the X11 primary selection too (Linux/Unix)

;; pbcopy: sync clipboard in terminal on macOS.
;; Only needed when running Emacs in a terminal on macOS.
(use-package pbcopy
  :if (and (eq system-type 'darwin) (not window-system))
  :config
  (turn-on-pbcopy))

;; xclip: sync clipboard in terminal on Linux.
;; Only needed when running Emacs in a terminal on Linux.
(use-package xclip
  :if (and (eq system-type 'gnu/linux) (not window-system))
  :config
  (xclip-mode 1))

;; Development
;; magit: Git porcelain inside Emacs.
(use-package magit)

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
 'lsp-ltex
 "Could not load lsp-ltex.el; LTEX is disabled.")

;; Languages
;; lua-mode: major mode for editing Lua.
(use-package lua-mode)

;; ssh-config-mode: major mode for ~/.ssh/config.
(use-package ssh-config-mode)

;; Theme
;; catppuccin-theme: Catppuccin theme collection.
(use-package catppuccin-theme)

;; Theme auto-detection via zsh-appearance-control.
(emacs-config-load-module
 'zac-theme-autodetection
 "Could not load zac-theme-autodetection.el; theme auto-switching is disabled.")

;; Set default font for Emacs
(set-face-attribute 'default nil :font "MesloLGS NF" :height 120)

;; Customize the mode line font
(set-face-attribute 'mode-line nil :font "MesloLGS NF" :height 120 :weight 'bold)
(set-face-attribute 'mode-line-inactive nil :font "MesloLGS NF" :height 120)

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

;; Prevent sudden recentering / keep point away from window edges
(setq scroll-margin 2)
(setq scroll-conservatively 101)
(setq scroll-step 1)

;; Smoother horizontal scrolling too
(setq hscroll-margin 2)
(setq hscroll-step 1)

;; vim: set expandtab tabstop=2 shiftwidth=2 softtabstop=2 :
