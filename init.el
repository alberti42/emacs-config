;;; init.el -*- lexical-binding: t; -*-

(setq backup-inhibited t) ; disable backup
(setq make-backup-files nil) ; stop creating ~ files
(setq auto-save-default nil) ; disable auto-save completely (no #…# files)
(setq create-lockfiles nil) ; stop lock files (.#filename)
(menu-bar-mode -1) ; turn off menu bar
(setq vc-follow-symlinks t) ; do not ask confirmation before following symbolic links

;; Local modules {{{
;;
;; This config is symlinked into ~/.config/emacs. To make local modules work
;; without extra symlinks, resolve the real location of this init file.
(defconst emacs-config-dir
  (file-name-directory (file-truename (or load-file-name user-init-file user-emacs-directory)))
  "Directory containing this Emacs configuration.")

(defun emacs-config-load-module (module warning)
  "Load local MODULE from `emacs-config-dir`.

MODULE is a symbol or string (e.g. 'zac-theme-autodetection).
If loading fails, emit WARNING via `display-warning` and return nil.
On success, return non-nil." 
  (let* ((name (if (symbolp module) (symbol-name module) module))
         (path (expand-file-name name emacs-config-dir)))
    (if (load path t 'nomessage)
        t
      (display-warning 'init warning :warning)
      nil)))

;; Packages: straight.el + use-package
;; straight is not on MELPA; it bootstraps itself from GitHub.
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

;; Install and configure use-package via straight.
;;
;; straight.el is our package manager: it can install packages from ELPA/MELPA
;; and also directly from Git repos (e.g. GitHub) via recipes.
;; use-package provides a declarative way to configure those packages.
(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

;; cl-lib: Common Lisp compatibility helpers used by many packages.
(use-package cl-lib)

;; Install packages (straight will install them if missing)
;; magit: Git porcelain inside Emacs.
(use-package magit)

;; catppuccin-theme: Catppuccin theme collection.
(use-package catppuccin-theme)

;; lua-mode: major mode for editing Lua.
(use-package lua-mode)

;; ssh-config-mode: major mode for ~/.ssh/config.
(use-package ssh-config-mode)

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

;; which-key: display available keybindings in popup.
(use-package which-key
  :straight nil  ; use built-in which-key (Emacs 30+), don't fetch via straight
  :config
  (which-key-mode 1))

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

;; Example for a GitHub-only package (uncomment if needed):
;; (use-package vim-modeline
;;   :straight (vim-modeline :type git :host github :repo "cinsk/emacs-vim-modeline"))

;; vim-file-locals: parse Vim modelines/file-local settings in files.
(use-package vim-file-locals
  :straight (vim-file-locals
             :type git
             :host github
             :repo "abougouffa/emacs-vim-file-locals")
  :config
  (vim-file-locals-mode 1))

;; Use spaces for indentation (never literal \t)
(setq-default indent-tabs-mode nil)

;; Configure indentation defaults
(setq-default tab-width 4)
(setq-default standard-indent 4)

;; Save minibuffer history
(savehist-mode 1)

;; Theme auto-detection via zsh-appearance-control.
(emacs-config-load-module
 'zac-theme-autodetection
 "Could not load zac-theme-autodetection.el; theme auto-switching is disabled.")

;; Set default font for Emacs
(set-face-attribute 'default nil :font "MesloLGS NF" :height 120)

;; Customize the mode line font
(set-face-attribute 'mode-line nil :font "MesloLGS NF" :height 120 :weight 'bold)
(set-face-attribute 'mode-line-inactive nil :font "MesloLGS NF" :height 120)

;; Set syntax for ssh config file
; (add-to-list 'auto-mode-alist '("/.ssh/config" . ssh-config-mode))
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(package-selected-packages nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )

;; Always sync kill ring <-> system clipboard
(setq select-enable-clipboard t)
(setq select-enable-primary t)   ; use the X11 primary selection too (Linux/Unix)

;; Enable mouse support
(unless window-system
  (require 'mouse)
  (xterm-mouse-mode 1)
  (global-set-key [wheel-up] (lambda ()
                               (interactive)
                               (scroll-down 1)))
  (global-set-key [wheel-down] (lambda ()
                                 (interactive)
                                 (scroll-up 1)))
  ;; Optional: support shift/ctrl modifiers
  (global-set-key [double-wheel-up] 'scroll-down-command)
  (global-set-key [double-wheel-down] 'scroll-up-command)
  (defun track-mouse (e))
  (setq mouse-sel-mode t))

;; Prevent sudden recentering / keep point away from window edges
(setq scroll-margin 2)
(setq scroll-conservatively 101)
(setq scroll-step 1)

;; Smoother horizontal scrolling too
(setq hscroll-margin 2)
(setq hscroll-step 1)

;; vim: set expandtab tabstop=4 shiftwidth=4 softtabstop=4 :
