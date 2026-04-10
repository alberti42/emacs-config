;;; syntaxes/text.el --- Text wrapping -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-text t
  "Whether to enable text-mode settings from syntaxes/text.el.")

(when emacs-config-syntaxes-enable-text
  (add-hook 'text-mode-hook
            (lambda ()
              ;; Skip soft-wrap for Git commit buffers. These use auto-fill-mode
              ;; for hard-wrapping at 72 columns and visual soft-wrap would
              ;; interfere with the intended commit message structure.
              (unless (or (and (boundp 'git-commit-mode) git-commit-mode)
                          (and (buffer-file-name)
                               (string-match-p "\\(COMMIT_EDITMSG\\|MERGE_MSG\\)$"
                                               (buffer-file-name))))
                ;; Visual soft wrap at 72 columns.
                (setq-local fill-column 72)
                (soft-wrap-mode 1)))))

(provide 'syntaxes-text)
;;; syntaxes/text.el ends here
