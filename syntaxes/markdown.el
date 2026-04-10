;;; syntaxes/markdown.el --- Markdown syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-markdown t
  "Whether to enable Markdown settings from syntaxes/markdown.el.")

(when emacs-config-syntaxes-enable-markdown
  (dolist (hook '(markdown-mode-hook gfm-mode-hook))
    (add-hook hook
              (lambda ()
                ;; Visual soft wrap at 72 columns.
                (setq-local fill-column 72)
                (soft-wrap-mode 1)))))

(provide 'syntaxes-markdown)
;;; syntaxes/markdown.el ends here
