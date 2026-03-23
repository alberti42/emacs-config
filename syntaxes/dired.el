;;; syntaxes/dired.el --- Dired display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-dired t
  "Whether to enable Dired settings from syntaxes/dired.el.")

(when emacs-config-syntaxes-enable-dired
  (add-hook 'dired-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-dired)

;;; syntaxes/dired.el ends here
