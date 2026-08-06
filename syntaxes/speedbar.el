;;; syntaxes/speedbar.el --- Speedbar display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-speedbar t
  "Whether to enable Speedbar settings from syntaxes/speedbar.el.")

(when emacs-config-syntaxes-enable-speedbar
  (add-hook 'speedbar-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-speedbar)

;;; syntaxes/speedbar.el ends here
