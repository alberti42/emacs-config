;;; ids.el --- Keep org-id in step with vulpea's database -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; vulpea and `org-id' read the same `:ID:' property but keep separate
;; indexes, and neither fills the other: vulpea has its SQLite db, `org-id'
;; has `org-id-locations' (persisted to `org-id-locations-file').  vulpea does
;; NOT hook `org-id' — its own commands (`vulpea-find' and friends) resolve
;; through the database, while following a plain `[[id:…]]' link goes through
;; `org-id-locations'.  So the symptom of a gap is one-sided and puzzling:
;; `vulpea-find' finds a note while a link to that same note fails.
;;
;; Two things close the gap, and they cover different cases:
;;
;; - `vulpea-vault-register-ids' on `vulpea-db-worker-done-functions', so a
;;   note arriving from outside Emacs becomes followable as it is indexed;
;;
;; - `vulpea-vault-update-id-locations', a repair command for the one case
;;   that misses — `org-id-locations' lost while vulpea's db is current, so
;;   every file reports `unchanged' and the hook stays quiet.
;;
;; Where `org-id-locations-file' lives is not decided here: it spans every org
;; file Emacs knows, not this vault alone, so it is set with the rest of org
;; (`org-config.el', under `emacs-config-cache-dir') rather than by any vault.
;;
;; Also here, because it is the same `:ID:' seen from the writing side: org
;; 9.8.7 still mints UUIDs by forking `org-id-uuid-program', which on macOS
;; returns them uppercase, while `org-id-locations' is an `equal'-test hash
;; table and a converted vault's IDs are all lowercase.  A note created with
;; an uppercase ID is found by vulpea and not by `id:'.

;;; Code:

(require 'org-id)
(require 'uuid)
(require 'vulpea-vault-core)

(defun vulpea-vault-register-ids (path status _count)
  "Register the IDs vulpea just indexed in PATH with `org-id'.

Added to `vulpea-db-worker-done-functions', which vulpea's file watcher
runs after indexing a file.  STATUS is `applied' when notes were written;
the other statuses (`unchanged', `stale', `requeued', `missing', `error')
mean there is nothing new to register.

The IDs come from vulpea's own database rather than from re-parsing the
file — it has just extracted them.  `org-id-add-location' is a single
`puthash'; `org-id-update-id-locations' is not usable here because it
clears `org-id-locations' and rescans every known file."
  (when (eq status 'applied)
    (dolist (note (vulpea-db-query-by-file-path path))
      (org-id-add-location (vulpea-note-id note) path))))

(defun vulpea-vault-update-id-locations ()
  "Register every note in the vault's database with `org-id'.

The notes come from the database, which already knows every ID and path;
there is nothing to scan.

Also drops IDs under `vulpea-vault-directory' that the database no longer
lists.  `org-id' has no removal API and never prunes, so deleting a note
leaves its ID pointing at a dead path, and following such a link fails
with a missing file rather than an unknown ID.

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

(defun vulpea-vault-org-id-new (&rest _)
  "Return a lowercase v4 UUID, using `uuid.el'.
An `:override' on `org-id-new', so every ID minted in this Emacs matches
the case of the ones already indexed.  `uuid-v4' returns a struct, hence
`uuid-to-string'."
  (uuid-to-string (uuid-v4)))

(advice-add 'org-id-new :override #'vulpea-vault-org-id-new)

(add-hook 'vulpea-db-worker-done-functions #'vulpea-vault-register-ids)

(provide 'vulpea-vault-ids)
;;; ids.el ends here
