;;; syntaxes/inferior-python.el --- inferior-python-mode display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-inferior-python t
  "Whether to enable inferior-python settings from syntaxes/inferior-python.el.")

(when emacs-config-syntaxes-enable-inferior-python
  (add-hook 'inferior-python-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-inferior-python)

;;; syntaxes/inferior-python.el ends here
