;;; syntaxes/markdown.el --- Markdown syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-markdown t
  "Whether to enable Markdown settings from syntaxes/markdown.el.")

(when emacs-config-syntaxes-enable-markdown
  (add-hook 'markdown-ts-mode-hook
            (lambda ()
              (setq-local fill-column 100)
              (setq-local soft-wrap-default-centered t)
              ;; Drop `#' from the default `adaptive-fill-regexp' for
              ;; markdown-ts-mode.  ATX headings are one-shot opening markers,
              ;; not paragraph continuation prefixes; they should not be
              ;; repeated on continuation lines or reserve column space.  This
              ;; also sidesteps a visual-wrap.el bug where invisible prefix
              ;; characters still reserve column space, but the override is
              ;; useful on its own merits.
              (setq-local adaptive-fill-regexp
                          "[-–!|%;>*·•‣⁃◦ \t]*")
              (soft-wrap-mode 1)
              ;; (olivetti-mode 1)

              ;; Prose word-completion: merged dabbrev + in-memory
              ;; dictionary super-CAPF (defined in completions/cape.el).
              ;; Surfaces buffer-recent words alongside dictionary words
              ;; in one popup, both gated to ≥3 chars.
              (add-hook 'completion-at-point-functions
                        #'emacs-config-cape-prose nil t))))

(provide 'syntaxes-markdown)
;;; syntaxes/markdown.el ends here
