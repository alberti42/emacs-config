;;; syntaxes/jupyter-repl.el --- jupyter-repl-mode display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-jupyter-repl t
  "Whether to enable jupyter-repl settings from syntaxes/jupyter-repl.el.")

(when emacs-config-syntaxes-enable-jupyter-repl
  (add-hook 'jupyter-repl-mode-hook
            (lambda ()
              (setq truncate-lines nil)
              (display-line-numbers-mode -1))))

(provide 'syntaxes-jupyter-repl)

;;; syntaxes/jupyter-repl.el ends here
