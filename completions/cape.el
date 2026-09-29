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

;;; -- Word-list CAPF for prose buffers. ---------------------------------------

  ;; Reads a language's word list once, caches it, and filters by prefix in
  ;; elisp. Replaces cape-dict for prose, which shells out to grep on every
  ;; cache miss and uses `-F` substring matching capped at `cape-dict-limit', a
  ;; combination that hides actual prefix matches behind alphabetically-earlier
  ;; substring matches and forces orderless (always appended as a fallback by
  ;; `completion--styles') to surface them.
  ;;
  ;; The language is the buffer's `lsp-ltex-plus-language', read at every
  ;; call, so a value set by `lsp-ltex-plus-change-language', `setq' or
  ;; `.dir-locals.el' applies without a hook.
  (defvar emacs-config-dict-sources
    '(("en-US" . "cat /usr/share/dict/words")
      ("de-DE" . "aspell -d de_DE dump master | aspell -l de expand | tr ' ' '\\n'")
      ;; aspell's Italian dictionary expands to 22 million forms (every verb
      ;; form with every clitic pronoun), so Italian uses the 50k most
      ;; frequent words of the OpenSubtitles corpus instead.
      ("it-IT" . "curl -fsSL https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/it/it_50k.txt | cut -d' ' -f1"))
    "Shell commands that print a language's word list, one word per line.
Keys are codes as in `lsp-ltex-plus-language', matched with case
ignored.  The output is kept in `emacs-config-cache-dir' as
dict-CODE.txt, so a command runs only while that file is missing.")

  (defvar emacs-config--dict-words nil
    "Alist of language code to cached word list.
A code whose list could not be built maps to nil, so its command is
not run again on every keystroke.")

  (defun emacs-config--dict-words (language)
    "Return the word list of LANGUAGE, building it on first use.
Nil when `emacs-config-dict-sources' has no entry for LANGUAGE or its
command printed nothing."
    (when-let* ((source (assoc-string language emacs-config-dict-sources t)))
      (let ((code (car source)))
        (if-let* ((cached (assoc code emacs-config--dict-words)))
            (cdr cached)
          (let ((file (emacs-config-cache-file (format "dict-%s.txt" code))))
            (unless (file-exists-p file)
              (call-process-shell-command (cdr source) nil (list :file file)))
            (let ((words (with-temp-buffer
                           (insert-file-contents file)
                           (split-string (buffer-string) "\n" t))))
              (unless words
                (delete-file file)
                (display-warning 'emacs-config-dict
                                 (format "No word list for %s: `%s' printed nothing"
                                         code (cdr source))))
              (push (cons code words) emacs-config--dict-words)
              words))))))

  (defun emacs-config--dict-languages ()
    "Return the languages whose words complete in the current buffer.
The buffer's `lsp-ltex-plus-language', or en-US without LTeX+.  For
\"auto\", every language in `emacs-config-dict-sources'."
    (let ((language (or (bound-and-true-p lsp-ltex-plus-language) "en-US")))
      (if (string-equal-ignore-case language "auto")
          (mapcar #'car emacs-config-dict-sources)
        (list language))))

  (defun emacs-config-cape-dict-prefix ()
    "Prefix-only dictionary CAPF; fires after 3 typed characters.
Completes from the word lists of `emacs-config--dict-languages'."
    (when-let* ((bounds (bounds-of-thing-at-point 'word))
                (beg (car bounds))
                (end (cdr bounds))
                ((>= (- end beg) 3))
                (languages (emacs-config--dict-languages)))
      (list beg end
            (completion-table-with-cache
             (lambda (prefix)
               (delete-dups
                (mapcan (lambda (language)
                          (seq-filter (lambda (w) (string-prefix-p prefix w t))
                                      (emacs-config--dict-words language)))
                        languages))))
            :annotation-function (lambda (_) " Dict")
            :company-kind (lambda (_) 'text)
            :category 'emacs-config-dict
            :exclusive 'no)))

  ;; Read every word list now, so the first completion after a language
  ;; switch does not wait for one.
  (mapc #'emacs-config--dict-words (mapcar #'car emacs-config-dict-sources)))

;;; -- Cape for prose: merged dabbrev + dict -----------------------------------

;; Used in Markdown, Org, plain text, LaTeX, …  Merges two word-bounded
;; sources into one popup via `cape-capf-super':
;;
;;   - `cape-dabbrev'                 — recent words from visible buffers.
;;   - `emacs-config-cape-dict-prefix' — dictionary of the buffer's language.
;;
;; Both share word bounds, so the merge is safe.  Order: dabbrev first
;; → buffer-recent words (project-specific names, jargon) rank above
;; dictionary words.
;;
;; Why merge instead of a flat chain: dict produces a non-empty result
;; for almost every 3+ char prefix (tens of thousands of words per
;; language → there's always a match), so `:exclusive 'no' fall-through
;; never happens and `cape-dabbrev' would be effectively dormant in prose. The super
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
