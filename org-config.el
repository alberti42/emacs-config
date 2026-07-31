;;; org-config.el --- Built-in Org with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; Uses the Org that ships with Emacs (`:straight (org :type built-in)'), not the tecosaur
;; fork.  That fork carried karthink's live `org-latex-preview' (auto-preview,
;; real-time updates while editing a fragment, dvisvgm SVG) which never made it
;; upstream, and the fork is now effectively unmaintained.  The previous
;; fork-based configuration is preserved, unloaded, in `org-karthink-config.el'.
;;
;; Math rendering here therefore uses built-in Org's classic on-demand preview
;; (`org-latex-preview' / `C-c C-x C-l', dvisvgm backend).  There is no live
;; per-keystroke preview minor mode in mainline Org.  If that ergonomics is
;; wanted long-term, it belongs in a dedicated homegrown package rather than a
;; dependency on the fork.
;; Base `:scale' for LaTeX fragment previews, before per-buffer text-scale zoom
;; is factored in (see `org-config--latex-preview-rescale').  A plain defvar so
;; it is in scope both when set into `org-format-latex-options' and when the
;; rescale hook recomputes the effective scale.
(defvar org-config-latex-preview-base-scale 1.5
  "Baseline `:scale' applied to Org LaTeX previews at 100% text scale.")

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
  ;; Render all LaTeX previews when opening a file.
  (org-startup-with-latex-preview t)
  ;; Display inline images (e.g. babel plot output) when opening a file.
  (org-startup-with-link-previews t)
  ;; Cap the maximum size of images.  List form `(N)' (not bare N or t) keeps
  ;; the per-image `#+ATTR_ORG: :width Npx' / `#+ATTR_HTML:' override fallback.
  (org-image-actual-width '(800))
  ;; Classic preview pipeline: convert LaTeX fragments to SVG via dvisvgm.
  (org-preview-latex-default-process 'dvisvgm)
  ;; Display LaTeX entity macros and sub/superscripts as Unicode in prose and
  ;; headings (e.g. \alpha → α, H_2O → H₂O).  Outside math fragments (which get
  ;; the SVG preview), this fills in everywhere else.
  (org-pretty-entities t)
  ;; Heading editing/insertion ergonomics.
  (org-special-ctrl-a/e t)
  (org-insert-heading-respect-content t)
  (org-catch-invisible-edits 'show-and-error)
  ;; Compact fold ellipsis.
  (org-ellipsis "…")
  :config
  ;; Bump the on-screen size of LaTeX fragment previews.  `org-format-latex-options'
  ;; is the classic-preview appearance plist; `:scale' multiplies the rendered
  ;; image size.  (The fork's `org-latex-preview-appearance-options :page-width'
  ;; has no mainline analogue.)
  (plist-put org-format-latex-options :scale org-config-latex-preview-base-scale)
  ;; Colour previews from the *default* face (theme foreground/background) at
  ;; generation time.  This is the stock value, made explicit because the
  ;; theme-switch refresh below relies on it: when the palette changes, the
  ;; regenerated fragments pick up the new default-face colours.  (`auto' would
  ;; instead read the face *at point*, which can leak `hl-line'/region colours
  ;; into the image.)
  (plist-put org-format-latex-options :foreground 'default)
  (plist-put org-format-latex-options :background 'default)

  ;; --- Fork parity: recolour on theme change, rescale on text-scale ---------
  ;;
  ;; Built-in (classic) preview bakes colour and size into the cached SVG at
  ;; generation time; it has no live tracking.  These two hooks re-render the
  ;; affected previews so they follow the OS-driven light/dark theme switch
  ;; (`zac-theme-autodetection' -> `enable-theme-functions') and buffer text
  ;; zoom (`text-scale-adjust').  Both are no-ops in buffers without previews.
  (defun org-config--latex-preview-refresh ()
    "Regenerate every LaTeX preview in the current buffer, if any exist."
    (when (and (derived-mode-p 'org-mode) (display-graphic-p))
      (when (seq-some
             (lambda (o) (eq (overlay-get o 'org-overlay-type) 'org-latex-overlay))
             (overlays-in (point-min) (point-max)))
        (org-clear-latex-preview (point-min) (point-max))
        (org--latex-preview-region (point-min) (point-max)))))

  (defun org-config--latex-preview-refresh-all-buffers (&rest _)
    "Recolour LaTeX previews in all Org buffers after a theme change."
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (org-config--latex-preview-refresh))))
  (add-hook 'enable-theme-functions
            #'org-config--latex-preview-refresh-all-buffers)

  (defun org-config--latex-preview-zoom ()
    "Scale existing LaTeX preview images to the buffer's text zoom.

Previews are SVG (vector), so this adjusts each overlay image's `:scale'
instead of re-running LaTeX+dvisvgm.  Regenerating (which is what changing
`org-format-latex-options :scale' would force, since `:scale' feeds the DPI and
is part of the cache-key hash) re-renders every fragment synchronously and
hangs Emacs for seconds on each zoom step.  The factor is recomputed absolutely
from `text-scale-mode-amount', so repeated calls are idempotent."
    (when (derived-mode-p 'org-mode)
      (let ((factor (expt text-scale-mode-step text-scale-mode-amount)))
        (dolist (ov (overlays-in (point-min) (point-max)))
          (when (eq (overlay-get ov 'org-overlay-type) 'org-latex-overlay)
            (let ((img (overlay-get ov 'display)))
              (when (and (consp img) (eq (car img) 'image))
                (setf (image-property img :scale) factor)
                (image-flush img)))))
        (force-window-update (current-buffer)))))
  (add-hook 'text-scale-mode-hook #'org-config--latex-preview-zoom)

  ;; Show inline images after evaluating babel blocks.
  (add-hook 'org-babel-after-execute-hook #'org-display-inline-images)

  ;; Structure-template expansion: `<s TAB' → #+BEGIN_SRC … #+END_SRC, `<q',
  ;; `<e', etc.  Not auto-loaded since Org 9.2.
  (require 'org-tempo)

  ;; `C-c '' (org-edit-special) opens the src block in a dedicated language
  ;; buffer — this is where LSP (basedpyright, etc.) actually runs for
  ;; python blocks.  Tuning the edit experience:
  ;;   - Reuse the current window instead of rearranging the frame.
  ;;   - Let the language's own TAB (indent) behavior apply inside the edit
  ;;     buffer, so Python indentation works naturally.
  ;;   - Preserve the source block's leading whitespace on round-trip so
  ;;     exiting `C-c '' does not reflow indentation.
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

  ;; General-purpose Python defaults.  Matplotlib-specific setup (Agg backend,
  ;; SVG savefig format, imports, rcParams) lives in per-file setup blocks or
  ;; yasnippets, not here.
  (setq org-babel-default-header-args:python
        '((:results . "output") ; captures the entire stdout as produced by a Python REPL
          (:exports . "both")   ; includes both the code block and the results in the exported file
          )))

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
  (org-appear-autolinks t)
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
             (if org-hide-emphasis-markers "hidden" "visible"))))

(provide 'org-config)
;;; org-config.el ends here
