;;; themes-config.el --- Theme loading and appearance synchronization -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Load order within this module is intentional and must be preserved:
;;
;;  1. theme-harmonize  — defines `emacs-config-harmonize-theme`.  Must be
;;                        loaded first so the function exists before anything
;;                        calls it.
;;
;;  2. load-theme       — activates the base theme.
;;
;;  3. zac-theme-autodetection — reads the OS appearance, sets face colors, and
;;                        calls `emacs-config-harmonize-theme` to propagate them.
;;                        Must come last so all faces and packages it touches are
;;                        already defined.

;;; Code:

;; Propagate theme face values to packages that need harmonizing (e.g.
;; git-gutter background matching the line-number column).  Defined here so
;; it is ready before zac-theme-autodetection calls it.
(emacs-config-load-module
  'theme-harmonize
  "Could not load theme-harmonize.el; theme face harmonization is disabled.")

;; catppuccin-theme: Catppuccin theme collection.
;; Disabled: too little contrast; keeping the package declaration for easy
;; re-enable when a replacement is chosen.
;; (use-package catppuccin-theme)

;; modus-vivendi-tinted: high-contrast, WCAG AAA. Built-in since Emacs 28.
;; (setq modus-themes-common-palette-overrides
;;       '((bg-line-number-inactive unspecified)
;;         (bg-line-number-active unspecified)))
(load-theme 'modus-vivendi-tinted t)

;; Theme auto-detection via zsh-appearance-control.  Reads the OS appearance
;; state file, applies face overrides (including line-number background), and
;; calls `emacs-config-harmonize-theme`.  Loaded last so every face and package
;; it touches is already initialized.
(emacs-config-load-module
  'zac-theme-autodetection
  "Could not load zac-theme-autodetection.el; theme auto-switching is disabled.")

(provide 'themes-config)
;;; themes-config.el ends here
