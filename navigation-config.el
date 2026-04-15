;;; navigation-config.el --- Cursor navigation behaviour -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Smart Home/End keys: first press jumps to beginning/end of line,
;; repeated press toggles to the first non-whitespace character or
;; last non-whitespace character respectively.
;;
;; Source: https://stackoverflow.com/a/35394552 (gavenkoa, CC BY-SA 3.0)
;;

;;; Code:

(defun emacs-config--smart-beginning-of-line ()
  "Move point to `beginning-of-line'.
If repeated, cycle to `back-to-indentation' instead."
  (interactive "^")
  (if (and (eq last-command 'emacs-config--smart-beginning-of-line)
           (= (line-beginning-position) (point)))
      (back-to-indentation)
    (beginning-of-line)))

(defun emacs-config--smart-end-of-line ()
  "Move point to `end-of-line'.
If repeated, cycle to the last non-whitespace character instead."
  (interactive "^")
  (if (and (eq last-command 'emacs-config--smart-end-of-line)
           (= (line-end-position) (point)))
      (skip-syntax-backward " " (line-beginning-position))
    (end-of-line)))

(global-set-key [home] #'emacs-config--smart-beginning-of-line)
(global-set-key [end]  #'emacs-config--smart-end-of-line)

;; `visual-line-mode' remaps C-a/C-e to visual-line boundaries, which are
;; determined by screen width rather than buffer content.  Clear the remaps
;; so logical-line movement remains in effect regardless of wrap mode.
(define-key visual-line-mode-map [remap move-beginning-of-line] nil)
(define-key visual-line-mode-map [remap move-end-of-line] nil)
(define-key visual-line-mode-map [remap kill-line] nil)

(provide 'navigation-config)

;;; navigation-config.el ends here
