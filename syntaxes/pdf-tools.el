;;; syntaxes/pdf-tools.el --- pdf-tools display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-pdf-tools t
  "Whether to enable pdf-tools settings from syntaxes/pdf-tools.el.")

(when emacs-config-syntaxes-enable-pdf-tools
  ;; Disable the line numbers that `global-display-line-numbers-mode'
  ;; turns on in every buffer.  `pdf-view-mode-hook' also runs in
  ;; `pdf-virtual-view-mode', which derives from `pdf-view-mode'.  The
  ;; annotation edit buffer runs plain `org-mode' or `latex-mode'; the
  ;; minor mode is what marks it, and its hook runs after theirs.
  (dolist (hook '(pdf-view-mode-hook
                  pdf-annot-edit-contents-minor-mode-hook
                  pdf-annot-list-mode-hook
                  pdf-outline-buffer-mode-hook
                  pdf-occur-buffer-mode-hook
                  pdf-metadata-buffer-mode-hook))
    (add-hook hook (lambda ()
                     (display-line-numbers-mode -1)))))

(provide 'syntaxes-pdf-tools)

;;; syntaxes/pdf-tools.el ends here
