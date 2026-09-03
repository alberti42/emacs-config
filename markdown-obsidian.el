;;; markdown-obsidian.el --- Obsidian wiki links and embeds for markdown-ts-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Obsidian's two non-CommonMark link forms, rendered and followed in
;; `markdown-ts-mode':
;;
;;   [[name]] / [[name|alias]]   a wiki link
;;   ![[file]] / ![[file|alias]] an embed, shown as an inline image
;;
;; Neither is part of the tree-sitter-markdown grammar, so there is no node
;; type to hang a treesit rule on: detection is text-level, via one bounded
;; single-line regex per window layered on top of the mode's treesit-driven
;; font-lock.  Everything CommonMark — inline links, images, tables, code
;; fences — is `markdown-config.el''s business and is not touched here.
;;
;; Loaded only when `markdown-config-enable-obsidian' is non-nil, from the
;; bottom of `markdown-config.el'.  Two things are borrowed from there and
;; nothing is required back: `markdown-config--link-keymap' (the shared,
;; parser-agnostic click keymap) and `markdown-config-follow-link-functions'
;; (the extension point this file hooks its wiki-link branch onto, so
;; `markdown-config-follow-link-at-point' need know nothing about Obsidian).
;;
;; Path resolution is Obsidian's, not Emacs': a name containing a `/' is
;; vault-relative and resolves from the vault root — the nearest ancestor of
;; the visited file holding a `.obsidian' directory — while a bare name
;; resolves from the visited file's own directory.

;;; Code:

(require 'treesit)

(defvar markdown-config--link-keymap)
(defvar markdown-config-follow-link-functions)

;;; -- vault-relative path resolution -----------------------------------------

(defun markdown-obsidian--vault-root (dir)
  "Return the Obsidian vault root at or above DIR, or nil if none.
The vault root is the nearest ancestor directory containing a
`.obsidian' subdirectory; nil is returned when no such ancestor
exists (DIR is not inside an Obsidian vault)."
  (when-let* ((root (locate-dominating-file
                     dir
                     (lambda (d)
                       (file-directory-p (expand-file-name ".obsidian" d))))))
    (file-name-as-directory (expand-file-name root))))

(defun markdown-obsidian--base-directory (name)
  "Return the directory NAME resolves against, or nil with no visiting file.
A NAME containing a `/' is vault-relative and resolves from the Obsidian
vault root; a bare NAME resolves from the visited file's own directory.
A slash-bearing NAME in a file outside any vault falls back to the
visited file's directory too, so following still does something sensible."
  (when buffer-file-name
    (let ((wp (file-name-directory buffer-file-name)))
      (or (and (string-search "/" name)
               (markdown-obsidian--vault-root wp))
          wp))))

(defun markdown-obsidian--resolve-wiki-path (name)
  "Resolve a wiki/embed NAME to an absolute path; nil with no visiting file.
Uses `markdown-obsidian--base-directory' but appends no `.md': an embed
names its target as written, image extension included."
  (when-let* ((base (markdown-obsidian--base-directory name)))
    (expand-file-name name base)))

