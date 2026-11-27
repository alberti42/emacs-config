;;; zotero.el --- Follow zotero: links to Zotero -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `zotero:' is the URL scheme Zotero.app registers with Launch Services;
;; `zotero://select/library/items/<KEY>' selects one item in the library, and
;; `zotero://open-pdf/library/items/<KEY>?page=N' opens an attachment.  Org has
;; no such link type, so `org-element' files every `zotero://…' link as
;; `fuzzy' — an internal search target — and following one fails.
;;
;; Registering the type hands the URL to the OS, which routes it to Zotero.

;;; Code:

(require 'ol)

(defun vulpea-vault-zotero-open (path _arg)
  "Hand a `zotero:' link to the OS, which routes it to Zotero.
PATH is the part after \"zotero:\", so the full URL is reassembled first."
  (browse-url (concat "zotero:" path)))

(org-link-set-parameters "zotero" :follow #'vulpea-vault-zotero-open)

(provide 'vulpea-vault-zotero)
;;; zotero.el ends here
