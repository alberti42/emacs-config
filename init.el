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

;; Install and configure use-package via straight
(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

(use-package cl-lib)

;; Install packages (straight will install them if missing)
(use-package magit)
(use-package catppuccin-theme)
(use-package lua-mode)
(use-package ssh-config-mode)
(use-package pbcopy)
(use-package xclip)

;; LSP + LTEX (grammar/spell/style checking via LanguageTool)
(use-package which-key
  :config
  (which-key-mode 1))

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")
  ;; Performance: increase the amount of data Emacs reads from subprocesses.
  ;; This helps with LSP servers that send larger JSON payloads.
  (setq read-process-output-max (* 1024 1024))
  :hook
  (lsp-mode . lsp-enable-which-key-integration))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :hook (lsp-mode . lsp-ui-mode)
  :init
  (setq lsp-ui-doc-position 'at-point))

;; Python LSP (Pyright). Requires an external server; see notes below.
(use-package lsp-pyright
  :after lsp-mode
  :init
  (setq lsp-pyright-langserver-command "basedpyright")
  :hook (python-mode . (lambda ()
                        (require 'lsp-pyright)
                        (lsp-deferred))))

;; TypeScript/JavaScript LSP. Requires typescript-language-server + tsserver.
(use-package typescript-mode
  :mode "\\.ts\\'"
  :mode "\\.tsx\\'"
  :hook (typescript-mode . lsp-deferred))

(use-package js
  :straight nil
  :hook (js-mode . lsp-deferred))

(use-package lsp-ltex
  :after lsp-mode
  :init
  (setq lsp-ltex-version "16.0.0")
  (setq lsp-ltex-language "en-US")
  ;; LTEX-LS requires Java 11+. Ensure Emacs launches it with a modern JDK.
  (let* ((jdk-home (cond
                    ((file-directory-p "/opt/homebrew/opt/openjdk@17")
                     "/opt/homebrew/opt/openjdk@17")
                    ((file-directory-p "/opt/homebrew/opt/openjdk@11")
                     "/opt/homebrew/opt/openjdk@11")
                    (t nil)))
         (jdk-bin (when jdk-home (expand-file-name "bin" jdk-home))))
    (when (and jdk-bin (file-executable-p (expand-file-name "java" jdk-bin)))
      (setenv "JAVA_HOME" jdk-home)
      (add-to-list 'exec-path jdk-bin)
      (let ((path (or (getenv "PATH") "")))
        (unless (string-match-p (regexp-quote jdk-bin) path)
          (setenv "PATH" (concat jdk-bin path-separator path))))))
  :hook ((org-mode markdown-mode latex-mode text-mode) .
         (lambda ()
           (require 'lsp-ltex)
           (lsp-deferred))))

;; Example for a GitHub-only package (uncomment if needed):
;; (use-package vim-modeline
;;   :straight (vim-modeline :type git :host github :repo "cinsk/emacs-vim-modeline"))

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
(cond
 ;; macOS: use pbcopy in terminal
 ((eq system-type 'darwin)
  (use-package pbcopy
    :ensure t
    :config
    (turn-on-pbcopy)))

 ;; GNU/Linux: use xclip in terminal
 ((eq system-type 'gnu/linux)
  (use-package xclip
    :ensure t
    :config
    (xclip-mode 1))))

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