(defun markdown-obsidian--follow-wiki-link (name &optional other)
  "Open the wiki-link target NAME, in another window when OTHER.
Spaces are kept verbatim, and \".md\" is appended only when NAME has no
file extension.  NAME is resolved by `markdown-obsidian--base-directory'.

Once resolved to FULL-PATH:
- Markdown targets (.md, .markdown): open with `find-file'.
- Other file types: open `dired' with the target highlighted.
- Non-existent targets: signal an error showing FULL-PATH.
- Never creates empty files."
  (unless buffer-file-name
    (user-error "Must be visiting a file"))
  (let* ((filename (if (file-name-extension name)
                       name
                     (concat name ".md")))
         (full-path (expand-file-name
                     filename (markdown-obsidian--base-directory filename))))
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

;;; -- rendering --------------------------------------------------------------

(defconst markdown-obsidian--wiki-link-regexp
  "\\[\\[\\([^]|\n]+?\\)\\(?:|[^]\n]*?\\)?\\]\\]"
  "Match `[[name]]' or `[[name|label]]'; group 1 is the resolvable name.
Used by the follow-link branch, which needs the target rather than the
label.  The font-lock matcher uses its own, laxer regex.")

(defface markdown-obsidian-wiki-link-face
  '((t :inherit link))
  "Face for Obsidian-style wiki links in `markdown-ts-mode'."
  :group 'markdown-ts)

(defcustom markdown-obsidian-inline-embed-images t
  "When non-nil, render Obsidian-style `![[file]]' embeds as inline images.
The image is shown in place of the markup and the embed's alias (if any) is
surfaced on hover (`help-echo'), not as buffer text.  When nil, an embed is
left as its literal `![[file|alias]]' markup -- still faced, clickable, and
with the target on hover, but neither rendered as an image nor markup-hidden --
so the vanilla, un-rendered behavior can be inspected and compared.

Image rendering also requires `markdown-ts-inline-images' (the bundled image
toggle, flipped by `markdown-ts-toggle-inline-images') to be on."
  :type 'boolean
  :group 'markdown-ts)

(defun markdown-obsidian--render-embed-image (embed-beg end target caption)
  "Render an inline image for an `![[TARGET]]' embed spanning EMBED-BEG..END.
EMBED-BEG is the position of the leading `!'.  CAPTION is the embed's explicit
alias (the `|alias' part) or nil for a bare `![[file]]'; when non-blank it is
surfaced as the image's `help-echo' so hovering or pointing at the image shows
it.  A bare embed with no alias gets no hover label.

Any prior embed-image overlay in range is cleared first so a refontify does
not stack duplicates; then, when `markdown-ts-inline-images' is on (the flag
`markdown-ts-toggle-inline-images' flips) and TARGET resolves to a displayable
local image, the image is shown via a `display' overlay on the embed's first
character, and the remainder of the `![[...]]' markup is hidden with a second
`invisible' overlay — so only the image shows, in place of the markup, on the
embed's own line.

Two overlays rather than one wide `display' overlay, for smooth scrolling.
The image is a `display' overlay rather than an `after-string': an
after-string has no buffer position, and prefixing it with a newline (the
\"image on its own line\" idiom that `markdown-ts--fontify-image' uses) puts
the image on a phantom display line that `pixel-scroll-precision-mode' cannot
anchor `window-start' to, so scrolling jumps by a whole image height (Emacs
bug#64252).  But a `display' overlay spanning the *whole* markup is nearly as
bad: these embed paths are ~180 chars, and a wide display span lets
`window-start' park deep inside the image region, reviving the same one-image
jump on scroll-up.  Confining the image to a single buffer position (with the
rest hidden) leaves `window-start' nowhere to park, so scrolling stays smooth.
This is also why the label is not rendered as a separate caption line — it
would need a phantom line too; the caption is shown on hover instead.

Both overlays are tagged `markdown-ts-image' so the toggle's
`markdown-ts--remove-image-overlays' clears embed images together with the
grammar-node ones, and the image overlay carries the shared link keymap so
clicking the image follows the embed exactly like clicking its label."
  (dolist (ov (overlays-in embed-beg (min (1+ end) (point-max))))
    (when (overlay-get ov 'markdown-obsidian-embed-image)
      (delete-overlay ov)))
  (when (and markdown-obsidian-inline-embed-images
             markdown-ts-inline-images (display-images-p))
    (when-let* ((path (markdown-obsidian--resolve-wiki-path target))
                ((not (file-remote-p path)))
                ((file-exists-p path))
                ((image-supported-file-p path))
                (max-w (if (eq markdown-ts-image-max-width 'window)
                           (window-body-width nil t)
                         markdown-ts-image-max-width))
                (img (create-image path nil nil :max-width max-w :scale 1)))
      ;; Put the image on a SINGLE buffer position and hide the rest of the
      ;; markup, rather than spreading `display' over the whole `![[...]]' span.
      ;; A wide display overlay lets `window-start' park deep inside the image
      ;; region, which reintroduces the bug#64252 one-image scroll-up jump (the
      ;; embed paths here are ~180 chars).  A one-char image plus an invisible
      ;; tail keeps the same "image in place of the markup" look while leaving
      ;; `window-start' nowhere to park, so scrolling stays smooth.
      (let ((img-ov (make-overlay embed-beg (1+ embed-beg) nil t nil)))
        (overlay-put img-ov 'markdown-obsidian-embed-image t)
        (overlay-put img-ov 'markdown-ts-image t)
        (overlay-put img-ov 'display img)
        (overlay-put img-ov 'keymap markdown-config--link-keymap)
        (overlay-put img-ov 'mouse-face 'highlight)
        (when (and caption (string-match-p "[^[:space:]]" caption))
          (overlay-put img-ov 'help-echo caption))
        (overlay-put img-ov 'evaporate t)
        (when (> end (1+ embed-beg))
          (let ((hide-ov (make-overlay (1+ embed-beg) end nil t nil)))
            (overlay-put hide-ov 'markdown-obsidian-embed-image t)
            (overlay-put hide-ov 'markdown-ts-image t)
            (overlay-put hide-ov 'invisible t)
            (overlay-put hide-ov 'evaporate t)))))))

(defun markdown-obsidian--wiki-link-fontify (limit)
  "Font-lock MATCHER for `[[name]]', `[[name|alias]]' and `![[name|alias]]'.
Restricts match data to the visible label so the keyword's face applies
to that region only.  Adds clickability (`keymap', `mouse-face',
`help-echo') to the WHOLE link span — brackets and the embed `!'
included — so the link is followable by click regardless of whether
`markdown-ts-hide-markup' is on (with markup shown the brackets are
visible and must be clickable too; with markup hidden the hidden
brackets simply carry harmless, undisplayed properties).  When
`markdown-ts-hide-markup' is on, also
sets `invisible' on the surrounding markup using the bundled
`markdown-ts--markup' spec — `markdown-ts-toggle-hide-markup' calls
`font-lock-flush' which re-runs this matcher with the new value.

A leading `!' marks an Obsidian embed: the `!' joins the hidden markup,
and when `markdown-ts-inline-images' is on the target image is rendered
in place of the markup via `markdown-obsidian--render-embed-image'."
  (when (re-search-forward "\\[\\[\\([^]\n]+\\)\\]\\]" limit t)
    (let* ((beg       (match-beginning 0))
           (end       (match-end 0))
           (inner-beg (match-beginning 1))
           (inner-end (match-end 1))
           (inner     (match-string-no-properties 1))
           (pipe      (string-match-p "|" inner))
           (label-beg (if pipe (+ inner-beg pipe 1) inner-beg))
           (label-end inner-end)
           (target    (if pipe (substring inner 0 pipe) inner))
           (embedp    (and (> beg (point-min)) (eq (char-before beg) ?!)))
           (markup-beg (if embedp (1- beg) beg)))
      ;; Clickability covers the entire link span (markup-beg..end), not just
      ;; the label, so a click anywhere on `[[name]]' / `![[name]]' follows it
      ;; whether or not `markdown-ts-hide-markup' has hidden the brackets.
      (add-text-properties markup-beg end
                           (list 'mouse-face 'highlight
                                 'keymap markdown-config--link-keymap
                                 'help-echo (concat (if embedp "Embed → " "Wiki link → ")
                                                    target)))
      ;; Hide the surrounding markup when `markdown-ts-hide-markup' is on.  An
      ;; embed only hides its markup when it is actually rendered as an image
      ;; (`markdown-obsidian-inline-embed-images'); otherwise its literal
      ;; `![[...]]' markup is left visible for inspection.
      (when (and markdown-ts-hide-markup
                 (or (not embedp) markdown-obsidian-inline-embed-images))
        (put-text-property markup-beg label-beg 'invisible 'markdown-ts--markup)
        (put-text-property label-end end       'invisible 'markdown-ts--markup))
      ;; Always call the renderer for embeds: it clears any prior embed-image
      ;; overlays (so toggling the option off removes a previously shown image)
      ;; and only draws a new one when `markdown-obsidian-inline-embed-images'
      ;; is on.
      (when embedp
        (markdown-obsidian--render-embed-image
         markup-beg end target
         ;; Only an explicit alias (the `|alias' part) is a real caption;
         ;; a bare `![[file]]' has no caption, so pass nil (no hover label).
         (and pipe (buffer-substring-no-properties label-beg label-end))))
      (set-match-data (list label-beg label-end))
      t)))

;;; -- wiring -----------------------------------------------------------------

(defun markdown-obsidian--follow-link-at-point ()
  "Follow the wiki link or embed at point; return non-nil when handled.
Registered on `markdown-config-follow-link-functions', which
`markdown-config-follow-link-at-point' consults before its own
CommonMark handling."
  (when (thing-at-point-looking-at markdown-obsidian--wiki-link-regexp)
    (markdown-obsidian--follow-wiki-link (match-string-no-properties 1))
    t))

(defun markdown-obsidian--setup ()
  "Add the wiki-link font-lock keyword to the current Markdown buffer."
  ;; `invisible' is managed by this keyword alone; the props
  ;; `markdown-config.el' needs for its own keywords are added there.
  (setq-local font-lock-extra-managed-props
              (append font-lock-extra-managed-props '(invisible)))
  (font-lock-add-keywords
   nil
   '((markdown-obsidian--wiki-link-fontify
      (0 'markdown-obsidian-wiki-link-face prepend)))
   'append)
  (font-lock-flush))

(add-hook 'markdown-config-follow-link-functions
          #'markdown-obsidian--follow-link-at-point)

;; Appended so it runs after `markdown-config--markdown-ts-mode-setup', which
;; `use-package' put on the hook with a plain (prepending) `add-hook'.
(add-hook 'markdown-ts-mode-hook #'markdown-obsidian--setup t)

(provide 'markdown-obsidian)
;;; markdown-obsidian.el ends here
