;;; syntaxes/org.el --- org-mode syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-org t
  "Whether to enable org-mode settings from syntaxes/org.el.")

(when emacs-config-syntaxes-enable-org
  (dolist (hook '(org-mode-hook))
    (add-hook hook
              (lambda ()
                ;; Visual soft wrap at 100 columns.
                (setq-local fill-column 100)))))

(provide 'syntaxes-org)
;;; syntaxes/org.el ends here
