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
;; This file is a database layer over *org* notes, so org is a hard dependency,
;; not an optional one.  Requiring it here — rather than leaning on a submodule
;; (`modified-stamp.el', `attachments.el') to pull it in transitively — makes the
;; `:after org' + `:demand t' on the `use-package vulpea' form below fire
;; deterministically as that form is reached, so the vault commands defined in
;; vulpea-vault/ have vulpea's (non-autoloaded) query API available even on a
;; fresh Emacs where no org file has been opened yet.
(require 'org)

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
  "Directory holding this vault's index -- the directory of `vulpea-db-location'.
Inside the vault by default (`<root>/.vulpea/'), so the index belongs to
the vault and travels with it; a vault may point its cache elsewhere
through `vulpea-vault-db-location', and this follows the directory part.

Safe to keep here: vulpea's scanner skips hidden directories — anything
whose path contains \"/.\" — so it neither indexes nor watches its own
state, and writing the database cannot retrigger a sync.")

(defvar vulpea-config-attach-directory nil
  "Central org-attach store, matching the converter's --attach-dir.
Must stay in sync with it: `org-attach' derives a note's directory
from this path plus its `:ID:', so a mismatch silently yields an
empty attachment directory rather than an error.

Absolute; its trailing directory name comes from
`vulpea-vault-data-directory', which a vault may set in its
`.dir-locals.el' — declared, with everything else a vault may say about
itself, in `vulpea-vault/scheme.el'.")

(defun vulpea-config--store-name (value root)
  "Return VALUE, the attachment store the vault at ROOT declares.

Warns when it is absolute and returns it regardless.  A store belongs
inside the vault — it holds content, travels with the notes, and is one
contract with the converter's --attach-dir — so an absolute value is
almost always a mistake; but it is the vault's statement to make, as it is
for `vulpea-vault-db-location', and honouring it is the only behaviour
that cannot surprise.  Falling back to the default would point a live
vault at an empty store instead, which reads as \"every attachment link is
broken\" and says nothing about why.

This is where the preference for a relative store lives, because this is
where it can be said out loud.  `vulpea-vault-data-directory-p' cannot:
a `safe-local-variable' predicate that returns nil makes Emacs discard the
vault's entire `.dir-locals.el' without a word.

Once per `vulpea-config-apply-vault' — startup and each
`vulpea-vault-switch' — not once per note, so it is not deduplicated the
way `vulpea-vault-version-check' is."
  (when (file-name-absolute-p value)
    (lwarn 'vulpea-vault :warning
           "Vault %s puts its attachment store outside itself (%s); \
using it as declared, but a store belongs in the vault"
           (abbreviate-file-name root) value))
  value)

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
  ;; `vulpea-vault-root' for the one spelling every root carries — absolute,
  ;; trailing slash — which the equality tests in `vulpea-vault/switch.el' and
  ;; `vulpea-vault/git.el' depend on, this being where most of them get it.
  (let* ((root (vulpea-vault-root root))
         ;; The store's name and the cache's location are both the vault's to
         ;; choose (declared in `vulpea-vault/scheme.el' as
         ;; `vulpea-vault-data-directory' and `vulpea-vault-db-location'), read
         ;; from the root the same way every other vault-declared variable is.
         ;; Absent, the defaults stand, so a vault that says nothing behaves as
         ;; before.  This is the deriving half of the contract: the scheme says
         ;; what a vault may state, this turns a stated value into the global
         ;; another package reads.
         (declared (with-temp-buffer
                     (setq default-directory root)
                     (hack-dir-local-variables-non-file-buffer)
                     (list (or vulpea-vault-data-directory "data")
                           (or vulpea-vault-db-location "./.vulpea/vulpea.db"))))
         ;; Absolute is admitted and warned about here rather than refused by
         ;; the predicate; see `vulpea-config--store-name'.  The
         ;; `expand-file-name' below needs no branch either way.
         (data (vulpea-config--store-name (nth 0 declared) root))
         ;; A relative value (the default) lands inside the vault; an absolute
         ;; one or a `~'-path is taken as-is.  `expand-file-name' does exactly
         ;; that, so no branch on the shape of the path is needed.
         (db (expand-file-name (nth 1 declared) root)))
    (setq vulpea-config-notes-directory root
          vulpea-config-state-directory (file-name-directory db)
          vulpea-config-attach-directory (expand-file-name
                                          (file-name-as-directory data) root)
          org-attach-id-dir vulpea-config-attach-directory
          vulpea-db-sync-directories (list root)
          vulpea-db-location db))
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

The history is walked rather than merely read: an entry that is not a
vault right now is skipped in favour of the one visited before it —
whether its directory is not there (an unmounted volume is a reason to
open something else, not to fail) or it no longer declares a
`vulpea-vault-version' (a `.dir-locals.el' edited away, or an ordinary
directory that slipped into the history before switching learned to
refuse one).  `vulpea-vault-p' answers both, guarded by `fboundp' since
it is not certain the scheme module loaded."
  (seq-find (lambda (d)
              (let ((dir (expand-file-name d)))
                (if (fboundp 'vulpea-vault-p)
                    (vulpea-vault-p dir)
                  (file-directory-p dir))))
            (bound-and-true-p vulpea-vault-history)))

;; The scheme module holds every variable a vault may declare, so it must be
;; loaded before anything reads a vault's `.dir-locals.el': a
;; `safe-local-variable' predicate has to be attached to a symbol before the
;; value is read, or the read prompts (or is discarded).  Both readers below run
;; at load time — `vulpea-config--initial-vault' asks `vulpea-vault-p', and
;; `vulpea-config-apply-vault' reads the store name and cache location — hence
;; here rather than with its siblings at the foot of the file.  It is
;; declarations and recognition only, requiring no other module of ours and
;; nothing of org, so loading it early is safe; the siblings that need it
;; `require' it and find it already provided.
(emacs-config-load-module
 "vulpea-vault/scheme"
 "Could not load vulpea-vault/scheme.el; vaults cannot be recognised as such.")

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
  (setq org-attach-preferred-new-method 'id)
  ;; One store per *note*, not per heading.  A converted note carries its :ID:
  ;; in the file-level property drawer, while its `attachment:' links sit under
  ;; whatever heading the text put them ("* Program", "* Slides", …).  With the
  ;; default `selective' -- and `org-use-property-inheritance' nil, as it is
  ;; here -- `org-attach-dir' looks only at the entry at point, finds no ID,
  ;; returns nil, and `org-attach-expand' falls back to resolving the filename
  ;; against the note's own directory: "No such file: <vault>/08 Conferences/
  ;; <attachment>.pdf".  `t' lets the search walk up to the file level, which
  ;; is where the key lives.  It also makes `org-attach' add new files to that
  ;; same store instead of minting an ID for the heading at point.
  (setq org-attach-use-inheritance t))

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
  ;; Load eagerly (org is required at the top of this file, so this fires as the
  ;; form is reached) rather than deferring to the first `:bind' command.  The
  ;; vault commands defined in vulpea-vault/ (e.g. `vulpea-vault-orphans',
  ;; `vulpea-config-update-id-locations') call the query API in
  ;; `vulpea-db-query.el' directly, and those functions are NOT autoloaded (the
  ;; build emits only `register-definition-prefixes').  A lazy vulpea would
  ;; leave them void until a `:bind' command happened to load the package.
  ;; `require'-ing vulpea pulls in `vulpea-db-query' transitively (through
  ;; `vulpea-buffer'), so demanding it here makes the whole query API present.
  :demand t
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
 "vulpea-vault/modified-stamp"
 "Could not load vulpea-vault/modified-stamp.el; :MODIFIED: will not refresh on save.")

(emacs-config-load-module
 "vulpea-vault/select"
 "Could not load vulpea-vault/select.el; note selection will show no dates.")

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

;; After switch.el, whose hooks it joins (and whose feature it requires).
(emacs-config-load-module
 "vulpea-vault/semantic"
 "Could not load vulpea-vault/semantic.el; org-semantic will not follow the vault.")

(emacs-config-load-module
 "vulpea-vault/git"
 "Could not load vulpea-vault/git.el; note saves will not be recorded in git.")

;; Push the vault's rollups over HTTPS with a GitLab token rather than over
;; SSH.  The remote is `git@gitlab.mpcdf.mpg.de:…', which authenticates through
;; the 1Password SSH agent — fine for the occasional interactive push, but the
;; rollup timer would wake it every six hours, unattended.  So only the rollup
;; subprocess rewrites the remote, and only in its own environment: Magit and
;; the shell keep using SSH, and nothing on disk changes.
;;
;; The token lives outside this repository, in the file the shell already
;; sources, and is read fresh at each rollup by `my/env-file-value' — nothing
;; secret is committed and nothing is baked into a variable at load time.  The
;; parser is in utils.el because reading such a file is not a vulpea concern;
;; only knowing which file, and which name in it, is.  `url.<https>.insteadOf'
;; does the rewrite through git's own GIT_CONFIG_* environment protocol, so no
;; on-disk git config is touched either.  This is host-specific and so lives
;; here, not in the (vault-agnostic) git module.
(defun vulpea-config-mpcdf-git-environment ()
  "Environment that pushes the vault to gitlab.mpcdf.mpg.de over HTTPS.
Rewrites the SSH remote to an HTTPS URL carrying an oauth2 token, so the
rollup's push authenticates with the token instead of an SSH key.
Returns nil when no token is available, leaving the push on SSH.

The file is read at each rollup through `my/env-file-value' (utils.el, one
of the plain `KEY=VALUE' files the shell sources), so the token is never
baked into a variable at load time and an absent file simply leaves the
push on SSH.  Called from the rollup timer, long after utils.el is loaded,
so the reference costs no load-order constraint."
  (when-let* ((token (my/env-file-value
                      (expand-file-name "~/.config/envs/gitlab_mpcdf.sh")
                      "GITLAB_MPCDF_TOKEN")))
    (list "GIT_CONFIG_COUNT=1"
          (format
           "GIT_CONFIG_KEY_0=url.https://oauth2:%s@gitlab.mpcdf.mpg.de/.insteadOf"
           token)
          "GIT_CONFIG_VALUE_0=git@gitlab.mpcdf.mpg.de:")))

(with-eval-after-load 'vulpea-vault-git
  (setq vulpea-vault-git-rollup-environment
        #'vulpea-config-mpcdf-git-environment))

;; Move the vault actually resumed to the front of the history: when the one
;; opened last was unreachable and an older one was taken instead, that older
;; one is now the last visited.  After the module above, which defines the list.
(when (and vulpea-config-notes-directory (boundp 'vulpea-vault-history))
  (let ((history-delete-duplicates t))
    (add-to-history 'vulpea-vault-history vulpea-config-notes-directory)))

(provide 'vulpea-config)
;;; vulpea-config.el ends here
