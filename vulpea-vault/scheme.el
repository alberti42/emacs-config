;;; scheme.el --- What makes a directory a vault -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; A vault announces itself with `vulpea-vault-version' in its
;; `.dir-locals.el'.  That declaration is the whole of what makes a directory
;; a vault — nothing is inferred from a `.dir-locals.el' being present, since
;; most projects have one, this configuration's own repository included.
;;
;; It names a version rather than merely asserting "vault", so that changing
;; what a vault is expected to declare need not leave older vaults quietly
;; misbehaving.  The scheme is everything the vault and these modules have
;; agreed on — today the folder roles of `vulpea-vault/directories.el', the
;; tag vocabulary read by `vulpea-vault/tags.el' and the per-folder templates
;; read by `vulpea-vault/create.el', and whatever is added to that list next.
;; Which is why the version lives here and not inside any one of them.
;;
;; An unrecognised version is reported, not refused.  Being unable to read a
;; vault perfectly is no reason to be unable to read it at all.

;;; Code:

(defconst vulpea-vault-schema-version 1
  "The vault scheme these modules implement.
Raised when a change would make an older vault behave wrongly rather
than merely differently — a variable renamed, a value read another way.
A vault declaring something else is reported by
`vulpea-vault-version-check'.")

(defvar-local vulpea-vault-version nil
  "Scheme version this directory's vault follows, or nil if it is not one.

The canonical marker: a directory is a vault because it says so here,
and for no other reason.  Declared in the vault's own `.dir-locals.el',
alongside everything else it says about itself:

  (vulpea-vault-version . 1)

See `vulpea-vault-schema-version' for what the number is weighed
against.")

(put 'vulpea-vault-version 'safe-local-variable #'natnump)

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
