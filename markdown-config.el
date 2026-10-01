;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `markdown-ts-mode' (tree-sitter backed, bundled with Emacs 31) is the
;; only Markdown major mode configured here.  See
;; `docs/modules/markdown-config.md' for the design and invariants.
;;
;; What this file adds, and why each piece is still needed — upstream has
;; grown a lot, so anything it now handles has been removed from here:
;;
;; - Local-file link policy.  `markdown-ts--make-link-button' opens every
;;   schemeless destination with `find-file', so clicking an image link lands
;;   a JPEG in `image-mode'.  Rerouted so markdown opens in a buffer and
;;   anything else lands in `dired' with point on the file.
;; - Bracketed and percent-encoded image paths.  `markdown-ts--fontify-image'
;;   resolves the raw node text with a bare `expand-file-name', so
;;   `![a](<path with spaces>)' and `%20'-encoded paths silently never render.
;; - Collapsing code-fence lines while editing.  Upstream hides whole fence
;;   lines in `markdown-ts-view-mode' only; in an editable buffer it marks
;;   just the delimiter text invisible, leaving a stray blank row per fence.
;; - SVG math preview, via the shared `latex-to-svg' front-end.
;;
;; Everything here is CommonMark.  Obsidian's `[[wiki links]]' and
;; `![[embeds]]' are not, and live entirely in `markdown-obsidian.el',
;; loaded from the bottom of this file only when
;; `markdown-config-enable-obsidian' is non-nil.
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
  "Resolve URL as a local path and open it according to its type.
Called by `markdown-config-follow-link-at-point' for `[label](path)'
inline-link destinations, and by the rerouted link buttons.  Returns
non-nil when handled.  Full URLs (with a scheme such as http://) return
nil so the caller can fall back to `browse-url'.  Local paths:
- Markdown files (.md, .markdown): open with `find-file', then jump to
  the heading named by a `#fragment', if URL has one.
- Other files: open `dired' with the target highlighted.
- Non-existent files: signal an error with the resolved path.
URL is split into path and fragment before either is percent-decoded
\(RFC 3986), so a `%23' in a file name stays part of the name."
  (let* ((struct (url-generic-parse-url url))
         (full (url-fullness struct))
         (fragment (markdown-config--percent-decode (url-target struct))))
    (unless full
      (let* ((file (markdown-config--percent-decode
                    (car (url-path-and-query struct))))
             (wp (and buffer-file-name
                      (file-name-directory buffer-file-name))))
        (when (and file wp (> (length file) 0))
          (let ((full-path (expand-file-name file wp)))
            (if (not (file-exists-p full-path))
                (user-error "Link target not found: %s" full-path)
              (let ((ext (downcase (or (file-name-extension full-path) ""))))
                (if (member ext '("md" "markdown"))
                    (progn
                      (find-file full-path)
                      (when (and fragment (> (length fragment) 0))
                        (markdown-ts--follow-fragment fragment)))
                  (dired (file-name-directory full-path))
                  (dired-goto-file full-path))))
            t))))))

(defun markdown-config--strip-pointy-brackets (text)
  "Strip a matched leading `<' and trailing `>' from TEXT.
Used to clean CommonMark's pointy-bracket form
`[label](<url with spaces>)' into a plain path."
  (if (and (string-prefix-p "<" text)
           (string-suffix-p ">" text))
      (substring text 1 -1)
    text))

(defun markdown-config--percent-decode (text)
  "Percent-decode TEXT as UTF-8 when it contains a `%XX' escape.
TEXT without an escape, or nil, is returned unchanged, so a literal `%'
in a filename is left alone."
  (if (and text (string-match-p "%[0-9A-Fa-f][0-9A-Fa-f]" text))
      (decode-coding-string (url-unhex-string text) 'utf-8)
    text))

(defun markdown-config--normalize-link-path (path)
  "Strip a `<...>' wrapper from PATH and percent-decode it when encoded.
Turns CommonMark's pointy-bracket form `<path with spaces>' and a
percent-encoded `path%20with%20spaces' into a plain filesystem path.
Percent-decoding runs only when PATH actually contains a `%XX' escape, so
a plain path (or an already-decoded one) is returned unchanged and a
literal `%' in a filename is left alone."
  (markdown-config--percent-decode
   (markdown-config--strip-pointy-brackets path)))

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

(defvar markdown-config-follow-link-functions nil
  "Abnormal hook of non-CommonMark link syntaxes to try first.
Each function is called with no arguments and returns non-nil once it has
followed a link at point, nil to let the next one try.  The extension
point exists so an optional module can add a link syntax of its own
without this file knowing what that syntax is.")

(defun markdown-config-follow-link-at-point ()
  "Follow the inline link or URL at point.
Bound on `markdown-config--link-keymap', which an optional link-syntax
module attaches as a `keymap' text property to its links.  Everything the
mode itself renders \(inline links, autolinks, bare URLs) is already a
real text button whose own `button-map' follows it on RET and mouse-1, so
it never reaches this command.

Syntaxes registered on `markdown-config-follow-link-functions' are tried
first; the rest is CommonMark."
  (interactive)
  (cond
   ((run-hook-with-args-until-success 'markdown-config-follow-link-functions))
   ((when-let* ((dest (markdown-config--inline-link-destination-at-point)))
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
       (or (markdown-config--follow-local-link
            (markdown-config--strip-pointy-brackets url))
           (find-file (markdown-config--normalize-link-path url)))))))

(with-eval-after-load 'markdown-ts-mode
  (advice-add 'markdown-ts--fontify-image :around
              #'markdown-config--fontify-image-normalize-dest)
  (advice-add 'markdown-ts--make-link-button :around
              #'markdown-config--reroute-link-button))

;;; -- click-to-follow keymap --------------------------------------------------

(defvar markdown-config--link-keymap
  (let ((map (make-sparse-keymap)))
    ;; The same three gestures `button-map' gives the links the mode renders
    ;; as real text buttons: RET and mouse-2 follow, and mouse-1 follows too
    ;; because `[follow-link]' is bound to `mouse-face' (the standard Emacs
    ;; convention activated by `mouse-1-click-follows-link').
    (define-key map (kbd "RET")   #'markdown-config-follow-link-at-point)
    (define-key map [mouse-2]     #'markdown-config-follow-link-at-point)
    (define-key map [follow-link] 'mouse-face)
    map)
  "Keymap installed via the `keymap' text property on link labels.
Covers the links that never become upstream buttons: whatever an optional
link-syntax module attaches it to.
Nothing here duplicates the mode's own buttons, which carry `button-map'
already — which is also why no separate follow-link chord is needed on
`markdown-ts-mode-map': RET works on both kinds.

The keymap is parser-agnostic — the bound command,
`markdown-config-follow-link-at-point', dispatches on what is actually
at point.")

(defun markdown-config--markdown-ts-mode-setup ()
  "Enable code-fence collapse and reveal-on-edit in this buffer."
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
  (markdown-ts-hide-markup nil)
  :hook (markdown-ts-mode . markdown-config--markdown-ts-mode-setup))

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

;;; -- SVG math preview (latex-to-svg-for-markdown) ---------------------------

;; SVG-math preview for Markdown
;;
;; The engine (`latex-to-svg-backend') and core (`latex-to-svg-frontend')
;; recipes are registered in `latex-to-svg-config.el', which init.el loads
;; first, so straight resolves this adaptor's dependencies from the local
;; `latex-to-svg' checkout.
(defun markdown-config--latex-to-svg-setup ()
  "Enable Markdown SVG-math preview in this buffer with tuned rescales.
Per-mode config lives here: inline / display size multipliers are set
buffer-locally (on top of the engine's global `latex-to-svg-backend-font-scale')
before the adaptor turns on the shared core."
  (setq-local latex-to-svg-frontend-rescale-inline 1.20
              latex-to-svg-frontend-rescale-display 1.25
              latex-to-svg-frontend-padding-display '(4 0 4 0)
              latex-to-svg-frontend-center-display-math t)
  (latex-to-svg-for-markdown-mode 1))

(use-package latex-to-svg-for-markdown
  :straight (latex-to-svg-for-markdown
             :type git
             :inherit nil
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg"
             :files ("latex-to-svg-for-markdown.el"))
  ;; Render math in every Markdown buffer (sets rescales, then enables).
  :hook (markdown-ts-mode-hook . markdown-config--latex-to-svg-setup))

;;; -- Aligned, wrapped tables (markdown-table-view) --------------------------

;; Draws each table row with columns aligned on the text a reader sees and
;; long cells wrapped; the row point is on shows its raw text.  It also runs
;; the `markdown-inline' grammar on table cells, so links in a cell are
;; fontified, hidden and followed by the mode's own rules.
(use-package markdown-table-view
  :straight (markdown-table-view
             :type git
             :local-repo "/Users/andrea/Documents/Programming/Emacs/markdown-table-view")
  :hook (markdown-ts-mode-hook . markdown-table-view-mode))

;;; -- Obsidian wiki links and embeds (optional) ------------------------------

(defcustom markdown-config-enable-obsidian nil
  "When non-nil, load `markdown-obsidian.el' for Obsidian link syntaxes.
That module renders and follows `[[wiki links]]' and renders `![[embeds]]'
as inline images, resolving slash-bearing names against the `.obsidian'
vault root.  None of it is CommonMark, and none of it is needed for
Markdown files that are not part of an Obsidian vault.

Read at load time only: set it in `custom.el' or before this module is
loaded.  Toggling it in a running Emacs has no effect, since the module
installs a `markdown-ts-mode-hook' and a follow-link handler on load."
  :type 'boolean
  :group 'markdown-ts)

;; Loaded last, so every name it borrows from this file
;; (`markdown-config--link-keymap', `markdown-config-follow-link-functions')
;; is already defined and it needs no `require' back into here.
(when markdown-config-enable-obsidian
  (emacs-config-load-module
   'markdown-obsidian
   "Could not load markdown-obsidian.el; Obsidian wiki links are disabled."))

(provide 'markdown-config)
;;; markdown-config.el ends here
