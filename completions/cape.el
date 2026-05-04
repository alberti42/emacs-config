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

  ;; In-memory English-word CAPF for prose buffers.
  ;;
  ;; Reads `cape-dict-file' once, caches the word list, and filters by prefix in
  ;; elisp. Replaces cape-dict for prose, which shells out to grep on every
  ;; cache miss and uses `-F` substring matching capped at `cape-dict-limit', a
  ;; combination that hides actual prefix matches behind alphabetically-earlier
  ;; substring matches and forces orderless (always appended as a fallback by
  ;; `completion--styles') to surface them.
  (defvar emacs-config--dict-words nil
    "Cached dictionary word list for `emacs-config-cape-dict-prefix'.")

  (defun emacs-config--dict-words ()
    (or emacs-config--dict-words
        (setq emacs-config--dict-words
              (with-temp-buffer
                (insert-file-contents cape-dict-file)
                (split-string (buffer-string) "\n" t)))))

  (defun emacs-config-cape-dict-prefix ()
    "Prefix-only English-word CAPF; fires after 3 typed characters."
    (when-let* ((bounds (bounds-of-thing-at-point 'word))
                (beg (car bounds))
                (end (cdr bounds))
                ((>= (- end beg) 3)))
      (list beg end
            (completion-table-with-cache
             (lambda (prefix)
               (seq-filter (lambda (w) (string-prefix-p prefix w t))
                           (emacs-config--dict-words))))
            :annotation-function (lambda (_) " Dict")
            :company-kind (lambda (_) 'text)
            :category 'emacs-config-dict
            :exclusive 'no))))

(provide 'completions-cape)
;;; cape.el ends here
