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
   '((file (styles basic partial-completion)) ; forcing cape-dict to basic
                                        ; (orderless on large dictionary
                                        ; CAPFs would rank oddly and can
                                        ; be slow)
     (cape-dict (styles basic))         ; forcing cape-dict to basic (orderless
                                        ; on large dictionary CAPFs ranks oddly
                                        ; and can be slow)
     )))

(provide 'completions-orderless)
;;; orderless.el ends here
