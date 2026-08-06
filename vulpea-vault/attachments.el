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
;;
;; The rest of the `fuzzy' pile *is* checkable, and is checked: `[[*Heading]]'
;; and `[[dedicated-target]]' both point inside the file that holds them, so
;; the file itself says whether they resolve.  This is the one place the report
;; reads a note, and only notes carrying such a link, once each.
;;
;; It also catches text that was never meant to be a link.  Org claims any
;; `[[…]]', so stabilizer-code notation (`[[8,3,2]]'), Mathematica part
;; extraction (`[[1]]') and a pasted config key all become links pointing
;; nowhere.  They belong in the report: org renders them as links, and the fix
;; is to make them verbatim.

;;; Code:

(require 'org)
(require 'org-attach)
(require 'seq)

(defconst vulpea-vault-checkable-link-types
  '("attachment" "id" "file" "pdffile" "fuzzy")
  "Link types `vulpea-vault-orphans' can verify.
Everything else is remote (`https:') or a scheme org does not know.
`fuzzy' is only partly verifiable — see `vulpea-vault--fuzzy-scheme'.")

(defun vulpea-vault--fuzzy-scheme (dest)
  "Return DEST's URI scheme when it has one.

`org-element' types a link with an unregistered scheme as `fuzzy', so
`message://…' arrives here looking like an internal target.  Reporting
the scheme instead of \"fuzzy\" tells the reader which link type is
missing an `org-link-set-parameters'.

The colon must be followed by a non-blank for this to count, so an
ordinary heading reference like `[[*Summary: incoherent averaging]]' is
not mistaken for a scheme."
  (when (string-match "\\`\\([A-Za-z][A-Za-z0-9+.-]*\\):[^ \t]" dest)
    (match-string 1 dest)))

(defun vulpea-vault--fuzzy-audit (note)
  "Audit the fuzzy links in NOTE's own file.

Return (DANGLING . SCHEMES): DANGLING is a list of link plists shaped
like vulpea's own, SCHEMES an alist of scheme to count.

The links come from `org-element', not from the database.  vulpea finds
links by regexp, which reports text that only looks like one — org reads
`\\([[8,3,2]]\\)' as a latex fragment and `=[[a|b]]=' as verbatim, so
neither is a link, but both match `[[…]]'.  Asking the parser is the
only way to tell, and this function already has the file open.

`delay-mode-hooks' matters: without it `org-mode' would fire
`org-mode-hook' once per note here, which is the cost
`vulpea-db-parse-method' was set to `single-temp-buffer' to avoid.

Org would also fall back to a plain-text search, which is deliberately
not imitated: a link's own text satisfies it every time, so every link
would pass.  An entry here means \"no anchor of any kind\"."
  (with-temp-buffer
    (insert-file-contents (vulpea-note-path note))
    (delay-mode-hooks (org-mode))
    (let* ((tree (org-element-parse-buffer 'object))
           (headings (org-element-map tree 'headline
                       (lambda (h) (org-element-property :raw-value h))))
           (targets (append
                     (org-element-map tree 'target
                       (lambda (x) (org-element-property :value x)))
                     (org-element-map tree org-element-all-elements
                       (lambda (e) (org-element-property :name e)))))
           dangling schemes)
      (org-element-map tree 'link
        (lambda (link)
          (let ((type (org-element-property :type link))
                (dest (org-element-property :path link)))
            (cond
             ((equal type "fuzzy")
              (let ((scheme (vulpea-vault--fuzzy-scheme dest)))
                (cond
                 (scheme (cl-incf (alist-get scheme schemes 0 nil #'equal)))
                 ((if (string-prefix-p "*" dest)
                      (member (substring dest 1) headings)
                    (or (member dest targets) (member dest headings))))
                 (t (push (list :type "fuzzy" :dest dest
                                :pos (org-element-property :begin link))
                          dangling)))))
             ;; Checked from the database, which knows the file each one names.
             ((member type vulpea-vault-checkable-link-types))
             ;; Everything else is tallied here rather than from the database,
             ;; because org and the index can disagree: registering a type with
             ;; `org-link-set-parameters' changes `message://…' from `fuzzy' to
             ;; `message' the moment it is loaded, while the index keeps saying
             ;; `fuzzy' until the note is next scanned.  Counting from the same
             ;; parse that judged the rest of the note keeps the two in step.
             (t (cl-incf (alist-get type schemes 0 nil #'equal)))))))
      (cons (nreverse dangling) schemes))))

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

(defun vulpea-vault--hidden-p (file)
  "Non-nil if any component of FILE below the store starts with a dot.

Covers both shapes of debris in one rule: a dotted *file* (.DS_Store, which
Finder writes into any directory it displays — and the store is meant to be
browsed, since `org-attach-reveal' opens it) and a dotted *directory*
(.ipynb_checkpoints, Jupyter's autosaves, which arrive alongside a notebook
attachment).  Neither is ever an attachment, and both come back on their
own, so reporting them as orphans would never end.

This is the same convention vulpea applies when scanning for notes: it
skips paths containing \"/.\"."
  (seq-some (lambda (part) (string-prefix-p "." part))
            (split-string (file-relative-name file org-attach-id-dir) "/" t)))

(defun vulpea-vault--store-files ()
  "Every attachment currently in the store, ignoring filesystem debris."
  (let ((dir org-attach-id-dir))
    (when (file-directory-p dir)
      (seq-filter (lambda (f)
                    (and (file-regular-p f)
                         (not (vulpea-vault--hidden-p f))))
                  (directory-files-recursively dir "")))))

(defun vulpea-vault--internal-p (entry)
  "Non-nil if ENTRY's dangling target belongs to the vault.
An `id:' target is a note, so always internal; a file target is judged by
whether it lives under `vulpea-config-notes-directory'."
  (let ((link (nth 1 entry))
        (target (nth 2 entry)))
    (or (member (plist-get link :type) '("id" "fuzzy"))
        (file-in-directory-p target vulpea-config-notes-directory))))

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
fixing.

Everything comes from vulpea's database except the same-file links,
which cannot be judged without the file: those notes are read once each,
in a second pass."
  (interactive)
  (let* ((notes (vulpea-db-query-by-directory vulpea-config-notes-directory))
         (ids (make-hash-table :test 'equal))
         (referenced (make-hash-table :test 'equal))
         (skipped (make-hash-table :test 'equal))
         (fuzzy (make-hash-table :test 'equal))
         dangling)
    (dolist (note notes)
      (puthash (vulpea-note-id note) t ids))
    ;; A note holding any same-file link is audited from its file, and its
    ;; unverifiable links are tallied there too — decided up front, so the
    ;; decision does not depend on the order links appear in.
    (dolist (note notes)
      (when (seq-some (lambda (l) (equal (plist-get l :type) "fuzzy"))
                      (vulpea-note-links note))
        (puthash (vulpea-note-path note) note fuzzy)))
    ;; One pass: collect what is referenced and what fails to resolve.
    (dolist (note notes)
      (let ((audited (gethash (vulpea-note-path note) fuzzy)))
        (dolist (link (vulpea-note-links note))
          (let ((type (plist-get link :type)))
            (cond
             ((equal type "fuzzy"))     ; the audit judges these
             ((not (member type vulpea-vault-checkable-link-types))
              (unless audited (cl-incf (gethash type skipped 0))))
             (t
              (let ((target (vulpea-vault--link-target note link)))
                (when target
                  (if (equal type "id")
                      (unless (gethash target ids)
                        (push (list note link target) dangling))
                    (puthash target t referenced)
                    (unless (file-exists-p target)
                      (push (list note link target) dangling)))))))))))
    ;; Second pass, one file read per note that has any fuzzy link.
    (maphash
     (lambda (_path note)
       (let ((audit (vulpea-vault--fuzzy-audit note)))
         (dolist (link (car audit))
           (push (list note link (plist-get link :dest)) dangling))
         (pcase-dolist (`(,scheme . ,count) (cdr audit))
           (cl-incf (gethash scheme skipped 0) count))))
     fuzzy)
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
              ;; "Not checked" is not the same as "broken": an https: link is
              ;; simply outside what this report can verify.  What matters is
              ;; whether org can follow it at all, which is one lookup away.
              (dolist (row (sort rows (lambda (a b) (> (cdr a) (cdr b)))))
                (insert (format "- %s: %d%s\n" (car row) (cdr row)
                                (if (org-link-get-parameter (car row) :follow)
                                    ""
                                  "   ← no handler; following one fails"))))
              (insert "\n  A type with no handler needs `org-link-set-parameters',\n"
                      "  not repair.  The rest are remote or open in another app.\n")))
          (goto-char (point-min)))
        (display-buffer (current-buffer))))))

(provide 'vulpea-vault-attachments)
;;; attachments.el ends here
