;;; nerd-icons-config.el --- Nerd icons integrations -*- lexical-binding: t; -*-

;; Library
(use-package nerd-icons
  :straight (nerd-icons
             :type git
             :host github
             :repo "rainstormstudio/nerd-icons.el"
             :files (:defaults "data"))
  :custom
  ;; "Symbols Nerd Font Mono" is a standalone icon-only font recommended by
  ;; the nerd-icons author.  It contains only Nerd Font glyphs (no text), so
  ;; Emacs uses it exclusively for icon codepoints without interfering with
  ;; the main text font.
  (nerd-icons-font-family "Symbols Nerd Font Mono")
  :config
  ;; Explicitly map the Nerd Font Private Use Area to the icon font so Emacs
  ;; uses the correct glyph metrics instead of falling back to an unknown font.
  ;; This fixes horizontal glyph truncation in GUI Emacs (e.g. in dired).
  (when (display-graphic-p)
    (set-fontset-font t '(#xe000 . #xffff) "Symbols Nerd Font Mono")))

;; Dired
(use-package nerd-icons-dired
  :after nerd-icons
  :hook (dired-mode . nerd-icons-dired-mode))

(provide 'nerd-icons-config)
;;; nerd-icons-config.el ends here
