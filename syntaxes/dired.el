;;; syntaxes/dired.el --- Dired display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-dired t
  "Whether to enable Dired settings from syntaxes/dired.el.")

(when emacs-config-syntaxes-enable-dired
  (add-hook 'dired-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)
              ;; No wrapping of long file lines: truncate instead.
              (when (bound-and-true-p soft-wrap-mode)
                (soft-wrap-mode -1))
              (visual-line-mode -1)
              (setq-local truncate-lines t)
              (setq-local word-wrap nil)
              (setq-local truncate-partial-width-windows nil))))

(provide 'syntaxes-dired)

;;; syntaxes/dired.el ends here
