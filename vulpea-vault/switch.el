;;; switch.el --- Open a different vault without restarting -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; A vault is not one setting but six, and three of them belong to other
;; packages: `org-attach' reads `org-attach-id-dir', vulpea reads
;; `vulpea-db-sync-directories' and opens its database from
;; `vulpea-db-location' as it finds it.  Reassigning them mid-session is not
;; enough — the old database stays open at the old path and the file watcher
;; goes on watching the tree you have left.
;;
;; `vulpea-vault-switch' does the whole sequence: stop the watcher, close the
;; database, re-point everything through `vulpea-config-apply-vault', start
;; the watcher again.  vulpea reopens the database lazily at the new location
;; and scans the new tree, so a vault opened for the first time indexes
;; itself.
;;
;; Nothing about the vaults themselves lives here, nor anywhere else in this
;; configuration.  Which vaults exist is `vulpea-vault-history', the ones that
;; have been opened; where the rest are is answered by typing a path the once.
;; What a vault contains it says itself, in its own `.dir-locals.el'.
;;
;; The vault being left is closed as well as unhooked: its notes and any dired
;; listing of it are killed, after `save-some-buffers' has offered to save
;; whatever was modified.  This is not tidiness.  A buffer's directory-locals
;; were applied when it was visited, so it would keep its own vault's tags and
;; templates — correct, and harmless.  `org-attach-id-dir' is a single global
;; with no per-buffer form, so it cannot do the same: an `attachment:' link
;; followed in a note left open from the old vault would resolve against the
;; new vault's store and quietly find nothing.  Closing the buffers is what
;; keeps that from being possible.

;;; Code:

(require 'seq)
(require 'vulpea-vault-scheme)

(defvar vulpea-vault-history nil
  "Vault roots opened in this Emacs, most recently opened first.

Grown by `vulpea-vault-switch' and offered back by it, the way
`project.el' offers the projects you have visited: a vault reached once
by typing its path need not be typed again.

This is the whole of what Emacs knows about which vaults exist — no
directory is named in the configuration — and it is also what
`vulpea-config--initial-vault' resumes at startup.

Persisted across sessions through `savehist' — the list is registered in
`savehist-additional-variables' below — and truncated to
`history-length' like any other history.")

(with-eval-after-load 'savehist
  (add-to-list 'savehist-additional-variables 'vulpea-vault-history))

(defconst vulpea-vault-choose-directory "... (choose a directory)"
  "Entry standing for a vault that is not in the list.
Worded as `project.el' words the same escape, since it is the same
gesture and there is nothing to gain by spelling it differently.")

(defun vulpea-vault--candidates ()
  "Return the vaults to offer, most recently opened first.

`vulpea-vault-history' in its own order, which is by use; the active
vault last, where it is out of the way but still says where you are; and
the escape to any other directory at the very end.

A remembered entry that is not a vault right now is left out of the
prompt rather than dropped from the history — whether because its
directory has gone (a volume not mounted is not gone, and comes back on
its own) or because it no longer declares a `vulpea-vault-version' (a
`.dir-locals.el' edited or removed).  `vulpea-vault-p' answers both.

The first time of all, the list is the escape alone: nothing has been
opened yet and nothing is configured, so there is nothing else to say."
  (let ((known (delete-dups
                (mapcar (lambda (d) (file-name-as-directory (expand-file-name d)))
                        vulpea-vault-history))))
    (append (seq-filter (lambda (d)
                          (and (not (equal d vulpea-config-notes-directory))
                               (vulpea-vault-p d)))
                        known)
            (delq nil (list vulpea-config-notes-directory
                            vulpea-vault-choose-directory)))))

(defun vulpea-vault--read ()
  "Prompt for a vault among those known, or for any other directory."
  (let* ((candidates (vulpea-vault--candidates))
         (choice (completing-read "Vault: " candidates nil t nil nil
                                  (car candidates))))
    (if (equal choice vulpea-vault-choose-directory)
        (read-directory-name "Vault directory: " nil nil t)
      choice)))

