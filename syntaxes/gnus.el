;;; syntaxes/gnus.el --- Gnus display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-gnus t
  "Whether to enable Gnus settings from syntaxes/gnus.el.")

(when emacs-config-syntaxes-enable-gnus
  ;; One hook covers every Gnus display buffer.  `gnus-group-mode',
  ;; `gnus-summary-mode', `gnus-article-mode', `gnus-server-mode',
  ;; `gnus-browse-mode', `gnus-category-mode' and `gnus-tree-mode' are all
  ;; derived from `gnus-mode', and a derived mode runs its parent's hook.
  (add-hook 'gnus-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)))

  ;; Writing a message is a `message-mode' buffer, which derives from
  ;; `text-mode' instead; so is `gnus-article-edit-mode'.
  (add-hook 'message-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-gnus)

;;; syntaxes/gnus.el ends here
