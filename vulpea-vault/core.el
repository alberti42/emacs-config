;;; core.el --- Which vault is in use, and what follows from it -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; One vault is in use at a time, and naming it settles five other things:
;; where the notes are, where the index is, where the attachment store is, and
;; the two of those that belong to other packages (`org-attach-id-dir',
;; `vulpea-db-sync-directories' / `vulpea-db-location').  Deriving all five
;; from a single root is `vulpea-vault-apply', and it is the only thing that
;; assigns them — a vault re-pointed by hand is a vault half re-pointed.
;;
;; `scheme.el' says what a vault may declare; this says what is done with it.
;; The two are the halves of one contract, which is why the deriving side is
;; also where an unwise-but-safe declaration is warned about: a predicate over
;; there cannot warn, it can only make Emacs discard the whole
;; `.dir-locals.el'.
;;
;; Assignment only — no database is opened, no watcher is touched, no buffer
;; is closed — so this is as safe to run at load time as it is mid-session.
;; Switching a running Emacs is `vulpea-vault-switch' (switch.el), which
;; supplies the teardown and restart around it.
;;
;; No vault open (`vulpea-vault-directory' nil) is an ordinary state, not a
;; broken one: an Emacs started before any vault has been opened.  Code that
;; only wants to know where it is tests the variable and carries on; a command
;; that cannot proceed without a vault says so through `vulpea-vault-or-error'.

;;; Code:

(require 'seq)
(require 'vulpea-vault-scheme)

(defvar vulpea-vault-directory nil
  "Root of the vault currently in use, or nil when none is open.

Assigned by `vulpea-vault-apply'; do not set it directly, since
everything below derives from it.

Spelled the way `vulpea-vault-root' spells every root — absolute, with a
trailing slash — which the equality tests in `switch.el' and `git.el'
depend on, this being where most of them get it.")

(defvar vulpea-vault-state-directory nil
  "Directory holding this vault's index -- the directory of `vulpea-db-location'.
Inside the vault by default (`<root>/.vulpea/'), so the index belongs to
the vault and travels with it; a vault may point its cache elsewhere
through `vulpea-vault-db-location', and this follows the directory part.

Safe to keep there: vulpea's scanner skips hidden directories — anything
whose path contains \"/.\" — so it neither indexes nor watches its own
state, and writing the database cannot retrigger a sync.")

(defvar vulpea-vault-attach-directory nil
  "Central org-attach store of the vault in use.
`org-attach' derives a note's directory from this path plus its `:ID:',
so a mismatch with the store the notes were written against silently
yields an empty attachment directory rather than an error — which is why
it is derived here rather than set anywhere by hand.

Absolute; its trailing directory name comes from
`vulpea-vault-data-directory', which a vault may set in its
`.dir-locals.el'.")

(defun vulpea-vault--store-name (value root)
  "Return VALUE, the attachment store the vault at ROOT declares.

Warns when it is absolute and returns it regardless.  A store belongs
inside the vault — it holds content, travels with the notes, and is one
contract with whatever wrote them — so an absolute value is almost always
a mistake; but it is the vault's statement to make, as it is for
`vulpea-vault-db-location', and honouring it is the only behaviour that
cannot surprise.  Falling back to the default would point a live vault at
an empty store instead, which reads as \"every attachment link is broken\"
and says nothing about why.

This is where the preference for a relative store lives, because this is
where it can be said out loud.  `vulpea-vault-data-directory-p' cannot:
a `safe-local-variable' predicate that returns nil makes Emacs discard the
vault's entire `.dir-locals.el' without a word.

Once per `vulpea-vault-apply' — startup and each `vulpea-vault-switch' —
not once per note, so it is not deduplicated the way
`vulpea-vault-version-check' is."
  (when (file-name-absolute-p value)
    (lwarn 'vulpea-vault :warning
           "Vault %s puts its attachment store outside itself (%s); \
using it as declared, but a store belongs in the vault"
           (abbreviate-file-name root) value))
  value)

(defun vulpea-vault-apply (root)
  "Point every vault-derived setting at ROOT, and return it.

The settings it owns are the reason a vault cannot simply be re-pointed
by hand: three of them belong to other packages, `org-attach' and vulpea
read plain values, and vulpea opens its database from
`vulpea-db-location' as it finds it."
  (let* ((root (vulpea-vault-root root))
         ;; The store's name and the cache's location are both the vault's to
         ;; choose (declared in `scheme.el' as `vulpea-vault-data-directory'
         ;; and `vulpea-vault-db-location'), read from the root the same way
         ;; every other vault-declared variable is.  Absent, the defaults
         ;; stand, so a vault that says nothing behaves as any other would.
         ;; This is the deriving half of the contract: the scheme says what a
         ;; vault may state, this turns a stated value into the global another
         ;; package reads.
         (declared (with-temp-buffer
                     (setq default-directory root)
                     (hack-dir-local-variables-non-file-buffer)
                     (list (or vulpea-vault-data-directory "data")
                           (or vulpea-vault-db-location "./.vulpea/vulpea.db"))))
         ;; Absolute is admitted and warned about here rather than refused by
         ;; the predicate; see `vulpea-vault--store-name'.  The
         ;; `expand-file-name' below needs no branch either way.
         (data (vulpea-vault--store-name (nth 0 declared) root))
         ;; A relative value (the default) lands inside the vault; an absolute
         ;; one or a `~'-path is taken as-is.  `expand-file-name' does exactly
         ;; that, so no branch on the shape of the path is needed.
         (db (expand-file-name (nth 1 declared) root)))
    (setq vulpea-vault-directory root
          vulpea-vault-state-directory (file-name-directory db)
          vulpea-vault-attach-directory (expand-file-name
                                         (file-name-as-directory data) root)
          org-attach-id-dir vulpea-vault-attach-directory
          vulpea-db-sync-directories (list root)
          vulpea-db-location db))
  (make-directory vulpea-vault-state-directory t)
  vulpea-vault-directory)

(defun vulpea-vault-or-error ()
  "Return the active vault root, or say that there is none.
For the commands that are meaningless without one — where nil would
otherwise travel a long way before failing as a wrong argument type."
  (or vulpea-vault-directory
      (user-error "No vault is open; `vulpea-vault-switch' opens one")))

(defun vulpea-vault-last-reachable ()
  "Return the vault to resume, or nil when there is none.

The one opened last, which is the only vault this configuration knows of
— no directory is named anywhere in it, since a vault is not something
Emacs has to be told about in advance.  Opening one is what makes it
known, and `vulpea-vault-history' is where that is kept.

That list belongs to `switch.el', which is loaded after this module and
so may not have run yet — but savehist restored it by plain `setq' when
`savehist-mode' started, hence `bound-and-true-p' rather than a reference
to a variable that may simply not exist.

The history is walked rather than merely read: an entry that is not a
vault right now is skipped in favour of the one visited before it —
whether its directory is not there (an unmounted volume is a reason to
open something else, not to fail) or it no longer declares a
`vulpea-vault-version' (a `.dir-locals.el' edited away, or an ordinary
directory that slipped into the history before switching learned to
refuse one)."
  (seq-find (lambda (d) (vulpea-vault-p (expand-file-name d)))
            (bound-and-true-p vulpea-vault-history)))

(defun vulpea-vault-resume ()
  "Open the most recently used vault that is still there, and return it.
Nil when the history holds none — a first run, or every remembered vault
away.  Startup's counterpart to `vulpea-vault-switch': nothing is torn
down, because nothing is open yet.

Also moves the vault actually resumed to the front of the history: when
the one opened last was unreachable and an older one was taken instead,
that older one is now the last visited."
  (when-let* ((root (vulpea-vault-last-reachable)))
    (vulpea-vault-apply root)
    (let ((history-delete-duplicates t))
      (add-to-history 'vulpea-vault-history vulpea-vault-directory))
    vulpea-vault-directory))

(provide 'vulpea-vault-core)
;;; core.el ends here