(defun vulpea-vault--buffers (root)
  "Return the buffers belonging to the vault at ROOT.
Both notes being visited and any dired listing of its directories —
each of them a window onto the vault being left."
  (seq-filter
   (lambda (buffer)
     (when-let* ((file (or (buffer-file-name buffer)
                           (with-current-buffer buffer
                             (and (derived-mode-p 'dired-mode)
                                  (expand-file-name default-directory))))))
       (file-in-directory-p file root)))
   (buffer-list)))

(defun vulpea-vault--close-buffers (root)
  "Close every buffer belonging to the vault at ROOT; return how many.

Modified notes are offered for saving first, `save-some-buffers' doing
the asking.  Declining leaves `kill-buffer' to ask again before losing
anything, which is the bargain any other kill makes."
  (let ((buffers (vulpea-vault--buffers root)))
    (when buffers
      (save-some-buffers nil (lambda () (memq (current-buffer) buffers)))
      (mapc #'kill-buffer buffers))
    (seq-count (lambda (b) (not (buffer-live-p b))) buffers)))

;;;###autoload
(defun vulpea-vault-switch (root)
  "Make ROOT the vault in use, without restarting Emacs.

Interactively, offer the vaults opened before, with
`vulpea-vault-choose-directory' for any other.  A vault opened by that
route is remembered in `vulpea-vault-history', so it is offered from
then on and resumed at the next startup — being opened is the whole of
how a vault becomes known.

A directory that declares no `vulpea-vault-version' in its
`.dir-locals.el' is refused: it is not a vault, and opening one as a
vault by mistake is the error this guards against.

A vault with no index yet is scanned in the background, so the switch
returns before its notes are findable."
  (interactive (list (vulpea-vault--read)))
  (let ((root (file-name-as-directory (expand-file-name root))))
    (unless (file-directory-p root)
      (user-error "Not a directory: %s" root))
    (when (equal root vulpea-config-notes-directory)
      (user-error "Already in %s" root))
    ;; The declaration is the whole of what makes a vault, and an explicit
    ;; switch is the one path with no other signal that a directory is one:
    ;; the `find-file-hook' guard keys off the per-buffer `vulpea-vault-version'
    ;; a note's own directory-locals set, but a directory chosen by hand has
    ;; only its `.dir-locals.el' to vouch for it.  Refuse when it does not,
    ;; rather than opening an ordinary directory as a vault by mistake.
    (let ((version (vulpea-vault-version-at root)))
      (unless version
        (user-error
         "Not a vulpea vault: %s declares no `vulpea-vault-version' in .dir-locals.el"
         (abbreviate-file-name root)))
      ;; A vault on a scheme these modules do not implement is still a vault;
      ;; warn but proceed, as everywhere else.
      (vulpea-vault-version-check version root))
    (let (;; With no vault open there was nothing to watch, so the watcher
          ;; being off says nothing about whether it is wanted — only a vault
          ;; left with it deliberately off keeps it off.
          (watching (or vulpea-db-autosync-mode (null vulpea-config-notes-directory)))
          ;; Closed before re-pointing, while this still names the vault being
          ;; left — and before the watcher stops, so a save made here is still
          ;; picked up by the index it belongs to.
          (closed (if vulpea-config-notes-directory
                      (vulpea-vault--close-buffers vulpea-config-notes-directory)
                    0)))
      (when watching (vulpea-db-autosync-mode -1))
      (vulpea-db-close)
      (vulpea-config-apply-vault root)
      (when watching (vulpea-db-autosync-mode +1))
      ;; Register whatever the new vault's index already holds.  A vault
      ;; indexed on a previous visit reports every file unchanged, so the hook
      ;; that normally feeds `org-id' stays quiet and `[[id:…]]' links would
      ;; fail until something re-scanned; a vault being indexed for the first
      ;; time has nothing here yet and is covered by that hook instead.
      (vulpea-config-update-id-locations)
      ;; Recorded only once the switch has gone through, so a directory that
      ;; turned out not to be openable is not offered again.  The binding is
      ;; what makes `add-to-history' move an already-known vault to the front
      ;; instead of listing it twice; the variable is nil by default.
      (let ((history-delete-duplicates t))
        (add-to-history 'vulpea-vault-history root))
      (message "Vault: %s — %d buffer%s closed"
               (abbreviate-file-name root) closed (if (= closed 1) "" "s")))))

;;;; Opening a note from a vault that is not the active one

(defun vulpea-vault--buffer-vault ()
  "Return the root of the vault this buffer's file belongs to, or nil.

The vault declared itself with `vulpea-vault-version', which the
directory-locals have already applied here, so the question costs no
file reading; and the answer does not depend on which vault happens to
be active, since where a file sits is not a matter of opinion.

A vault from a scheme these modules do not implement is still a vault,
and is treated as one — the warning has been given, and refusing to see
it would help nobody."
  (when (and buffer-file-name vulpea-vault-version)
    (when-let* ((root (locate-dominating-file default-directory dir-locals-file))
                (root (file-name-as-directory (expand-file-name root))))
      (vulpea-vault-version-check vulpea-vault-version root)
      root)))

(defun vulpea-vault-check-buffer ()
  "Offer to activate this note's vault when it is not the active one.

Reading a note from an inactive vault mostly works — its tags and
templates come from its own directory-locals — but `org-attach-id-dir'
is a single global, so every `attachment:' link in it resolves against
the active vault's store and finds nothing.  That failure is silent,
which is why this asks rather than letting it happen.

Run from `find-file-hook', after directory-locals have been applied.
With no vault active the note's own is simply opened; there is nothing
to weigh up."
  (when (derived-mode-p 'org-mode)
    (when-let* ((vault (vulpea-vault--buffer-vault)))
      (unless (equal vault vulpea-config-notes-directory)
        (if (null vulpea-config-notes-directory)
            (vulpea-vault-switch vault)
          (pcase (car (read-multiple-choice
                       (format "%s belongs to vault %s, not the active %s"
                               (file-name-nondirectory buffer-file-name)
                               (abbreviate-file-name vault)
                               (abbreviate-file-name vulpea-config-notes-directory))
                       '((?s "switch" "Activate that vault, closing this one's buffers")
                         (?o "open anyway" "Read it as it is; attachment: links will not resolve")
                         (?c "cancel" "Do not open the file"))))
            (?s (vulpea-vault-switch vault))
            (?c (let ((name buffer-file-name))
                  ;; Killed before signalling, so `find-file' has nothing left
                  ;; to display and no half-visited buffer is left behind.
                  (set-buffer-modified-p nil)
                  (kill-buffer)
                  (user-error "Not opened: %s" (abbreviate-file-name name))))
            (_ nil)))))))

(add-hook 'find-file-hook #'vulpea-vault-check-buffer)

(provide 'vulpea-vault-switch)
;;; switch.el ends here
