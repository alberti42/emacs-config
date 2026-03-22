;;; wrap.el --- Soft and hard wrap helpers -*- lexical-binding: t; -*-

;; Code

;;; Packages:
;;
;; There are two mutually exclusive approaches to the same goal of managing long lines:
;;
;; - auto-fill-mode — hard wrap: inserts actual newlines as you type past fill-column. The line break becomes part of the file content.
;; - visual-line-mode — built-in mode for soft/visual wrap: no newlines inserted, text just appears wrapped on screen.
;;   The file content is unchanged. The built-in mode wraps lines at the window edge.
;; - visual-fill-column-mode — adds margins to the window so that visual-line-mode wraps at a specific column rather than the window edge

;;; Commentary on patched visual-fill-column
;;
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
;; it, so both packages can coexist.

;;; Code

(defvar-local wrap--saved-auto-fill nil
  "Value of `auto-fill-function' before soft wrap was enabled.
Used by `soft-wrap-disable' to restore hard-wrap state.")

(use-package visual-fill-column
    :straight (visual-fill-column
               :type git
               :host codeberg
               :repo "alberti42/fork-visual-fill-column")
    :defer t)

(use-package adaptive-wrap
  :defer t)

(defun soft-wrap-enable (&optional width)
  "Enable visual soft wrapping in the current buffer.

WIDTH, when non-nil, is the target wrap column (defaults to `fill-column').
Disables hard wrapping (`auto-fill-mode') if it is active."
  (interactive "P")
  ;; Save hard-wrap state so soft-wrap-disable can restore it
  (setq-local wrap--saved-auto-fill auto-fill-function)
  ;; Disable complementary mode auto-fill-mode by providing a negative argument
  (auto-fill-mode -1)
  (require 'visual-fill-column)
  (let ((width (if width
                   (prefix-numeric-value width) ; convert width to a number if not nil
                 fill-column                    ; choose fill-column if width is nil
                 )))
    (visual-line-mode 1) ; enable built-in visual-line-mode required by visual-fill-column-mode
    (setq-local word-wrap t) ; makes visual line breaks happen only at word boundaries (spaces, hyphens) rather than mid-word
    (setq-local truncate-lines nil) ; must be set to nil when visual-line-mode is enabled (per doc)
    (setq-local visual-fill-column-width width)
    (visual-fill-column-mode 1)))

(defun soft-wrap-disable ()
  "Disable visual soft wrapping in the current buffer."
  (interactive)
  ;; Check that the mode visual-fill-column is available
  (when (fboundp 'visual-fill-column-mode)
    ;; Disable complementary mode auto-fill-mode by providing a negative argument
    (visual-fill-column-mode -1))
  ;; Disable the built-in visual-line-mode
  (visual-line-mode -1)
  ;; Remove local variables
  (dolist (var '(word-wrap truncate-lines visual-fill-column-width))
    (when (local-variable-p var)
      (kill-local-variable var)))
  ;; Restore hard-wrap state if it was active before soft wrap was enabled
  (when wrap--saved-auto-fill
    (auto-fill-mode 1))
  (kill-local-variable 'wrap--saved-auto-fill))

(defun soft-wrap-toggle (&optional width)
  "Toggle visual soft wrapping in the current buffer.

If enabling, WIDTH is passed to `soft-wrap-enable'."
  (interactive "P")
  ;; Check that the mode visual-fill-column exists and is active
  (if (bound-and-true-p visual-fill-column-mode)
      (soft-wrap-disable)
    (soft-wrap-enable width)))

;;; Hard wrap (auto-fill-mode) — uses fill-column as the wrap column.

(defun hard-wrap-enable ()
  "Enable hard wrapping (auto-fill-mode) in the current buffer.

Disables soft wrapping if it is active.  The wrap column is `fill-column'."
  (interactive)
  ;; Disables the complementary visual-fill-column-mode
  (soft-wrap-disable)
  ;; Enable hard wrap mode
  (auto-fill-mode 1))

(defun hard-wrap-disable ()
  "Disable hard wrapping (auto-fill-mode) in the current buffer."
  (interactive)
  ;; Disable hard wrapping
  (auto-fill-mode -1))

(defun hard-wrap-toggle ()
  "Toggle hard wrapping (auto-fill-mode) in the current buffer."
  (interactive)
  ;; Check if hard wrapping is enabled 
  (if auto-fill-function
      (hard-wrap-disable)
    (hard-wrap-enable)))

(provide 'wrap)
;;; wrap.el ends here
