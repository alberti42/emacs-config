;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `markdown-ts-mode' (tree-sitter backed, bundled with Emacs 31) is the
;; only Markdown major mode configured here.  Out of the box it lacks
;; wiki-link parsing, link-following, and full markup-hiding plumbing for
;; standard inline links; this file adds all of that.  See
;; `docs/modules/markdown-config.md' for the design and invariants.
;;
;; Note: `markdown-mode' the package remains installed as a transitive
;; dependency of `lsp-mode' (lsp-mode requires it for hover popup
;; rendering), but it is not configured here — no `:mode' entry, no
;; hooks, no custom variables.  Our `:mode' below routes `.md' /
;; `.markdown' directly to `markdown-ts-mode'.

;;; Code:

;;; -- Link helpers -----------------------------------------------------------

(defun markdown-config--follow-local-link (url)
  "Resolve URL as a local path symmetrically with wiki-link following.
Called by `markdown-config-follow-link-at-point' for `[label](path)'
inline-link destinations.  Returns non-nil when handled.  Full URLs
(with a scheme such as http://) return nil so the caller can fall
back to `browse-url'.  Local paths follow the same rules as wiki
links:
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

(defun markdown-config--strip-pointy-brackets (text)
  "Strip a matched leading `<' and trailing `>' from TEXT.
Used to clean CommonMark's pointy-bracket form
`[label](<url with spaces>)' into a plain path."
  (if (and (string-prefix-p "<" text)
           (string-suffix-p ">" text))
      (substring text 1 -1)
    text))

(defun markdown-config--inline-link-destination-node (link-node)
  "Return the `link_destination' child of LINK-NODE (an `inline_link'), or nil."
  (when link-node
    (car (treesit-filter-child
          link-node
          (lambda (c)
            (string= (treesit-node-type c) "link_destination"))))))

