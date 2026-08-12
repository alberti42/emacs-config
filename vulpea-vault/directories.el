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
;; The variable itself is declared in `vulpea-vault/scheme.el', with the rest
;; of what a vault may say about itself; this file only reads it.
;;
;; Where the vault *is* stays in the configuration, as
;; `vulpea-config-notes-directory'.  Something has to know that much before it
;; can read anything the vault says about itself.

;;; Code:

(require 'vulpea-vault-scheme)

(defun vulpea-vault-special-directory (role)
  "Return the absolute directory the vault gives ROLE, or nil if none.

Read from the vault root through
`hack-dir-local-variables-non-file-buffer', which is how a buffer not
visiting a file picks up directory-local variables — the caller is
usually somewhere else entirely, and may be outside the vault.

Nil as well when no vault is open: no vault, no roles."
  (when vulpea-config-notes-directory
    (let ((alist (with-temp-buffer
                   (setq default-directory vulpea-config-notes-directory)
                   (hack-dir-local-variables-non-file-buffer)
                   vulpea-vault-special-directories)))
      (when-let* ((dir (alist-get role alist)))
        (file-name-as-directory
         (expand-file-name dir vulpea-config-notes-directory))))))

(provide 'vulpea-vault-directories)
;;; directories.el ends here
