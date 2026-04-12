;;; minibuffer-vertico.el --- Vertico minibuffer UI -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Vertico provides a modern minibuffer completion UI.
;;

;;; Code:

(use-package vertico
  :init
  (setq vertico-cycle t)
  (setq vertico-count 10)
  (setq vertico-resize 'grow-only)
  (vertico-mode 1)
  (setq vertico-multiform-commands
        '((find-file (vertico-count . 20))
          ;; Preserve recentf-list order (most-recently-opened first).
          (recentf-open (vertico-sort-function . nil))))
  (vertico-multiform-mode 1))

(provide 'completions-minibuffer-vertico)
;;; minibuffer-vertico.el ends here
