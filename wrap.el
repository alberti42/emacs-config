;;; wrap.el --- Soft and hard wrap helpers -*- lexical-binding: t; -*-

;; Packages
;; Use a patched fork of visual-fill-column to fix a conflict with git-gutter
;; in TTY frames.
;;
;; visual-fill-column constrains text to a column width by adding fake margins
;; to the window (e.g. left margin = 20 cols to center 80 cols in a 120-col
;; window).  It recomputes these margins on every redisplay.
;;
;; git-gutter (TTY mode) displays +/-/~ indicators by reserving a left-margin
;; column.  Both packages therefore write to the same window left-margin slot.
;;
;; The upstream bug: visual-fill-column resets the left margin to 0 before
;; writing its own value.  That zero-reset wiped git-gutter's reservation on
;; every redisplay, making the gutter disappear.
;;
;; The fork fixes this by reading the current left margin first and adding to
;; it, so both packages can coexist.  See Emacs bug #70941.
(use-package visual-fill-column
    :straight (visual-fill-column
               :type git
               :host codeberg
               :repo "alberti42/fork-visual-fill-column")
    :defer t)

(use-package adaptive-wrap
  :defer t)

(defun emacs-config-soft-wrap-enable (&optional width)
  "Enable visual soft wrapping in the current buffer.

WIDTH, when non-nil, is the target wrap column (defaults to `fill-column').
Disables hard wrapping (`auto-fill-mode') if it is active."
  (interactive "P")
  (auto-fill-mode -1)
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

;;; Hard wrap (auto-fill-mode) — uses fill-column as the wrap column.

(defun emacs-config-hard-wrap-enable ()
  "Enable hard wrapping (auto-fill-mode) in the current buffer.

Disables soft wrapping if it is active.  The wrap column is `fill-column'."
  (interactive)
  (emacs-config-soft-wrap-disable)
  (auto-fill-mode 1))

(defun emacs-config-hard-wrap-disable ()
  "Disable hard wrapping (auto-fill-mode) in the current buffer."
  (interactive)
  (auto-fill-mode -1))

(defun emacs-config-hard-wrap-toggle ()
  "Toggle hard wrapping (auto-fill-mode) in the current buffer."
  (interactive)
  (if auto-fill-function
      (emacs-config-hard-wrap-disable)
    (emacs-config-hard-wrap-enable)))

(provide 'wrap)
;;; wrap.el ends here
