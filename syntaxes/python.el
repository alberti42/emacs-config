;;; syntaxes/python.el --- Python indentation -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-python t
  "Whether to enable Python settings from syntaxes/python.el.")

(when emacs-config-syntaxes-enable-python
  (dolist (hook '(python-mode-hook python-ts-mode-hook))
    (add-hook hook
              (lambda ()
                (setq python-indent-offset 4)
                (setq indent-tabs-mode nil)))))

(provide 'syntaxes-python)

;;; syntaxes/python.el ends here
