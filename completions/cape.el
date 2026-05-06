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

  ;; cape-dabbrev completes words from visible buffers (e.g. the Magit diff
  ;; while editing COMMIT_EDITMSG). Min length 3 to keep typing cheap.
  (defun emacs-config-cape-visible-buffers ()
    "Return buffers currently displayed in any window on a visible frame."
    (let (bufs)
      (walk-windows (lambda (w) (push (window-buffer w) bufs)) nil 'visible)
      (delete-dups bufs)))
  (add-to-list 'completion-at-point-functions
               (cape-capf-prefix-length #'cape-dabbrev 3) t)
  (setq cape-dabbrev-buffer-function #'emacs-config-cape-visible-buffers)

  :config

;;; -- English-word CAPF for prose buffers. ------------------------------------

  ;; Reads `cape-dict-file' once, caches the word list, and filters by prefix in
  ;; elisp. Replaces cape-dict for prose, which shells out to grep on every
  ;; cache miss and uses `-F` substring matching capped at `cape-dict-limit', a
  ;; combination that hides actual prefix matches behind alphabetically-earlier
  ;; substring matches and forces orderless (always appended as a fallback by
  ;; `completion--styles') to surface them.
  (defvar emacs-config--dict-words nil
    "Cached dictionary word list for `emacs-config-cape-dict-prefix'.")

  (defun emacs-config--dict-words ()
    "Precache list of English words."
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

;;; -- Cape for prose: merged dabbrev + dict -----------------------------------

;; Used in Markdown, Org, plain text, LaTeX, …  Merges two word-bounded
;; sources into one popup via `cape-capf-super':
;;
;;   - `cape-dabbrev'                 — recent words from visible buffers.
;;   - `emacs-config-cape-dict-prefix' — English dictionary.
;;
;; Both share word bounds, so the merge is safe.  Order: dabbrev first
;; → buffer-recent words (project-specific names, jargon) rank above
;; dictionary words.
;;
;; Why merge instead of a flat chain: dict produces a non-empty result
;; for almost every 3+ char prefix (≈250k English words → there's
;; always a match), so `:exclusive 'no' fall-through never happens and
;; `cape-dabbrev' would be effectively dormant in prose. The super
;; ranks both side-by-side instead.
;;
;; `:exclusive 'no' lets the chain fall through to subsequent CAPFs
;; (cape-file inside path strings, cape-tex after `\') when neither
;; dabbrev nor dict matches.
;;
;; Snippets are intentionally *not* in this super.  Auto-popup
;; completion for snippet keys was a poor fit (3-char gate fights with
;; "I know snippets exist but forgot the key", dabbrev shadowed
;; matches when buffer text duplicated a snippet key, etc.).  Snippet
;; insertion is now bound to `C-c y' (`yas-insert-snippet') in
;; `yasnippet-config.el' — manual trigger, lists *all* snippets for
;; the active mode in one minibuffer prompt.
(with-eval-after-load 'cape
  (defalias 'emacs-config-cape-prose
    (cape-capf-properties
     (cape-capf-super
      (cape-capf-prefix-length #'cape-dabbrev 3)
      #'emacs-config-cape-dict-prefix)
     :exclusive 'no)
    "Merged dabbrev + dictionary CAPF for prose buffers."))

(provide 'completions-cape)
;;; cape.el ends here
