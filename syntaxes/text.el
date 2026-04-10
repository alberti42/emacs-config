;;; syntaxes/text.el --- Text wrapping -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-text t
  "Whether to enable text-mode settings from syntaxes/text.el.")

(when emacs-config-syntaxes-enable-text
  (add-hook 'text-mode-hook
            (lambda ()
              ;; Visual soft wrap at 72 columns.
              (setq-local fill-column 72)
              (soft-wrap-mode 1))))

(provide 'syntaxes-text)
;;; syntaxes/text.el ends here
