;;; syntaxes/python.el --- Python indentation -*- lexical-binding: t; -*-

(add-hook 'python-mode-hook
          (lambda ()
            (setq python-indent-offset 4)
            (setq indent-tabs-mode nil)))

(provide 'syntaxes-python)

;;; syntaxes/python.el ends here
