;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `markdown-ts-mode' (tree-sitter backed, bundled with Emacs 31) is the
;; only Markdown major mode configured here.  Out of the box it lacks
;; wiki-link parsing, link-following, and full markup-hiding plumbing for
;; standard inline links; this file adds all of that.  See
;; `docs/modules/markdown-config.md' for the design and invariants.
;;
;; Note: classic `markdown-mode' is not configured or used here at all —
;; no `:mode' entry, no hooks, no custom variables, and no preview package
;; depends on it.  It is only installed if some other package pulls it in
;; as a dependency (e.g. `rustic').  Our `:mode' below routes `.md' /
;; `.markdown' directly to `markdown-ts-mode'.

;;; Code:

(require 'cl-lib)                        ; `cl-letf' (preview major-mode advice)

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

(defun markdown-config--obsidian-vault-root (dir)
  "Return the Obsidian vault root at or above DIR, or nil if none.
The vault root is the nearest ancestor directory containing a
`.obsidian' subdirectory; nil is returned when no such ancestor
exists (DIR is not inside an Obsidian vault)."
  (when-let* ((root (locate-dominating-file
                     dir
                     (lambda (d)
                       (file-directory-p (expand-file-name ".obsidian" d))))))
    (file-name-as-directory (expand-file-name root))))

(defun markdown-config--follow-wiki-link (name &optional other)
  "Custom wiki-link follower for Obsidian-style notes.
Resolves NAME to a file and opens it.  Spaces are kept verbatim, and
\".md\" is appended only when NAME has no file extension.

NAME is resolved against a base directory chosen by its shape:
- NAME containing a `/' is a vault-relative path: it resolves from the Obsidian
  vault root, i.e. the nearest ancestor directory of the current file that
  contains a `.obsidian' subdirectory.  When the current file lives outside any
  Obsidian vault (no such ancestor), it resolves from the current file's
  directory instead.
- A bare NAME (no `/') always resolves from the current file's directory.

Once resolved to FULL-PATH:
- Markdown targets (.md, .markdown): open with `find-file'.
- Other file types: open `dired' with the target highlighted.
- Non-existent targets: signal an error showing FULL-PATH.
- Never creates empty files."
  (unless buffer-file-name
    (user-error "Must be visiting a file"))
  (let* ((wp (file-name-directory buffer-file-name))
         (filename (if (file-name-extension name)
                       name
                     (concat name ".md")))
         ;; Obsidian paths with a slash are vault-relative; bare names resolve
         ;; against the current file's directory.  Fall back to the current
         ;; directory when no vault root is found.
         (base (or (and (string-search "/" filename)
                        (markdown-config--obsidian-vault-root wp))
                   wp))
         (full-path (expand-file-name filename base)))
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

(defconst markdown-config--inline-link-regexp
  "\\[\\([^]\n]+\\)\\](\\(<[^>\n]*>\\|[^)\n]+\\))"
  "Match a CommonMark inline link `[label](url)'; group 1 label, 2 url.
Group 2 matches either the pointy-bracket form `<url>' (which may itself
contain `)') or a bare `url' that stops at the first `)'.  Callers strip
the angle brackets via `markdown-config--strip-pointy-brackets'.
Used where the tree-sitter `inline_link' node is unavailable — notably
inside table cells, whose content the grammar does not route through the
`markdown-inline' parser, so no `inline_link' node ever exists there.")

(defun markdown-config--strip-pointy-brackets (text)
  "Strip a matched leading `<' and trailing `>' from TEXT.
Used to clean CommonMark's pointy-bracket form
`[label](<url with spaces>)' into a plain path."
  (if (and (string-prefix-p "<" text)
           (string-suffix-p ">" text))
      (substring text 1 -1)
    text))

(defun markdown-config--normalize-link-path (path)
  "Strip a `<...>' wrapper from PATH and percent-decode it when encoded.
Turns CommonMark's pointy-bracket form `<path with spaces>' and a
percent-encoded `path%20with%20spaces' into a plain filesystem path.
Percent-decoding runs only when PATH actually contains a `%XX' escape, so
a plain path (or an already-decoded one) is returned unchanged and a
literal `%' in a filename is left alone."
  (let ((p (markdown-config--strip-pointy-brackets path)))
    (if (string-match-p "%[0-9A-Fa-f][0-9A-Fa-f]" p)
        (url-unhex-string p)
      p)))

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
   ;; Regex fallback for `[label](url)' where there is no `inline_link'
   ;; node to resolve against — chiefly inside table cells.
   ((thing-at-point-looking-at markdown-config--inline-link-regexp)
    (let ((dest (markdown-config--strip-pointy-brackets
                 (match-string-no-properties 2))))
      (or (markdown-config--follow-local-link dest)
          (browse-url dest))))
   ((when-let* ((url (thing-at-point 'url)))
      (browse-url url)))
   (t (user-error "No link at point"))))

;;; -- bundled link/image handling fixes -------------------------------------
;;
;; Two corrections to the bundled `markdown-ts-mode' that share
;; `markdown-config--normalize-link-path':
;;
;;   1. `markdown-ts--fontify-image' resolves an image's `link_destination'
;;      with a bare `expand-file-name' on the raw node text, so the
;;      pointy-bracket form `![a](<path with spaces>)' keeps its literal
;;      `<>' and a `%20'-encoded path keeps its escapes — both then fail the
;;      `file-exists-p' guard and the image silently never renders.  We
;;      normalize the destination by hooking the one `treesit-node-text'
;;      call the fontifier makes (guarded to `link_destination' nodes) for
;;      the dynamic extent of ORIG.  Hooking `expand-file-name' here would
;;      be wrong: it is a C primitive, and redefining it forces native-comp
;;      trampoline rebuilds on every fontify pass.  `treesit-node-text' is a
;;      native-compiled Lisp function (`subr-native-elisp-p'), so rebinding
;;      it needs no trampoline.
;;
;;   2. `markdown-ts--make-link-button' gives every schemeless destination a
;;      stock `find-file' action, so clicking an image/link button opens the
;;      target in a buffer (e.g. a JPEG in image-mode) regardless of type.
;;      We reroute schemeless (local-file) buttons through
;;      `markdown-config--follow-local-link' so they obey the same policy as
;;      `C-c C-o': markdown opens with `find-file', anything else lands in
;;      `dired' with point on the file.  URLs, `mailto:' and `#fragment'
;;      targets keep the stock action.

(defun markdown-config--fontify-image-normalize-dest (orig &rest args)
  "Around advice on `markdown-ts--fontify-image': accept bracketed/encoded paths.
Rebinds `treesit-node-text' for the duration of ORIG so that the text of a
`link_destination' node passes through `markdown-config--normalize-link-path'
before path resolution, letting `![a](<path with spaces>)' and `%20'-encoded
local images render.  Only `link_destination' results are rewritten; every
other node's text is returned verbatim.  `treesit-node-text' is a Lisp
function, so this rebind triggers no native-comp trampoline (unlike rebinding
the C primitive `expand-file-name')."
  (cl-letf* ((orig-fn (symbol-function 'treesit-node-text))
             ((symbol-function 'treesit-node-text)
              (lambda (node &optional no-property)
                (let ((text (funcall orig-fn node no-property)))
                  (if (and node
                           (string= (treesit-node-type node) "link_destination"))
                      (markdown-config--normalize-link-path text)
                    text)))))
    (apply orig args)))

(defun markdown-config--reroute-link-button (orig beg end url)
  "Around advice on `markdown-ts--make-link-button': route local files via dired.
Builds the stock button (ORIG over BEG, END, URL), then for a schemeless
URL (a local file path) replaces the stock `find-file' action with
`markdown-config--follow-local-link', so clicking obeys the same
type-aware policy as `markdown-config-follow-link-at-point'.  Fragments,
`mailto:' and other `scheme:' URLs keep the stock action."
  (funcall orig beg end url)
  (unless (or (string-prefix-p "#" url)
              (let ((case-fold-search nil))
                (string-match-p "\\`[a-z]+:" url)))
    (put-text-property
     beg end 'action
     (lambda (_button)
       (let ((dest (markdown-config--normalize-link-path url)))
         (or (markdown-config--follow-local-link dest)
             (find-file dest)))))))

(with-eval-after-load 'markdown-ts-mode
  (advice-add 'markdown-ts--fontify-image :around
              #'markdown-config--fontify-image-normalize-dest)
  (advice-add 'markdown-ts--make-link-button :around
              #'markdown-config--reroute-link-button))

;;; -- markdown-ts-mode link rendering -----------------------------------------
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

(defun markdown-config--in-table-cell-p (pos)
  "Return non-nil when POS lies inside a `pipe_table'.
Used to scope regex-based inline-link rendering to table cells, whose
content the grammar parses as raw block-level tokens rather than routing
it through the `markdown-inline' parser (so no `inline_link' node exists
there for the treesit-driven rules to match)."
  (when-let* ((node (treesit-node-at pos 'markdown)))
    (treesit-parent-until node "\\`pipe_table\\'" t)))

(defun markdown-config--table-inline-link-fontify (limit)
  "Font-lock MATCHER for `[label](url)' inside table cells, up to LIMIT.
The grammar emits no `inline_link' node inside a `pipe_table_cell', so
the treesit rule that renders inline links in paragraphs never fires
there.  This regex matcher fills the gap: it applies the `link' face and
click-to-follow to the label and, when `markdown-ts-hide-markup' is on,
replaces the surrounding `[' and `](url)' markup with a width-preserving
`display' space — unlike `invisible', which collapses the text to zero
width — so the cell keeps the same column count as its raw text and the
table stays aligned."
  (let (matched)
    (while (and (not matched)
                (re-search-forward markdown-config--inline-link-regexp limit t))
      (let ((beg       (match-beginning 0))
            (label-beg (match-beginning 1))
            (label-end (match-end 1))
            (end       (match-end 0))
            (target    (markdown-config--strip-pointy-brackets
                        (match-string-no-properties 2))))
        ;; Paragraph links are handled by the treesit path; only take over
        ;; inside table cells, where no `inline_link' node exists.
        (when (markdown-config--in-table-cell-p beg)
          (add-text-properties label-beg label-end
                               (list 'mouse-face 'highlight
                                     'keymap markdown-config--link-keymap
                                     'help-echo (concat "Link → " target)))
          (when markdown-ts-hide-markup
            (put-text-property beg label-beg 'display
                               `(space :width ,(- label-beg beg)))
            (put-text-property label-end end 'display
                               `(space :width ,(- end label-end))))
          (set-match-data (list label-beg label-end))
          (setq matched t))))
    matched))

(defun markdown-config--markdown-ts-mode-setup ()
  "Wire wiki-link rendering and inline-link extras.

Adds two layers on top of the bundled `markdown-ts-mode' rules — see
the section commentary above for what each layer does and why each
is needed."
  ;; --- Wiki-link font-lock keyword (regex-based) ---------------------------
  (setq-local font-lock-extra-managed-props
              (append font-lock-extra-managed-props
                      '(invisible display mouse-face keymap help-echo)))
  (font-lock-add-keywords
   nil
   '((markdown-config--wiki-link-fontify
      (0 'markdown-config-wiki-link-face prepend))
     ;; Inline links `[label](url)' inside table cells: the treesit path
     ;; cannot reach them (no `inline_link' node in a `pipe_table_cell'),
     ;; so render them via the same parser-agnostic keyword mechanism.
     (markdown-config--table-inline-link-fontify
      (0 'link prepend)))
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
  ;; --- Code-fence collapse + reveal-on-edit -------------------------------
  ;; `markdown-config--collapse-fence-line' (advice) hides each fence line with
  ;; a `display' overlay; `reveal-mode' opens the one point is on for editing;
  ;; the notifier prunes overlays when a fence is deleted.
  (when treesit-primary-parser
    (treesit-parser-add-notifier
     treesit-primary-parser #'markdown-config--prune-fence-overlays))
  (reveal-mode 1)
  (font-lock-flush))

;;; -- markdown-ts-mode -------------------------------------------------------

;; Emacs 31 ships markdown-ts-mode as the default for `.md' / `.markdown'.
;; Nothing here configures classic `markdown-mode' anymore.  Should it ever
;; get pulled in as a transitive dependency (e.g. `rustic' requires it), its
;; autoloads prepend an `auto-mode-alist' entry whose broader regex
;; (mkd|mdown|mkdn|mdwn|mdx|md|markdown) would shadow the built-in
;; markdown-ts-mode association.  Rewrite the entry on `markdown-mode' load so
;; the same regex routes to markdown-ts-mode.  Guard only: if markdown-mode
;; never loads, this hook never fires and the built-in association suffices.
(with-eval-after-load 'markdown-mode
  (dolist (entry auto-mode-alist)
    (when (eq (cdr entry) 'markdown-mode)
      (setcdr entry 'markdown-ts-mode))))

(use-package markdown-ts-mode
  :straight nil  ; bundled with Emacs 31
  :mode (("\\.md\\'"       . markdown-ts-mode)
         ("\\.markdown\\'" . markdown-ts-mode))
  :custom
  (markdown-ts-hide-markup t)
  :hook (markdown-ts-mode . markdown-config--markdown-ts-mode-setup)
  ;; Keep M-<left>/M-<right> as word navigation everywhere (Emacs default
  ;; `left-word'/`right-word') and route structural left/right onto
  ;; `C-c C-x <left>'/`<right>' instead.  The chord is symmetric and
  ;; context-sensitive: outside a table it promotes/demotes the heading;
  ;; inside a table the higher-priority `markdown-ts-in-table-mode-map'
  ;; takes over and moves the current column.
  :bind (:map markdown-ts-mode-map
              ("C-c C-o"      . markdown-config-follow-link-at-point) ; Follow link at point
              ("C-c C-x RET"  . markdown-ts-toggle-hide-markup)
              ("M-<left>"     . nil)    ; Free M-<left>/M-<right> for word navigation
              ("M-<right>"    . nil)
              ("C-c C-x <left>"  . markdown-ts-promote)
              ("C-c C-x <right>" . markdown-ts-demote)
              ;; Fill table cells to a max width, then realign the table.
              ("C-c C-x t"       . (lambda ()
                                     (interactive)
                                     (call-interactively #'markdown-ts-table-fill-cells)
                                     (call-interactively #'markdown-ts-table-align-table)))

              ;; Inside a table this minor-mode map shadows the major-mode map
              ;; above.  Restore word navigation on M-<left>/M-<right> and put
              ;; the column-move commands on the symmetric C-c C-x arrows.
              :map markdown-ts-in-table-mode-map
              ("M-<left>"        . left-word)
              ("M-<right>"       . right-word)
              ("C-c C-x <left>"  . markdown-ts-table-move-column-left)
              ("C-c C-x <right>" . markdown-ts-table-move-column-right)))

;; Collapse code-fence lines (```lang opener, closing ```) when markup is
;; hidden, and let stock `reveal-mode' un-collapse the one point is on so it
;; can be edited.  The bundled fontifier marks only the delimiter *text*
;; invisible, leaving the line's newline live, so each hidden fence leaves a
;; stray blank row.  We hide the whole physical line — newline included — with
;; an overlay `display' of "", which renders the range as nothing and pulls the
;; next line up.
;;
;; Why an overlay + `display' instead of the `invisible' text property:
;; `reveal-mode' only reveals OVERLAYS (it scans `overlays-at'), and only those
;; hidden via ellipsis-`invisible' or a `display' property carrying a
;; `reveal-toggle-invisible' function (see its `reveal-open-new-overlays').  A
;; plain `invisible' overlay/property is invisible to it; ellipsis would render
;; a literal "…" on the row.  `display' "" + a toggle function is the only form
;; that both fully removes the line and is revealable.
;;
;; The host also marks the delimiter/info_string text `invisible'; we drop that
;; on every fontify pass so that when reveal clears our `display' the fence text
;; (including the language tag) is actually visible for editing.  Acting on both
;; `fenced_code_block_delimiter' (open + close) and `info_string' (the language
;; tag, on the opener's line) keeps one overlay per fence line regardless of
;; the order font-lock visits the captures.
;;
;; Reveal mirrors onto the block's opposite fence so opener and closer reveal
;; and re-collapse together.  The sibling link is stored on each overlay at
;; fontify time (where the parse tree is solid) rather than looked up inside
;; the reveal toggle — a toggle-time treesit query was the earlier approach and
;; it failed: if the closing fence had not been fontified yet its overlay did
;; not exist, and any error in the lookup was swallowed by reveal's
;; `with-demoted-errors', so the opener toggled but the closer silently did not.

(defun markdown-config--fence-overlay-toggle (ov hidep)
  "Collapse OV's fence line when HIDEP, reveal it otherwise.
Mirrors the same `display' onto OV's stored sibling overlay (the block's
other fence line) so opener and closer move together.  Does no treesit
work — just reads `markdown-config-fence-sibling'.  `reveal-toggle-invisible'
function: `reveal-mode' calls it with HIDEP nil to reveal and non-nil to
re-hide.  Collapsing uses a `display' of \"\" so the whole line (newline
included) renders as nothing."
  (let ((disp (and hidep ""))
        (sib (overlay-get ov 'markdown-config-fence-sibling)))
    (overlay-put ov 'display disp)
    (when (and sib (overlay-buffer sib))
      (overlay-put sib 'display disp))))

(defun markdown-config--ensure-fence-overlay (beg end)
  "Return the fence-collapse overlay spanning BEG..END, creating it collapsed.
Reuses an existing `markdown-config-fence-collapse' overlay on the line
\(repositioning it) WITHOUT touching its `display', so a fence currently
revealed by `reveal-mode' is not re-collapsed mid-edit by a refontify."
  (let ((ov (seq-find (lambda (o) (overlay-get o 'markdown-config-fence-collapse))
                      (overlays-at beg))))
    (if ov
        (move-overlay ov beg end)
      (setq ov (make-overlay beg end nil t nil))
      (overlay-put ov 'markdown-config-fence-collapse t)
      (overlay-put ov 'reveal-toggle-invisible
                   #'markdown-config--fence-overlay-toggle)
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'display ""))
    ov))

(defun markdown-config--ensure-block-fence-overlays (block)
  "Ensure a collapse overlay on each fence line of BLOCK and cross-link them.
Both overlays are created from parse-tree positions, so the closing
fence's overlay exists even before that line has been fontified or
scrolled into view — that is what lets `reveal-mode' mirror the opener
onto a not-yet-displayed closer.  Links the pair via
`markdown-config-fence-sibling' so the toggle needs no treesit lookup."
  (let (ovs)
    (dolist (child (treesit-node-children block t))
      (when (equal (treesit-node-type child) "fenced_code_block_delimiter")
        (save-excursion
          (goto-char (treesit-node-start child))
          (push (markdown-config--ensure-fence-overlay
                 (line-beginning-position)
                 (min (point-max) (1+ (line-end-position))))
                ovs))))
    (when (= (length ovs) 2)
      (overlay-put (car ovs) 'markdown-config-fence-sibling (cadr ovs))
      (overlay-put (cadr ovs) 'markdown-config-fence-sibling (car ovs)))))

(defun markdown-config--collapse-fence-line (node &rest _)
  "Collapse NODE's fence line via an overlay so `reveal-mode' can open it.
:after advice on `markdown-ts--fontify-delimiter'.  Acts on the fence
delimiter and the opener's info_string; drops the host's `invisible' text
property on the node so a revealed fence shows its real text, and ensures
both of the block's fence overlays (cross-linked) so reveal can mirror.

Skipped in `markdown-ts-view-mode': that read-only mode already hides whole
fence lines via the host's `invisible' text property (no stray blank line,
nothing to reveal), and swapping it for an overlay `display' would break
off-screen consumers that extract the buffer with `buffer-substring' — e.g.
lsp-mode's hover/signature rendering, which does not capture overlays."
  (when (and (not (derived-mode-p 'markdown-ts-view-mode))
             (member (treesit-node-type node)
                     '("fenced_code_block_delimiter" "info_string")))
    (if markdown-ts-hide-markup
        (let ((block (treesit-parent-until node "\\`fenced_code_block\\'" t)))
          (remove-text-properties (treesit-node-start node)
                                  (treesit-node-end node)
                                  '(invisible nil))
          (when block
            (markdown-config--ensure-block-fence-overlays block)))
      ;; Markup shown: drop any leftover collapse overlay on this line.
      (save-excursion
        (goto-char (treesit-node-start node))
        (dolist (o (overlays-at (line-beginning-position)))
          (when (overlay-get o 'markdown-config-fence-collapse)
            (delete-overlay o)))))))

(defun markdown-config--prune-fence-overlays (ranges _parser)
  "Delete fence-collapse overlays whose `fenced_code_block' is gone.
`treesit-parser' notifier mirroring `markdown-ts--host-ranges-notifier':
after a host reparse, drop any `markdown-config-fence-collapse' overlay in
a changed RANGES region that no longer sits inside a fenced code block."
  (dolist (range ranges)
    (dolist (ov (overlays-in (car range) (cdr range)))
      (when (overlay-get ov 'markdown-config-fence-collapse)
        (let* ((s (overlay-start ov))
               (node (and s (treesit-node-at s 'markdown))))
          (unless (and node
                       (treesit-parent-until node "\\`fenced_code_block\\'" t))
            (delete-overlay ov)))))))

(with-eval-after-load 'markdown-ts-mode
  (advice-add 'markdown-ts--fontify-delimiter :after
              #'markdown-config--collapse-fence-line))

;;; -- table cell wrapping ----------------------------------------------------
;;
;; `markdown-ts-table-fill-cells' reflows the data rows of the table at point so
;; no cell exceeds a chosen column width.  Each cell is wrapped with the
;; standard fill machinery (`fill-region', same as `fill-paragraph'); a row
;; whose widest cell needs N lines is replaced by N physical lines, filling one
;; column fragment per line (empty where a column ran out of fragments).  Header
;; and delimiter rows are left untouched — only `pipe_table_row' nodes are
;; rewritten.  No padding/alignment is applied: follow up with `C-c C-c'
;; (`markdown-ts-table-align-table'), which pads each column to its widest
;; (now-wrapped) cell.
;;
;; This is deliberately a standalone command rather than an extension of
;; `markdown-ts-table-align-table': it keeps the logic portable and lets you
;; fill first, then re-align.  The names sit in the upstream `markdown-ts-table-'
;; namespace for consistency with the built-in table commands (verified free of
;; collisions against the bundled mode).

(defcustom markdown-ts-table-fill-cell 60
  "Default maximum column width offered by `markdown-ts-table-fill-cells'.
Analogous to `fill-column', but scoped to Markdown table cells."
  :type 'integer
  :group 'markdown-ts)

(defun markdown-ts-table--fill-string (text width)
  "Wrap TEXT to WIDTH columns with fill machinery; return a list of lines.
Long single words are not broken, matching `fill-paragraph' behaviour."
  (if (string-empty-p text)
      (list "")
    (with-temp-buffer
      (insert text)
      (let ((fill-column width)
            (adaptive-fill-mode nil))
        (fill-region (point-min) (point-max)))
      (split-string (buffer-string) "\n"))))

(defun markdown-ts-table--format-wrapped-row (wrapped nlines)
  "Build NLINES physical table lines from WRAPPED.
WRAPPED is a list of per-cell line lists (as returned by
`markdown-ts-table--fill-string').  Line K holds, cell by cell, each
column's K-th fragment, or the empty string when that column has fewer than
K+1 fragments.  No alignment/padding is applied."
  (mapconcat
   (lambda (k)
     (concat "| "
             (mapconcat (lambda (cell) (or (nth k cell) "")) wrapped " | ")
             " |"))
   (number-sequence 0 (1- nlines))
   "\n"))

(defun markdown-ts-table-fill-cells (width)
  "Fill each data-row cell of the Markdown table at point to WIDTH columns.
Tree-sitter locates the enclosing `pipe_table' node and its rows; each
`pipe_table_row' (i.e. every row below the delimiter) is reflowed so no
cell exceeds WIDTH columns, splitting a row into as many physical lines as
its widest cell requires.  The header and `|---|' delimiter rows are left
untouched.  Signals a `user-error' when point is not inside a table.

Interactively, prompts for WIDTH (defaulting to
`markdown-ts-table-fill-cell')."
  (interactive (list (read-number "Maximum column width: "
                                  markdown-ts-table-fill-cell)))
  (unless (and (integerp width) (> width 0))
    (user-error "Column width must be a positive integer"))
  (let ((table (treesit-parent-until (treesit-node-at (point) 'markdown)
                                     "\\`pipe_table\\'" t)))
    (unless table
      (user-error "Point is not inside a Markdown table"))
    (let (edits)
      (dolist (row (treesit-node-children table))
        (when (equal (treesit-node-type row) "pipe_table_row")
          (let* ((cells (treesit-filter-child
                         row
                         (lambda (n)
                           (equal (treesit-node-type n) "pipe_table_cell"))))
                 (wrapped (mapcar
                           (lambda (c)
                             (markdown-ts-table--fill-string
                              (string-trim (treesit-node-text c t)) width))
                           cells))
                 (nlines (apply #'max 1 (mapcar #'length wrapped))))
            (when (> nlines 1)
              ;; `push' onto `edits' yields bottom-to-top order, so the loop
              ;; below rewrites lower rows first and leaves the start/end
              ;; positions of the earlier (higher) rows valid.
              (push (list (treesit-node-start row)
                          (treesit-node-end row)
                          (markdown-ts-table--format-wrapped-row wrapped nlines))
                    edits)))))
      (save-excursion
        (dolist (e edits)
          (delete-region (nth 0 e) (nth 1 e))
          (goto-char (nth 0 e))
          (insert (nth 2 e)))))))

;;; -- preview --------------------------------------------------------------

;; No in-Emacs preview package is configured.  `markdown-preview-mode' (and
;; classic `markdown-live-preview-mode') dragged in `markdown-mode' plus a
;; `web-server' recipe workaround and a major-mode-stubbing advice — a lot of
;; machinery to do what one shell command does.  Render from a terminal with
;; pandoc instead, e.g.:
;;
;;   pandoc --from=gfm --to=html5 file.md -o file.html
;;
;; and, for live updates, pair it with a watcher (e.g. `entr', `watchexec',
;; or `ls file.md | entr pandoc ...') plus the browser's own auto-reload.

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
