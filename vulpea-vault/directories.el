;;; directories.el --- What a vault says it is, and which folders it has -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; A vault announces itself with `vulpea-vault-version' in its
;; `.dir-locals.el'.  That declaration is what makes a directory a vault —
;; nothing is inferred from a `.dir-locals.el' being present, since most
;; projects have one — and it names the scheme the vault was written for, so
;; that changing the scheme later need not leave older vaults quietly
;; misbehaving.
;;
;; A vault names some of its folders for what they are *for* rather than for
;; where they sit: one holds the dated notes, another might hold the
;; templates, the inbox, the archive.  Code that needs such a folder should be
;; able to ask for the role and be told the path, without carrying the vault's
;; layout around with it — "01 Daily notes/" is the vault's business, and a
;; second vault is free to spell it differently or not have one at all.
;;
;; The map is `vulpea-vault-special-directories', declared once in the vault's
;; own `.dir-locals.el' and read back through
;; `vulpea-vault-special-directory'.  The lookup resolves against the vault
;; root rather than the current buffer, because the folder is often wanted
;; from outside the vault entirely — the daily note is where a note goes when
;; nothing about the buffer says otherwise.
;;
;; Where the vault *is* stays in the configuration, as
;; `vulpea-config-notes-directory'.  Something has to know that much before it
;; can read anything the vault says about itself.

;;; Code:

(require 'seq)

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

Naming a version rather than merely asserting \"vault\" is what leaves
room to change the scheme later.  See `vulpea-vault-schema-version'.")

(put 'vulpea-vault-version 'safe-local-variable #'natnump)

(defvar vulpea-vault--version-warned (make-hash-table :test 'equal)
  "Vault root to the version already reported for it, so each is said once.
Keyed on the version too, so a vault corrected — or broken — mid-session
is reported afresh.")

(defun vulpea-vault-version-check (version root)
  "Warn unless VERSION, declared by the vault at ROOT, is one we implement.
Returns non-nil when it is.  A vault from a newer scheme is the case
worth catching: it may rely on being read in ways these modules do not
yet know about, and the symptoms would otherwise be scattered.

Warns and carries on rather than refusing.  Being unable to read a vault
perfectly is no reason to be unable to read it at all."
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

(defvar-local vulpea-vault-special-directories nil
  "Alist of ROLE to directory for this vault, or nil.

ROLE is a symbol naming what the folder is for; the directory is
relative to the vault root unless absolute.  Meant to be declared in the
vault's `.dir-locals.el', so the layout travels with the notes:

  (vulpea-vault-special-directories . ((daily . \"01 Daily notes/\")))

Roles in use: `daily', where a note goes when nothing else says where.
Unknown roles are simply never asked for, so the alist may carry more
than any code reads.")

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

(defun vulpea-vault-special-directory (role)
  "Return the absolute directory the vault gives ROLE, or nil if none.

Read from the vault root through
`hack-dir-local-variables-non-file-buffer', which is how a buffer not
visiting a file picks up directory-local variables — the caller is
usually somewhere else entirely, and may be outside the vault."
  (let ((alist (with-temp-buffer
                 (setq default-directory vulpea-config-notes-directory)
                 (hack-dir-local-variables-non-file-buffer)
                 vulpea-vault-special-directories)))
    (when-let* ((dir (alist-get role alist)))
      (file-name-as-directory
       (expand-file-name dir vulpea-config-notes-directory)))))

(provide 'vulpea-vault-directories)
;;; directories.el ends here
