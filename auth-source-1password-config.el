;;; auth-source-1password-config.el --- 1Password-backed auth-source for ghub/Forge -*- lexical-binding: t; -*-

;;; Commentary:
;; Serve secrets to `auth-source' from the 1Password CLI (`op'), so that ghub/Forge read the GitHub
;; token from 1Password instead of a plaintext ~/.authinfo.
;;
;; ghub looks the token up by (:host "api.github.com" :user "<github.user>^forge").
;; `auth-source-1password-config-items' maps each served (HOST . USER) to the 1Password *item
;; ID* that holds its secret; `auth-source-1password-config--reference' turns that into
;; op://<vault>/<id>/token.  Referencing by item ID (not title) keeps the reference stable however
;; the item is renamed in 1Password, and sidesteps titles that are invalid in an `op://' reference.
;; The token lives in the item's "token" field (the label 1Password's GitHub personal-access-token
;; auto-save uses; `op' resolves it by label, so the field's section is omitted).
;;
;; Keying on (HOST . USER) -- not host alone -- lets several tokens share one host.  GitHub issues
;; separate fine-grained tokens for personal resources and for each joined organization, so the same
;; `api.github.com' host needs more than one secret; ghub picks between them with the per-repo
;; `github.user' ident (set a distinct `git config github.user' in repos that must use an org-scoped
;; token).  Only the item ID is encoded in the `op://' path -- the ident selects the item, and `^'
;; is invalid in a reference anyway.
;;
;; The stock backend answers *every* auth-source query, returning the `op read' output verbatim
;; (even an error message), which would shadow ~/.authinfo and break other consumers such as
;; smtpmail.  The backend is therefore restricted to the idents listed in
;; `auth-source-1password-config-items'; lookups for any other host fall through to the remaining
;; `auth-sources'.

;;; Code:

(defcustom auth-source-1password-config-items
  '((("api.github.com" . "alberti42^forge")           . "lk7ir6tihrlf4t7o2tinfgkvtm")
    (("api.github.com" . "alberti42-ltex-plus^forge") . "jllbbdxvzmlsq7htlev4nhm5ey"))
  "Alist mapping a (HOST . USER) auth-source ident to its 1Password item ID.
HOST and USER are exactly what ghub/Forge query by, e.g.
\(:host \"api.github.com\" :user \"alberti42^forge\").  Keying on the pair lets
several tokens share one host: GitHub issues separate fine-grained tokens for
personal resources and for each joined organization, and ghub disambiguates
them by the per-repo `github.user' ident (see `auth-source-1password-config'
commentary).  The item ID is a stable handle that survives renaming the item
in 1Password and avoids titles that are invalid in an `op://' reference.  Only
idents listed here are served by the 1Password backend; lookups for any other
host fall through to the remaining `auth-sources'."
  :type '(alist :key-type (cons string string) :value-type string)
  :group 'auth-source-1password)

(defun auth-source-1password-config--item (host user)
  "Return the 1Password item ID serving (HOST . USER), or nil.
Match on both HOST and USER; when USER is nil (a host-only auth-source
probe), fall back to the first entry registered for HOST."
  (or (cdr (assoc (cons host user) auth-source-1password-config-items))
      (and (null user)
           (cdr (seq-find (lambda (e) (equal (caar e) host))
                          auth-source-1password-config-items)))))

(defun auth-source-1password-config--scope (fn &rest spec)
  "Restrict the 1Password backend to hosts in `auth-source-1password-config-items'.
FN is the wrapped `auth-source-1password-search'; SPEC is its
auth-source query plist.  Return nil for unlisted idents so the other
backends run."
  (when (auth-source-1password-config--item (plist-get spec :host)
                                            (plist-get spec :user))
    (apply fn spec)))

(defun auth-source-1password-config--reference (_backend _type host user _port)
  "Build an `op://' secret reference for the (HOST . USER) ident.
Look the ident up in `auth-source-1password-config-items' and target the
item's \"token\" field (the label 1Password's GitHub personal-access-token
template uses).  Reference by item ID so the path is stable regardless of the
item's title.  The ident selects the item; `^' is invalid in an `op://'
reference, so only the resolved item ID is encoded in the path."
  (let ((id (auth-source-1password-config--item host user)))
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
             :repo "alberti42/fork-auth-source-1password")
  :demand t
  :custom
  (auth-source-1password-vault "Personal")
  (auth-source-1password-construct-secret-reference #'auth-source-1password-config--reference)
  :config
  (advice-add 'auth-source-1password-search :around #'auth-source-1password-config--scope)
  (auth-source-1password-enable))

(provide 'auth-source-1password-config)
;;; auth-source-1password-config.el ends here
