;;; directories.el --- Folders a vault gives a role to -*- lexical-binding: t; -*-

;;; Commentary:
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
