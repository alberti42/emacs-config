;;; bibdesk.el --- Follow x-bdsk: links to BibDesk -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `x-bdsk:' is a URL scheme BibDesk.app registers with Launch Services
;; ("BibDesk publication URL"), used to address one publication in the library.
;; Org has no such link type, so `org-element' files every `x-bdsk://…' link as
;; `fuzzy' — an internal search target — and following one fails.  The notes
;; migrated from the Obsidian vault contain several hundred of them.
;;
;; Registering the type hands the URL to the OS, which routes it to BibDesk.
;;
;; The links also carry query parameters that are not BibDesk's: `doc=N' chose
;; which of a publication's attached files to open, and `page', `rect',
;; `color', `selection' and `annotation' came from PDF++ and located a passage
;; inside it.  BibDesk ignores what it does not recognise, so following a link
;; opens the publication and the extra fields are inert — but they are kept in
;; the link rather than discarded, so a richer `:follow' (resolve the citekey in
;; the .bib, open its Nth file in Skim at that page) can be added later without
;; the information having been thrown away.

;;; Code:

(require 'ol)

(defun vulpea-vault-bibdesk-open (path _arg)
  "Hand an `x-bdsk:' link to the OS, which routes it to BibDesk.
PATH is the part after \"x-bdsk:\", so the full URL is reassembled first."
  (browse-url (concat "x-bdsk:" path)))

(org-link-set-parameters "x-bdsk" :follow #'vulpea-vault-bibdesk-open)

(provide 'vulpea-vault-bibdesk)
;;; bibdesk.el ends here
