;;; org-config.el --- Org mode with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; Install Org from tecosaur's fork to get karthink's org-latex-preview
;; (auto-preview, live updates, dvisvgm SVG rendering).  We follow the
;; instructiosn from: https://abode.karthinks.com/org-latex-preview/. The
;; feature has not yet been merged into mainline Org.  This recipe must appear
;; before any package that depends on Org.
(use-package org
  :straight `(org
              :fork (:host nil
                           :repo "https://git.tecosaur.net/tec/org-mode.git"
                           :branch "dev"
                           :remote "tecosaur")
              :files (:defaults "etc")
              :build t
              :pre-build
              (with-temp-file "org-version.el"
                (require 'lisp-mnt)
                (let ((version
                       (with-temp-buffer
                         (insert-file-contents "lisp/org.el")
                         (lm-header "version")))
                      (git-version
                       (string-trim
                        (with-temp-buffer
                          (call-process "git" nil t nil
                                        "rev-parse" "--short" "HEAD")
                          (buffer-string)))))
                  (insert
                   (format "(defun org-release () \"The release version of Org.\" %S)\n" version)
                   (format "(defun org-git-version () \"The truncate git commit hash of Org mode.\" %S)\n" git-version)
                   "(provide 'org-version)\n")))
              :pin nil)
  :defer t
  :hook
  (org-mode . org-latex-preview-mode)
  :custom
  ;; Render all LaTeX previews when opening a file.  Fragments whose hash
  ;; matches a `org-persist' entry load instantly; new or edited fragments
  ;; (cache misses) are sent to LaTeX + dvisvgm for fresh rendering.
  (org-startup-with-latex-preview t)
  ;; Display inline images (e.g. babel plot output) when opening a file.
  (org-startup-with-link-previews t)
  ;; Enable consistent equation numbering
  (org-latex-preview-numbered t)
  ;; Turn on live previews: This shows you a live preview of a LaTeX fragment
  ;; and updates the preview in real-time as you edit it.  To preview only
  ;; environments, set it to '(block edit-special) instead
  (org-latex-preview-mode-display-live t)
  ;; The default process to convert LaTeX fragments to image files (default:
  ;; dvisvgm)
  (org-latex-preview-process-default 'dvisvgm)
  ;; Cap the maximum size of images
  (org-image-actual-width '(800))
  ;; Display LaTeX entity macros and sub/superscripts as Unicode in prose and
  ;; headings (e.g. \alpha → α, H_2O → H₂O).  Complements
  ;; `org-latex-preview-mode': inside math fragments the SVG preview takes
  ;; over the visual, this fills in everywhere else.
  (org-pretty-entities t)
  ;; Heading editing/insertion ergonomics.
  (org-special-ctrl-a/e t)
  (org-insert-heading-respect-content t)
  (org-catch-invisible-edits 'show-and-error)  
  ;; Compact fold ellipsis.
  (org-ellipsis "…")
  :config
  ;; Pre-emptive stale-.fmt purge.  After a TeX Live upgrade, pdfTeX refuses the
  ;; precompiled preamble `.fmt' files cached under
  ;; `$XDG_CACHE_HOME/org-persist/' because their binary fingerprint no longer
  ;; matches.  Org's cache key is the preamble hash, not the engine, so the
  ;; cache looks valid and the first preview fails with exit 252 ("format file
  ;; ... made by different executable version").  Cheap mtime check: if `pdftex'
  ;; is newer than a `.fmt', it was built against an older engine — delete it so
  ;; the next preview rebuilds via `pdftex -ini'.  Runs once, inside `:config',
  ;; which is before the `org-mode' body's startup-preview call.
  (when-let* ((pdftex (executable-find "pdftex"))
              (cache (expand-file-name
                      "org-persist/"
                      (or (getenv "XDG_CACHE_HOME") "~/.cache")))
              ((file-directory-p cache)))
    (dolist (fmt (directory-files-recursively cache "\\.fmt\\'"))
      (when (file-newer-than-file-p pdftex fmt)
        (message "org-latex-preview: purging stale %s"
                 (file-name-nondirectory fmt))
        (delete-file fmt)
        ;; Sibling metadata file: same stem minus the `-<preamble-hash>.fmt'
        ;; suffix.  Example:
        ;;   <dir>/ROOT-HASH-PREAMBLE.fmt  →  <dir>/ROOT-HASH
        (let ((meta (replace-regexp-in-string "-[^-/]+\\.fmt\\'" "" fmt)))
          (when (and (not (equal meta fmt)) (file-exists-p meta))
            (delete-file meta))))))

  ;; Show inline images after evaluating babel blocks.
  (add-hook 'org-babel-after-execute-hook #'org-display-inline-images)

  ;; Suppress the `*Org-Babel Error Output*' popup when the subprocess
  ;; exited cleanly.  ob-eval.el always pops the buffer whenever stderr is
  ;; non-empty (even on exit 0), which is noisy for tools like matplotlib
  ;; that print benign warnings to stderr.  The buffer is still written to,
  ;; so real errors (non-zero exit) still pop and past stderr remains
  ;; inspectable via `M-x switch-to-buffer'.
  ;; (define-advice org-babel-eval-error-notify
  ;;     (:around (oldfun exit-code stderr) suppress-on-success)
  ;;   (let ((display-buffer-alist
  ;;          (if (and exit-code (not (zerop exit-code)))
  ;;              display-buffer-alist
  ;;            (cons (cons (regexp-quote org-babel-error-buffer-name)
  ;;                        '(display-buffer-no-window
  ;;                          (allow-no-window . t)))
  ;;                  display-buffer-alist))))
  ;;     (funcall oldfun exit-code stderr)))

  ;; Set preview width to be sufficiently large to avoice chopped formulas
  (plist-put org-latex-preview-appearance-options
             :page-width 0.8)

  ;; More immediate live-previews -- the default delay is 1 second
  (setq org-latex-preview-mode-update-delay 0.25)

  ;; ;; Block C-n, C-p etc from opening up previews when using `org-latex-preview-mode'
  (setq org-latex-preview-mode-ignored-commands
        '(next-line previous-line mwheel-scroll
                    scroll-up-command scroll-down-command))

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

;; ;; Modern visual style for Org buffers (headlines, keywords, tables, blocks,
;; ;; tags, timestamps).  Uses text properties — no SVG, fragments stay editable.
;; (use-package org-modern
;;   :after org
;;   :hook
;;   (org-mode . org-modern-mode)
;;   (org-agenda-finalize . org-modern-agenda)
;;   :config  
;;   ;; JetBrainsMonoNL Nerd Font Mono lacks glyphs in the Miscellaneous Symbols
;;   ;; and Arrows block (U+2B00–U+2BFF) — e.g. ⯈/⯆ used by `org-modern' for
;;   ;; level 3+ heading fold indicators.  Without an explicit mapping macOS
;;   ;; either renders tofu or falls back to a font with mismatched metrics.
;;   ;; `Iosevka Nerd Font Mono' covers this block with consistently-sized
;;   ;; monospace glyphs that align well with JetBrainsMono's metrics.
;;   ;; Harmless on TTY frames, which ignore fontset entries.
;;   (set-fontset-font t '(#x2b00 . #x2bff) "Iosevka Nerd Font Mono" nil 'append)
;;   :custom
;;   ;; Tag column settings: with `org-modern' tags become boxed labels, so the
;;   ;; historic right-flush alignment via padding spaces no longer makes sense.
;;   (org-auto-align-tags nil)
;;   (org-tags-column 0)
;;   (org-agenda-tags-column 0)
;;   ;; Plain ASCII tables align cleanly because they use only characters from
;;   ;; the default font; org-modern's prettified box-drawing borders pull
;;   ;; glyphs from another range whose cell width disagrees with
;;   ;; JetBrainsMonoNL, breaking column alignment.
;;   (org-modern-table nil))

(provide 'org-config)
;;; org-config.el ends here
