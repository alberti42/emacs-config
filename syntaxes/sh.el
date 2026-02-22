;;; syntaxes/sh.el --- Shell script indentation -*- lexical-binding: t; -*-

(add-hook 'sh-mode-hook
          (lambda ()
            (setq sh-basic-offset 2)
            (setq indent-tabs-mode nil)))

(provide 'syntaxes-sh)

;;; syntaxes/sh.el ends here
