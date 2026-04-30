;;; syntaxes/text.el --- Text wrapping -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-text t
  "Whether to enable text-mode settings from syntaxes/text.el.")

(when emacs-config-syntaxes-enable-text
  (add-hook 'text-mode-hook
            (lambda ()
              ;; Only act on plain `text-mode' — derived modes (markdown-ts-mode,
              ;; yaml-ts-mode, org-mode, ...) opt in from their own syntax files.
              ;; Skip Git commit buffers, which use auto-fill at 72 columns and
              ;; would conflict with visual soft-wrap.
              (when (and (eq major-mode 'text-mode)
                         (not (and (boundp 'git-commit-mode) git-commit-mode))
                         (not (and (buffer-file-name)
                                   (string-match-p "\\(COMMIT_EDITMSG\\|MERGE_MSG\\)$"
                                                   (buffer-file-name)))))

                ;; ;; English-word completion in prose buffers only. cape-dict loads a flat
                ;; ;; word file once into memory, so matching stays in-process (no aspell
                ;; ;; subprocess per keystroke).
                ;; (add-hook 'completion-at-point-functions #'cape-dict nil t)

                (setq-local fill-column 72)
                (soft-wrap-mode 1)))))

(provide 'syntaxes-text)
;;; syntaxes/text.el ends here
