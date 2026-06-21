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
        ;; `mixed-fonts' makes code/table faces inherit from `fixed-pitch'
        ;; instead of `default'.  That is useful only when `default' is a
        ;; proportional font (prose-writing setup); ours is already monospace,
        ;; so enabling it routes org tables and code blocks through whatever
        ;; `fixed-pitch' resolves to and they could misalign.  Keep off unless
        ;; `default' ever becomes proportional.
        modus-themes-mixed-fonts nil)
  (setq modus-operandi-palette-overrides
        '((fg-heading-1 "#2e6b6a")))
  (setq modus-vivendi-tinted-palette-overrides
        '((fg-heading-1 "#8fbcbb")))
  ;; Theme selection is delegated to zac-theme-autodetection, which picks
  ;; modus-operandi (light) or modus-vivendi-tinted (dark) based on OS appearance.
  )

;; modus tints `markdown-ts-html-block' as a prose block.  HTML comments in
;; Markdown (e.g. `<!-- ltex: ... -->') are prose, not code, so clear that
;; background and let the default show through.  `load-theme' re-runs on every
;; new frame (via zac) and would restore the tint, so re-apply on
;; `enable-theme-functions'; the `with-eval-after-load' covers the case where
;; markdown-ts-mode is loaded after the theme.
(defun themes-config--clear-markdown-html-block-bg (&rest _)
  (when (facep 'markdown-ts-html-block)
    (set-face-attribute 'markdown-ts-html-block nil :background 'unspecified)))
(add-hook 'enable-theme-functions #'themes-config--clear-markdown-html-block-bg)
(with-eval-after-load 'markdown-ts-mode
  (themes-config--clear-markdown-html-block-bg))

;; Propagate theme face values to packages that need harmonizing (e.g.
;; git-gutter background matching the line-number column).  Defined here so
;; it is ready before zac-theme-autodetection calls it.
(use-package theme-harmonize
  :straight nil
  :demand t
  :load-path emacs-config-dir
  :config
  ;; Line-number background colors (Catppuccin) applied to both TTY and GUI
  ;; frames: gutter column, left margin, and fringes all share this color.
  (setq theme-harmonize-line-number-bg
        (list :light "#eff1f5"    ; Catppuccin Latte
              :dark "#303446"))   ; Catppuccin Frappe
  (setq theme-harmonize-git-gutter-colors
        '(:light (:added "#01e002" :modified "#ffb500" :deleted "#cf222e")
                 :dark  (:added "#3fb950" :modified "#d29922" :deleted "#f85149")))
  ;; ANSI 16-color palette (Catppuccin Latte / Frappe — same as WezTerm) so
  ;; ghostel, eshell, term, and compilation buffers render colors
  ;; identically to the host terminal in TTY mode.  Order: 0–7 normal
  ;; (black, red, green, yellow, blue, magenta, cyan, white) then 8–15 bright.
  ;; Black/white slots follow WezTerm's Catppuccin plugin: ansi[0]=surface1,
  ;; ansi[7]=subtext1, ansi[8]=surface2, ansi[15]=subtext0.  In Latte that
  ;; means 0/8 are LIGHT grays and 7/15 are DARK grays — opposite of the
  ;; "0=dark, 15=light" convention but matches what WezTerm renders.
  (setq theme-harmonize-ansi-color-palette
        '(:light ["#bcc0cc" "#d20f39" "#40a02b" "#df8e1d"
                  "#1e66f5" "#ea76cb" "#179299" "#5c5f77"
                  "#acb0be" "#d20f39" "#40a02b" "#df8e1d"
                  "#1e66f5" "#ea76cb" "#179299" "#6c6f85"]
          :dark  ["#51576d" "#e78284" "#a6d189" "#e5c890"
                  "#8caaee" "#f4b8e4" "#81c8be" "#b5bfe2"
                  "#626880" "#e78284" "#a6d189" "#e5c890"
                  "#8caaee" "#f4b8e4" "#81c8be" "#a5adce"])))

;; Theme auto-detection via zac-theme-autodetection provided by
;; zsh-appearance-control plugin.  Reads the OS appearance state file
;; and invokes `zac-load-theme-callback'.  Loaded last so every face
;; and package it touches is already initialized.
(use-package zac-theme-autodetection
  :straight nil
  :after theme-harmonize
  :load-path (lambda () (list (expand-file-name "local" emacs-config-dir)))
  :init
  ;; Theme selection callback for zac-theme-autodetection.  Set before loading
  ;; the module so the watcher picks it up on first application.
  (setq zac-load-theme-callback
        (lambda (appearance)
          (load-theme (if (eq appearance :light)
                          'modus-operandi
                        'modus-vivendi-tinted) t)
          )))

(provide 'themes-config)
;;; themes-config.el ends here
