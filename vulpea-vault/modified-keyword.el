;;; modified-keyword.el --- Keep #+modified: current on save -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Notes converted from the Obsidian vault carry `#+created:' and `#+modified:'
;; keywords.  In Obsidian the frontmatter-modified-date plugin refreshed the
;; latter on every edit; this does the same on save.
;;
;; Only buffers that already have the keyword are touched, so this never adds
;; it to an org file that does not use the convention.

;;; Code:

(defconst vulpea-vault-modified-time-format "%FT%T%:z"
  "`format-time-string' spec for the `#+modified:' value.
Matches what the vault already contains, e.g. 2026-04-13T08:08:00+02:00.
Note `%:z' for the colon in the zone offset; plain `%z' would write
+0200 and make new stamps differ from the migrated ones.")

(defun vulpea-vault-modified-keyword-update ()
  "Set this buffer's `#+modified:' keyword to the current time.
Does nothing if the buffer has no such keyword."
  (when (derived-mode-p 'org-mode)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char (point-min))
        ;; Keywords apply to the file only before the first headline, so stop
        ;; there rather than scanning the whole buffer.
        (let ((limit (save-excursion
                       (if (re-search-forward "^\\*+[ \t]" nil t)
                           (match-beginning 0)
                         (point-max))))
              (case-fold-search t))
          (when (re-search-forward "^#\\+modified:[ \t]*\\(.*\\)$" limit t)
            (replace-match (format-time-string vulpea-vault-modified-time-format)
                           t t nil 1)))))))

(defun vulpea-vault-modified-keyword-setup ()
  "Refresh `#+modified:' when this buffer is saved."
  (add-hook 'before-save-hook #'vulpea-vault-modified-keyword-update nil t))

(add-hook 'org-mode-hook #'vulpea-vault-modified-keyword-setup)

(provide 'vulpea-vault-modified-keyword)
;;; modified-keyword.el ends here
