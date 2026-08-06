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
;; Nothing about the vaults themselves lives here.  Which vaults exist is
;; `vulpea-config-vaults', and what each one contains it says itself, in its
;; own `.dir-locals.el'.
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

(defun vulpea-vault--candidates ()
  "Return the known vaults, current one first, as absolute directories."
  (let ((known (mapcar (lambda (d) (file-name-as-directory (expand-file-name d)))
                       vulpea-config-vaults)))
    (append (seq-remove (lambda (d) (equal d vulpea-config-notes-directory)) known)
            (list vulpea-config-notes-directory))))

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

Interactively, offer `vulpea-config-vaults', the current one last; any
other directory may be typed instead, which opens it as a vault without
adding it to that list.

A vault with no index yet is scanned in the background, so the switch
returns before its notes are findable."
  (interactive
   (list (completing-read "Vault: " (vulpea-vault--candidates) nil nil nil nil
                          (car (vulpea-vault--candidates)))))
  (let ((root (file-name-as-directory (expand-file-name root))))
    (unless (file-directory-p root)
      (user-error "Not a directory: %s" root))
    (when (equal root vulpea-config-notes-directory)
      (user-error "Already in %s" root))
    (let ((watching vulpea-db-autosync-mode)
          ;; Closed before re-pointing, while this still names the vault being
          ;; left — and before the watcher stops, so a save made here is still
          ;; picked up by the index it belongs to.
          (closed (vulpea-vault--close-buffers vulpea-config-notes-directory)))
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
      (message "Vault: %s — %d buffer%s closed"
               (abbreviate-file-name root) closed (if (= closed 1) "" "s")))))

(provide 'vulpea-vault-switch)
;;; switch.el ends here
