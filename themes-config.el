;;; themes-config.el --- Theme loading and appearance synchronization -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Load order within this module is intentional and must be preserved:
;;
;;  1. theme-harmonize  — defines `theme-harmonize-theme'.  Must be loaded
;;                        first so the function exists before anything calls it.
;;
;;  2. load-theme       — activates the base theme.
;;
;;  3. zac-theme-autodetection — reads the OS appearance and invokes
;;                        `zac-load-theme-callback'.  `theme-harmonize-theme'
;;                        fires automatically via `enable-theme-functions' inside
;;                        `load-theme'.  Must come last so all faces and packages
;;                        it touches are already defined.

;;; Code:

;; modus-themes: high-contrast, WCAG AAA. Built-in since Emacs 28; installing
;; the package here to get the latest version from Protesilaos.
(use-package modus-themes
  :ensure t
  :demand t
  :config
  (setq modus-themes-italic-constructs t
        modus-themes-bold-constructs t
        modus-themes-mixed-fonts t)
  ;; Theme selection is delegated to zac-theme-autodetection, which picks
  ;; modus-operandi (light) or modus-vivendi-tinted (dark) based on OS appearance.
  )

;; Propagate theme face values to packages that need harmonizing (e.g.
;; git-gutter background matching the line-number column).  Defined here so
;; it is ready before zac-theme-autodetection calls it.
(emacs-config-load-module
  'theme-harmonize
  "Could not load theme-harmonize.el; theme face harmonization is disabled.")

;; TTY line-number background colors to match WezTerm's padding (Catppuccin),
;; so the gutter column blends with the terminal border in both appearances.
(setq theme-harmonize-tty-line-number
      (list :light "#eff1f5"    ; Catppuccin Latte
            :dark "#303446"))   ; Catppuccin Frappe

;; Theme selection callback for zac-theme-autodetection.  Set before loading
;; the module so the watcher picks it up on first application.
(setq zac-load-theme-callback
      (lambda (appearance)
        (load-theme (if (eq appearance :light)
                        'modus-operandi
                      'modus-vivendi-tinted) t)
        ))

;; Theme auto-detection via zac-theme-autodetection provided by
;; zsh-appearance-control plugin.  Reads the OS appearance state file
;; and invokes `zac-load-theme-callback'.  Loaded last so every face
;; and package it touches is already initialized.
(emacs-config-load-module
  'zac-theme-autodetection
  "Could not load zac-theme-autodetection.el; theme auto-switching is disabled.")

(provide 'themes-config)
;;; themes-config.el ends here