(defun markdown-config--inline-link-destination-at-point ()
  "Return the URL of the `inline_link' tree-sitter node at point, or nil.

Strips a leading `<' and trailing `>' from CommonMark's pointy-bracket
form (`[label](<url with spaces>)') so the destination is a plain path.

The `markdown-inline' parser is used explicitly because `inline_link'
lives in that grammar (markdown-ts-mode runs `markdown' as host and
embeds `markdown-inline' inside `(inline)' nodes); without the language
hint, `treesit-node-at' returns a node from the host tree where
`inline_link' does not exist."
  (when-let* ((node (treesit-parent-until
                     (treesit-node-at (point) 'markdown-inline)
                     (lambda (n)
                       (string= (treesit-node-type n) "inline_link"))
                     t))
              (dest (markdown-config--inline-link-destination-node node))
              (text (treesit-node-text dest t)))
    (markdown-config--strip-pointy-brackets text)))

(defun markdown-config-follow-link-at-point ()
  "Follow the wiki link, inline link, or URL at point.
Bound on `markdown-ts-mode-map' and on `markdown-config--link-keymap'
(used by both wiki-link and inline-link mouse text properties)."
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

;;; -- markdown-ts-mode link rendering ---------------------------------------
;;
;; Two gaps in the bundled `markdown-ts-mode' to close:
;;
;;   1. Wiki links `[[name]]' / `[[name|alias]]' aren't a grammar node type,
;;      so neither face nor markup hiding nor click-to-follow apply.  We add
;;      all three with a single font-lock keyword layered on top of the
;;      treesit-driven rules (one bounded single-line regex per window —
;;      negligible).
;;
;;   2. Inline links `[label](url)' ARE in the grammar (the bundled mode
;;      applies `link' face to the label), but it does NOT hide the
;;      brackets/parens/URL when `markdown-ts-hide-markup' is on — only
;;      headings, code spans, and a few other constructs are — and it does
;;      NOT make the label clickable.  We extend `treesit-font-lock-settings'
;;      with one rule whose queries run the bundled
;;      `markdown-ts--fontify-delimiter' over `[' `]' `(' `)' /
;;      `link_destination' / `link_title' (giving us face + invisibility
;;      against the `markdown-ts--markup' spec) and our own fontifier over
;;      `link_text' (giving us mouse-1 / mouse-2 click-to-follow via the
;;      shared link keymap).  Both wiki links and inline links route their
;;      clicks through `markdown-config-follow-link-at-point' — same
;;      dispatcher, same destination resolution.

(defface markdown-config-wiki-link-face
  '((t :inherit link))
  "Face for Obsidian-style wiki links in `markdown-ts-mode'."
  :group 'markdown-ts)

(defvar markdown-config--link-keymap
  (let ((map (make-sparse-keymap)))
    ;; mouse-2 follows; mouse-1 also follows because `[follow-link]' is
    ;; bound to `mouse-face' (the standard Emacs convention activated by
    ;; `mouse-1-click-follows-link').
    (define-key map [mouse-2]     #'markdown-config-follow-link-at-point)
    (define-key map [follow-link] 'mouse-face)
    map)
  "Keymap installed via the `keymap' text property on link labels.
Shared between wiki-link labels (`[[…]]', via the regex font-lock
keyword) and inline-link labels (`[label](url)', via the treesit
fontifier).  The keymap is parser-agnostic — the bound command,
`markdown-config-follow-link-at-point', dispatches based on what's
actually at point.")

(defun markdown-config--wiki-link-fontify (limit)
  "Font-lock MATCHER for `[[name]]' and `[[name|alias]]'.
Restricts match data to the visible label so the keyword's face applies
to that region only.  Adds clickability (`keymap', `mouse-face',
`help-echo') to the label and, when `markdown-ts-hide-markup' is on,
sets `invisible' on the surrounding markup using the bundled
`markdown-ts--markup' spec — `markdown-ts-toggle-hide-markup' calls
`font-lock-flush' which re-runs this matcher with the new value."
  (when (re-search-forward "\\[\\[\\([^]\n]+\\)\\]\\]" limit t)
    (let* ((beg       (match-beginning 0))
           (end       (match-end 0))
           (inner-beg (match-beginning 1))
           (inner-end (match-end 1))
           (inner     (match-string-no-properties 1))
           (pipe      (string-match-p "|" inner))
           (label-beg (if pipe (+ inner-beg pipe 1) inner-beg))
           (label-end inner-end)
           (target    (if pipe (substring inner 0 pipe) inner)))
      (add-text-properties label-beg label-end
                           (list 'mouse-face 'highlight
                                 'keymap markdown-config--link-keymap
                                 'help-echo (concat "Wiki link → " target)))
      (when markdown-ts-hide-markup
        (put-text-property beg label-beg 'invisible 'markdown-ts--markup)
        (put-text-property label-end end  'invisible 'markdown-ts--markup))
      (set-match-data (list label-beg label-end))
      t)))

(defun markdown-config--inline-link-text-fontify (node _override _start _end &rest _)
  "Treesit fontifier: add clickability to a `link_text' NODE.

Attaches `mouse-face', `keymap' (the shared `markdown-config--link-keymap'),
and a `help-echo' that previews the link's destination.  The bundled
mode already applies the `link' face to this region; we only add the
text properties.  All other arguments are part of the treesit
fontifier signature and unused.

The destination is read from the parent `inline_link' node's
`link_destination' child — angle brackets are stripped for display
so the help-echo shows a plain path even for the pointy-bracket
form."
  (let* ((node-beg (treesit-node-start node))
         (node-end (treesit-node-end   node))
         (parent   (treesit-node-parent node))
         (dest     (and parent
                        (string= (treesit-node-type parent) "inline_link")
                        (markdown-config--inline-link-destination-node parent)))
         (target   (and dest
                        (markdown-config--strip-pointy-brackets
                         (treesit-node-text dest t)))))
    (add-text-properties
     node-beg node-end
     (list 'mouse-face 'highlight
           'keymap     markdown-config--link-keymap
           'help-echo  (if target (concat "Link → " target) "Link")))))

(defun markdown-config--markdown-ts-mode-setup ()
  "Wire wiki-link rendering and inline-link extras.

Adds two layers on top of the bundled `markdown-ts-mode' rules — see
the section commentary above for what each layer does and why each
is needed."
  ;; --- Wiki-link font-lock keyword (regex-based) ---------------------------
  (setq-local font-lock-extra-managed-props
              (append font-lock-extra-managed-props
                      '(invisible mouse-face keymap help-echo)))
  (font-lock-add-keywords
   nil
   '((markdown-config--wiki-link-fontify
      (0 'markdown-config-wiki-link-face prepend)))
   'append)
  ;; --- Inline-link extras: hiding + click-to-follow (treesit-based) -------
  ;; Reuse the bundled `markdown-ts--fontify-delimiter' on the brackets,
  ;; parens, `link_destination' and `link_title' so face + invisibility
  ;; behave like the rest of the mode's hidden markup.  Add our own
  ;; fontifier on `link_text' to attach `mouse-face' / `keymap' /
  ;; `help-echo' so the label is clickable via the shared link keymap.
  ;; The feature symbol is registered in level 3 so it activates at the
  ;; default `treesit-font-lock-level' of 3.
  (setq-local treesit-font-lock-settings
              (append treesit-font-lock-settings
                      (treesit-font-lock-rules
                       :language 'markdown-inline
                       :feature 'markdown-config-inline-link-extras
                       :override 'append
                       '((inline_link [ "[" "]" "(" ")" ]
                                      @markdown-ts--fontify-delimiter)
                         (inline_link (link_destination)
                                      @markdown-ts--fontify-delimiter)
                         (inline_link (link_title)
                                      @markdown-ts--fontify-delimiter)
                         (inline_link (link_text)
                                      @markdown-config--inline-link-text-fontify)))))
  (setq-local treesit-font-lock-feature-list
              (treesit-merge-font-lock-feature-list
               treesit-font-lock-feature-list
               '(() () (markdown-config-inline-link-extras))))
  (treesit-font-lock-recompute-features)
  (font-lock-flush))

;;; -- markdown-ts-mode -------------------------------------------------------

;; Emacs 31 ships markdown-ts-mode as the default for `.md' / `.markdown'.
;; lsp-mode hard-`require's `markdown-mode' at load time (for hover popup
;; rendering), and that require prepends an `auto-mode-alist' entry whose
;; broader regex (mkd|mdown|mkdn|mdwn|mdx|md|markdown) shadows the built-in
;; markdown-ts-mode association.  Rewrite the entry on `markdown-mode' load
;; so the same regex routes to markdown-ts-mode.  This relies on lsp-mode
;; (or some other consumer) actually loading markdown-mode; if nothing ever
;; does, the hook is a no-op and the built-in `.md'/`.markdown' association
;; is sufficient.
(with-eval-after-load 'markdown-mode
  (dolist (entry auto-mode-alist)
    (when (eq (cdr entry) 'markdown-mode)
      (setcdr entry 'markdown-ts-mode))))

(use-package markdown-ts-mode
  :straight nil  ; bundled with Emacs 31, shadowed by local patched copy
  :load-path (lambda () (list (expand-file-name "markdown-ts-mode" emacs-config-dir)))
  :mode (("\\.md\\'"       . markdown-ts-mode)
         ("\\.markdown\\'" . markdown-ts-mode))
  :custom
  (markdown-ts-hide-markup t)
  :hook (markdown-ts-mode . markdown-config--markdown-ts-mode-setup)
  :bind (:map markdown-ts-mode-map
              ("C-c C-o"     . markdown-config-follow-link-at-point) ; Same as in classic markdown-mode for `markdown-follow-thing-at-point'
              ("C-c C-x RET" . markdown-ts-toggle-hide-markup)
              ("M-<left>"    . nil)     ; Free M-<left>/M-<right> for word navigation (Emacs default `left-word'/`right-word')
              ("M-<right>"   . nil)
              ("C-c C-x l"   . markdown-ts-promote) ; Use bindings as in classic markdown-mode
              ("C-c C-x r"   . markdown-ts-demote)))

;;; -- grip-mode: live GitHub Markdown preview in browser --------------------

(use-package grip-mode
  :straight t
  :defer t)

;;; -- debug function ----------------------------------------------------------

;; The function below was provided off-the-list by Rahul Juliato (maintainer of markdown-ts-mode).
;;
;; When a problem occurs, move the point over where the problem is and
;; M-x my/md-recreate-inline-parser-at-point RET.

(defun my/md-recreate-inline-parser-at-point ()
  "Delete stale local markdown-inline parser+overlay covering point, recreate."
  (interactive)
  (let* ((p (point))
         (target-ov
          (catch 'f
            (dolist (ov (overlays-in (point-min) (point-max)))
              (let ((pr (overlay-get ov 'treesit-parser)))
                (when (and pr
                           (overlay-get ov 'treesit-parser-local-p)
                           (eq (treesit-parser-language pr) 'markdown-inline)
                           (<= (overlay-start ov) p (overlay-end ov)))
                  (throw 'f ov)))))))
    (unless target-ov (user-error "No markdown-inline overlay covers point"))
    (let* ((old-pr (overlay-get target-ov 'treesit-parser))
           (host (overlay-get target-ov 'treesit-host-parser))
           (level (treesit-parser-embed-level old-pr))
           (r-start (overlay-start target-ov))
           (r-end (overlay-end target-ov)))
      (treesit-parser-delete old-pr)
      (delete-overlay target-ov)
      (let ((new (treesit-parser-create 'markdown-inline nil t 'embedded))
            (ov (make-overlay r-start r-end nil nil t)))
        (treesit-parser-set-embed-level new level)
        (overlay-put ov 'treesit-parser new)
        (overlay-put ov 'treesit-parser-local-p t)
        (overlay-put ov 'treesit-host-parser host)
        (overlay-put ov 'treesit-parser-ov-timestamp (buffer-chars-modified-tick))
        (treesit-parser-set-included-ranges new `((,r-start . ,r-end)))
        (font-lock-flush r-start r-end)
        (message "Recreated markdown-inline parser for (%d . %d)" r-start r-end)))))

(provide 'markdown-config)
;;; markdown-config.el ends here
