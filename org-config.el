;;; org-config.el --- Built-in Org with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; NOTE: this must register Org as built-in with `:type built-in' rather than a
;; bare `:straight nil'.  `org-appear' declares `(org "9.3")' in its
;; Package-Requires, so straight resolves `org' as a dependency; without an
;; explicit built-in recipe here straight rebuilds whatever `org' checkout lives
;; in `straight/repos/org' (the leftover tecosaur fork) and puts it on
;; `load-path', shadowing the bundled Org.  `:type built-in' makes both this
;; block and the org-appear dependency resolve to the Emacs-bundled Org.
(use-package org
  :straight (org :type built-in)
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
  ;; `latex-to-svg-for-org-mode' has un-previewed.  Set to nil if that bites.
  (org-pretty-entities t)
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
  ;; and live inside the vault. — see `vulpea-db-location'.  Keeping the two in
  ;; step is done by `vulpea-vault/ids.el'.
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
  (setq-local latex-to-svg-frontend-inline-rescale 1.20
              latex-to-svg-frontend-display-rescale 1.25)
  (latex-to-svg-for-org-mode 1))

(use-package latex-to-svg-for-org
  :straight (latex-to-svg-for-org
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg"
             :files ("latex-to-svg-for-org.el"))
  :init
  (add-hook 'org-mode-hook #'org-config--latex-to-svg-setup))

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
