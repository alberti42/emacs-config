;;; eldoc-config.el --- ElDoc display in a child frame -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; ElDoc shows information about the thing at point (lsp-mode hover,
;; Emacs Lisp signatures, Flymake diagnostics).  `eldoc-box' moves that
;; text from the echo area into a child frame next to point.
;;
;; `eldoc-box-hover-at-point-mode' is buffer-local, so it is turned on
;; from `eldoc-mode-hook', which `global-eldoc-mode' runs in every
;; buffer where ElDoc is on.  The hook also runs when ElDoc is turned
;; off; the box follows it.  `C-g' hides the child frame.

;;; Code:

(defun eldoc-config--follow-eldoc-mode ()
  "Turn `eldoc-box-hover-at-point-mode' on or off with `eldoc-mode'."
  (eldoc-box-hover-at-point-mode (if eldoc-mode 1 -1)))

(use-package eldoc-box
  :hook (eldoc-mode . eldoc-config--follow-eldoc-mode))

(provide 'eldoc-config)

;;; eldoc-config.el ends here
