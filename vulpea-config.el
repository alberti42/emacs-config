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
(require 'seq)

(defvar vulpea-config-notes-directory nil
  "Root of the vault currently in use, or nil when none is open.

Assigned by `vulpea-config-apply-vault'; do not set it directly, since
everything below derives from it.  Must match DEFAULT_OUT in
`etc/goodies/obsidian-to-org.py' for a converted tree.

Nil is an ordinary state, not a broken one — an Emacs started before any
vault has been opened.  Code that only wants to know where it is tests
this and carries on; a command that cannot proceed without a vault says
so through `vulpea-config-vault-or-error'.")

(defvar vulpea-config-state-directory nil
  "Per-vault state, kept inside the vault rather than in a global cache.
The index then belongs to the vault and travels with it, which is what
makes a second vault a matter of pointing at it.

Safe to keep here: vulpea's scanner skips hidden directories — anything
whose path contains \"/.\" — so it neither indexes nor watches its own
state, and writing the database cannot retrigger a sync.")

(defvar vulpea-config-attach-directory nil
  "Central org-attach store, matching the converter's --attach-dir.
Must stay in sync with it: `org-attach' derives a note's directory
from this path plus its `:ID:', so a mismatch silently yields an
empty attachment directory rather than an error.")

(defun vulpea-config-apply-vault (root)
  "Point every vault-derived setting at ROOT, and return it.

Assignment only — no database is opened and no watcher is touched — so
it is as safe to run at load time as it is mid-session.  Switching a
running Emacs needs the teardown and restart around it that
`vulpea-vault-switch' supplies.

The settings it owns are the reason a vault cannot simply be re-pointed
by hand: three of them belong to other packages, `org-attach' and vulpea
read plain values, and vulpea opens its database from
`vulpea-db-location' as it finds it."
  (setq vulpea-config-notes-directory (file-name-as-directory (expand-file-name root))
        vulpea-config-state-directory (expand-file-name
                                       ".vulpea/" vulpea-config-notes-directory)
        vulpea-config-attach-directory (expand-file-name
                                        "data/" vulpea-config-notes-directory)
        org-attach-id-dir vulpea-config-attach-directory
        vulpea-db-sync-directories (list vulpea-config-notes-directory)
        vulpea-db-location (expand-file-name "vulpea.db" vulpea-config-state-directory))
  (make-directory vulpea-config-state-directory t)
  vulpea-config-notes-directory)

(defun vulpea-config-vault-or-error ()
  "Return the active vault root, or say that there is none.
For the commands that are meaningless without one — where nil would
otherwise travel a long way before failing as a wrong argument type."
  (or vulpea-config-notes-directory
      (user-error "No vault is open; `vulpea-vault-switch' opens one")))

(defun vulpea-config--initial-vault ()
  "Return the vault to resume at startup, or nil when there is none.

The one opened last, which is the only vault this configuration knows of
— no directory is named anywhere in it, since a vault is not something
Emacs has to be told about in advance.  Opening one is what makes it
known, and `vulpea-vault-history' is where that is kept.

That list belongs to `vulpea-vault/switch.el', which is loaded at the
foot of this file and so has not run yet — but savehist restored it by
plain `setq' when `savehist-mode' started, long before this file was
reached, hence `bound-and-true-p' rather than a reference to a variable
that may simply not exist yet.

The history is walked rather than merely read: a vault whose directory
is not there right now is skipped in favour of the one visited before
it, which is what makes an unmounted volume a reason to open something
else instead of a reason to fail."
  (seq-find (lambda (d) (file-directory-p (expand-file-name d)))
            (bound-and-true-p vulpea-vault-history)))

;; Before the `use-package' forms below, so their `:init' blocks and every
;; module loaded from here see the vault already in place.  Setting a defcustom
;; a package has not defined yet is what those blocks were doing anyway:
;; `defcustom' keeps a value that is already bound.
(when-let* ((root (vulpea-config--initial-vault)))
  (vulpea-config-apply-vault root))

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
  (let* ((vault (vulpea-config-vault-or-error))
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
  ;; `org-attach-id-dir' is set by `vulpea-config-apply-vault', which follows
  ;; the vault.  Attach by ID rather than by an explicit :DIR: property, so a
  ;; note's attachments follow it through renames and moves.
  (setq org-attach-preferred-new-method 'id))

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
  ;; `vulpea-db-sync-directories' and `vulpea-db-location' are set by
  ;; `vulpea-config-apply-vault', which follows the vault.  Note their exact
  ;; names: `vulpea-directory' and `vulpea-db-file' are NOT vulpea variables —
  ;; the first survives only in a commented example in vulpea.el's header, the
  ;; second never existed.  Setting those does nothing but create globals,
  ;; leaving vulpea on its defaults: the database in `user-emacs-directory'
  ;; and the watch list at `org-directory' (~/org), wider than any one vault.
  (setq ;; Parse in one reused buffer without re-running `org-mode' per file.
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
  ;; Watch the tree and index in the background.  Guarded twice over, so both
  ;; "no vault opened yet" and "a vault whose tree is not there" degrade to
  ;; "vulpea installed but idle" rather than erroring at startup.
  ;; `vulpea-vault-switch' starts the watcher when a vault is opened later.
  (cond
   ((null vulpea-config-notes-directory)
    (message "vulpea: no vault open; M-x vulpea-vault-switch opens one"))
   ((file-directory-p vulpea-config-notes-directory)
    (vulpea-db-autosync-mode +1))
   (t
    (message "vulpea: %s does not exist yet; autosync not started"
             vulpea-config-notes-directory))))

;; Vault utilities live in vulpea-vault/, one concern per file, loaded from here
;; the way `completion.el' loads completions/.
(emacs-config-load-module
 "vulpea-vault/modified-keyword"
 "Could not load vulpea-vault/modified-keyword.el; #+modified: will not refresh on save.")

(emacs-config-load-module
 "vulpea-vault/scheme"
 "Could not load vulpea-vault/scheme.el; vaults cannot be recognised as such.")

(emacs-config-load-module
 "vulpea-vault/directories"
 "Could not load vulpea-vault/directories.el; the vault's folder roles are unavailable.")

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

(emacs-config-load-module
 "vulpea-vault/switch"
 "Could not load vulpea-vault/switch.el; `vulpea-vault-switch' is unavailable.")

;; Move the vault actually resumed to the front of the history: when the one
;; opened last was unreachable and an older one was taken instead, that older
;; one is now the last visited.  After the module above, which defines the list.
(when (and vulpea-config-notes-directory (boundp 'vulpea-vault-history))
  (let ((history-delete-duplicates t))
    (add-to-history 'vulpea-vault-history vulpea-config-notes-directory)))

(provide 'vulpea-config)
;;; vulpea-config.el ends here
