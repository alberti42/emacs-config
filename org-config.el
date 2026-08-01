;;; org-config.el --- Built-in Org with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; Uses the Org that ships with Emacs (`:straight (org :type built-in)'), not the tecosaur
;; fork.  That fork carried karthink's live `org-latex-preview' (auto-preview,
;; real-time updates while editing a fragment, dvisvgm SVG) which never made it
;; upstream, and the fork is now effectively unmaintained.  The previous
;; fork-based configuration is preserved, unloaded, in `org-karthink-config.el'.
;;
;; Math rendering here is done by the homegrown `org-latex-to-svg' package (a
;; front-end over the `latex-to-svg' engine, wired up at the end of this file),
;; NOT by built-in Org's classic `org-latex-preview'.  It compiles each unique
;; equation once (content-addressed) and re-tints / re-scales from cache on a
;; theme switch or text zoom with no LaTeX recompile — the ergonomics the
;; tecosaur fork provided, without depending on the fork.  Built-in Org's
;; classic `org-latex-preview' stays available (dvisvgm) as a fallback when
;; `org-latex-to-svg-mode' is off.

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
  ;; (LaTeX-math previews are handled by `org-latex-to-svg-mode', not Org's
  ;; `org-startup-with-latex-preview'.)
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
  ;; Keep the classic `org-latex-preview' (available as a fallback when
  ;; `org-latex-to-svg-mode' is off) on the dvisvgm backend.  The live
  ;; recolour/rescale hooks that used to live here are obsolete —
  ;; `org-latex-to-svg' does that from the shared engine cache without a
  ;; recompile.

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

;; Homegrown SVG-math preview for Org, over the `latex-to-svg' engine.  Replaces
;; built-in Org's classic `org-latex-preview' for in-buffer math: compiles each
;; equation once (content-addressed) and re-tints on theme switch / re-scales on
;; text zoom straight from cache — no LaTeX recompile.
;;
;; `latex-to-svg' is the shared engine; it is also registered from
;; `agent-shell-setup.el'.  Registering the same local-checkout recipe here too
;; is safe (straight caches an identical recipe) and removes any dependence on
;; which module loads first — straight must know this recipe before it resolves
;; `org-latex-to-svg''s `Package-Requires' dependency on it.
(use-package latex-to-svg
  :straight (latex-to-svg
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/latex-to-svg")
  :defer t)

(use-package org-latex-to-svg
  :straight (org-latex-to-svg
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/org-latex-to-svg")
  :after org
  ;; Render math in every Org buffer (replaces `org-startup-with-latex-preview').
  :hook (org-mode . org-latex-to-svg-mode))

(provide 'org-config)
;;; org-config.el ends here
