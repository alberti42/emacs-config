;;; attachments.el --- The vault's ID-keyed attachment store -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; A vault keeps every attachment in one store, keyed by the `:ID:' of the
;; note that owns it (`vulpea-vault-attach-directory', derived from the root
;; in core.el).  This is the `org-attach' side of that layout: the two
;; settings it requires, and the one link syntax it lacks.
;;
;; Neither setting is taste.  `org-attach-preferred-new-method' is `id' so
;; that a note's attachments follow it through renames and moves, the store
;; being keyed by something the note carries rather than by where it sits.
;;
;; `org-attach-use-inheritance' is `t' because the key is at file level: a
;; note carries its `:ID:' in the file-level property drawer, while its
;; `attachment:' links sit under whatever heading the text put them ("*
;; Program", "* Slides", …).  With the default `selective' —
;; `org-use-property-inheritance' being nil here — `org-attach-dir' looks only
;; at the entry at point, finds no ID, returns nil, and `org-attach-expand'
;; falls back to resolving the filename against the note's own directory: "No
;; such file: <vault>/08 Conferences/<attachment>.pdf".  `t' lets the search
;; walk up to the file level, which is where the key lives.  It also makes
;; `org-attach' add new files to that same store instead of minting an ID for
;; the heading at point.
;;
;; Cross-note attachment links.  Stock `attachment:' carries only a filename,
;; which `org-attach-expand' resolves against the *current* node, so there is
;; no syntax for another note's attachment — though an ID-keyed store makes
;; one trivially expressible.  This adds "attachment:<uuid>/file",
;; discriminated by a leading UUID and resolved through the target's `:ID:',
;; so the link survives renaming and moving that note.
;;
;; `org-attach-expand' is the choke point shared by following
;; (`org-attach-follow'), inline preview (`org-attach-preview-file') and
;; export (`org-attach-expand-links'), so advising it covers all three.  The
;; UUID pattern is not version-specific — a converted vault carries both v4
;; and v5 — and a filename that merely contains a UUID stays local, since the
;; discriminator is a UUID followed by "/" as the leading path component.

;;; Code:

(require 'rx)
(require 'org-attach)

;; `org-attach-id-dir' is assigned by `vulpea-vault-apply', which follows the
;; vault; these two are the same for every vault, so they are set once.
(setq org-attach-preferred-new-method 'id)
(setq org-attach-use-inheritance t)

(defconst vulpea-vault-attach-crossref-regexp
  (rx bos (group (= 8 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 12 hex))
      "/" (group (+ nonl)) eos)
  "Match \"UUID/relative/path\" in an `attachment:' link path.")

(defun vulpea-vault-attach-expand (orig file)
  "Expand FILE, treating a leading UUID as another note's attachment.
ORIG is the stock `org-attach-expand', used for every other path."
  (if (string-match vulpea-vault-attach-crossref-regexp file)
      (let ((id (match-string 1 file))
            (rest (match-string 2 file)))
        (expand-file-name rest (org-attach-dir-from-id id)))
    (funcall orig file)))

(advice-add 'org-attach-expand :around #'vulpea-vault-attach-expand)

(provide 'vulpea-vault-attachments)
;;; attachments.el ends here
