;;; destination-repro.el --- Link destinations are used verbatim -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Reproducer for: `markdown-ts-mode' never removes CommonMark's pointy-bracket
;; wrapper from a link destination, and never percent-decodes one.
;;
;; Run against the build under test:
;;
;;     emacs -Q --batch -l destination-repro.el
;;
;; and against a patched copy of markdown-ts-mode.el:
;;
;;     emacs -Q --batch -L /dir/holding/patched -l destination-repro.el
;;
;; It creates a temporary directory holding real files, writes a Markdown
;; buffer linking to them, pushes each link's button with `find-file' and
;; `browse-url' stubbed, and compares what each one was handed against an
;; explicit expectation.  Nothing is opened and nothing is browsed.
;;
;; Two independent axes are covered, because a space in a file name can be
;; spelled either way and both spellings occur in the wild:
;;
;;   <my file.md>      pointy brackets -- Markdown syntax.  The destination
;;                     *is* `my file.md'; the brackets are delimiters the
;;                     parser must strip (CommonMark 0.31.2 section 6.3).
;;   my%20file.md      percent-encoding -- URI syntax.  The destination is
;;                     literally `my%20file.md', and naming `my file.md'
;;                     requires reading it as a URI reference.
;;
;; They compose: `<my%20file.md>' is bracketed *and* encoded.  A bare
;; `my file.md' is neither, and is not a link at all -- the grammar is right to
;; refuse it, which is what makes the bracket form the only Markdown-level
;; spelling and this bug a conformance matter rather than a convenience.

;;; Code:

(require 'markdown-ts-mode)
(require 'cl-lib)

(defvar markdown-ts-repro--opened nil)
(defvar markdown-ts-repro--browsed nil)

(defconst markdown-ts-repro--files
  '("my target.md" "plain.md" "50% off.md" "100%25 done.md"
    "Förster resonance.md")
  "Real files created on disk, named exactly like this.")

(defconst markdown-ts-repro--cases
  ;; (DESTINATION-AS-WRITTEN EXPECTED DESCRIPTION), where EXPECTED is the file
  ;; name that should reach `find-file', the symbol `browse' for a URL that
  ;; should reach `browse-url', or `unreachable' when the destination must NOT
  ;; be able to name the target file -- a bare space makes the construct a
  ;; shortcut link (`[d]' resolving to the label `d'), not an inline link, so
  ;; correct behaviour here is *not* reaching `my target.md'.
  '(("<my target.md>"     "my target.md"  "bracketed name with a space")
    ("my%20target.md"     "my target.md"  "percent-encoded name with a space")
    ("<my%20target.md>"   "my target.md"  "bracketed AND percent-encoded")
    ("my target.md"       unreachable     "control: bare space cannot name the file")
    ("plain.md"           "plain.md"      "control: plain relative name")
    ("<https://ex.com/x?a=1&b=2>" browse   "bracketed URL")
    ("https://ex.com/q?s=a%20b"   browse   "control: URL keeps its escapes")
    ("<50% off.md>"       "50% off.md"    "bracketed name with a literal %")
    ("<100%25 done.md>"   "100%25 done.md" "bracketed name literally containing %25")
    ("Fo%CC%88rster%20resonance.md" "Förster resonance.md"
     "UTF-8 percent-escapes (needs decoding to characters, not bytes)"))
  "Each entry is (DESTINATION EXPECTED DESCRIPTION).")

(defun markdown-ts-repro--verdict (expected)
  "Return non-nil when the stubs recorded what EXPECTED asks for."
  (cond ((eq expected 'browse)
         (and markdown-ts-repro--browsed (not markdown-ts-repro--opened)))
        ((eq expected 'unreachable)
         ;; Correct behaviour is failing to name the file, by design.
         (not (equal markdown-ts-repro--opened "my target.md")))
        (t (equal markdown-ts-repro--opened expected))))

(defun markdown-ts-repro--run ()
  "Print what each link's button hands to `find-file' / `browse-url'."
  (let ((dir (make-temp-file "md-repro" t))
        (fails 0))
    (dolist (f markdown-ts-repro--files)
      (with-temp-file (expand-file-name f dir) (insert "# target\n")))
    (with-current-buffer (find-file-noselect (expand-file-name "note.md" dir))
      (cl-loop for (dest _expected _desc) in markdown-ts-repro--cases
               for i from 1
               ;; Single-character labels, so the button is exactly one char
               ;; wide and `push-button' has to land on it precisely.
               do (insert (format "%d [%c](%s)\n" i (+ ?a i -1) dest)))
      (markdown-ts-mode)
      (font-lock-ensure)
      (message "markdown-ts-mode: %s"
               (if (fboundp 'markdown-ts--unbracket-destination)
                   "PATCHED (normalization present)"
                 "as shipped"))
      (message "files on disk: %S" markdown-ts-repro--files)
      (when (boundp 'markdown-ts-percent-decode-destinations)
        (message "markdown-ts-percent-decode-destinations: %S"
                 markdown-ts-percent-decode-destinations))
      (message "")
      (message " #  %-28s %-24s %s" "destination as written" "handed to" "")
      (message " -- %-28s %-24s %s" (make-string 28 ?-) (make-string 24 ?-) "----")
      (cl-letf (((symbol-function 'find-file)
                 (lambda (f &rest _) (setq markdown-ts-repro--opened f)))
                ((symbol-function 'browse-url)
                 (lambda (u &rest _) (setq markdown-ts-repro--browsed u))))
        (cl-loop for (dest expected desc) in markdown-ts-repro--cases
                 for i from 1
                 do (goto-char (point-min))
                    (search-forward (format "%d [" i))
                    (setq markdown-ts-repro--opened nil
                          markdown-ts-repro--browsed nil)
                    (when (get-text-property (point) 'button)
                      (push-button (point)))
                    (let ((ok (markdown-ts-repro--verdict expected)))
                      (unless ok (setq fails (1+ fails)))
                      (message " %d  %-28s %-24s %s   %s" i dest
                               (cond (markdown-ts-repro--browsed
                                      (format "browse-url %S"
                                              markdown-ts-repro--browsed))
                                     (markdown-ts-repro--opened
                                      (format "find-file %S"
                                              markdown-ts-repro--opened))
                                     (t "(no button)"))
                               (if ok "PASS" "FAIL")
                               desc)))))
    (message "")
    (message "%d of %d cases fail." fails (length markdown-ts-repro--cases))))

(markdown-ts-repro--run)

;; The last case fails on a patched build too, and that is inherent rather than
;; a defect in the patch: a file whose name literally contains "%25" is
;; indistinguishable from an encoded "%" once you decide to percent-decode
;; local destinations at all.  It is the reason the bracket half of this fix
;; (Markdown syntax, no interpretation, no trade-off) is worth separating from
;; the percent-decoding half (a URI reading of the destination, with this known
;; ambiguity attached).

;;; destination-repro.el ends here
