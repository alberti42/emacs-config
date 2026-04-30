;;; syntaxes/markdown.el --- Markdown syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-markdown t
  "Whether to enable Markdown settings from syntaxes/markdown.el.")

(when emacs-config-syntaxes-enable-markdown
  (add-hook 'markdown-ts-mode-hook
            (lambda ()
              (setq-local fill-column 100)
              (soft-wrap-mode 1)

              ;; English-word completion in prose buffers only. cape-dict loads a flat
              ;; word file once into memory, so matching stays in-process (no aspell
              ;; subprocess per keystroke).
              (add-hook 'completion-at-point-functions #'cape-dict-3 nil t))))

(provide 'syntaxes-markdown)
;;; syntaxes/markdown.el ends here
