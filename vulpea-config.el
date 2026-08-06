;;; vulpea-config.el --- Note database over the org notes (vulpea) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; vulpea v2 is a database layer over org notes: it indexes every org node that
;; carries an `:ID:' and answers queries about them without blocking.  It is
;; standalone as of v2 — no org-roam involved.
;;
;; Three things key off that one `:ID:' property: `org-id' (for `id:' links),
;; `org-attach' (for the attachment directory) and vulpea (as its primary key).
;;
;; Notes:
;;
;; - vulpea does NOT hook `org-id'.  Its own commands (`vulpea-find' and
;;   friends) resolve through the database, but following a plain `[[id:…]]'
;;   link goes through `org-id-locations', which has to be populated
;;   separately — run `vulpea-config-update-id-locations' once after a
;;   conversion, and again after adding notes outside Emacs.
;;
;; - The database lives in the vault, under `.vulpea/', so the index belongs to
;;   the vault and a second vault is just a different
;;   `vulpea-config-notes-directory'.  `org-id-locations' stays under XDG cache
;;   instead: it spans every org file Emacs knows, not this vault alone.
;;   Neither ever lands in this git worktree.
;;
;; - Attachment layout must match what the converter emitted: `org-attach' mode
;;   puts everything in one ID-keyed store, mirror mode leaves a
;;   "<note> (attachments)" folder beside each note and uses `file:' links.
;;   Only the former needs `org-attach-id-dir'.

;;; Code:

(require 'rx)

(defconst vulpea-config-notes-directory
  (expand-file-name "~/org/Work/")
  "Root of the converted org notes.
The single place to change when the tree moves.  Must match
DEFAULT_OUT in `etc/goodies/obsidian-to-org.py', and must match the
directory's case on disk: macOS is case-insensitive so a wrong case
still opens files, but `org-id' stores abbreviated paths and
`vulpea-config-update-id-locations' compares them with
`string-prefix-p', which is not.")

(defconst vulpea-config-state-directory
  (expand-file-name ".vulpea/" vulpea-config-notes-directory)
  "Per-vault state, kept inside the vault rather than in a global cache.
The index then belongs to the vault and travels with it, which is what
makes a second vault (Private, …) a matter of pointing
`vulpea-config-notes-directory' elsewhere.

Safe to keep here: vulpea's scanner skips hidden directories — anything
whose path contains \"/.\" — so it neither indexes nor watches its own
state, and writing the database cannot retrigger a sync.")

