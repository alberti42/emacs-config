;;; message.el --- Follow message: links to Mail.app -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `message:' is the URL scheme Mail.app registers with Launch Services; a
;; message dragged out of Mail becomes `message://%3C<Message-ID>%3E', the
;; angle brackets percent-encoded.  Org has no such link type, so
;; `org-element' files every one as `fuzzy' — an internal search target — and
;; following it fails.  The notes migrated from the Obsidian vault contain 23.
;;
;; Registering the type hands the URL to the OS, which routes it to Mail.
;; Nothing here is Mail-specific beyond that: whichever application claims the
;; scheme gets the link.
;;
;; Both spellings occur in the vault — `message://%3C…%3E' and, once,
;; `message:%3C…%3E' without the slashes.  Reassembling the URL from the path
;; org hands back preserves whichever was written, and Mail accepts both.
;;
;; A Message-ID is a permanent identifier, so these links survive the message
;; being moved between mailboxes; they break only if it is deleted.

;;; Code:

(require 'ol)

(defun vulpea-vault-message-open (path _arg)
  "Hand a `message:' link to the OS, which routes it to Mail.app.
PATH is the part after \"message:\", so the full URL is reassembled first."
  (browse-url (concat "message:" path)))

(org-link-set-parameters "message" :follow #'vulpea-vault-message-open)

(provide 'vulpea-vault-message)
;;; message.el ends here
