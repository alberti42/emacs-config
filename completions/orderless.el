;;; orderless.el --- Orderless completion style -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Orderless allows space-separated patterns to match candidates in any order.
;; Great for "command palette" style completion.
;;

;;; Code:

(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides
   '((file (styles orderless basic))
     (emacs-config-dict (styles basic)))))

(provide 'completions-orderless)
;;; orderless.el ends here
