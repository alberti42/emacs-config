;;; ids.el --- Keep org-id in step with vulpea's database -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; vulpea and `org-id' read the same `:ID:' property but keep separate
;; indexes: vulpea has its SQLite db, `org-id' has `org-id-locations'
;; (persisted to `org-id-locations-file').  vulpea registers every ID it
;; indexes with `org-id', so a note arriving from outside Emacs becomes
;; followable as it is indexed.  It registers only the files it indexes, and
;; it never unregisters one.  Those are the two gaps closed here.
;;
;; - `vulpea-vault-unregister-dropped-ids' on `vulpea-db-updated-functions',
;;   vulpea's data-changed hook.  `org-id' has no removal function and never
;;   drops entries by itself, so the ID of a deleted note otherwise stays in
;;   `org-id-locations', naming a file that no longer exists.  A link to it
;;   still reports an unknown ID, since `org-id-find' falls back to
;;   `org-id-update-id-locations' and retries; what is left behind is the
;;   entry, written to `org-id-locations-file' and read by anything that
;;   consults the table directly.
;;
;; - `vulpea-vault-update-id-locations' registers a whole tree from the
;;   database.  `vulpea-vault-switch' runs it for the vault being entered,
;;   every file of which is unchanged and therefore indexes nothing; it is
;;   also the repair for an `org-id-locations' lost while the db is current.
;;
;; Where `org-id-locations-file' lives is not decided here: it spans every org
;; file Emacs knows, not this vault alone, so it is set with the rest of org
;; (`org-config.el', under `emacs-config-cache-dir') rather than by any vault.

;;; Code:

(require 'org-id)
(require 'vulpea-vault-core)

(defun vulpea-vault-unregister-dropped-ids (path count)
  "Drop `org-id' registrations for PATH when vulpea stops indexing it.

On `vulpea-db-updated-functions', vulpea's single data-changed hook,
called with (PATH COUNT) once per file whose database content changed and
after the transaction commits.  COUNT is the number of notes written, and
0 when PATH's notes were dropped: the file was deleted, or it left the
tracked set.  Only that case is acted on — registering is vulpea's own,
done as it indexes.

Paths are compared abbreviated, which is how `org-id' stores them, and
the table is loaded first for the same reason `org-id-add-location' loads
it."
  (when (and (numberp count) (zerop count))
    (unless org-id-locations (org-id-locations-load))
    (let ((dead (abbreviate-file-name path))
          (stale nil))
      (maphash (lambda (id file) (when (equal file dead) (push id stale)))
               org-id-locations)
      (dolist (id stale) (remhash id org-id-locations)))))

(defun vulpea-vault-update-id-locations ()
  "Register every note in the vault's database with `org-id'.

The notes come from the database, which already knows every ID and path;
there is nothing to scan.

Also drops IDs under `vulpea-vault-directory' that the database no longer
lists.  `org-id' has no removal function and never drops entries by
itself, so a deleted note otherwise leaves an entry in
`org-id-locations' naming a file that no longer exists - persisted to
`org-id-locations-file', and read by anything consulting the table
without going through `org-id-find'.

The database is the authority for what the tree contains, so pruning
compares against it rather than testing the disk: `file-exists-p' cannot
tell a deleted file from one on an unmounted volume or an evicted cloud
file, and would discard IDs that are merely unreachable.  Entries outside
the tree belong to other org files and are never touched."
  (interactive)
  (unless org-id-locations (org-id-locations-load))
  (let* ((vault (vulpea-vault-or-error))
         (notes (vulpea-db-query-by-directory vault))
         (live (make-hash-table :test 'equal :size (length notes)))
         (root (abbreviate-file-name vault))
         (dropped 0))
    (dolist (note notes)
      (puthash (vulpea-note-id note) t live))
    ;; org-id stores abbreviated paths, hence comparing against an
    ;; abbreviated root.  No filesystem access in either half.
    (let (stale)
      (maphash (lambda (id file)
                 (when (and (string-prefix-p root file)
                            (not (gethash id live)))
                   (push id stale)))
               org-id-locations)
      (dolist (id stale) (remhash id org-id-locations))
      (setq dropped (length stale)))
    (dolist (note notes)
      (org-id-add-location (vulpea-note-id note) (vulpea-note-path note)))
    (message "org-id: %d registered from the notes tree, %d stale dropped"
             (length notes) dropped)))

(add-hook 'vulpea-db-updated-functions #'vulpea-vault-unregister-dropped-ids)

(provide 'vulpea-vault-ids)
;;; ids.el ends here
