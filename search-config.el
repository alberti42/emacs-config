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

(defun search--recenter-if-near-edge ()
  "Scroll minimally to keep the current search match in context.
  When the match is within `search-recenter-edge-threshold' lines of the window
  edge, scroll just enough to show `search-recenter-context-lines' lines beyond
  it — checking the bottom edge for forward search (C-s), top for reverse (C-r)."
  (while-no-input
    (redisplay)
    (let ((check-bottom (if isearch-wrapped (not isearch-forward) isearch-forward)))
      (if check-bottom
          (let ((lines-to-end (count-lines (point) (window-end nil))))
            (when (< lines-to-end search-recenter-edge-threshold)
              (scroll-up (- search-recenter-context-lines lines-to-end))))
        (let ((lines-to-top (count-lines (window-start) (point))))
          (when (< lines-to-top search-recenter-edge-threshold)
            (scroll-down (- search-recenter-context-lines lines-to-top))))))))

(add-hook 'isearch-mode-end-hook #'search--recenter-if-near-edge)
(add-hook 'isearch-update-post-hook #'search--recenter-if-near-edge)

(use-package xref
  :straight nil
  :init
  ;; `project-find-regexp' uses the xref search backend.
  ;; Force ripgrep when available for dramatically better performance.
  (setq xref-search-program 'ripgrep))

(provide 'search-config)
;;; search-config.el ends here
