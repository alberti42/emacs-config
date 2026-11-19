;;; syntaxes/image.el --- image-mode display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-image t
  "Whether to enable image-mode settings from syntaxes/image.el.")

(when emacs-config-syntaxes-enable-image
  (add-hook 'image-mode-hook
            (lambda ()
              (display-line-numbers-mode -1)
              ;; Disable `git-gutter-mode', which `global-git-gutter-mode'
              ;; turns on in every buffer visiting a file.  Calling it
              ;; from the major-mode hook marks it as set explicitly, so
              ;; the global mode leaves it off.
              (when (fboundp 'git-gutter-mode)
                (git-gutter-mode -1)))))

(provide 'syntaxes-image)

;;; syntaxes/image.el ends here
