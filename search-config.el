;;; search-config.el --- Fast project search defaults -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Prefer ripgrep for project/xref search commands such as `project-find-regexp`.
;; This makes `C-x p g` behave closer to editor-native "Find in Files".
;;

;;; Code:

(defvar search-recenter-edge-threshold 5
  "Trigger scrolling when the isearch match is within this many lines of the window edge.")

(defvar search-recenter-context-lines 10
  "Number of lines to expose beyond the isearch match after scrolling.")

(defun search-recenter-isearch-match ()
  "Scroll the window so the isearch match is not jammed against an edge.
Uses `search-recenter-edge-threshold' to decide when to scroll, and
`search-recenter-context-lines' to choose how much context to expose."
  (when (and isearch-success (not (input-pending-p)))
    (let* ((window-height (window-body-height))
           (lines-from-top (count-screen-lines (window-start) (point)))
           (lines-from-bottom (- window-height lines-from-top)))
      (cond
       ((< lines-from-bottom search-recenter-edge-threshold)
        (recenter (- search-recenter-context-lines)))
       ((< lines-from-top search-recenter-edge-threshold)
        (recenter search-recenter-context-lines))))))

(add-hook 'isearch-update-post-hook #'search-recenter-isearch-match)

;; DEL deletes one character from the search string instead of undoing the
;; last input action (which would remove an entire yank in one keystroke).
(define-key isearch-mode-map [remap isearch-delete-char] #'isearch-del-char)

(defun consult-fd-here ()
  "Like `consult-fd' but rooted at `default-directory' instead of the project root."
  (interactive)
  (consult-fd default-directory))

(defun consult-ripgrep-here ()
  "Like `consult-ripgrep' but rooted at `default-directory' instead of the project root."
  (interactive)
  (consult-ripgrep default-directory))

(use-package xref
  :straight nil
  :init
  ;; `project-find-regexp' uses the xref search backend.
  ;; Force ripgrep when available for dramatically better performance.
  (setq xref-search-program 'ripgrep))

(provide 'search-config)
;;; search-config.el ends here
