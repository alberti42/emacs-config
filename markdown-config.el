;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Two modes are configured side by side:
;;
;; - `markdown-ts-mode' (primary, daily): tree-sitter backed, fast on large
;;   files.  Lacks wiki-link parsing, link-following, and markup-hiding
;;   plumbing out of the box; we add them here.
;;
;; - `markdown-mode' (escape hatch via `M-x markdown-mode'): kept until
;;   `markdown-ts-mode' reaches feature parity for our workflow.  All the
;;   historical fixes (wiki-link follower override, link-functions hook,
;;   markup hiding) stay active so the escape hatch behaves correctly.
;;
;; The two modes share the same link-resolution helpers below.

;;; Code:

;;; -- Shared link helpers ----------------------------------------------------

(defun markdown-config--follow-local-link (url)
  "Resolve URL as a local path symmetrically with wiki-link following.
Used as a member of `markdown-follow-link-functions' (markdown-mode)
and called directly by `markdown-config-follow-link-at-point'
(markdown-ts-mode).  Returns non-nil when handled.  Full URLs (with a
scheme such as http://) return nil so the caller can fall back to
`browse-url'.  Local paths follow the same rules as wiki links:
- Markdown files (.md, .markdown): open with `find-file'.
- Other files: open `dired' with the target highlighted.
- Non-existent files: signal an error with the resolved path."
  (let* ((struct (url-generic-parse-url url))
         (full (url-fullness struct)))
    (unless full
      (let* ((file (car (url-path-and-query struct)))
             (wp (and buffer-file-name
                      (file-name-directory buffer-file-name))))
        (when (and file wp (> (length file) 0))
          (let ((full-path (expand-file-name file wp)))
            (if (not (file-exists-p full-path))
                (user-error "Link target not found: %s" full-path)
              (let ((ext (downcase (or (file-name-extension full-path) ""))))
                (if (member ext '("md" "markdown"))
                    (find-file full-path)
                  (dired (file-name-directory full-path))
                  (dired-goto-file full-path))))
            t))))))

(defun markdown-config--follow-wiki-link (name &optional other)
  "Custom wiki-link follower for Obsidian-style notes.
Resolves NAME relative to the current buffer's directory without
mangling spaces or blindly appending the buffer's own extension.

If NAME has no file extension, \".md\" is appended.  Then:
- Markdown targets (.md, .markdown): open with `find-file'.
- Other file types: open `dired' with the target highlighted.
- Non-existent targets: signal an error showing the resolved path.
- Never creates empty files."
  (unless buffer-file-name
    (user-error "Must be visiting a file"))
  (let* ((wp (file-name-directory buffer-file-name))
         (filename (if (file-name-extension name)
                       name
                     (concat name ".md")))
         (full-path (expand-file-name filename wp)))
    (if (not (file-exists-p full-path))
        (user-error "Wiki link target not found: %s" full-path)
      (let ((ext (downcase (or (file-name-extension full-path) ""))))
        (if (member ext '("md" "markdown"))
            (if other
                (find-file-other-window full-path)
              (find-file full-path))
          ;; Non-markdown file: open its containing directory in dired
          ;; and move point to the file so the user can act on it.
          (let ((dir (file-name-directory full-path)))
            (if other
                (dired-other-window dir)
              (dired dir))
            (dired-goto-file full-path)))))))

(defconst markdown-config--wiki-link-regexp
  "\\[\\[\\([^]|\n]+?\\)\\(?:|[^]\n]*?\\)?\\]\\]"
  "Match `[[name]]' or `[[name|label]]'; group 1 is the resolvable name.
The tree-sitter-markdown grammar does not expose wiki links as a node
type, so detection is text-level even under `markdown-ts-mode'.")

(defun markdown-config--inline-link-destination-at-point ()
  "Return the URL of the `inline_link' tree-sitter node at point, or nil."
  (when-let* ((node (treesit-parent-until
                     (treesit-node-at (point))
                     (lambda (n)
                       (string= (treesit-node-type n) "inline_link"))
                     t))
              (dest (car (treesit-filter-child
                          node
                          (lambda (c)
                            (string= (treesit-node-type c)
                                     "link_destination"))))))
    (treesit-node-text dest t)))

(defun markdown-config-follow-link-at-point ()
  "Follow the wiki link, inline link, or URL at point.
Bound on `markdown-ts-mode-map'.  `markdown-mode' has its own native
handler patched via advice; do not bind this command there."
  (interactive)
  (cond
   ((thing-at-point-looking-at markdown-config--wiki-link-regexp)
    (markdown-config--follow-wiki-link (match-string-no-properties 1)))
   ((when-let* ((dest (markdown-config--inline-link-destination-at-point)))
      (or (markdown-config--follow-local-link dest)
          (browse-url dest))))
   ((when-let* ((url (thing-at-point 'url)))
      (browse-url url)))
   (t (user-error "No link at point"))))

;;; -- markdown-ts-mode (primary) ---------------------------------------------

(use-package markdown-ts-mode
  :straight nil  ; bundled with Emacs 31
  :custom
  (markdown-ts-hide-markup t)
  :bind (:map markdown-ts-mode-map
              ("C-c C-o"   . markdown-config-follow-link-at-point)
              ("C-c C-c g" . grip-mode)))

;;; -- markdown-mode (escape hatch — fixes preserved) -------------------------
;;
;; Daily routing goes to `markdown-ts-mode' via `major-mode-remap-alist' in
;; `treesitter-config.el'.  This block keeps `markdown-mode' fully usable via
;; `M-x markdown-mode' so the historical fixes remain available until the
;; tree-sitter flow reaches feature parity for note-taking workflows.

(defun markdown-config--markdown-mode-setup ()
  "Enable markup hiding in `markdown-mode'.
`markdown-hide-markup' is a superset of `markdown-hide-urls', so enabling
it alone is sufficient to hide URLs, brackets, asterisks, etc."
  ;; markdown-toggle-markup-hiding does more than setq: it updates
  ;; invisibility-spec and calls markdown-reload-extensions.
  (markdown-toggle-markup-hiding 1))

(use-package markdown-mode
  :straight t
  :mode (("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :custom
  (markdown-fontify-code-blocks-natively t)
  (markdown-enable-wiki-links t)
  (markdown-wiki-link-alias-first nil)
  :hook ((markdown-mode gfm-mode) . markdown-config--markdown-mode-setup)
  :bind (:map markdown-mode-command-map
              ("g" . grip-mode))
  :config
  ;; Replace the default follower, which appends the current buffer's
  ;; extension to the link name (turning "foo.pdf" into "foo.pdf.md")
  ;; and replaces spaces with dashes, breaking Obsidian-style paths.
  (advice-add 'markdown-follow-wiki-link :override
              #'markdown-config--follow-wiki-link)
  ;; Apply the same logic to standard [label](path) links.
  (add-hook 'markdown-follow-link-functions
            #'markdown-config--follow-local-link))

;;; -- grip-mode: live GitHub Markdown preview in browser --------------------

(use-package grip-mode
  :straight t
  :defer t)

(provide 'markdown-config)
;;; markdown-config.el ends here
