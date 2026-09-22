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
;;
;; `C-c n t' (`vulpea-vault-find-by-tag') searches the vault's database that
;; way: it expands a group tag into its members before querying, reading the
;; groups from a temporary buffer at the vault root so that it works from any
;; buffer.

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

(defun vulpea-vault-call-with-tags (fn)
  "Call FN with the vault's tag declarations in effect, and return its value.
`org-current-tag-alist' and `org-tag-groups-alist' are buffer-local and
filled only in a buffer under the vault root, so a command run from
anywhere else would see no groups.  FN runs in a temporary `org-mode'
buffer whose `default-directory' is the root; applying the dir-locals
there runs `vulpea-vault-apply-tag-alist' as it does for a note."
  (with-temp-buffer
    (setq default-directory (vulpea-vault-or-error))
    (delay-mode-hooks (org-mode))
    (hack-dir-local-variables-non-file-buffer)
    (funcall fn)))

(defun vulpea-vault-find-by-tag (tag)
  "Find a note tagged TAG, or tagged with any member of the group TAG.
Groups are the vault's own, from `org-tag-alist' in its `.dir-locals.el',
expanded by `vulpea-tags-expand'.  The candidates are the tags the
vault declares and the tags its notes carry."
  (interactive
   (list (completing-read
          "Tag: "
          (seq-uniq
           (append (vulpea-vault-call-with-tags
                    (lambda ()
                      (seq-filter #'stringp
                                  (mapcar #'car org-current-tag-alist))))
                   (vulpea-db-query-tags)))
          nil t)))
  (let ((tags (vulpea-vault-call-with-tags
               (lambda () (vulpea-tags-expand (list tag))))))
    (vulpea-find
     :require-match t
     :candidates-fn (lambda (_) (vulpea-db-query-by-tags-some tags)))))

(keymap-global-set "C-c n t" #'vulpea-vault-find-by-tag)

(provide 'vulpea-vault-tags)
;;; tags.el ends here
