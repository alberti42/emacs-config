;;; code-cells-config.el --- Spyder-style code cells in plain source files -*- lexical-binding: t; -*-

;; `code-cells' recognizes `# %%' (and language-appropriate variants)
;; markers in plain source files and provides cell-aware navigation and
;; evaluation.  Language-agnostic — Python today, Julia/R/MATLAB later if
;; needed.  `code-cells-mode-maybe' auto-activates only in buffers that
;; actually contain cell markers, so files without `# %%' aren't affected.

;; Hoisted helpers — top-level so byte-compile and reload behave cleanly.

(defun my/code-cells-eval-and-insert ()
  "Evaluate the current cell, advance to the next, and insert a new
  empty cell after it (mirrors Jupyter's Alt-Enter)."
  (interactive)
  (call-interactively #'code-cells-eval-and-step)
  ;; If we landed on an existing cell, insert a new one *before* it.
  ;; If we ran the last cell, point is at end-of-buffer; insert there.
  (save-excursion
    (insert "\n# %%\n\n"))
  ;; Move into the body of the freshly-created cell.
  (forward-line 2))

(defun my/code-cells-recenter-after (&rest _)
  "Place the cell's first line near the top of the window after stepping."
  (recenter-top-bottom 0))

(use-package code-cells
  :straight t
  :hook ((python-mode python-ts-mode) . code-cells-mode-maybe)
  :config
  (advice-add 'code-cells-eval-and-step :after #'my/code-cells-recenter-after)
  (let ((map code-cells-mode-map))
    (keymap-set map "M-p"       #'code-cells-backward-cell)
    (keymap-set map "M-n"       #'code-cells-forward-cell)
    ;; Jupyter triad — execution keys
    (keymap-set map "C-<return>" #'code-cells-eval)              ; stay
    (keymap-set map "S-<return>" #'code-cells-eval-and-step)     ; advance
    (keymap-set map "M-<return>" #'my/code-cells-eval-and-insert) ; advance + new cell
    ;; Keep a non-modifier fallback for TTYs that can't distinguish C/S/M-RET
    (keymap-set map "C-c C-c"   #'code-cells-eval)
    ;; Jupyter remap stays useful for keys jupyter binds elsewhere
    (with-eval-after-load 'jupyter
      (keymap-set map "<remap> <jupyter-eval-line-or-region>"
                  #'code-cells-eval))))

(provide 'code-cells-config)
;;; code-cells-config.el ends here
