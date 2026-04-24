;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Code:

;;; -- Setup and fixes for markdown-mode ---------------------------------------

(defun markdown-config--follow-local-link (url)
  "Handle local file links symmetrically with `markdown-config--follow-wiki-link'.
Added to `markdown-follow-link-functions'.  Full URLs (with a scheme
such as http://) are returned nil so the default browser handler runs.
Local paths follow the same rules as wiki links:
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

(use-package markdown-mode
  :straight t
  :mode (("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :custom
  ;; Fontify fenced code blocks using their language's major mode.
  (markdown-fontify-code-blocks-natively t)
  ;; Support wiki links
  (markdown-enable-wiki-links t)
  ;; Parse wiki links with the correct structure [[link|label]]
  (markdown-wiki-link-alias-first nil)
  :hook ((markdown-mode gfm-mode) . markdown-config--markup-setup)
  :config
  ;; Replace the default follower, which appends the current buffer's
  ;; extension to the link name (turning "foo.pdf" into "foo.pdf.md")
  ;; and replaces spaces with dashes, breaking Obsidian-style paths.
  (advice-add 'markdown-follow-wiki-link :override
              #'markdown-config--follow-wiki-link)
  ;; Apply the same logic to standard [label](path) links.
  (add-hook 'markdown-follow-link-functions
            #'markdown-config--follow-local-link))

(defun markdown-config--markup-setup ()
  "Enable markup hiding for a clean reading experience.
`markdown-hide-markup' is a superset of `markdown-hide-urls', so
enabling it alone is sufficient to hide URLs, brackets, asterisks, etc."
  ;; markdown-toggle-markup-hiding does more than setq: it updates
  ;; invisibility-spec and calls markdown-reload-extensions.
  (markdown-toggle-markup-hiding 1))

;;; -- grip-mode: live GitHub Markdown preview in browser ----------------------

(use-package grip-mode
  :straight t
  :bind (:map markdown-mode-command-map
              ("g" . grip-mode)))

;;; -- Support for Obsidian vault ----------------------------------------------

;; Currently disabled because buggy and malfunctioning
(when nil
  (use-package obsidian
    :straight (obsidian :type git
                        :local-repo "/Users/andrea/google-drive/dotfiles/.config/emacs/local"
                        :files ("obsidian.el"))
    :hook ((markdown-mode gfm-mode) . obsidian-mode)
    :config
    :bind (:map obsidian-mode-map
                ("C-c o f" . obsidian-follow-link-at-point)
                ("C-c o b" . obsidian-backlinks)
                ("C-c o F" . obsidian-find-file)
                ("C-c o i" . obsidian-insert-wikilink))))

(provide 'markdown-config)
;;; markdown-config.el ends here
