;;; apheleia-config.el --- Formatter configuration via Apheleia -*- lexical-binding: t; -*-

;;; Code:

(use-package apheleia
  :straight t
  :config
  ;; Define ktlint as a formatter.
  ;; --log-level none is required to keep stdout clean of INFO logs.
  ;; --stdin-path ensures rule evaluation that depends on filename/extension works.
  (setf (alist-get 'ktlint apheleia-formatters)
        '("ktlint" "--format" "--stdin" "--stdin-path" filepath "--log-level" "none"))

  ;; Run ruff lint-fix first (import sorting + auto-fixable violations),
  ;; then ruff format (style/whitespace). Both are built into apheleia-formatters.
  (setf (alist-get 'python-mode apheleia-mode-alist)
        '(ruff-isort ruff))
  (setf (alist-get 'python-ts-mode apheleia-mode-alist)
        '(ruff-isort ruff))

  ;; Kotlin formatting
  (setf (alist-get 'kotlin-mode apheleia-mode-alist) 'ktlint)
  (setf (alist-get 'kotlin-ts-mode apheleia-mode-alist) 'ktlint)

  (apheleia-global-mode +1))

(provide 'apheleia-config)
;;; apheleia-config.el ends here
