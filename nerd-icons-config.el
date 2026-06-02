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
  (nerd-icons-scale-factor 1.0))

;; NOTE: the Private Use Area (#xe000–#xffff) → "Symbols Nerd Font Mono"
;; fontset mapping is intentionally NOT installed here.  It must ride the
;; `default'-font application in `emacs-config-apply-frame-font' (init.el):
;; changing the default font re-derives the fontset and drops standalone
;; `set-fontset-font' entries, and on macOS a detached re-mapping does not
;; refresh an already-settled frame.  See `emacs-config-setup-pua-fontset'.

(provide 'nerd-icons-config)
;;; nerd-icons-config.el ends here
