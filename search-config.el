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
  "Scroll to maintain `search-recenter-context-lines' of context when point is
within `search-recenter-edge-threshold' lines of the window edge.
For forward search (C-s) checks the bottom; for reverse (C-r) checks the top.
Scrolls the minimum amount needed rather than recentering, to avoid distraction.
Uses (sit-for 0) to flush pending display before measuring, mirroring the
pattern used by isearch-lazy-highlight-new-loop."
  (when (sit-for 0)   ; flush display; returns nil (skip) if input is pending
    (if isearch-forward
        (let ((lines-to-end (count-lines (point) (window-end nil))))
          (when (< lines-to-end search-recenter-edge-threshold)
            (scroll-up (- search-recenter-context-lines lines-to-end))))
      (let ((lines-to-top (count-lines (window-start) (point))))
        (when (< lines-to-top search-recenter-edge-threshold)
          (scroll-down (- search-recenter-context-lines lines-to-top)))))))

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
