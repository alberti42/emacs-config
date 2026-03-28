;;; syntaxes/elisp.el --- Elisp settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-elisp t
  "Whether to enable Elisp settings from syntaxes/elisp.el.")

(when emacs-config-syntaxes-enable-elisp
  (add-hook 'emacs-lisp-mode-hook
            (lambda ()
              (setq-local fill-column 80))))

(provide 'syntaxes-elisp)
;;; syntaxes/elisp.el ends here