(defconst vulpea-config-attach-directory
  (expand-file-name "data/" vulpea-config-notes-directory)
  "Central org-attach store, matching the converter's --attach-dir.
Must stay in sync with it: `org-attach' derives a note's directory
from this path plus its `:ID:', so a mismatch silently yields an
empty attachment directory rather than an error.")

(defun vulpea-config--cache-dir ()
  "Return the XDG cache directory for this config, creating it."
  (let* ((cache-home (or (getenv "XDG_CACHE_HOME")
                         (expand-file-name "~/.cache")))
         (dir (expand-file-name "emacs" cache-home)))
    (make-directory dir t)
    dir))

(defun vulpea-config-update-id-locations ()
  "Register every note in vulpea's database with `org-id'.

vulpea and `org-id' read the same `:ID:' property but keep separate
indexes, and neither fills the other: vulpea has its SQLite db, `org-id'
has `org-id-locations' (persisted to `org-id-locations-file').  The
symptom of a gap is one-sided — `vulpea-find' finds a note while
following an `[[id:…]]' link to it fails.

`vulpea-config-register-ids' keeps the two in step as files are indexed,
so this is a repair command for the one case that misses: when
`org-id-locations' is lost but vulpea's db is current, so vulpea reports
every file `unchanged' and the hook stays quiet.

The notes come from the database, which already knows every ID and path;
there is nothing to scan.

Also drops IDs under `vulpea-config-notes-directory' that the database no longer
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
  (let* ((notes (vulpea-db-query-by-directory vulpea-config-notes-directory))
         (live (make-hash-table :test 'equal :size (length notes)))
         (root (abbreviate-file-name vulpea-config-notes-directory))
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

(defun vulpea-config-org-id-new (&rest _)
  "Return a lowercase v4 UUID, using `uuid.el'.
Org 9.8.7 still builds UUIDs by forking `org-id-uuid-program',
which on macOS returns uppercase; `org-id-locations' is an
`equal'-test hash table and every migrated ID is lowercase.
`uuid-v4' returns a struct, hence `uuid-to-string'."
  (uuid-to-string (uuid-v4)))

(use-package org-id
  :straight nil
  :after org
  :init
  (setq org-id-locations-file
        (expand-file-name "org-id-locations.eld" (vulpea-config--cache-dir)))
  :config
  (require 'uuid)
  (advice-add 'org-id-new :override #'vulpea-config-org-id-new))

(use-package org-attach
  :straight nil
  :after org
  :init
  (setq org-attach-id-dir vulpea-config-attach-directory
        ;; Attach by ID rather than by an explicit :DIR: property, so a note's
        ;; attachments follow it through renames and moves.
        org-attach-preferred-new-method 'id))

;; Cross-note attachment links.  Stock `attachment:' carries only a filename,
;; which `org-attach-expand' resolves against the *current* node, so there is no
;; syntax for another note's attachment.  This adds "attachment:<uuid>/file",
;; discriminated by a leading UUID and resolved through the target's :ID:, so it
;; survives renaming and moving that note.  The converter emits 51 of them.
;;
;; `org-attach-expand' is the choke point shared by following
;; (`org-attach-follow'), inline preview (`org-attach-preview-file') and export
;; (`org-attach-expand-links'), so advising it covers all three.  The UUID
;; pattern is not version-specific — the vault carries both v4 and v5 — and a
;; filename that merely contains a UUID stays local, since the discriminator is
;; a UUID followed by "/" as the leading path component.

(defconst vulpea-config-crossref-regexp
  (rx bos (group (= 8 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 4 hex) "-" (= 12 hex))
      "/" (group (+ nonl)) eos)
  "Match \"UUID/relative/path\" in an `attachment:' link path.")

(defun vulpea-config-attach-expand (orig file)
  "Expand FILE, treating a leading UUID as another note's attachment.
ORIG is the stock `org-attach-expand', used for every other path."
  (if (string-match vulpea-config-crossref-regexp file)
      (let ((id (match-string 1 file))
            (rest (match-string 2 file)))
        (expand-file-name rest (org-attach-dir-from-id id)))
    (funcall orig file)))

(advice-add 'org-attach-expand :around #'vulpea-config-attach-expand)

(defun vulpea-config-register-ids (path status _count)
  "Register the IDs vulpea just indexed in PATH with `org-id'.

Added to `vulpea-db-worker-done-functions', which vulpea's file watcher
runs after indexing a file, so a note arriving from outside Emacs becomes
followable by `[[id:…]]' without a manual scan.  STATUS is `applied' when
notes were written; the other statuses (`unchanged', `stale', `requeued',
`missing', `error') mean there is nothing new to register.

The IDs come from vulpea's own database rather than from re-parsing the
file — it has just extracted them.  `org-id-add-location' is a single
`puthash'; `org-id-update-id-locations' is not usable here because it
clears `org-id-locations' and rescans every known file."
  (when (eq status 'applied)
    (dolist (note (vulpea-db-query-by-file-path path))
      (org-id-add-location (vulpea-note-id note) path))))

(use-package vulpea
  :straight (vulpea :type git :host github :repo "d12frosted/vulpea")
  :after org
  :bind (("C-c n f" . vulpea-find)
         ("C-c n i" . vulpea-insert)
         ("C-c n b" . vulpea-find-backlink))
  :init
  ;; Note the exact names.  `vulpea-directory' and `vulpea-db-file' are NOT
  ;; vulpea variables — the first survives only in a commented example in
  ;; vulpea.el's header, the second never existed.  Setting them does nothing
  ;; but create globals, leaving vulpea on its defaults: the database in
  ;; `user-emacs-directory' and the watch list at `org-directory' (~/org),
  ;; which is wider than this vault.
  (make-directory vulpea-config-state-directory t)
  (setq vulpea-db-sync-directories (list vulpea-config-notes-directory)
        vulpea-db-location (expand-file-name "vulpea.db" vulpea-config-state-directory)
        ;; Parse in one reused buffer without re-running `org-mode' per file.
        ;; The default `temp-buffer' re-runs it WITH hooks, so a full scan fires
        ;; `org-mode-hook' once per note — here that means `org-appear-mode',
        ;; the latex-to-svg setup, and lsp-ltex-plus trying to attach to a
        ;; buffer that is not visiting a file, 1000 times over.
        ;;
        ;; Safe for these notes: vulpea reads `#+filetags:' from the parsed
        ;; syntax tree rather than from `org-file-tags' (which mode init would
        ;; set), no note uses per-file `#+TODO:', `#+PROPERTY:', `#+TAGS:',
        ;; `#+SETUPFILE:' or `:DIR:', and `org-attach-id-dir' is global.
        vulpea-db-parse-method 'single-temp-buffer)
  :config
  (add-hook 'vulpea-db-worker-done-functions #'vulpea-config-register-ids)
  ;; Watch the tree and index in the background.  Guarded so a missing tree
  ;; degrades to "vulpea installed but idle" instead of erroring at startup —
  ;; the conversion may not have been run yet.
  (if (file-directory-p vulpea-config-notes-directory)
      (vulpea-db-autosync-mode +1)
    (message "vulpea: %s does not exist yet; autosync not started"
             vulpea-config-notes-directory)))

;; Vault utilities live in vulpea-vault/, one concern per file, loaded from here
;; the way `completion.el' loads completions/.
(emacs-config-load-module
 "vulpea-vault/modified-keyword"
 "Could not load vulpea-vault/modified-keyword.el; #+modified: will not refresh on save.")

(emacs-config-load-module
 "vulpea-vault/tags"
 "Could not load vulpea-vault/tags.el; the vault's tag groups will not be in effect.")

(emacs-config-load-module
 "vulpea-vault/create"
 "Could not load vulpea-vault/create.el; new notes will use vulpea's own defaults.")

(emacs-config-load-module
 "vulpea-vault/attachments"
 "Could not load vulpea-vault/attachments.el; `vulpea-vault-orphans' is unavailable.")

(emacs-config-load-module
 "vulpea-vault/bibdesk"
 "Could not load vulpea-vault/bibdesk.el; x-bdsk: links will not open.")

(emacs-config-load-module
 "vulpea-vault/pdffile"
 "Could not load vulpea-vault/pdffile.el; pdffile: links will not open.")

(emacs-config-load-module
 "vulpea-vault/message"
 "Could not load vulpea-vault/message.el; message: links will not open.")

(provide 'vulpea-config)
;;; vulpea-config.el ends here
