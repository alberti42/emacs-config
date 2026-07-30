;;; syntaxes/image.el --- image-mode display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-image t
  "Whether to enable image-mode settings from syntaxes/image.el.")

(when emacs-config-syntaxes-enable-image
  (add-hook 'image-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-image)

;;; syntaxes/image.el ends here
