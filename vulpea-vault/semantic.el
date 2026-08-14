;;; semantic.el --- The active vault is the one org-semantic searches -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; vulpea indexes what a note *is* — its `:ID:', its title, its tags, what
;; links to it.  org-semantic indexes what a note *says*, and answers questions
;; put in words that appear nowhere in it.  Two indexes over one tree, and this
;; file is the whole of what they have to agree on: which tree.
;;
;; They agree because a vault root is a vault root.  `.vulpea/' and
;; `.org-semantic/' sit side by side in it, each package owning its own, and
;; neither is told about the other's.  So there is no path to keep in sync
;; here, only a lifetime:
;;
;; - LEAVING.  One org-semantic process holds every vault that has been
;;   searched, and holds it until told otherwise — chunk tables and vectors, a
;;   couple of megabytes for a small vault and about ten for a large one.
;;   `vulpea-vault-switch' is exactly the moment the vault being left stops
;;   being searched, so that is where `close' is sent.  What it buys is a
;;   ceiling rather than a refund: the memory returns on the allocator's own
;;   schedule, so nothing accumulates over a session of switching, but the
;;   number does not fall while you watch it.
;;
;; - ENTERING.  Nothing to open.  The server loads a vault on the first search
;;   against it and shares the embedding model with whatever else it holds, so
;;   an `open' would only pay for a load that may never be wanted.  The enter
;;   hook is used for one thing: saying, once, that the vault has no index yet
;;   — and only when the server is already running, since a vault switch is no
;;   reason to start it.
;;
;; - FINDING.  `org-semantic-vault' asks the buffer where it is, which is right
;;   for a note and answers nothing for `*scratch*', a project file, or an
;;   agenda buffer.  The active vulpea vault is the answer in that case: `C-c
;;   n s' means "search my notes" from wherever it is pressed, exactly as
;;   `C-c n f' does.  A buffer that *is* in an org-semantic vault keeps its
;;   own — the fallback runs only when the question came back empty.
;;
;; - KEEPING UP.  `org-semantic-auto-reindex-mode' hears about a note through
;;   `after-save-hook', which is every change made in this Emacs by editing and
;;   none of the others: a rename or a delete in Dired, a `git pull', a file
;;   arriving from a sync.  vulpea hears about all of them — it watches the
;;   tree with filenotify or fswatch, because its own database has the same
;;   problem — so what it already knows is passed on with
;;   `org-semantic-auto-reindex-touch'.  Two indexes over one tree, one
;;   watcher.
;;
;;   WHICH file changed is not passed on, and does not need to be: a reindex is
;;   a vault-wide incremental scan, so a rename is caught by the arrival of the
;;   new name alone — the same scan finds the old one gone.  That is why the
;;   quieter half of a rename, the removal, is worth catching only for its own
;;   sake, a note deleted and nothing put in its place.
;;
;;   A save is reported by the watcher like any other write, so
;;   `org-semantic-auto-reindex-mode' — whose whole content is an
;;   `after-save-hook' — is left OFF in `org-semantic-config.el'.  It would be
;;   a second signal for the case already covered, and the weaker of the two.
;;   `org-semantic-auto-reindex-touch' is deliberately independent of it.
;;
;; Nothing here loads org-semantic.  Every entry point into it is autoloaded
;; and the advice is installed under `with-eval-after-load', so a session that
;; never searches pays nothing, and a switch in such a session does nothing at
;; all.  The reindex hooks are the one exception in spirit and not in fact:
;; they run on every file vulpea indexes, and do nothing at all until something
;; has loaded org-semantic.  They do not need its `-auto-reindex-mode', which is
;; why that mode can stay off here.
;;
;; - WHEN IT BREAKS.  Two of the three signals are `advice-add' on vulpea's own
;;   functions, and one of those is private.  `advice-add' on a name vulpea has
;;   since renamed succeeds, advises nothing, and reports nothing — so the
;;   deletions, or the edits, would simply stop arriving.  The two checks at the
;;   foot of this file turn that into a warning, since the alternative is an
;;   index that quietly stops being updated and looks exactly like one that is.

;;; Code:

(require 'seq)
(require 'vulpea-vault-core)
(require 'vulpea-vault-switch)

(declare-function org-semantic-canonical-vault "org-semantic" (dir))
(declare-function org-semantic-auto-reindex-touch "org-semantic" (&optional vault))

(defun vulpea-vault-semantic-root (root)
  "Return ROOT spelled as the org-semantic server keys it.

Through `file-truename' and without a trailing slash, which is what
`org-semantic-vault' returns and therefore what a search from inside the
vault was recorded under.  A `close' naming it any other way — the
symlinked path, or with the slash vulpea keeps — closes nothing, and
says so with a cheerful message about zero entries dropped.

