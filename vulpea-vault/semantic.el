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
;;   `C-c n f' does.  A buffer that *is* in a declared vault keeps its own,
;;   since a declaration is answered first.
;;
;;   This is `org-semantic-vault-root', set to a function in
;;   `org-semantic-config.el' — not advice.  It was advice until org-semantic
;;   could hold a function, and the difference is worth naming: an answer that
;;   package asks for, rather than one taken behind its back.
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
;;   The signal is `vulpea-db-updated-functions', vulpea's own single
;;   data-changed hook: it fires once per file whose database content changed,
;;   after the transaction commits, for a synchronous write, for a result
;;   arriving from the extraction worker, and — with a count of 0 — for a
;;   removal.  So one `add-hook' covers every way a note can change, and
;;   nothing here advises anything.
;;
;;   It replaced three signals, which is worth recording because two of them
;;   were `advice-add' and one of those was on a private function: an advice on
;;   a name vulpea had since renamed would have succeeded, advised nothing and
;;   reported nothing, leaving the index quietly out of date.  That whole
;;   hazard went with them, and so did the `fboundp' checks that guarded it.
;;
;;   WHICH file changed is not passed on, and does not need to be: a reindex is
;;   a vault-wide incremental scan, so a rename is caught by the arrival of the
;;   new name alone — the same scan finds the old one gone.  The count is
;;   ignored for the same reason: removal and rewrite call for the identical
;;   scan.
;;
;;   A save reaches the same hook, so `org-semantic-auto-reindex-mode' — whose
;;   whole content is an `after-save-hook' — is left OFF in
;;   `org-semantic-config.el'.  It would be a second signal for a case already
;;   covered, and the weaker of the two: it fires *before* vulpea's database
;;   update, where this hook fires after it.
;;   `org-semantic-auto-reindex-touch' is deliberately independent of that mode.
;;
;; Nothing here loads org-semantic.  Every entry point into it is autoloaded,
;; and what this file installs is a hook and a function's name, so a session
;; that never searches pays nothing and a switch in such a session does nothing
;; at all.  The reindex hook is the one exception in spirit and not in fact: it
;; runs on every file vulpea indexes, and does nothing at all until something
;; has loaded org-semantic.  It does not need its `-auto-reindex-mode', which is
;; why that mode can stay off here.

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

(defun vulpea-vault-semantic-vault ()
  "Return the active vulpea vault, spelled as org-semantic keys it.

The value of `org-semantic-vault-root', set in `org-semantic-config.el',
which is why this takes no arguments and is not advice.  org-semantic
asks it for every buffer that carries no declaration of its own — which
is every buffer that is not a note: `*scratch*\=', an agenda, a file in
some other project.  A note inside a declared vault keeps that vault,
since a declaration is answered before this is asked.

So `C-c n s\=' means "search my notes" wherever it is pressed, exactly as
`C-c n f\=' does, and it follows `vulpea-vault-switch\=' rather than naming
one vault for the session.  With none open it returns nil, which
org-semantic reads as no vault here and reports as such — the truth.

It was `:after-until\=' advice on `org-semantic-vault\=' until that
package could hold a function, which is the better arrangement for the
obvious reason: this is an answer it asks for, not a decision taken
behind its back."
  (when vulpea-vault-directory
    (vulpea-vault-semantic-root vulpea-vault-directory)))

(defun vulpea-vault-semantic-touch (path &optional _count)
  "Tell org-semantic that PATH, whose vulpea rows have just changed, changed.

On `vulpea-db-updated-functions', vulpea's single data-changed hook,
which is called with (PATH COUNT) after the write or delete transaction
commits.  COUNT is ignored: 0 means the file's notes were removed and
anything else means they were written, and both call for the identical
vault-wide scan.

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

(add-hook 'vulpea-db-updated-functions #'vulpea-vault-semantic-touch)

(provide 'vulpea-vault-semantic)
;;; semantic.el ends here
