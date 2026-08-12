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
;; Nothing here loads org-semantic.  Every entry point into it is autoloaded
;; and the advice is installed under `with-eval-after-load', so a session that
;; never searches pays nothing, and a switch in such a session does nothing at
;; all.

;;; Code:

(require 'seq)
(require 'vulpea-vault-switch)

(defvar vulpea-config-notes-directory)

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
one is used."
  (directory-file-name (file-truename (expand-file-name root))))

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
  (when vulpea-config-notes-directory
    (vulpea-vault-semantic-root vulpea-config-notes-directory)))

(with-eval-after-load 'org-semantic
  (advice-add 'org-semantic-vault :after-until #'vulpea-vault-semantic-vault))

(provide 'vulpea-vault-semantic)
;;; semantic.el ends here
