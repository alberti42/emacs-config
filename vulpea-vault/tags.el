;;; tags.el --- Let a note tree declare its own tag vocabulary -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; The vault's tags are declared in its own `.dir-locals.el', as
;; `org-tag-alist' and optionally `org-tag-persistent-alist', so they reach
;; the notes under that root and no other org file on the machine.  Two things
;; stand between writing them there and their having any effect.
;;
;; Neither variable is safe as a file-local, so Emacs would ask on every note
;; opened.  That permission — and the predicate behind it — is granted in
;; `vulpea-vault/scheme.el', with every other declaration a vault may make.
;;
;; The second thing is what is left here.  Dir-locals are applied *after* the
;; major mode has run, by which point
;; `org-mode' has already derived `org-current-tag-alist' — the buffer-local
;; value everything downstream actually reads — from the global settings.
;; Setting `org-tag-alist' at that point does nothing whatsoever until the
;; derivation runs again, which is what the hook below is for.
;;
;; Background on why the vault's list is mostly groups: Obsidian's tags were
;; hierarchical (#Log/Daily, #Teaching/E4) and org tags cannot contain a
;; slash, so the converter kept the last segment and expressed each parent as
;; a tag group.  Searching Log still matches Daily and Meeting.

;;; Code:

(defun vulpea-vault-apply-tag-alist ()
  "Re-derive the tag settings a dir-local has just supplied.

Runs from `hack-local-variables-hook', once the dir-locals are applied.
`org-mode' derived `org-current-tag-alist' before that, from values the
dir-local has since replaced, so without this the buffer keeps the tags
it would have had — for the vault, none.  Re-deriving rather than
assigning also preserves org's own precedence, under which a note
declaring `#+TAGS:' overrides `org-tag-alist' but not
`org-tag-persistent-alist'."
  (when (and (derived-mode-p 'org-mode)
             (or (local-variable-p 'org-tag-alist)
                 (local-variable-p 'org-tag-persistent-alist)))
    (org-set-regexps-and-options 'tags-only)))

(add-hook 'hack-local-variables-hook #'vulpea-vault-apply-tag-alist)

(provide 'vulpea-vault-tags)
;;; tags.el ends here
