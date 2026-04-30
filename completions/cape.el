;;; cape.el --- Extra CAPF sources (Cape) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Cape extends Emacs' completion-at-point (CAPF) with extra sources.
;;

;;; Code:

(use-package cape
  :init
  ;; Keep these as fallbacks by appending them.
  (add-to-list 'completion-at-point-functions #'cape-file t)

  ;; cape-tex completes \-prefixed commands to their Unicode equivalents;
  ;; enabled globally, but removed in tex-mode where \commands must stay as-is.
  (add-to-list 'completion-at-point-functions #'cape-tex t)

  ;; cape-dabbrev completes word from current buffers
  (add-to-list 'completion-at-point-functions #'cape-dabbrev t)

  :config
  ;; lsp-completion-at-point is exclusive by default: when it returns a
  ;; non-nil result Emacs stops trying further CAPFs, so cape-file never
  ;; runs for file paths (e.g. ~/Documents/). Inject :exclusive 'no into
  ;; its return value so Emacs falls through to subsequent CAPFs when LSP
  ;; has no candidates.
  (with-eval-after-load 'lsp-completion
    (define-advice lsp-completion-at-point
        (:filter-return (result) cape-nonexclusive)
      (if (consp result)
          (let ((head (seq-take result 3))
                (props (nthcdr 3 result)))
            (append head (plist-put (copy-sequence props) :exclusive 'no)))
        result)))

  ;; Defines an alias to set up cape-dict triggered by 3-character prefix
  (defalias 'cape-dict-3 (cape-capf-prefix-length #'cape-dict 3)
    "cape-dict that only fires after 3 typed characters.")

  )

(provide 'completions-cape)
;;; cape.el ends here
