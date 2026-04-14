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
  :hook (dired-mode . nerd-icons-dired-mode)
  :config
  ;; Upstream wraps each icon in (propertize s 'display s) to fix a visual
  ;; artifact when hl-line-mode is active: without it, the icon overlay retains
  ;; the default frame background rather than inheriting the hl-line highlight
  ;; color.  The wrapper causes a side-effect: Emacs defers face evaluation on
  ;; first display, so icons appear colorless until a redisplay is triggered
  ;; (e.g. highlight or g).  We don't use hl-line-mode, so the workaround is
  ;; unnecessary and we drop it here.
  (defun nerd-icons-dired--add-overlay (pos string)
    "Add overlay to display STRING at POS."
    (let ((ov (make-overlay (1- pos) pos)))
      (overlay-put ov 'nerd-icons-dired-overlay t)
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'after-string string))))

(provide 'nerd-icons-config)
;;; nerd-icons-config.el ends here
