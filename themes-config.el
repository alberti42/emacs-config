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

;; Theme selection callback for zac-theme-autodetection.  Set before loading
;; the module so the watcher picks it up on first application.
(setq zac-load-theme-function
      (lambda (appearance)
        (load-theme (if (equal appearance "0")
                        'modus-operandi
                      'modus-vivendi-tinted) t)))

;; Theme auto-detection via zsh-appearance-control.  Reads the OS appearance
;; state file, applies face overrides (including line-number background), and
;; calls `emacs-config-harmonize-theme`.  Loaded last so every face and package
;; it touches is already initialized.
(emacs-config-load-module
  'zac-theme-autodetection
  "Could not load zac-theme-autodetection.el; theme auto-switching is disabled.")

(provide 'themes-config)
;;; themes-config.el ends here
