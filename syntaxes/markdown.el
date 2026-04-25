;;; syntaxes/markdown.el --- Markdown syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-markdown t
  "Whether to enable Markdown settings from syntaxes/markdown.el.")

(when emacs-config-syntaxes-enable-markdown
  (add-hook 'markdown-ts-mode-hook
            (lambda ()
              (setq-local fill-column 100)
              (soft-wrap-mode 1))))

(provide 'syntaxes-markdown)
;;; syntaxes/markdown.el ends here
