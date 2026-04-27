;;; code-cells-config.el --- Spyder-style code cells in plain source files -*- lexical-binding: t; -*-

;; `code-cells' recognizes `# %%' (and language-appropriate variants)
;; markers in plain source files and provides cell-aware navigation and
;; evaluation.  Language-agnostic — Python today, Julia/R/MATLAB later if
;; needed.  `code-cells-mode-maybe' auto-activates only in buffers that
;; actually contain cell markers, so files without `# %%' aren't affected.

(use-package code-cells
  :straight t
  :hook ((python-mode python-ts-mode) . code-cells-mode-maybe)
  :config  
  (defun my/code-cells-eval-maybe-advance (&optional advance)
    "Evaluate the current cell.
With a prefix argument ADVANCE (\\[universal-argument]), move point to
the next cell after evaluating."
    (interactive "P")
    (call-interactively #'code-cells-eval)
    (when advance
      (code-cells-forward-cell)
      (recenter-top-bottom 0)))

  ;; A set of shorter keybindings recommended by the package author
  (let ((map code-cells-mode-map))
    (keymap-set map "M-p" 'code-cells-backward-cell)
    (keymap-set map "M-n" 'code-cells-forward-cell)
    (keymap-set map "M-RET" 'jupyter-eval-line-or-region)
    (keymap-set map "C-c C-c" 'my/code-cells-eval-maybe-advance)
    ;; When emacs-jupyter is also loaded, redirect its line-region eval to
    ;; cell-aware eval.  `<remap> <COMMAND>' operates at the command-symbol
    ;; level (not the key level), so this catches *whatever* key jupyter
    ;; binds to `jupyter-eval-line-or-region' — present or future — without
    ;; us having to know the key or fight keymap-priority order.
    (with-eval-after-load 'jupyter
      (keymap-set map "<remap> <jupyter-eval-line-or-region>"
                  'code-cells-eval))))

(provide 'code-cells-config)
;;; code-cells-config.el ends here
