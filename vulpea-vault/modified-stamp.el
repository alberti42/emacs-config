;;; modified-stamp.el --- Keep :MODIFIED: current on save -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Notes converted from the Obsidian vault carry their creation and
;; modification times.  In Obsidian the frontmatter-modified-date plugin
;; refreshed the latter on every edit; this does the same on save.
;;
;; The stamps live in the file-level property drawer, `:CREATED:' and
;; `:MODIFIED:' beside the `:ID:' — the drawer belongs to the file-level node,
;; which is the node they describe.  They were `#+created:'/`#+modified:'
;; keywords until vulpea turned out to index properties and not keywords: a
;; property is a fact the database can answer questions about, a keyword is
;; text.
;;
;; Only buffers that already have the property are touched, so this never adds
;; a stamp to an org file that does not use the convention.  `org-entry-get'
;; returning nil is what says so, and it is also what makes the check cheap.

;;; Code:

(require 'org)

(defconst vulpea-vault-modified-time-format "%FT%T%:z"
  "`format-time-string' spec for the `:MODIFIED:' value.
Matches what the vault already contains, e.g. 2026-04-13T08:08:00+02:00.
Note `%:z' for the colon in the zone offset; plain `%z' would write
+0200 and make new stamps differ from the migrated ones.")

(defun vulpea-vault-modified-stamp-update ()
  "Set this buffer's `:MODIFIED:' property to the current time.
Does nothing if the buffer has no such property.

`point-min' addresses the file-level node, whose drawer org requires to
be the first element in the buffer — before the first heading and before
every keyword, comments alone allowed above it.  Put a `#+title:' above
that drawer and org stops recognising it as one, which is why the
migration inserted into the existing drawer rather than writing a new."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (save-restriction
        (widen)
        (when (org-entry-get (point-min) "MODIFIED")
          (org-entry-put (point-min) "MODIFIED"
                         (format-time-string vulpea-vault-modified-time-format)))))))

(defun vulpea-vault-modified-stamp-setup ()
  "Refresh `:MODIFIED:' when this buffer is saved."
  (add-hook 'before-save-hook #'vulpea-vault-modified-stamp-update nil t))

(add-hook 'org-mode-hook #'vulpea-vault-modified-stamp-setup)

(provide 'vulpea-vault-modified-stamp)
;;; modified-stamp.el ends here
