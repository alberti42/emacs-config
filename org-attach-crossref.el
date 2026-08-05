;;; org-attach-crossref.el --- Cross-note attachment: links -*- lexical-binding: t; -*-

;; Stock `attachment:' links carry only a filename, which `org-attach-expand'
;; expands against the *current* node's attachment directory.  There is no
;; syntax for pointing at another note's attachment.
;;
;; This teaches the same link type a second form, discriminated by a leading
;; UUID:
;;
;;   [[attachment:report.pdf]]                       this note's attachment
;;   [[attachment:b8ddf2b1-…-55b5b66af5e9/report.pdf]]   another note's
;;
;; The cross-reference resolves through the target note's ID rather than its
;; filename or location, so it survives renaming and moving that note — the
;; same guarantee `id:' links give.  With an ID-derived `org-attach-id-dir'
;; nothing in the link mentions where the other note lives.
;;
;; Implemented as advice on `org-attach-expand' because that one function is
;; the choke point for following a link (`org-attach-follow'), inline preview
;; (`org-attach-preview-file') and export (`org-attach-expand-links'), so all
;; three learn the new form together.

(require 'org-attach)
(require 'rx)

(defconst org-attach-crossref-uuid-regexp
  (rx bos (group (= 8 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 12 hex))
      "/" (group (+ nonl)) eos)
  "Match \"UUID/relative/path\" in an `attachment:' link path.
Deliberately not version-specific: a vault may carry both v4 and v5
UUIDs, and org compares IDs as plain strings.")

(defun org-attach-crossref-expand (orig file)
  "Expand FILE, treating a leading UUID as another note's attachment.
ORIG is the stock `org-attach-expand', used for every other path."
  (if (string-match org-attach-crossref-uuid-regexp file)
      (let* ((id (match-string 1 file))
             (rest (match-string 2 file))
             ;; Prefer a directory that exists, so an alternative entry in
             ;; `org-attach-id-to-path-function-list' is honoured; otherwise
             ;; fall back to the default mapping so the error names the path
             ;; that was looked for.
             (dir (or (org-attach-dir-from-id id t)
                      (org-attach-dir-from-id id))))
        (if dir
            (expand-file-name rest dir)
          (user-error "No attachment directory for ID %s" id)))
    (funcall orig file)))

(advice-add 'org-attach-expand :around #'org-attach-crossref-expand)

(provide 'org-attach-crossref)
;;; org-attach-crossref.el ends here
