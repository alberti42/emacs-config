;;; org-config.el --- Org with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; Org comes from its own repository at Savannah.  Not from the copy bundled
;; with Emacs, which moves only when the Org maintainer commits a released tree
;; into emacs master branch.
;;
;; We use the org branch is `main'; the `bugfix' branch carries fixes for the
;; current released.  The price of main is that it is pre-release.
;;
;; Nothing must load a package requiring `org' before the org module below runs;
;; otherwise, the copy bundled with Emacs is the one that ends up in memory.
(use-package org
  :straight (org :type git :host nil
                 :repo "https://git.savannah.gnu.org/git/emacs/org-mode.git"
                 :local-repo "org" :branch "main" :depth full
                 :pre-build (straight-recipes-org-elpa--build)
                 :build (:not autoloads)
                 :files (:defaults "lisp/*.el"
                                   ("etc/styles/" "etc/styles/*")
                                   ("etc/csl/" "etc/csl/*")
                                   ("etc/org-babel/" "etc/org-babel/*")
                                   ("etc/schema/" "etc/schema/*")))
  :defer t
  :custom
  ;; Display inline images (e.g. babel plot output) when opening a file.
  (org-startup-with-link-previews t)
  ;; Cap the maximum size of images.  List form `(N)' (not bare N or t) honors
  ;; the per-image attributes `#+ATTR_ORG: :width Npx' / `#+ATTR_HTML:'.
  (org-image-actual-width '(800))
  ;; Which backend Org's own `org-latex-preview' uses.  Stock default is
  ;; `dvipng' (PNG); dvisvgm gives SVG instead.  Note this is a fallback that is
  ;; almost never used: every Org buffer enables `latex-to-svg-for-org-mode',
  ;; which shadows C-c C-x C-l (org-latex-preview).  To reach the setting below,
  ;; one needs to turn `latex-to-svg-for-org-mode' off and call M-x
  ;; org-latex-preview by name.
  (org-preview-latex-default-process 'dvisvgm)
  ;; Display LaTeX entity macros and sub/superscripts as Unicode in prose and
  ;; headings (e.g. \alpha → α, H_2O → H₂O).  `org-fontify-entities' guards only
  ;; on `org-at-comment-p', NOT on LaTeX fragments, so `\alpha' composes to `α'
  ;; inside math too -- visible while editing a fragment that
  ;; `latex-to-svg-for-org-mode' has un-previewed.
  (org-pretty-entities nil)
  ;; C-a/C-e stop at the end of the heading text (before tags) on the first
  ;; press, at the true line bounds on the second.
  (org-special-ctrl-a/e t)
  ;; Check if in invisible region before inserting or deleting a character.
  (org-catch-invisible-edits 'show-and-error)
  ;; Compact fold ellipsis.
  (org-ellipsis "…")
  :hook
  ;; Number sections as overlays rather than as text in the heading.
  (org-mode . org-num-mode)
  :bind (:map org-mode-map
              ("C-c t l" . org-toggle-link-display))
  :config
  ;; Show inline images after evaluating babel blocks.
  (add-hook 'org-babel-after-execute-hook #'org-display-inline-images)

  ;; Structure-template expansion: `<s' → #+BEGIN_SRC … #+END_SRC,
  ;; `<q' → #+BEGIN_QUOTE … #+END_QUOTE, `<e' → `#+BEGIN_EXAMPLE' … `#+END_EXAMPLE'
  (require 'org-tempo)

  ;; C-c ' (org-edit-special) opens the src block in a dedicated language buffer.
  ;; This is where LSP (basedpyright, etc.) actually runs for python blocks.
  ;; Tuning the edit experience:
  ;; - Reuse the current window instead of rearranging the frame.
  ;; - Let the language's own TAB (indent) behavior apply inside the edit buffer;
  ;;   thus, Python indentation works naturally.
  ;; - Preserve the source block's leading whitespace on round-trip so exiting C-c '
  ;;   does not reflow indentation.
  (setq org-src-window-setup 'current-window
        org-src-tab-acts-natively t
        org-src-preserve-indentation t)

  ;; Load org-babel languages (eg., Python)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)))

  ;; Don't ask for confirmation on every C-c C-c in trusted files.
  ;; Set to a function if you want selective confirmation.
  (setq org-confirm-babel-evaluate nil)

  ;; General-purpose Python defaults.
  (setq org-babel-default-header-args:python
        '((:results . "output") ; captures the entire stdout as produced by a Python REPL
          (:exports . "both")   ; includes both the code block and the results in the exported file
          )))

;;; -- org-id ------------------------------------------------------------------

(use-package org-id
  :straight nil
  :after org
  :init
  ;; `org-id-locations' is a map from ID to file path on THIS machine, rebuilt
  ;; by rescanning, and it spans every org file this Emacs knows.  It is stored
  ;; in a cache file.  Remember: indexes owned by vulpea are a different thing
  ;; and live inside the vault. — see `vulpea-db-location'.  vulpea keeps the
  ;; two in step itself: it registers the ids of every file it indexes, drops
  ;; them when it forgets a file, and registers a whole tree when autosync
  ;; starts.
  (setq org-id-locations-file (emacs-config-cache-file "org-id-locations.eld")))

;;; -- org-appear --------------------------------------------------------------

;; Enables automatic visibility toggling of various Org elements depending on
;; cursor position.  It supports automatic toggling of emphasis markers, links,
;; subscripts and superscripts, entities, and keywords.  By default, toggling is
;; instantaneous and only affects emphasis markers.  If Org mode custom
;; variables that control visibility of elements are configured to show hidden
;; parts, the respective `org-appear' settings do not have an effect.
(use-package org-appear
  :hook (org-mode . org-appear-mode)
  :after org
  :bind (:map org-mode-map
              ("C-c t e" . my/org-toggle-emphasis-markers))
  :custom
  ;; Non-nil enables automatic toggling of links.
  (org-appear-autolinks t)
  ;; Non-nil enables automatic toggling of subscript and superscript markers.
  (org-appear-autosubmarkers t)
  ;; Reveal markers at point
  (org-appear-autoemphasis t)
  ;; Hide emphasis markers as default setting
  (org-hide-emphasis-markers nil)
  :config
  (defun my/org-toggle-emphasis-markers ()
    "Toggle `org-hide-emphasis-markers' and re-fontify the buffer."
    (interactive)
    (setq org-hide-emphasis-markers (not org-hide-emphasis-markers))
    (font-lock-flush)
    (message "Org emphasis markers: %s"
             (if org-hide-emphasis-markers "hidden" "visible")))

  ;; Never reveal markup in response to a mouse click -- otherwise clicking a
  ;; link only reveals it and you must click a second time to follow it.
  ;; Why: `org-appear' reveals on `down-mouse-1' (point enters the element on
  ;; the press), which reflows the line while the button is still down.  Emacs
  ;; classifies a press+release as a *click* only if the buffer position under
  ;; the pointer is unchanged (`make_lispy_event', src/keyboard.c); here it
  ;; changed, so the release arrives as `drag-mouse-1' -- and a drag never
  ;; follows a link (see `mouse-1-click-follows-link').  Suppressing only the
  ;; reveal keeps hide-on-leave intact, so nothing is left unhidden.
  ;; A mouse click is navigation; use the keyboard when you mean to edit.
  (defun my/org-appear-not-mouse-p (&rest _)
    "Return nil when the current command came from the mouse."
    (not (mouse-event-p last-command-event)))
  (advice-add 'org-appear--show-with-lock
              :before-while #'my/org-appear-not-mouse-p))

;;; -- Aligned, wrapped tables (pretty-tables-for-org) ------------------------

;; Draws each table row with columns aligned on the text a reader sees and
;; long cells wrapped; the row point is on shows its raw text.  The shared
;; `pretty-tables' recipe is registered in pretty-tables-config.el.
(use-package pretty-tables-for-org
  :straight (pretty-tables-for-org
             :type git
             :local-repo "/Users/andrea/Documents/Programming/Emacs/pretty-tables"
             :files ("pretty-tables-for-org.el"))
  :hook (org-mode-hook . pretty-tables-for-org-mode))

;;; -- latex-to-svg-for-org: render math in every Org buffer -------------------

;; SVG-math preview for Org: the Org adaptor of the shared
;; `latex-to-svg-frontend' core.  Replaces built-in Org's classic
;; `org-latex-preview' for in-buffer math.
;;
;; The engine (`latex-to-svg-backend') and core (`latex-to-svg-frontend')
;; recipes are registered in `latex-to-svg-config.el' (loaded first in init.el),
;; satisfying this adaptor's `Package-Requires' from the local checkouts.
(defun org-config--latex-to-svg-setup ()
  "Enable Org SVG-math preview in this buffer with tuned rescales.
Per-mode config lives here: inline / display size multipliers are set
buffer-locally before the adaptor turns on the shared core."
  (setq-local latex-to-svg-frontend-rescale-inline 1.20
              latex-to-svg-frontend-rescale-display 1.25
              latex-to-svg-frontend-padding-display '(4 0 4 0)
              latex-to-svg-frontend-center-display-math t)
  (latex-to-svg-for-org-mode 1))

(use-package latex-to-svg-for-org
  :straight (latex-to-svg-for-org
             :type git
             :inherit nil
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg"
             :files ("latex-to-svg-for-org.el"))
  :hook (org-mode . org-config--latex-to-svg-setup)
  :init
  ;; Ignore `#+startup: latexpreview': it would run Org's own preview
  ;; before this mode turns on (see Troubleshooting).
  (with-eval-after-load 'org
    (setq org-startup-options
          (assoc-delete-all "latexpreview" org-startup-options))))

;;; -- Remote images -----------------------------------------------------------

;; `org-display-remote-inline-images' applies to TRAMP files only, and Org
;; gives the http and https link types no `:preview' function, so an image
;; link to a web server is never displayed.  `my/org-link-preview-url'
;; downloads the image asynchronously each time previews are drawn and keeps
;; no cache; `my/org-attach-remote-images' stores it in the note's attachment
;; directory instead, so the link no longer depends on the server.

(defun my/org-remote-image-link-p (link)
  "Return non-nil if LINK is an http or https link to an image file."
  (and (member (org-element-property :type link) '("http" "https"))
       (string-match-p (image-file-name-regexp)
                       (org-element-property :path link))))

(defun my/org-link-preview-url (ov _path link)
  "Download the image LINK points to and display it in overlay OV.
Intended as the `:preview' link parameter of http and https links."
  (when (and (display-graphic-p) (my/org-remote-image-link-p link))
    (let ((width (org-display-inline-image--width link)))
      (url-retrieve
       (org-element-property :raw-link link)
       (lambda (status)
         (unless (plist-get status :error)
           (goto-char (point-min))
           ;; The image data starts after the blank line ending the headers.
           (when (re-search-forward "\r?\n\r?\n" nil t)
             (let ((image (create-image
                           (buffer-substring-no-properties (point) (point-max))
                           nil t :width width)))
               (when (overlay-buffer ov)
                 (overlay-put ov 'display image)
                 (overlay-put ov 'face 'default)
                 (overlay-put ov 'keymap image-map)))))
         (kill-buffer))
       nil t)
      t)))

(with-eval-after-load 'ol
  (dolist (type '("http" "https"))
    (org-link-set-parameters type :preview #'my/org-link-preview-url)))

(defun my/org--remote-image-links (beg end)
  "Return the http and https image links between BEG and END."
  (let (links)
    (save-excursion
      (goto-char beg)
      (while (re-search-forward org-link-any-re end t)
        (let ((link (save-excursion
                      (forward-char -1)
                      (org-element-lineage (org-element-context) 'link t))))
          (when (and link (my/org-remote-image-link-p link))
            (push link links)))))
    links))

(defun my/org--remote-image-target (link)
  "Return (BEG END URL NAME DESC) for the remote image LINK.
BEG and END are markers, because `org-attach-url' tags the heading and
so moves the text after it."
  (list (copy-marker (org-element-begin link))
        (copy-marker (- (org-element-end link)
                        (org-element-post-blank link)))
        (org-element-property :raw-link link)
        (file-name-nondirectory (org-element-property :path link))
        (and (org-element-contents-begin link)
             (buffer-substring-no-properties
              (org-element-contents-begin link)
              (org-element-contents-end link)))))

(defun my/org--attach-remote-image (target)
  "Download the image of TARGET and replace its link with an attachment link.
TARGET is a list returned by `my/org--remote-image-target'.  A file
already in the attachment directory under the same name is used as it
is, without downloading it again."
  (pcase-let ((`(,beg ,end ,url ,name ,desc) target))
    (save-excursion
      ;; `org-attach-dir' finds the attachment directory from point.
      (goto-char beg)
      (unless (file-exists-p (expand-file-name name (org-attach-dir t)))
        (org-attach-url url))
      (delete-region beg end)
      (goto-char beg)
      (insert (org-link-make-string (concat "attachment:" name) desc)))
    (set-marker beg nil)
    (set-marker end nil)))

(defun my/org-attach-remote-images (&optional arg beg end)
  "Download remote images into the attachment directory of the note.
Replace each http or https image link with an `attachment:' link to
the downloaded file.

Act on the link at point.  When region BEG..END is active, act on the
links in the region.  With prefix ARG \\[universal-argument] \
\\[universal-argument], act on the links in the
accessible portion of the buffer."
  (interactive (cons current-prefix-arg
                     (when (use-region-p)
                       (list (region-beginning) (region-end))))
               org-mode)
  (require 'org-attach)
  (let ((targets
         (mapcar
          #'my/org--remote-image-target
          (cond
           ((equal arg '(16))
            (my/org--remote-image-links (point-min) (point-max)))
           (beg (my/org--remote-image-links beg end))
           (t (let ((link (org-element-lineage (org-element-context) 'link t)))
                (if (and link (my/org-remote-image-link-p link))
                    (list link)
                  (user-error "No remote image link at point"))))))))
    (mapc #'my/org--attach-remote-image targets)
    (message "Attached %d remote image%s"
             (length targets) (if (= (length targets) 1) "" "s"))))

;;; -- Two-column table -> description list ------------------------------------

;; A two-column table whose second column is prose is a description list
;; wearing a table's clothes: the alignment has to be maintained by hand, the
;; long column cannot wrap, and export has to be told how wide to make it.
;; This converts it back.  Rows wrapped with `org-table-wrap-region' (an empty
;; first field continuing the row above) are rejoined into one description.

(defun my/org--table-cookie-row-p (row)
  "Non-nil when ROW holds only width/alignment cookies, e.g. `<10>' or `<r>'."
  (cl-every (lambda (field)
              (string-match-p "\\`<[lrc]?[0-9]*>\\'" (string-trim field)))
            row))

(defun my/org-table-to-description-list (&optional keep-header)
  "Replace the Org table at point with a description list.

Each row becomes `- FIRST :: SECOND'.  Horizontal rules and width/alignment
cookie rows are dropped.  A row with an empty first field continues the
description of the row above, so cells split with `org-table-wrap-region'
survive as one entry.

The first row is treated as a header and dropped when a rule follows it;
with a prefix argument KEEP-HEADER it becomes an entry like any other.

The table must have exactly two columns."
  (interactive "P")
  (unless (org-at-table-p)
    (user-error "Point is not in an Org table"))
  (when (org-at-table.el-p)
    (user-error "This is a table.el table; convert it with `C-c ~' first"))
  (let* ((beg (org-table-begin))
         (end (org-table-end))
         ;; Drop cookie rows first: a leading one would otherwise hide the
         ;; "first row followed by a rule" shape that marks a header.
         (table (seq-remove (lambda (row)
                              (and (listp row)
                                   (my/org--table-cookie-row-p row)))
                            (org-table-to-lisp)))
         (header-p (and (not keep-header)
                        (listp (car table))
                        (eq 'hline (nth 1 table))))
         (rows (seq-remove (lambda (row) (eq row 'hline)) table))
         items)
    (dolist (row rows)
      (unless (= (length row) 2)
        (user-error "Table has %d column(s); this command needs exactly 2"
                    (length row))))
    (when header-p (setq rows (cdr rows)))
    (dolist (row rows)
      (let ((term (string-trim (nth 0 row)))
            (desc (string-trim (nth 1 row))))
        (cond
         ;; Continuation of the entry above.
         ((and (string-empty-p term) items)
          (unless (string-empty-p desc)
            (setcar items (concat (car items) " " desc))))
         ((and (string-empty-p term) (string-empty-p desc)) nil)
         (t (push (format "- %s :: %s" term desc) items)))))
    (unless items
      (user-error "Nothing to convert"))
    (delete-region beg end)
    (goto-char beg)
    (insert (mapconcat #'identity (nreverse items) "\n") "\n")))

(provide 'org-config)
;;; org-config.el ends here
