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
;; Every six hours the window is folded into one commit on the branch and the
;; WIP ref is dropped, by `etc/goodies/notes-git-rollup.sh'.  The history is
;; then four readable commits a day, while the last few hours stay available
;; save by save.  Older detail is discarded on purpose: it is the price of a
;; log a human can skim.
;;
;; A timer here drives that, not a launchd agent, because an agent has to name
;; a repository and this configuration names no vault — an agent would go on
;; rolling up the vault it was written for after `vulpea-vault-switch' had
;; moved on, silently and forever.  The timer reads
;; `vulpea-config-notes-directory' at each tick, so it follows the switch.
;;
;; It ticks far more often than it acts.  Six hours is not something a timer
;; can be trusted to measure — Emacs restarts, and a repeating timer restarts
;; its clock with it — so the interval is decided by the script from the age
;; of HEAD.  Rollups are the only thing that commits, which makes HEAD's
;; timestamp the record of when the last one happened: nothing to persist,
;; right per repository, and right after a week with Emacs closed.
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

;;;; Folding the saves into the branch

(defcustom vulpea-vault-git-rollup-interval (* 6 60 60)
  "Seconds a rollup commit covers.
The window of saves folded into one commit — and so, roughly, how many
commits a day of note-taking leaves behind.  Saves made since the last
rollup stay individually available; older ones do not."
  :type 'natnum
  :group 'vulpea)

(defcustom vulpea-vault-git-rollup-check-interval (* 20 60)
  "Seconds between checks for a rollup being due.
Sets how late a rollup can be, not how often one happens: a check with
nothing to do costs one `git log -1', and stops there without reading
the working tree."
  :type 'natnum
  :group 'vulpea)

(defvar vulpea-vault-git--rollup-timer nil
  "The repeating check, so that reloading this file replaces it rather
than adding a second one.")

(defun vulpea-vault-git--rollup-script ()
  "Return the rollup script, or nil with a warning if it is not runnable."
  (let ((script (expand-file-name "etc/goodies/notes-git-rollup.sh"
                                  emacs-config-dir)))
    (cond
     ((not (file-exists-p script))
      (ignore (lwarn 'vulpea-vault :warning "Missing %s; no rollups" script)))
     ((not (file-executable-p script))
      (ignore (lwarn 'vulpea-vault :warning "%s is not executable; no rollups"
                     script)))
     (t script))))

(defun vulpea-vault-git-rollup (&optional now)
  "Fold the vault's saves into one commit, if one is due.

Due is the script's decision, from the age of HEAD against
`vulpea-vault-git-rollup-interval'.  With NOW non-nil (a prefix argument
interactively) the interval is waived and anything uncommitted is
committed at once.

Runs asynchronously: the rollup writes objects, and nothing in Emacs
needs to wait for it.  Failure is reported; success says nothing, since
this fires unattended all day."
  (interactive "P")
  (when-let* ((root vulpea-config-notes-directory)
              ((file-directory-p (expand-file-name ".git" root)))
              (script (vulpea-vault-git--rollup-script)))
    (let ((buffer (get-buffer-create " *notes-git-rollup*")))
      (with-current-buffer buffer (erase-buffer))
      (make-process
       :name "notes-git-rollup"
       :buffer buffer
       :noquery t
       :command (list script root
                      (number-to-string
                       (if now 0 vulpea-vault-git-rollup-interval)))
       :sentinel
       (lambda (process _event)
         (when (and (eq (process-status process) 'exit)
                    (/= (process-exit-status process) 0))
           (lwarn 'vulpea-vault :error "Rollup failed (%s): %s"
                  (process-exit-status process)
                  (with-current-buffer (process-buffer process)
                    (string-trim (buffer-string))))))))))

;; First check a couple of minutes in rather than at load: a vault changed
;; while Emacs was closed should not wait out a whole interval, and startup
;; should not wait for git.
(when (timerp vulpea-vault-git--rollup-timer)
  (cancel-timer vulpea-vault-git--rollup-timer))
(setq vulpea-vault-git--rollup-timer
      (run-with-timer 120 vulpea-vault-git-rollup-check-interval
                      #'vulpea-vault-git-rollup))

;;;; Reading it back

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
