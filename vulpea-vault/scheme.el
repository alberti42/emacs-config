;;; scheme.el --- The contract between a vault and these modules -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Everything a vault may say about itself is declared here: the variables,
;; their defaults, and the predicates that make each one safe to set from a
;; `.dir-locals.el'.  Nothing else in vulpea-vault/ declares one.  Ask this
;; file "what may a vault declare?" and the answer is the whole of it, in the
;; same order as the header of the vault's own `.dir-locals.el'.
;;
;; A vault announces itself with `vulpea-vault-version'.  That declaration is
;; the whole of what makes a directory a vault — nothing is inferred from a
;; `.dir-locals.el' being present, since most projects have one, this
;; configuration's own repository included.
;;
;; It names a version rather than merely asserting "vault", so that changing
;; what a vault is expected to declare need not leave older vaults quietly
;; misbehaving.  The version is a version OF THE DECLARATIONS BELOW, which is
;; why they share a file with it:
;;
;;   ADDING OR CHANGING A DECLARATION HERE IS THE MOMENT TO WEIGH A BUMP OF
;;   `vulpea-vault-schema-version'.  Split the two across files and the edit
;;   that must not be forgotten becomes the easy one to forget, and forgetting
;;   it is silent — an old vault keeps declaring version 1 and is read wrongly
;;   rather than reported.
;;
;; An unrecognised version is reported, not refused.  Being unable to read a
;; vault perfectly is no reason to be unable to read it at all.
;;
;; A predicate here answers one question only: IS THIS VALUE SAFE TO READ?
;; — inert data, no function symbols, nothing that could introduce code.  It
;; does NOT answer whether the value is *wise*.  That distinction is not
;; pedantry: a predicate returning nil makes Emacs discard the WHOLE
;; `.dir-locals.el', silently when non-interactive, so a vault refused one
;; unwise value loses its tags, its templates and its version too — it stops
;; being a vault at all.  A rule about what a sensible value looks like
;; therefore belongs where it can be reported and recovered from, which is the
;; deriving side (`vulpea-vault-apply'), never here.
;;
;; Where each declaration is *used* is named in its docstring; this file only
;; states the contract and recognises a vault by it.  What a vault says is read
;; in two different ways, which is why the declarations are not all of a kind:
;;
;; - `defvar-local' — read per buffer or per folder, through the directory keys
;;   of `.dir-locals.el', so a subfolder may answer differently from its
;;   parent: `vulpea-vault-version', `vulpea-vault-special-directories',
;;   `vulpea-vault-template'.
;;
;; - plain `defvar' — read once from the vault root by
;;   `vulpea-vault-apply' (core.el), which derives a global setting belonging to
;;   another package from it: `vulpea-vault-data-directory',
;;   `vulpea-vault-db-location'.  A per-folder value would be meaningless,
;;   there being one store and one index per vault.
;;
;; Which is also why this is the first vulpea-vault module loaded: a predicate
;; must be attached to a symbol *before* anything reads a `.dir-locals.el'
;; naming it, and the vault resumed at startup is read before the rest of the
;; modules load.  Declarations only, so loading it early costs nothing and
;; needs nothing — no module of ours, and of org nothing at all.
;;
;; Where the vault *is* is not here either: that is `vulpea-vault-directory'
;; (core.el).  Something has to know that much before it can read anything the
;; vault says about itself.

;;; Code:

(require 'seq)
;; `string-empty-p', used by two of the predicates below.
(require 'subr-x)

(defconst vulpea-vault-schema-version 1
  "The vault scheme these modules implement.
Raised when a change would make an older vault behave wrongly rather
than merely differently — a variable renamed, a value read another way.
A vault declaring something else is reported by
`vulpea-vault-version-check'.")


;;;; How a vault root is spelled

(defun vulpea-vault-root (dir)
  "Return DIR spelled the way every vault root is spelled here.
Absolute, with a trailing slash.

One spelling, because equality depends on it: a candidate is hidden from
the switch prompt by `equal' against `vulpea-vault-directory', the
active root and the remembered ones are folded together with
`delete-dups' before backup, and `file-in-directory-p' decides which
buffers belong to a vault.  Two spellings of one directory would show it
twice, back it up twice, or fail to recognise it — none of which announces
itself as a spelling problem.

Normalisation only.  Every caller already holds an absolute path
\=(a `default-directory', a `locate-dominating-file' result, an entry of
`vulpea-vault-history', which is only ever written from
`vulpea-vault-directory'), so this expands `~' and `..' and settles
the trailing slash; it is not the relative-to-absolute step.  A relative
DIR does resolve against `default-directory', which is what a Lisp caller
of `vulpea-vault-switch' would mean by one.

Deliberately NOT `file-truename': vulpea, `org-attach' and the buffer list
all speak the path as the user opened it, symlinks unresolved, and
resolving them here would stop `file-in-directory-p' from recognising a
vault reached through a symlink.  `vulpea-vault-semantic-root' is the one
place that needs the truename spelling — the org-semantic server keys its
vaults that way — and owns that conversion itself.  Do not fold it in
here: a `close' sent under the wrong spelling closes nothing and reports
success."
  (file-name-as-directory (expand-file-name dir)))


;;;; Is this a vault, and which scheme does it follow

(defvar-local vulpea-vault-version nil
  "Scheme version this directory's vault follows, or nil if it is not one.

The canonical marker: a directory is a vault because it says so here,
and for no other reason.  Declared in the vault's own `.dir-locals.el',
alongside everything else it says about itself:

  (vulpea-vault-version . 1)

See `vulpea-vault-schema-version' for what the number is weighed
against.")

(put 'vulpea-vault-version 'safe-local-variable #'natnump)


;;;; Where the attachments live

(defvar vulpea-vault-data-directory "data"
  "Name of the attachment store, relative to the vault root.

Declared by the vault in its `.dir-locals.el', so where its data lives
travels with the notes:

  ((nil . ((vulpea-vault-data-directory . \"00 Meta/data\"))))

Default \"data\" is a visible directory at the root; \".data\" tucks the
store out of sight (a leading dot also keeps vulpea's scanner from
walking it, since it skips any path containing \"/.\").  Whatever the
value, it MUST match the converter's --attach-dir
(`etc/goodies/obsidian-to-org.py'): the two are one contract, and a
mismatch yields an empty attachment directory rather than an error.

Read from the root by `vulpea-vault-apply', which expands it into
`org-attach-id-dir'; the store wiring that then resolves an
`attachment:' link through it is `vulpea-vault/attachments.el'.

Relative \=-> inside the vault, which is where a store belongs; an
absolute value or a `~'-path is taken as-is, as for
`vulpea-vault-db-location', but is warned about — unlike a cache, a store
holds content, and a store outside the vault is far more often a mistake
than a decision.  Write a relative value with a leading \"./\" to mark it
as one; not required (`expand-file-name' needs no marker), but it says so
to a reader.

Existing links survive a move — `attachment:' and the UUID crossref form
both resolve through `org-attach-dir-from-id', never a literal path — but
the files themselves must be moved to the new name (a one-time `git mv').
Keep the store in a directory that holds nothing but attachments, so no
stray `.org' under it is mistaken for a note.")

(defun vulpea-vault-data-directory-p (value)
  "Return non-nil if VALUE could name an attachment store.
A non-empty string; the value is inert data, never code.

Whether it is *relative* is deliberately not judged here, though a
relative value is what a store should be.  This predicate once required
it, which made a vault naming an absolute store lose its whole
`.dir-locals.el' — tags, templates, folder roles, and the
`vulpea-vault-version' that makes it a vault at all — silently, over a
setting no other declaration depends on.  A predicate is read as a safety
gate by Emacs and cannot report anything; the preference belongs where it
can warn, and does: `vulpea-vault-apply'.  Same admission rule as
`vulpea-vault-db-location-p', so all three declared paths now accept the
same shapes."
  (and (stringp value)
       (not (string-empty-p value))))

(put 'vulpea-vault-data-directory 'safe-local-variable
     #'vulpea-vault-data-directory-p)


;;;; Where the index lives

(defvar vulpea-vault-db-location "./.vulpea/vulpea.db"
  "Where this vault's index -- a SQLite *cache*, not content -- is stored.

Declared by the vault in its `.dir-locals.el', so a vault says where its
own cache belongs:

  ((nil . ((vulpea-vault-db-location . \"./.vulpea/vulpea.db\"))))

Resolved with `expand-file-name' against the vault root by
`vulpea-vault-apply': a relative value (the default) lands inside
the vault -- encrypted-at-rest and unmounting with it on an encrypted
disk -- while an absolute value or a `~'-path is taken as-is, for a
per-machine local cache when the vault is shared.  Its directory becomes
`vulpea-vault-state-directory' and is created if absent; keep it hidden
(a leading dot) so vulpea's scanner, which skips any path containing
\"/.\", neither indexes nor watches the cache.

Caveat for a *shared* vault: its `.dir-locals.el' travels with it, so a
hardwired absolute path here would be identical on every machine -- not
per-machine.  For that case leave the value relative and sync-exclude the
directory, or resolve the per-machine path from user configuration keyed
on the vault rather than naming it here.")

(defun vulpea-vault-db-location-p (value)
  "Return non-nil if VALUE is a valid `vulpea-vault-db-location'.
A non-empty string.  Unlike `vulpea-vault-data-directory' an absolute
path is admitted, since the point is to be able to place the cache
outside a shared vault; the value is inert data, never code.  (Opening an
untrusted vault that redirects its cache is the reason to tighten this to
relative-only should such vaults ever be a concern.)"
  (and (stringp value)
       (not (string-empty-p value))))

(put 'vulpea-vault-db-location 'safe-local-variable
     #'vulpea-vault-db-location-p)


;;;; Folders the vault gives a role to

(defvar-local vulpea-vault-special-directories nil
  "Alist of ROLE to directory for this vault, or nil.

ROLE is a symbol naming what the folder is for; the directory is
relative to the vault root unless absolute.  Meant to be declared in the
vault's `.dir-locals.el', so the layout travels with the notes:

  (vulpea-vault-special-directories . ((daily . \"01 Daily notes/\")))

Roles in use: `daily', where a note goes when nothing else says where.
Unknown roles are simply never asked for, so the alist may carry more
than any code reads.

Read back through `vulpea-vault-special-directory'
\(`vulpea-vault/directories.el'), which resolves a role against the vault
root rather than the current buffer.")

(defun vulpea-vault-special-directories-p (value)
  "Return non-nil if VALUE is a well-formed role-to-directory alist.
Symbols and strings only, so a vault's `.dir-locals.el' can describe its
layout without being able to introduce code."
  (and (listp value)
       (seq-every-p (lambda (entry)
                      (and (consp entry)
                           (symbolp (car entry))
                           (stringp (cdr entry))))
                    value)))

(put 'vulpea-vault-special-directories 'safe-local-variable
     #'vulpea-vault-special-directories-p)


;;;; What a folder's notes start as

(defvar-local vulpea-vault-template nil
  "What a note created in this directory starts as, or nil for the defaults.

A plist, meant to be set per folder from the vault's `.dir-locals.el'
using its directory keys.  Keys, all optional:

  :tags   list of filetags
  :head   keywords added after `#+title:' and `#+filetags:'
  :body   initial content, written a blank line below the keywords
  :dated  nil to leave the title alone; otherwise today's date opens it

An entry carries only what makes its folder differ.  Emacs replaces the
value of a shallower directory key rather than merging into it, so a
subfolder cannot inherit half of its parent's — what is absent comes
from `vulpea-vault-create-defaults' instead
\(`vulpea-vault/create.el', which reads this).")

(defconst vulpea-vault-template-keys '(:tags :head :body :dated)
  "The keys `vulpea-vault-template' may carry.")

(defun vulpea-vault-template-p (value)
  "Return non-nil if VALUE is a well-formed `vulpea-vault-template'.

Admits inert data only — strings, lists of strings, and t or nil — and
in particular no function symbols, so a vault's `.dir-locals.el' can
describe its folders without being able to introduce code."
  (and (listp value)
       (zerop (% (length value) 2))
       (let ((rest value) (ok t))
         (while (and ok rest)
           (let ((key (pop rest))
                 (val (pop rest)))
             (setq ok (pcase key
                        (:tags (and (listp val) (seq-every-p #'stringp val)))
                        ((or :head :body) (stringp val))
                        (:dated (or (eq val t) (null val)))
                        (_ nil)))))
         ok)))

(put 'vulpea-vault-template 'safe-local-variable #'vulpea-vault-template-p)


;;;; The tag vocabulary

;; Org's own variables rather than proxies of ours, so what a vault writes in
;; its `.dir-locals.el' is what the org manual describes.  Neither is safe as a
;; file-local out of the box, so without the permission below Emacs would ask
;; on every note opened.  Granting it gives up nothing: the value is inert
;; data.  Making the declaration *take effect* is a second matter, and the one
;; thing left in `vulpea-vault/tags.el'.

(defconst vulpea-vault-tag-alist-keywords
  '(:startgroup :startgrouptag :grouptags :endgroup :endgrouptag :newline)
  "The structural keywords org allows in a tag alist.")

(defun vulpea-vault-tag-alist-p (value)
  "Return non-nil if VALUE has the shape org expects of a tag alist.
That shape is inert data throughout — tag names, fast-selection
characters and the grouping keywords — so a `.dir-locals.el' satisfying
it can name tags and nothing else.  See `org-tag-alist'."
  (and (listp value)
       (seq-every-p
        (lambda (entry)
          (pcase entry
            (`(,(pred stringp)) t)
            (`(,(pred stringp) . ,(pred characterp)) t)
            (`(,(pred keywordp)) (memq (car entry) vulpea-vault-tag-alist-keywords))
            (_ nil)))
        value)))

(dolist (var '(org-tag-alist org-tag-persistent-alist))
  (put var 'safe-local-variable #'vulpea-vault-tag-alist-p))


;;;; Recognising a vault by its declaration

(defvar vulpea-vault--version-warned (make-hash-table :test 'equal)
  "Vault root to the version already reported for it, so each is said once.
Keyed on the version too, so a vault corrected — or broken — mid-session
is reported afresh.")

(defun vulpea-vault-version-check (version root)
  "Warn unless VERSION, declared by the vault at ROOT, is one we implement.
Returns non-nil when it is.  A vault from a newer scheme is the case
worth catching: it may rely on being read in ways these modules do not
yet know about, and the symptoms would otherwise be scattered."
  (cond
   ((equal version vulpea-vault-schema-version) t)
   ;; Once per vault per session.  The check runs for every note opened
   ;; there, and the same warning on each is noise rather than information —
   ;; the more so where warnings are surfaced as popups.
   ((equal version (gethash root vulpea-vault--version-warned 'unseen)) nil)
   (t
    (puthash root version vulpea-vault--version-warned)
    (ignore
     (if (null version)
         (lwarn 'vulpea-vault :warning
                "%s declares no `vulpea-vault-version'; opening it as a vault regardless"
                (abbreviate-file-name root))
       (lwarn 'vulpea-vault :warning
              "Vault %s follows scheme version %s; this Emacs implements %s"
              (abbreviate-file-name root) version vulpea-vault-schema-version))))))

(defun vulpea-vault-version-at (root)
  "Return the scheme version the vault at ROOT declares, or nil.
Read from ROOT itself, so a vault can be inspected without a buffer
being open anywhere inside it."
  (with-temp-buffer
    (setq default-directory root)
    (hack-dir-local-variables-non-file-buffer)
    vulpea-vault-version))

(defun vulpea-vault-p (dir)
  "Return non-nil if DIR is a vulpea vault.

A directory is a vault only when its `.dir-locals.el' declares a
`vulpea-vault-version' — the sole marker, since a bare `.dir-locals.el'
means nothing.  Only the declaration's presence is weighed here, not
which version it names; whether that version is one these modules
implement is `vulpea-vault-version-check'."
  (and (file-directory-p dir)
       (vulpea-vault-version-at dir)))

(provide 'vulpea-vault-scheme)
;;; scheme.el ends here
