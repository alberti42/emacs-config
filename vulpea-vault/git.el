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
;; moved on, silently and forever.  The timer reads the set of vaults opened in
;; this Emacs at each tick (`vulpea-vault-git--known-vaults'), so it follows
;; whatever has been opened and backs each one up in turn.
;;
;; Backup is not scoped to the one active vault: a note edited in another vault
;; belongs to that vault's own git repository and is worth recording all the
;; same.  Every vault opened in this Emacs is rolled up, each on its own repo —
;; the single-active-vault limit is vulpea's database, not git's, and git has
;; no such limit.  See docs/modules/vulpea-config.md "Multiple vaults".
;;
;; It ticks far more often than it acts.  Six hours is not something a timer
;; can be trusted to measure — Emacs restarts, and a repeating timer restarts
;; its clock with it — so the interval is decided by the script from the age
;; of HEAD.  Rollups are the only thing that commits, which makes HEAD's
;; timestamp the record of when the last one happened: nothing to persist,
;; right per repository, and right after a week with Emacs closed.
;;
;; Scoped to the vaults deliberately.  `magit-wip-mode' is global and would
;; record a save in every repository on this machine, this configuration's own
;; included; here the save hooks are added buffer-locally, and only to files
;; living under a vault opened in this Emacs.  `magit-wip' records to whichever
;; repository the file lives in, so a note from any vault is recorded on that
;; vault's own ref with no further arrangement — each vault being its own repo.
;;
;; A note has to be tracked before its saves are recorded — `magit-wip' checks
;; `magit-file-tracked-p'.  A newly created note therefore has no per-save
;; history until the next rollup, whose `git add -A' picks it up.

;;; Code:

(require 'seq)
;; For `vulpea-vault-root': the roots below are compared with `equal' and folded
;; with `delete-dups', so they must carry the one spelling it defines.
(require 'vulpea-vault-scheme)

(declare-function magit-wip-commit-buffer-file "magit-wip")
(declare-function magit-wip-commit-initial-backup "magit-wip")
(declare-function magit-wip-log-current "magit-wip")

(defun vulpea-vault-git--known-vaults ()
  "Return the vault roots whose saves are recorded and rolled up.

The vaults opened in this Emacs — `vulpea-vault-history', persisted
across sessions by savehist — plus the active one, deduplicated and
expanded.  Not scoped to the single active vault, because backup is not:
each vault is its own git repository, `magit-wip' records to whichever
one a note lives in, and the rollup timer folds each in turn.  The
single-active-vault limit is vulpea's database, which git does not share.

`vulpea-vault-history' belongs to `vulpea-vault/switch.el', loaded before
this file; `bound-and-true-p' guards the case of this module loaded on
its own."
  (delete-dups
   (mapcar #'vulpea-vault-root
           (append (and vulpea-config-notes-directory
                        (list vulpea-config-notes-directory))
                   (bound-and-true-p vulpea-vault-history)))))

(defun vulpea-vault-git--vault-file-p ()
  "Non-nil when this buffer visits a file inside a known vault.
Any vault opened in this Emacs, not only the active one — see
`vulpea-vault-git--known-vaults'."
  (and buffer-file-name
       (seq-some (lambda (root)
                   (file-in-directory-p buffer-file-name root))
                 (vulpea-vault-git--known-vaults))))

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

(defcustom vulpea-vault-git-push-stale-days 3
  "Days commits may sit unpushed before that is worth a warning.

Skipping a push for want of a network is silent, which is right for an
afternoon and wrong for a fortnight — a credential that has expired, or
a reachability check that has stopped working, would otherwise go
unnoticed for as long as nobody thought to look at the remote.  Counted
from the earliest commit still waiting."
  :type 'natnum
  :group 'vulpea)

(defcustom vulpea-vault-git-rollup-environment nil
  "Extra environment for the rollup subprocess.

Either a list of \"NAME=VALUE\" strings or a function of no arguments
returning such a list, prepended to `process-environment' for the git
the rollup runs — and so for its push.

This is the seam for pushing without an interactive credential.  The
rollup fires unattended all day; if the remote authenticates over SSH
through a GUI agent — a 1Password prompt, a passphrase dialog — every
push wakes it.  Point git at an HTTPS remote and a token here instead
and the push goes out silently.  A function is resolved at each rollup,
so a credential read from a file is read fresh rather than baked in at
load time.

Nothing host- or vault-specific belongs in this module: the mapping from
a remote to a credential is supplied from outside, in the user's own
configuration."
  :type '(choice (repeat string) function)
  :group 'vulpea)

(defun vulpea-vault-git--rollup-environment ()
  "Resolve `vulpea-vault-git-rollup-environment' to a list of strings."
  (if (functionp vulpea-vault-git-rollup-environment)
      (funcall vulpea-vault-git-rollup-environment)
    vulpea-vault-git-rollup-environment))

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

(defun vulpea-vault-git--rollup-run (script root now)
  "Run the rollup SCRIPT on the vault at ROOT; NOW waives the interval.

Asynchronous: the rollup writes objects and nothing in Emacs waits for
it.  Success says nothing, since this fires unattended all day; a failure
is warned about, naming ROOT since several vaults may be rolled up at
once.  Being off the network is not a failure — the script establishes
that before pushing and skips silently, so what reaches here is a fault
worth interrupting for."
  (let ((buffer (get-buffer-create
                 (format " *notes-git-rollup:%s*" (abbreviate-file-name root))))
        ;; Applied to the whole subprocess, of which the push is the only
        ;; part that touches the network and so the only part that needs a
        ;; credential; the rest ignores it.  Local to this process — the
        ;; interactive remote is left exactly as it is on disk.  The mapping
        ;; only rewrites the one remote it names, so it is harmless on a vault
        ;; whose remote it does not match.
        (process-environment (append (vulpea-vault-git--rollup-environment)
                                     process-environment)))
    (with-current-buffer buffer (erase-buffer))
    (make-process
     :name "notes-git-rollup"
     :buffer buffer
     :noquery t
     :command (list script root
                    (number-to-string
                     (if now 0 vulpea-vault-git-rollup-interval))
                    (number-to-string vulpea-vault-git-push-stale-days))
     :sentinel
     (lambda (process _event)
       (when (and (eq (process-status process) 'exit)
                  (/= (process-exit-status process) 0))
         ;; The script says what went wrong, in its own words — a push that
         ;; git refused, or a backlog that has waited too long.  Repeating
         ;; it verbatim beats wrapping it in a sentence that guesses which.
         (let ((output (with-current-buffer (process-buffer process)
                         (string-trim (buffer-string)))))
           (lwarn 'vulpea-vault :error "%s: %s"
                  (abbreviate-file-name root)
                  (if (string-empty-p output)
                      (format "notes-git-rollup exited %s and said nothing"
                              (process-exit-status process))
                    output))))))))

(defun vulpea-vault-git-rollup (&optional now)
  "Fold each known vault's saves into one commit, wherever one is due.

Every vault opened in this Emacs (`vulpea-vault-git--known-vaults') that
is a git repository is rolled up in turn, so a note edited in a vault
other than the active one is backed up all the same — each on its own
repository.

Due is the script's decision per repository, from the age of HEAD
against `vulpea-vault-git-rollup-interval'.  With NOW non-nil the
interval is waived and anything uncommitted is committed at once.  Called
interactively NOW is always t: asking for a rollup by hand is an explicit
“do it now”, not a request gated on the interval — that gate is for the
unattended timer, which calls with no arguments."
  (interactive (list t))
  (when-let* ((script (vulpea-vault-git--rollup-script)))
    (dolist (root (vulpea-vault-git--known-vaults))
      (when (file-directory-p (expand-file-name ".git" root))
        (vulpea-vault-git--rollup-run script root now)))))

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
