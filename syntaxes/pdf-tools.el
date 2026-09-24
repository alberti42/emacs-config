;;; syntaxes/pdf-tools.el --- pdf-tools display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-pdf-tools t
  "Whether to enable pdf-tools settings from syntaxes/pdf-tools.el.")

(when emacs-config-syntaxes-enable-pdf-tools
  ;; The annotation edit buffer runs plain `org-mode' or `latex-mode';
  ;; this minor mode is what marks it, and its hook runs after theirs.
  (add-hook 'pdf-annot-edit-contents-minor-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-pdf-tools)

;;; syntaxes/pdf-tools.el ends here
