;;; wrap.el --- Soft wrap helpers -*- lexical-binding: t; -*-

;; Packages
(use-package visual-fill-column
  :defer t)

(use-package adaptive-wrap
  :defer t)

(defun emacs-config-soft-wrap-enable (&optional width)
  "Enable visual soft wrapping in the current buffer.

WIDTH, when non-nil, is the target wrap column (defaults to `fill-column')."
  (interactive "P")
  (require 'visual-fill-column)
  (let ((width (if width (prefix-numeric-value width) fill-column)))
    (visual-line-mode 1)
    (setq-local word-wrap t)
    (setq-local truncate-lines nil)
    (setq-local visual-fill-column-width width)
    (visual-fill-column-mode 1)))

(defun emacs-config-soft-wrap-disable ()
  "Disable visual soft wrapping in the current buffer."
  (interactive)
  (when (fboundp 'visual-fill-column-mode)
    (visual-fill-column-mode -1))
  (visual-line-mode -1)
  (dolist (var '(word-wrap truncate-lines visual-fill-column-width))
    (when (local-variable-p var)
      (kill-local-variable var))))

(defun emacs-config-soft-wrap-toggle (&optional width)
  "Toggle visual soft wrapping in the current buffer.

If enabling, WIDTH is passed to `emacs-config-soft-wrap-enable'."
  (interactive "P")
  (if (bound-and-true-p visual-fill-column-mode)
      (emacs-config-soft-wrap-disable)
    (emacs-config-soft-wrap-enable width)))

(provide 'wrap)
;;; wrap.el ends here
