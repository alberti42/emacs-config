;;; syntaxes/latex.el --- LaTeX syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-latex t
  "Whether to enable LaTeX settings from syntaxes/latex.el.")

(when emacs-config-syntaxes-enable-latex
  (add-hook 'LaTeX-mode-hook
            (lambda ()
              (setq-local fill-column 100))))

(provide 'syntaxes-latex)
;;; syntaxes/latex.el ends here
