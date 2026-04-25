;;; syntaxes/org.el --- org-mode syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-org t
  "Whether to enable org-mode settings from syntaxes/org.el.")

(when emacs-config-syntaxes-enable-org
  (add-hook 'org-mode-hook
            (lambda ()
              (setq-local fill-column 100)
              (soft-wrap-mode 1))))

(provide 'syntaxes-org)
;;; syntaxes/org.el ends here
