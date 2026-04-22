;;; syntaxes/python.el --- Python indentation -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-python t
  "Whether to enable Python settings from syntaxes/python.el.")

(when emacs-config-syntaxes-enable-python
  ;; Use `--simple-prompt' to prevent the fancy IPython prompt from choking the
  ;; command interpreter `comint'
  (setq python-shell-interpreter "ipython"
        python-shell-interpreter-args "-i --simple-prompt")
  (dolist (hook '(python-mode-hook python-ts-mode-hook))
    (add-hook hook
              (lambda ()
                (setq python-indent-offset 4)
                (setq indent-tabs-mode nil)))))

(provide 'syntaxes-python)

;;; syntaxes/python.el ends here
