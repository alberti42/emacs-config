;;; syntaxes/json.el --- JSON indentation -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-json t
  "Whether to enable JSON settings from syntaxes/json.el.")

(when emacs-config-syntaxes-enable-json
  ;; Built-in JSON mode from js.el (Emacs 29+) or json-mode package
  (dolist (hook '(js-json-mode-hook json-mode-hook))
    (add-hook hook
              (lambda ()
                (setq-local js-indent-level 2)
                (setq-local indent-tabs-mode nil))))

  ;; Tree-sitter JSON mode
  (add-hook 'json-ts-mode-hook
            (lambda ()
              (setq-local json-ts-mode-indent-offset 2)
              (setq-local indent-tabs-mode nil))))

(provide 'syntaxes-json)

;;; syntaxes/json.el ends here