Hence NOT `vulpea-vault-root', which is how every other root here is
spelled: absolute, trailing slash, symlinks left alone.  This function is
the boundary between the two spellings, and the only place the truename
one is used.

The spelling itself is org-semantic's to define, so it is asked rather
than reproduced: a copy of those three calls here would go on working
after theirs changed, and the failure is silent — a `close' that drops
nothing.  Only call this once org-semantic is loaded, which every caller
below already checks."
  (org-semantic-canonical-vault root))

(defun vulpea-vault-semantic-close (root)
  "Tell the org-semantic server we are finished with the vault at ROOT.

Silent, and a no-op, when org-semantic was never loaded or its process
is not running: there is then nothing holding an index, and starting a
process in order to tell it to forget something it never had would be
worse than doing nothing."
  (when (and (featurep 'org-semantic)
             (fboundp 'org-semantic-running-p)
             (org-semantic-running-p))
    (ignore-errors
      (org-semantic-close (vulpea-vault-semantic-root root)))))

(defun vulpea-vault-semantic-check (root)
  "Say whether the vault at ROOT has an org-semantic index, when cheap.

Only asked of a server that is already running — a switch is not a
reason to start one — and only worth saying when the answer is no, since
that is the case where a later `C-c n s' would come back with an offer
to build instead of with hits."
  (when (and (featurep 'org-semantic)
             (fboundp 'org-semantic-running-p)
             (org-semantic-running-p))
    (let* ((vault (vulpea-vault-semantic-root root))
           (status (ignore-errors (org-semantic-status vault))))
      (when (and status
                 (seq-empty-p (append (plist-get status :semantic) nil))
                 (not (org-semantic-true-p (plist-get status :lexical))))
        (message "org-semantic: %s has no index yet (M-x org-semantic-reindex)"
                 (abbreviate-file-name vault))))))

(add-hook 'vulpea-vault-leave-functions #'vulpea-vault-semantic-close)
(add-hook 'vulpea-vault-enter-functions #'vulpea-vault-semantic-check)

(defun vulpea-vault-semantic-vault (&rest _)
  "Return the active vulpea vault, spelled as org-semantic keys it.

Advice of the `:after-until' kind on `org-semantic-vault', so it is
consulted only when the buffer itself belongs to no org-semantic vault
— which is every buffer that is not a note.  With no vault open it
returns nil in turn, leaving `org-semantic-vault-or-error' to say there
is no vault here, which is the truth."
  (when vulpea-vault-directory
    (vulpea-vault-semantic-root vulpea-vault-directory)))

(with-eval-after-load 'org-semantic
  (advice-add 'org-semantic-vault :after-until #'vulpea-vault-semantic-vault))

(defun vulpea-vault-semantic-touch (path)
  "Tell org-semantic that PATH, which vulpea has just indexed or dropped, changed.

A no-op until org-semantic is loaded — `featurep' rather than
`fboundp', since the function is autoloaded and calling it would load
the package on the first file vulpea syncs.  So a session that never
searches pays one variable lookup per file vulpea indexes.

It does NOT require `org-semantic-auto-reindex-mode', which is off
here, and that is load-bearing rather than incidental: the mode is
that package's own `after-save-hook' and not a policy switch, so
gating the touch on it would demand the very hook this file makes
redundant.  What the touch does take from the mode is its manners —
the debounce, the silence on success, and the refusal to *build* an
index that does not exist.

The vault is the active one and not PATH's own: vulpea watches the
directories `vulpea-vault-apply' gave it, which are that vault, so a
path from its watcher is in it by construction.  The containment check
is for the case of somebody widening `vulpea-db-sync-directories' by
hand — a tree synced but not the vault would otherwise reindex the
notes and say it worked, which is the mistake
`org-semantic-auto-reindex--on-save' guards against on its own side."
  (when (and (featurep 'org-semantic)
             path
             vulpea-vault-directory
             (file-in-directory-p path vulpea-vault-directory))
    (org-semantic-auto-reindex-touch
     (vulpea-vault-semantic-root vulpea-vault-directory))))

(defun vulpea-vault-semantic-touch-updated (path &rest _)
  "Touch org-semantic for PATH, whose notes vulpea has just written.

An `:after' advice on `vulpea-db-update-file', which is where a file's
rows are written whatever brought it there: the sync queue, a vulpea
command, `vulpea-utils-with-note-sync'.  A file whose hash matched does
not reach it, so an unchanged file costs nothing.

This is the signal that actually fires here.  The queue only uses the
background worker when `vulpea-db-async-extraction' is on, and it is
off by default — so `vulpea-db-worker-done-functions', the declared
extension point, never runs in this configuration.  The hook below is
kept for the day that changes; between them the two cover both
branches, and a file that somehow reached both costs one run, not two."
  (vulpea-vault-semantic-touch path))

(defun vulpea-vault-semantic-touch-indexed (path status _count)
  "Touch org-semantic for PATH when vulpea's worker really wrote it.

On `vulpea-db-worker-done-functions', which runs only while
`vulpea-db-async-extraction' is on.  STATUS `applied' is the only one
that means the file's content is new to vulpea, and therefore the only
one worth a scan: `unchanged' is a file whose hash matched, and the
rest (`stale', `requeued', `missing', `error') are a dispatch that
ended without a result, its retry to come.

A file arriving under a new name — the loud half of a rename — reaches
here as `applied', because a path vulpea has no row for is new whatever
its content used to be called."
  (when (eq status 'applied)
    (vulpea-vault-semantic-touch path)))

(defun vulpea-vault-semantic-touch-removed (path &rest _)
  "Touch org-semantic for PATH, which vulpea has just forgotten.

An `:after' advice on `vulpea-db-sync--handle-removed-file', which is
where vulpea's watcher lands a `deleted' event and the vacating half of
a `renamed' one.  Private, deliberately: it is the only signal that a
note is gone, and it comes from a watcher, so it sees a deletion made
by any means — `dired-do-delete', `rm', a `git pull' — where an advice
on `delete-file' would see only this Emacs.  An upstream rename
silently costs the deletion signal and nothing else, since every other
change still arrives through the hook above."
  (vulpea-vault-semantic-touch path))

(advice-add 'vulpea-db-update-file :after #'vulpea-vault-semantic-touch-updated)
(add-hook 'vulpea-db-worker-done-functions #'vulpea-vault-semantic-touch-indexed)
(advice-add 'vulpea-db-sync--handle-removed-file :after
            #'vulpea-vault-semantic-touch-removed)

(defun vulpea-vault-semantic--check-signal (fn what)
  "Warn unless FN, which this file advises, is still defined by vulpea.

WHAT names what stops reaching org-semantic if it is not, and is
written to finish the sentence \"will no longer hear about\".

`advice-add' on a name that no longer exists is not an error: it
records the advice against an unbound symbol, where nothing will ever
call it.  Nothing fails, nothing is logged, and the index simply stops
being told about a class of change — which is indistinguishable from an
index that is up to date.  Hence a warning, which is the cheapest thing
that is not silence.

Checked under `with-eval-after-load' of the file that defines FN, not
at load: these are autoloaded, so `fboundp' here would answer nil for a
function that is merely not needed yet and warn on every startup."
  (unless (fboundp fn)
    (display-warning
     'vulpea-vault
     (format (concat "vulpea no longer defines `%s', so org-semantic will no "
                     "longer hear about %s.  Re-point the advice in "
                     "vulpea-vault/semantic.el.")
             fn what)
     :warning)))

(with-eval-after-load 'vulpea-db-extract
  (vulpea-vault-semantic--check-signal 'vulpea-db-update-file
                                       "notes that were edited"))

(with-eval-after-load 'vulpea-db-sync
  (vulpea-vault-semantic--check-signal 'vulpea-db-sync--handle-removed-file
                                       "notes that were deleted or renamed away"))

(provide 'vulpea-vault-semantic)
;;; semantic.el ends here
