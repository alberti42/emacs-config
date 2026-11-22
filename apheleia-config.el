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

  (add-hook 'apheleia-formatter-exited-hook #'apheleia-config--show-error)

  (apheleia-global-mode +1))

(defun apheleia-config--show-error (&rest args)
  "Show the first stderr line of a failed formatter in the echo area.
ARGS are the keyword arguments of `apheleia-formatter-exited-hook'.
Apheleia's own message gives only the exit status and names the first
word of the command. The hook runs before that message is printed, so
this message is shown from a timer to replace it."
  (let ((formatter (plist-get args :formatter))
        (log (plist-get args :log)))
    (when (and (plist-get args :error) (buffer-live-p log))
      (let ((line
             (with-current-buffer log
               (save-excursion
                 (save-restriction
                   (widen)
                   ;; Log entries are separated by a form feed; each
                   ;; is a header line, "$ COMMAND", a blank line,
                   ;; then the formatter's stderr.
                   (goto-char (point-max))
                   (unless (search-backward "\f" nil t)
                     (goto-char (point-min)))
                   (when (re-search-forward "^\\$ .*\n\n" nil t)
                     (skip-chars-forward " \t\n")
                     (buffer-substring-no-properties
                      (point) (line-end-position))))))))
        (when (and line (not (string-empty-p line)))
          (run-at-time 0 nil #'message "%s: %s" formatter line))))))

(provide 'apheleia-config)
;;; apheleia-config.el ends here
