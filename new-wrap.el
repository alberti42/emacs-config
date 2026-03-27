;;; new-wrap.el --- Local wrapper for soft-wrap -*- lexical-binding: t; -*-

;; Code

;; This module is user-specific glue.  The soft-wrap implementation lives in
;; soft-wrap.el.

(use-package soft-wrap
  :straight nil
  :load-path emacs-config-dir
  :commands (soft-wrap-enable soft-wrap-disable soft-wrap-debug-dump))

(provide 'new-wrap)
;;; new-wrap.el ends here
