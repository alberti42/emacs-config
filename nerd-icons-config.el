;;; nerd-icons-config.el --- Nerd icons integrations -*- lexical-binding: t; -*-

;; Library
(use-package nerd-icons
  :custom
  ;; "Symbols Nerd Font Mono" is a standalone icon-only font recommended by
  ;; the nerd-icons author.  It contains only Nerd Font glyphs (no text), so
  ;; Emacs uses it exclusively for icon codepoints without interfering with
  ;; the main text font.
  (nerd-icons-font-family "Symbols Nerd Font Mono")
  ;; Render icons slightly smaller than the surrounding text.  Applied by the
  ;; nerd-icons-* functions as a :height property, so it scales relative to the
  ;; text font and tracks text-scale adjustments (dired, ibuffer, treemacs,
  ;; corfu kind-icons).
  (nerd-icons-scale-factor 1.0)
  :config
  ;; Explicitly map the Nerd Font Private Use Area to the icon font so Emacs
  ;; uses the correct glyph metrics instead of falling back to an unknown font.
  ;; This fixes horizontal glyph truncation in GUI Emacs (e.g. in dired).
  (when (display-graphic-p)
    (set-fontset-font t '(#xe000 . #xffff) "Symbols Nerd Font Mono")))

(provide 'nerd-icons-config)
;;; nerd-icons-config.el ends here
