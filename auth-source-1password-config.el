;;; auth-source-1password-config.el --- Forge's GitHub tokens from 1Password -*- lexical-binding: t; -*-

;;; Commentary:
;; Forge reads its GitHub tokens from 1Password through this file.  Nothing else in this Emacs
;; asks for a secret that 1Password answers here.
;;
;; What does not go through this file:
;; - Commits.  Git signs each commit with an SSH key (`gpg.format ssh' in ~/.config/git/config).
;;   The 1Password SSH agent holds that key and asks for the fingerprint.  Emacs is not involved,
;;   and the same prompt appears for a commit from a terminal.
;; - Pushes and fetches over SSH.  `ssh' gets the key from the same SSH agent.
;; - Magit itself.  Magit runs git, and git talks to the SSH agent.
;;
;; What goes through this file, step by step:
;; 1. Forge pulls issues and pull requests from GitHub.  To make the API request, it calls ghub,
;;    the GitHub API library that Forge depends on.
;; 2. ghub asks `auth-source' for a token with
;;      :host "api.github.com" :user "<github.user>^forge"
;;    where <github.user> is the value of `git config github.user' in the current repository.
;; 3. `auth-source' asks its backends in turn.  `auth-source-1password' is one of them.
;; 4. `auth-source-1password' calls `auth-source-1password-config--reference', which looks up the
;;    pair (HOST . USER) in `auth-source-1password-config-items'.
;;    - If the pair is listed, it returns the path Personal/<item ID>/token, and
;;      `auth-source-1password' runs `op read op://Personal/<item ID>/token'.  1Password may ask for
;;      the fingerprint, and the token goes back to Forge.
;;    - If the pair is not listed, it returns nil.  `auth-source-1password' then does not run `op',
;;      and `auth-source' asks the next backend (~/.authinfo, which smtpmail uses, for example).
;;
;; Why the user ends in "^forge": ghub wants one token per package that uses it, so that each
;; token has only the GitHub permissions ("scopes") its package needs.  An `auth-source' entry has
;; three fields (host, user, secret), so ghub puts the package name into the user field:
;; USERNAME^PACKAGE.  Forge is the only package installed here that uses ghub.
;;
;; Why there are two entries: a GitHub fine-grained token belongs to one owner, either your
;; account or one organization.  The repositories of the `ltex-plus' organization need a token
;; owned by that organization.  To make ghub ask for it, those repositories set
;;   git config github.user alberti42-ltex-plus
;; This value is only a label that selects the entry in `auth-source-1password-config-items'.
;; ghub never sends it to GitHub, and both tokens authenticate as the account `alberti42'.  Forge
;; also treats the value as your GitHub login, so in those repositories two Forge features would
;; use the wrong name: forking (Forge would ask to fork into an organization called `alberti42')
;; and filtering topics assigned to you.
;;
;; To add a token:
;; 1. Save the token in 1Password, in the vault named by `auth-source-1password-vault', in a field
;;    labelled "token".
;; 2. Find the item ID with `op item list --vault Personal'.
;; 3. Add an entry ((HOST . USER) . ITEM-ID) to `auth-source-1password-config-items', with HOST
;;    and USER exactly as the package asks for them.
;; 4. Run `M-x auth-source-forget-all-cached'.

;;; Code:

(defcustom auth-source-1password-config-items
  '((("api.github.com" . "alberti42^forge")           . "lk7ir6tihrlf4t7o2tinfgkvtm")
    (("api.github.com" . "alberti42-ltex-plus^forge") . "jllbbdxvzmlsq7htlev4nhm5ey"))
  "The `auth-source' queries that 1Password answers, and the item that answers each.
Each entry is ((HOST . USER) . ITEM-ID).  HOST and USER are compared
exactly with the :host and :user of the query; for Forge they are
\"api.github.com\" and \"<github.user>^forge\".  ITEM-ID is the ID of a
1Password item in the vault `auth-source-1password-vault'; the secret is
read from its field labelled \"token\".  An item ID stays the same when
the item is renamed in 1Password.

A query for a pair not listed here is not answered by 1Password and goes
to the next entry in `auth-sources'.  See the commentary of
auth-source-1password-config.el for why Forge's user ends in \"^forge\"
and why there are two GitHub entries."
  :type '(alist :key-type (cons string string) :value-type string)
  :group 'auth-source-1password)

(defun auth-source-1password-config--item (host user)
  "Return the item ID listed for HOST and USER, or nil.
Look up (HOST . USER) in `auth-source-1password-config-items'.  When
USER is nil, return the first item listed for HOST."
  (or (cdr (assoc (cons host user) auth-source-1password-config-items))
      (and (null user)
           (cdr (seq-find (lambda (e) (equal (caar e) host))
                          auth-source-1password-config-items)))))

(defun auth-source-1password-config--reference (_backend _type host user _port)
  "Return the 1Password path of the secret for HOST and USER, or nil.
`auth-source-1password' calls this for every `auth-source' query and
runs `op read op://PATH' on the result.  The path is VAULT/ITEM-ID/token,
with ITEM-ID from `auth-source-1password-config-items'.  The user name
is not part of the path, because `op://' paths cannot contain the `^'
in \"alberti42^forge\".

Return nil when the pair is not listed.  `auth-source-1password' then
does not run `op', and `auth-source' asks the next backend."
  (let ((id (auth-source-1password-config--item host user)))
    (when id
      (mapconcat #'identity
                 (list auth-source-1password-vault id "token")
                 "/"))))

(use-package auth-source-1password
  :straight (auth-source-1password
             :type git
             :host github
             :repo "dlobraico/auth-source-1password")
  :demand t
  :custom
  (auth-source-1password-vault "Personal")
  (auth-source-1password-construct-secret-reference #'auth-source-1password-config--reference)
  :config
  ;; Put 1Password first in `auth-sources'.
  (auth-source-1password-enable))

(provide 'auth-source-1password-config)
;;; auth-source-1password-config.el ends here
