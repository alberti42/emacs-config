;;; syntaxes/js.el --- JavaScript/TypeScript indentation -*- lexical-binding: t; -*-

(dolist (hook '(js-mode-hook
                js-ts-mode-hook
                typescript-mode-hook
                typescript-ts-mode-hook))
  (add-hook hook
            (lambda ()
              (setq js-indent-level 2)
              (setq indent-tabs-mode nil))))

(provide 'syntaxes-js)

;;; syntaxes/js.el ends here
