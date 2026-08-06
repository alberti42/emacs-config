;;; tags.el --- Let a note tree declare its own tag vocabulary -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; The vault's tags are declared in its own `.dir-locals.el', as
;; `org-tag-alist' and optionally `org-tag-persistent-alist', so they reach
;; the notes under that root and no other org file on the machine.  Two things
;; stand between writing them there and their having any effect.
;;
;; Neither variable is safe as a file-local, so Emacs would ask on every note
;; opened.  Both are declared safe here behind a predicate admitting tag
;; names, fast-selection characters and the grouping keywords and nothing
;; else: the value is inert data, so waiving the prompt gives up nothing.
;;
;; And dir-locals are applied *after* the major mode has run, by which point
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

(defconst vulpea-vault-tag-alist-keywords
  '(:startgroup :startgrouptag :grouptags :endgroup :endgrouptag :newline)
  "The structural keywords org allows in a tag alist.")

(defun vulpea-vault-tag-alist-p (value)
  "Return non-nil if VALUE has the shape org expects of a tag alist.
That shape is inert data throughout — tag names, fast-selection
characters and the grouping keywords — so a `.dir-locals.el' satisfying
it can name tags and nothing else.  See `org-tag-alist'."
  (and (listp value)
       (seq-every-p
        (lambda (entry)
          (pcase entry
            (`(,(pred stringp)) t)
            (`(,(pred stringp) . ,(pred characterp)) t)
            (`(,(pred keywordp)) (memq (car entry) vulpea-vault-tag-alist-keywords))
            (_ nil)))
        value)))

;; Org's own variables rather than proxies of ours, so what a vault writes in
;; its `.dir-locals.el' is what the org manual describes.
(dolist (var '(org-tag-alist org-tag-persistent-alist))
  (put var 'safe-local-variable #'vulpea-vault-tag-alist-p))

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
