;;; 01-link-destination-repro.el --- Link destinations are used verbatim -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Reproducer for: `markdown-ts-mode' never removes CommonMark's pointy-bracket
;; wrapper from a link destination, and never percent-decodes one.
;;
;; Run against the build under test:
;;
;;     emacs -Q --batch -l 01-link-destination-repro.el
;;
;; and against a patched copy of markdown-ts-mode.el:
;;
;;     emacs -Q --batch -L /dir/holding/patched -l 01-link-destination-repro.el
;;
;; It creates a temporary directory holding four real files, writes a Markdown
;; buffer linking to them, pushes each link's button with `find-file' and
;; `browse-url' stubbed, and prints what each one was handed plus whether that
;; name exists on disk.  Nothing is opened and nothing is browsed.
;;
;; A correct build reaches every existing file and routes both URLs to
;; `browse-url'.  Case 7 is expected to fail even when patched -- see the note
;; at the end.

;;; Code:

(require 'markdown-ts-mode)
(require 'cl-lib)

(defvar markdown-ts-repro--opened nil)
(defvar markdown-ts-repro--browsed nil)

(defconst markdown-ts-repro--files
  '("my target.md" "plain.md" "50% off.md" "100%25 done.md")
  "Real files created on disk, named exactly like this.")

(defconst markdown-ts-repro--cases
  '(("[a](<my target.md>)"            "bracketed name with a space")
    ("[b](my%20target.md)"            "percent-encoded name with a space")
    ("[c](plain.md)"                  "control: plain relative name")
    ("[d](<https://ex.com/x?a=1&b=2>) " "bracketed URL")
    ("[e](https://ex.com/q?s=a%20b)"  "control: URL with a %20 escape")
    ("[f](<50% off.md>)"              "bracketed name with a literal %")
    ("[g](<100%25 done.md>)"          "bracketed name literally containing %25"))
  "Each entry is (MARKDOWN DESCRIPTION); label is the Nth letter.")

(defun markdown-ts-repro--run ()
  "Print what each link's button hands to `find-file' / `browse-url'."
  (let ((dir (make-temp-file "md-repro" t)))
    (dolist (f markdown-ts-repro--files)
      (with-temp-file (expand-file-name f dir) (insert "# target\n")))
    (with-current-buffer (find-file-noselect (expand-file-name "note.md" dir))
      (cl-loop for (md _desc) in markdown-ts-repro--cases
               for i from 1
               do (insert (format "%d %s\n" i md)))
      (markdown-ts-mode)
      (font-lock-ensure)
      (message "markdown-ts-mode: %s"
               (if (fboundp 'markdown-ts--unbracket-destination)
                   "PATCHED (normalization present)"
                 "as shipped"))
      (message "files on disk: %S" markdown-ts-repro--files)
      (message "")
      (message " #  %-34s %-26s %s" "destination as written" "handed to" "ok?")
      (message " -- %-34s %-26s %s" (make-string 34 ?-) (make-string 26 ?-) "---")
      (cl-letf (((symbol-function 'find-file)
                 (lambda (f &rest _) (setq markdown-ts-repro--opened f)))
                ((symbol-function 'browse-url)
                 (lambda (u &rest _) (setq markdown-ts-repro--browsed u))))
        (cl-loop for (md desc) in markdown-ts-repro--cases
                 for i from 1
                 do (goto-char (point-min))
                    (search-forward (format "%d [" i))
                    ;; Point now sits on the single-character label, which is
                    ;; the button; `push-button' needs to land exactly there.
                    (setq markdown-ts-repro--opened nil
                          markdown-ts-repro--browsed nil)
                    (push-button (point))
                    (let* ((dest (progn (looking-at "[a-z]\\](\\(.*?\\))")
                                        (match-string 1)))
                           (urlp (string-match-p "\\`<?https?:" (or dest "")))
                           (ok (cond (markdown-ts-repro--browsed urlp)
                                     (markdown-ts-repro--opened
                                      (and (not urlp)
                                           (file-exists-p
                                            (expand-file-name
                                             markdown-ts-repro--opened dir)))))))
                      (message " %d  %-34s %-26s %s   %s" i dest
                               (if markdown-ts-repro--browsed
                                   (format "browse-url %S" markdown-ts-repro--browsed)
                                 (format "find-file %S" markdown-ts-repro--opened))
                               (if ok "PASS" "FAIL")
                               desc)))))))

(markdown-ts-repro--run)

;; Case 7 fails on a patched build too, and that is inherent rather than a
;; defect in the patch: a file whose name literally contains "%25" is
;; indistinguishable from an encoded "%" once you decide to percent-decode
;; local destinations at all.  It is the reason the bracket half of this fix
;; (cases 1, 4 and 6 -- unambiguous, pure CommonMark conformance) is worth
;; separating from the percent-decoding half (case 2 -- a convenience with this
;; known trade-off).

;;; 01-link-destination-repro.el ends here
