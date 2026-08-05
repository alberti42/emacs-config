;;; attachments.el --- Find orphans in the vault -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `vulpea-vault-orphans' reports the two complementary failures of an
;; ID-keyed attachment store:
;;
;;   - dangling links: a note points at something that is not there;
;;   - orphan files: something is in the store that no note points at.
;;
;; Both come from vulpea's database, which already holds every link with its
;; type and position, so nothing re-parses the notes.
;;
;; Link types org cannot resolve on its own are counted, not listed as
;; dangling.  A vault converted from Obsidian carries several hundred
;; `x-bdsk:', `pdffile:' and `message:' links; org has no such link types, so
;; `org-element' files them all as `fuzzy'.  Calling those broken would bury
;; the handful of genuinely dangling links.  Registering the types with
;; `org-link-set-parameters' is the fix for them, not repair.

;;; Code:

(require 'org)
(require 'org-attach)
(require 'seq)

(defconst vulpea-vault-checkable-link-types '("attachment" "id" "file" "pdffile")
  "Link types `vulpea-vault-orphans' can verify.
Everything else is either remote (`https:'), or a type org does not
know, or an internal target that would need the file parsed.")

(defun vulpea-vault--attachment-file (note dest)
  "Resolve an `attachment:' DEST written in NOTE to an absolute file.
Mirrors `vulpea-config-attach-expand': a leading UUID names another
note's store, otherwise the store belongs to NOTE itself."
  (if (string-match vulpea-config-crossref-regexp dest)
      (expand-file-name (match-string 2 dest)
                        (org-attach-dir-from-id (match-string 1 dest)))
    (expand-file-name dest (org-attach-dir-from-id (vulpea-note-id note)))))

(defun vulpea-vault--link-target (note link)
  "Return the file or ID that LINK in NOTE points at, or nil if unverifiable."
  (let ((type (plist-get link :type))
        (dest (plist-get link :dest)))
    (pcase type
      ("attachment" (vulpea-vault--attachment-file note dest))
      ("id" dest)
      ("file" (expand-file-name (car (split-string dest "::"))
                                (file-name-directory (vulpea-note-path note))))
      ;; `fboundp' rather than `require': vulpea-vault/pdffile.el is loaded as a
      ;; file, not a feature on `load-path', and by report time it is present.
      ("pdffile" (and (fboundp 'vulpea-vault-pdffile-parse)
                      (car (vulpea-vault-pdffile-parse dest))))
      (_ nil))))

(defun vulpea-vault--line-of (path pos)
  "Line number of character POS in PATH, or nil."
  (when (file-readable-p path)
    (with-temp-buffer
      (insert-file-contents path)
      (line-number-at-pos (min (max pos (point-min)) (point-max))))))

(defconst vulpea-vault-junk-filenames '(".DS_Store" "Thumbs.db" ".localized")
  "Filesystem debris that is never an attachment.
Finder writes .DS_Store into any directory it displays, and the store is
meant to be browsed — `org-attach-reveal' opens it — so these reappear on
their own and would otherwise be reported as orphans forever.")

(defun vulpea-vault--store-files ()
  "Every attachment currently in the store, ignoring filesystem debris."
  (let ((dir org-attach-id-dir))
    (when (file-directory-p dir)
      (seq-filter
       (lambda (f)
         (and (file-regular-p f)
              (not (member (file-name-nondirectory f) vulpea-vault-junk-filenames))))
       (directory-files-recursively dir "")))))

(defun vulpea-vault--internal-p (entry)
  "Non-nil if ENTRY's dangling target belongs to the vault.
An `id:' target is a note, so always internal; a file target is judged by
whether it lives under `vulpea-directory'."
  (let ((link (nth 1 entry))
        (target (nth 2 entry)))
    (or (equal (plist-get link :type) "id")
        (file-in-directory-p target vulpea-directory))))

(defun vulpea-vault--insert-dangling (heading entries)
  "Insert a section HEADING listing dangling ENTRIES, sorted by note path."
  (insert (format "\n* %s (%d)\n" heading (length entries)))
  (if (null entries)
      (insert "  none\n")
    (dolist (entry (sort entries
                         (lambda (a b) (string< (vulpea-note-path (car a))
                                                (vulpea-note-path (car b))))))
      (let* ((note (nth 0 entry))
             (link (nth 1 entry))
             (target (nth 2 entry))
             (path (vulpea-note-path note))
             (line (vulpea-vault--line-of path (plist-get link :pos))))
        (insert (format "- %s\n  %s: %s\n"
                        (vulpea-vault--org-link path line (vulpea-note-title note))
                        (plist-get link :type) target))))))

(defun vulpea-vault--org-link (path line label)
  "An org link to LINE of PATH, shown as LABEL."
  (format "[[file:%s%s][%s]]"
          (org-link-escape path)
          (if line (format "::%d" line) "")
          (replace-regexp-in-string "[][]" "" label)))

(defun vulpea-vault-orphans ()
  "Report dangling links and unreferenced attachment files.
Both lists are clickable: follow a link to reach the place that needs
fixing.  Reads vulpea's database; the notes are not re-parsed."
  (interactive)
  (let* ((notes (vulpea-db-query-by-directory vulpea-directory))
         (ids (make-hash-table :test 'equal))
         (referenced (make-hash-table :test 'equal))
         (skipped (make-hash-table :test 'equal))
         dangling)
    (dolist (note notes)
      (puthash (vulpea-note-id note) t ids))
    ;; One pass: collect what is referenced and what fails to resolve.
    (dolist (note notes)
      (dolist (link (vulpea-note-links note))
        (let ((type (plist-get link :type)))
          (if (not (member type vulpea-vault-checkable-link-types))
              (cl-incf (gethash type skipped 0))
            (let ((target (vulpea-vault--link-target note link)))
              (when target
                (if (equal type "id")
                    (unless (gethash target ids)
                      (push (list note link target) dangling))
                  (puthash target t referenced)
                  (unless (file-exists-p target)
                    (push (list note link target) dangling)))))))))
    (let ((orphans (seq-remove (lambda (f) (gethash f referenced))
                              (vulpea-vault--store-files))))
      (with-current-buffer (get-buffer-create "*vulpea orphans*")
        (let ((inhibit-read-only t))
          (erase-buffer)
          (org-mode)
          (insert "#+title: Vault orphans\n\n"
                  (format "%d notes, %d dangling links, %d unreferenced files\n\n"
                          (length notes) (length dangling) (length orphans)))
          ;; Split by where the target lives: inside the vault it is the vault's
          ;; own problem to repair, outside it is a file that moved or a volume
          ;; that is not mounted — a different kind of follow-up.
          (let ((inside (seq-filter #'vulpea-vault--internal-p dangling))
                (outside (seq-remove #'vulpea-vault--internal-p dangling)))
            (vulpea-vault--insert-dangling "Dangling links inside the vault" inside)
            (vulpea-vault--insert-dangling "Dangling links to external files" outside))
          (insert (format "\n* Unreferenced files in the store (%d)\n" (length orphans)))
          (if (null orphans)
              (insert "  none\n")
            (dolist (f (sort orphans #'string<))
              (insert (format "- %s\n"
                              (vulpea-vault--org-link f nil (file-name-nondirectory f))))))
          (insert "\n* Not checked\n")
          (if (zerop (hash-table-count skipped))
              (insert "  nothing\n")
            (let (rows)
              (maphash (lambda (k v) (push (cons k v) rows)) skipped)
              (dolist (row (sort rows (lambda (a b) (> (cdr a) (cdr b)))))
                (insert (format "- %s: %d\n" (car row) (cdr row))))
              (insert "\n  `fuzzy' covers link types org does not know, such as\n"
                      "  x-bdsk:, pdffile: and message:.  Those need\n"
                      "  `org-link-set-parameters', not repair.\n")))
          (goto-char (point-min)))
        (display-buffer (current-buffer))))))

(provide 'vulpea-vault-attachments)
;;; attachments.el ends here
