;;; syntaxes/help.el --- Help display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-help t
  "Whether to enable Help settings from syntaxes/help.el.")

(when emacs-config-syntaxes-enable-help
  (add-hook 'help-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-help)

;;; syntaxes/help.el ends here
