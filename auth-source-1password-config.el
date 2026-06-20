;;; auth-source-1password-config.el --- 1Password-backed auth-source for ghub/Forge -*- lexical-binding: t; -*-

;;; Commentary:
;; Serve secrets to `auth-source' from the 1Password CLI (`op'), so that
;; ghub/Forge read the GitHub token from 1Password instead of a plaintext
;; ~/.authinfo.
;;
;; ghub looks the token up by (:host "api.github.com" :user "<github.user>^forge").
;; `auth-source-1password-config-items' maps each served host to the 1Password
;; *item ID* that holds its secret; `auth-source-1password-config--reference'
;; turns that into op://<vault>/<id>/token.  Referencing by item ID (not title)
;; keeps the reference stable however the item is renamed in 1Password, and
;; sidesteps titles that are invalid in an `op://' reference.  The token lives
;; in the item's "token" field (the label 1Password's GitHub personal-access-
;; token auto-save uses; `op' resolves it by label, so the field's section is
;; omitted).  The ghub ident is not encoded: the host alone selects the item,
;; and the `^' in the ident is invalid in an `op://' reference anyway.
;;
;; The stock backend answers *every* auth-source query, returning the `op read'
;; output verbatim (even an error message), which would shadow ~/.authinfo and
;; break other consumers such as smtpmail.  The backend is therefore restricted
;; to the hosts listed in `auth-source-1password-config-items'; lookups for any
;; other host fall through to the remaining `auth-sources'.

;;; Code:

(defcustom auth-source-1password-config-items
  '(("api.github.com" . "lk7ir6tihrlf4t7o2tinfgkvtm"))
  "Alist mapping an auth-source host to its 1Password item ID.
The item ID is a stable handle that survives renaming the item in 1Password
and avoids titles that are invalid in an `op://' reference.  Only hosts listed
here are served by the 1Password backend; lookups for any other host fall
through to the remaining `auth-sources'."
  :type '(alist :key-type string :value-type string)
  :group 'auth-source-1password)

(defun auth-source-1password-config--scope (fn &rest spec)
  "Restrict the 1Password backend to hosts in `auth-source-1password-config-items'.
FN is the wrapped `auth-source-1password-search'; SPEC is its auth-source
query plist.  Return nil for unlisted hosts so the other backends run."
  (when (assoc (plist-get spec :host) auth-source-1password-config-items)
    (apply fn spec)))

(defun auth-source-1password-config--reference (_backend _type host _user _port)
  "Build an `op://' secret reference for HOST.
Look HOST up in `auth-source-1password-config-items' and target the item's
\"token\" field (the label 1Password's GitHub personal-access-token template
uses).  Reference by item ID so the path is stable regardless of the item's
title.  The ghub ident (USER) is not encoded -- the host alone selects the
item, and `^' is invalid in an `op://' reference."
  (let ((id (cdr (assoc host auth-source-1password-config-items))))
    (when id
      (mapconcat #'identity
                 (list auth-source-1password-vault id "token")
                 "/"))))

(use-package auth-source-1password
  :straight (auth-source-1password
             :type git
             :host github
             :local-repo  "/Users/andrea/Documents/Programming/Others/fork-auth-source-1password"
             :branch "fix/return-nil-on-failed-op-read"
             :repo "alberti42/auth-source-1password")
  :demand t
  :custom
  (auth-source-1password-vault "Personal")
  (auth-source-1password-construct-secret-reference
   #'auth-source-1password-config--reference)
  :config
  (advice-add 'auth-source-1password-search :around
              #'auth-source-1password-config--scope)
  (auth-source-1password-enable))

(provide 'auth-source-1password-config)
;;; auth-source-1password-config.el ends here
