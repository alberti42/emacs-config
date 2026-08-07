;;; git.el --- Per-save history for the vault's notes -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; A backup answers "get it back"; this answers "what did I change".  The two
;; are different questions, and duplicacy only does the first well — it holds
;; hourly snapshots of the whole tree, but reading what moved between two of
;; them means diffing snapshots from a shell.
;;
;; So the notes are a git repository, and every save is recorded in it without
;; anyone writing a commit.  Magit's work-in-progress refs do that: each save
;; is committed to `refs/wip/wtree/refs/heads/<branch>', an ordinary git ref
;; that simply is not a branch, so `git log' and Magit's own log show nothing
;; unusual.  The commits are made with `git commit-tree' — plumbing, no
;; invention.
;;
;; Every six hours a launchd agent (`etc/goodies/notes-git-rollup.sh') commits
;; whatever the working tree holds to the branch and deletes the WIP ref.  The
;; history is then four readable commits a day, while the last few hours stay
;; available save by save.  Older detail is discarded on purpose: it is the
;; price of a log a human can skim.
;;
;; Scoped to the vault deliberately.  `magit-wip-mode' is global and would
;; record a save in every repository on this machine, this configuration's own
;; included; here the save hooks are added buffer-locally, and only to files
;; living under the open vault.
;;
;; A note has to be tracked before its saves are recorded — `magit-wip' checks
;; `magit-file-tracked-p'.  A newly created note therefore has no per-save
;; history until the next rollup, whose `git add -A' picks it up.

;;; Code:

(declare-function magit-wip-commit-buffer-file "magit-wip")
(declare-function magit-wip-commit-initial-backup "magit-wip")
(declare-function magit-wip-log-current "magit-wip")

(defun vulpea-vault-git--vault-file-p ()
  "Non-nil when this buffer visits a file inside the open vault."
  (and buffer-file-name
       vulpea-config-notes-directory
       (file-in-directory-p buffer-file-name vulpea-config-notes-directory)))

(defun vulpea-vault-git-setup ()
  "Record this buffer's saves on the vault's work-in-progress ref.

Two hooks, both buffer-local: one commits the file as it was before the
first change of the session, the other commits it after every save.  The
first is what lets you recover the state you started from, which no
number of later saves can reconstruct.

Loading `magit-wip' here rather than at startup keeps Magit out of the
boot path; the first note opened pays for it."
  (when (vulpea-vault-git--vault-file-p)
    (require 'magit-wip)
    (add-hook 'before-save-hook #'magit-wip-commit-initial-backup nil t)
    (add-hook 'after-save-hook #'magit-wip-commit-buffer-file nil t)))

(add-hook 'find-file-hook #'vulpea-vault-git-setup)

;;;###autoload
(defun vulpea-vault-log-saves ()
  "Show the vault's history with every individual save woven into it.

The rolled-up commits on the branch and the per-save commits on the
work-in-progress ref appear in one log, so a day's commit sits directly
above the saves that produced it.  Ordinary Magit from there: RET on a
commit for its diff.

A prefix argument is passed through to `magit-wip-log-current', where a
negative value shows the saves alone."
  (interactive)
  (require 'magit-wip)
  (let ((default-directory (vulpea-config-vault-or-error)))
    (unless (file-directory-p (expand-file-name ".git" default-directory))
      (user-error "%s is not a git repository; nothing records its saves"
                  (abbreviate-file-name default-directory)))
    (call-interactively #'magit-wip-log-current)))

(keymap-global-set "C-c n l" #'vulpea-vault-log-saves)

(provide 'vulpea-vault-git)
;;; git.el ends here
