;;; apheleia-config.el --- Formatter configuration via Apheleia -*- lexical-binding: t; -*-

;;; Code:

(use-package apheleia
  :straight t
  :config
  ;; Run ruff lint-fix first (import sorting + auto-fixable violations),
  ;; then ruff format (style/whitespace). Both are built into apheleia-formatters.
  (setf (alist-get 'python-mode apheleia-mode-alist)
        '(ruff-isort ruff))
  (setf (alist-get 'python-ts-mode apheleia-mode-alist)
        '(ruff-isort ruff))
  (apheleia-global-mode +1))

(provide 'apheleia-config)
;;; apheleia-config.el ends here
