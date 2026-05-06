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

;;; -- yasnippet-capf proposing yasnippet keys for completion ------------------

  ;; It matches the active major mode and any `yas-activate-extra-mode' bridges
  ;; for the completion candidates
  ;;
  ;; Two adjustments on top of bare `yasnippet-capf':
  ;;
  ;; 1. Literal-prefix candidate filter via `:predicate'. The bare CAPF
  ;;    returns *every* snippet for the active mode and lets completion
  ;;    styles do the filtering. Combined with orderless's substring
  ;;    semantics, that surfaces every snippet whose key contains the
  ;;    typed character anywhere — distracting even after one keystroke.
  ;;    The predicate restricts the candidate set to snippets whose key
  ;;    *starts with* the typed prefix, regardless of the completion
  ;;    style in effect (so the behaviour stays prefix-only even inside
  ;;    `cape-capf-super', whose merged `:category cape-super' would
  ;;    otherwise mask any per-category style override).
  ;;
  ;; 2. ≥3 char gate via `cape-capf-prefix-length'. Snippet keys are
  ;;    practically always 3+ chars; gating saves the popup from
  ;;    snippet-key noise on 1–2 char input where the much larger LSP
  ;;    candidate list dominates anyway.
  ;;
  ;; The wrapped function `emacs-config-yasnippet-capf' is the form used
  ;; both for the global registration here and inside the LSP super-CAPF
  ;; in `lsp-core.el', so the prefix-only / 3-char rules apply uniformly.
  (use-package yasnippet-capf
    :after yasnippet
    :init
    (defun emacs-config--yasnippet-capf-strict ()
      "Like `yasnippet-capf', but
1. widen bounds detection to include `-' (yasnippet-capf's regex
   `\\sw\\|\\s_' misses `-' in modes like python-ts-mode where it has
   punctuation syntax, so typing `mpl-' matches only `mpl' and the
   `point in or just after match' check in `thing-at-point-looking-at'
   fails — yasnippet-capf returns nil and snippet candidates never
   surface).  Shadowed only around `yasnippet-capf'; expansion runs
   in the original syntax table, untouched.
2. restrict candidates to literal-prefix matches."
      (let* ((tbl (let ((s (copy-syntax-table (syntax-table))))
                    (modify-syntax-entry ?- "_" s)
                    s))
             (orig (with-syntax-table tbl (yasnippet-capf))))
        (pcase orig
          (`(,beg ,end ,table . ,plist)
           (let* ((prefix (buffer-substring-no-properties beg end))
                  (existing-pred (plist-get plist :predicate))
                  (prefix-pred
                   (lambda (key &optional val)
                     (let ((s (cond
                               ((symbolp key) (symbol-name key))
                               ((consp key)
                                (let ((k (car key)))
                                  (if (symbolp k) (symbol-name k) k)))
                               (t key))))
                       (and (string-prefix-p prefix s t)
                            (or (null existing-pred)
                                (funcall existing-pred key val)))))))
             `(,beg ,end ,table
                    :predicate ,prefix-pred
                    :category yasnippet
                    ,@plist))))))

    (defalias 'emacs-config-yasnippet-capf
      (cape-capf-prefix-length #'emacs-config--yasnippet-capf-strict 3)
      "yasnippet-capf gated to ≥3 chars and filtered to literal-prefix matches.")

    (add-to-list 'completion-at-point-functions #'emacs-config-yasnippet-capf))

;;; -- English-word CAPF for prose buffers. -----------------------------------

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

;;; -- Cape for prose combining cape-dabbrev and cape --------------------------

;; This cape is used in Markdown, Org, plain text, LaTeX, ...
;;
;; It combines `cape-dabbrev' (recent words from visible buffers) with
;; `emacs-config-cape-dict-prefix' (English dictionary), both gated to ≥3 chars.
;; Both inner CAPFs share word bounds, so `cape-capf-super' merges their
;; candidate sets cleanly.
;;
;; Order matters: dabbrev first → buffer-recent words (project-specific
;; names, jargon) rank above dictionary words.  Without the super, dict
;; produces a non-empty result for almost every 3+ char prefix and the
;; chain never falls through to dabbrev.
;;
;; `:exclusive 'no' lets the chain fall through to subsequent CAPFs
;; (cape-file inside path strings, cape-tex after \) when neither
;; dabbrev nor dict matches.
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
