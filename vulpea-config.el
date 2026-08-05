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
;; - State (the database, `org-id' locations) lives under XDG cache, never in
;;   the notes tree or this git worktree.
;;
;; - Attachment layout must match what the converter emitted: `org-attach' mode
;;   puts everything in one ID-keyed store, mirror mode leaves a
;;   "<note> (attachments)" folder beside each note and uses `file:' links.
;;   Only the former needs `org-attach-id-dir'.

;;; Code:

(defconst vulpea-config-notes-directory
  (expand-file-name "~/Org/Work/")
  "Root of the converted org notes.
The single place to change when the tree moves.  Must match
DEFAULT_OUT in `etc/goodies/obsidian-to-org.py'.")

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
  "Teach `org-id' about every note, so plain `id:' links resolve.
vulpea's own database is separate and always current; this only
feeds `org-id-locations', which `org-open-at-point' consults."
  (interactive)
  (if (not (file-directory-p vulpea-config-notes-directory))
      (user-error "No notes directory at %s" vulpea-config-notes-directory)
    (org-id-update-id-locations
     (directory-files-recursively vulpea-config-notes-directory "\\.org\\'"))))

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

;; Teaches the stock `attachment:' link type a second form,
;; "attachment:<uuid>/file", for referring to another note's attachment.  The
;; converter emits 51 of these; without it they do not resolve.
(emacs-config-load-module
 'org-attach-crossref
 "Could not load org-attach-crossref.el; cross-note attachment: links will not resolve.")

(use-package vulpea
  :straight (vulpea :type git :host github :repo "d12frosted/vulpea")
  :after org
  :bind (("C-c n f" . vulpea-find)
         ("C-c n i" . vulpea-insert)
         ("C-c n b" . vulpea-find-backlink))
  :init
  (setq vulpea-directory vulpea-config-notes-directory
        vulpea-db-file (expand-file-name "vulpea.db" (vulpea-config--cache-dir)))
  :config
  ;; Watch the tree and index in the background.  Guarded so a missing tree
  ;; degrades to "vulpea installed but idle" instead of erroring at startup —
  ;; the conversion may not have been run yet.
  (if (file-directory-p vulpea-directory)
      (vulpea-db-autosync-mode +1)
    (message "vulpea: %s does not exist yet; autosync not started"
             vulpea-directory)))

(provide 'vulpea-config)
;;; vulpea-config.el ends here
