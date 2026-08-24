;;; latex-config.el --- AUCTeX and LaTeX compilation -*- lexical-binding: t; -*-

;; Shared Skim revert/open helpers (also used by typst-config.el).
(require 'pdf-preview)

(defcustom latex-config-pdf-viewer 'skim
  "Which PDF viewer AUCTeX uses for output-pdf jobs.
Choices:
  `auto'      – pdf-tools in GUI frames, Skim in TTY frames (decided
                per-view, so it works correctly when GUI and TTY frames
                coexist on the same daemon).
  `skim'      – external macOS app, SyncTeX via Skim's displayline tool.
  `pdf-tools' – in-Emacs viewer, continuous scroll, SyncTeX built-in.
                Requires a GUI frame; will not work in TTY."
  :type '(choice (const :tag "Auto (GUI → pdf-tools, TTY → Skim)" auto)
                 (const :tag "Skim (macOS)"                       skim)
                 (const :tag "pdf-tools (in-Emacs, GUI only)"     pdf-tools))
  :group 'tex)

(use-package tex
  :straight auctex
  :defer t
  :init
  (defun latex-config--apply-tex-magic-comments ()
    "Set `TeX-master' and `TeX-engine' from magic comments if present.
Scans the first 10 lines of the buffer, case-insensitively.

  % !TeX root = FILE     sets `TeX-master' to FILE.
  % !TeX program = NAME  sets `TeX-engine' to the corresponding AUCTeX
                         engine symbol (pdflatex → pdflatex, lualatex →
                         luatex, xelatex → xetex, latex → default)."
    (save-excursion
      (goto-char (point-min))
      (let ((case-fold-search t)
            (limit (line-end-position 10)))
        (save-excursion
          (when (re-search-forward
                 "^%[[:space:]]*!TeX[[:space:]]+root[[:space:]]*=[[:space:]]*\\(.+\\)"
                 limit t)
            (setq-local TeX-master (string-trim (match-string-no-properties 1)))))
        (save-excursion
          (when (re-search-forward
                 "^%[[:space:]]*!TeX[[:space:]]+program[[:space:]]*=[[:space:]]*\\(.+\\)"
                 limit t)
            (let* ((name (downcase (string-trim (match-string-no-properties 1))))
                   (engine (cond ((string= name "lualatex") 'luatex)
                                 ((string= name "luatex")   'luatex)
                                 ((string= name "xelatex")  'xetex)
                                 ((string= name "xetex")    'xetex)
                                 ((string= name "pdflatex") 'default)
                                 ((string= name "latex")    'default)
                                 (t nil))))
              (when engine
                (setq-local TeX-engine engine))))))))
  
  ;; Use LuaLaTeX. LuaLaTeX only produces PDF, so no DVI viewer is ever needed.
  (setq-default TeX-engine 'default)

  ;; Force PDF output (pdflatex) instead of DVI (latex)
  (setq-default TeX-PDF-mode t)
  
  ;; Put all auxiliary and output files (including the PDF) in ._aux/ next to
  ;; the master file. AUCTeX's built-in commands include %(output-dir) in their
  ;; templates, so this works without additional glue. The directory is created
  ;; on first compile.
  (setq-default TeX-output-dir "._aux")

  ;; Register the magic-comment hook before AUCTeX loads so it fires on the
  ;; very first .tex buffer. Inside :config it would be too late — AUCTeX loads
  ;; when the first LaTeX-mode buffer opens, so LaTeX-mode-hook has already run
  ;; by the time :config executes.
  (add-hook 'LaTeX-mode-hook #'latex-config--apply-tex-magic-comments)
  (add-hook 'TeX-mode-hook   #'latex-config--apply-tex-magic-comments)
  :custom
  ;; Prevent super/subscripts from being raised/lowered
  (font-latex-fontify-script nil)
  ;; Keep `\item' flush with the environment body and don't add an extra
  ;; indent to lines following `\item'.  Default -2 outdents `\item' and
  ;; indents continuation lines by +2 relative to it.
  (LaTeX-item-indent 0)

  :config
  ;; Ensure `completion-at-point' is available in LaTeX-mode
  (define-key TeX-mode-map (kbd "M-TAB") nil t)
  (define-key TeX-mode-map (kbd "C-c TAB") #'TeX-complete-symbol)

  ;; Prompt for the master file when no magic comment or Local Variables are present.
  (setq-default TeX-master t)

  ;; Work around a latexenc.el bug (present in Emacs ≤31): when TeX-master is a
  ;; string (e.g. set via the % -*- modeline or dir-locals), the fallback path in
  ;; `latexenc-find-file-coding-system' returns t instead of the string, then
  ;; passes t to `concat', crashing on `revert-buffer'.  Catch the error and
  ;; return nil (undecided) so Emacs falls back to normal coding-system detection.
  ;; TeX-master is left untouched; compilation is unaffected.
  (define-advice latexenc-find-file-coding-system
      (:around (orig arg-list) fix-tex-master-type-bug)
    (condition-case nil
        (funcall orig arg-list)
      (wrong-type-argument nil)))
  
  ;; Show the compilation output buffer only on errors.
  (setq TeX-show-compilation nil)
  ;; Save the buffer automatically before compiling without asking.
  (setq TeX-save-query nil)

  ;; The "View" entry in TeX-command-list has its confirm flag set to t by
  ;; default, causing AUCTeX to show the expanded viewer command and wait for
  ;; confirmation before running it.  Clear the flag so the viewer launches
  ;; immediately without prompting.
  (let ((entry (assoc "View" TeX-command-list)))
    (when entry (setf (nth 3 entry) nil)))

  ;; Enable SyncTeX so forward search (C-c C-v) embeds position information.
  ;; TeX-source-correlate-mode adds -synctex=1 to the compilation command.
  (TeX-source-correlate-mode 1)
  (setq TeX-source-correlate-method 'synctex)

  ;; PDF viewer + post-compilation revert.  Selection is driven by
  ;; `latex-config-pdf-viewer'; both branches set up SyncTeX forward and
  ;; inverse search.
  (pcase latex-config-pdf-viewer
    ('skim
     ;; macOS: use Skim as the PDF viewer.
     ;; Skim's displayline script drives SyncTeX forward search (Emacs → Skim).
     ;; No flags are passed (`%n %o %b' are displayline's line/pdf/tex
     ;; arguments, not options), so displayline uses its default behaviour:
     ;; bring Skim to the foreground and jump to the target line.
     ;; `TeX-source-correlate-start-server' is needed for Skim's emacsclient
     ;; callback (backward search: Skim → Emacs).
     (when (eq system-type 'darwin)
       (setq TeX-source-correlate-start-server t)
       (setq TeX-view-program-list
             '(("Skim" "/Applications/Skim.app/Contents/SharedSupport/displayline %n %o %b")))
       (setq TeX-view-program-selection '((output-pdf "Skim"))))
     ;; Auto-open viewer after compile.  Explicitly revert in Skim before
     ;; the SyncTeX jump so the refreshed document shows even when Skim's
     ;; "Watch for file changes" is off; revert is a no-op on first compile.
     (add-hook 'TeX-after-compilation-finished-functions
               (lambda (output-file)
                 (with-current-buffer TeX-command-buffer
                   (pdf-preview-skim-revert output-file)
                   (TeX-view)))))

    ('pdf-tools
     ;; In-Emacs viewer.  pdf-tools registers itself in
     ;; `TeX-view-program-list-builtin' (entry "PDF Tools" → wired to
     ;; `pdf-sync-mode' for SyncTeX forward and inverse search), so we
     ;; only have to select it.  Inverse search runs in-process; no
     ;; emacsclient server needed.
     ;;
     ;; Force a real `pdf-tools' load.  `pdf-tools-config.el' uses the lazy
     ;; `pdf-loader-install', under which `pdf-tools-install' (called by
     ;; AUCTeX's `TeX-pdf-tools-sync-view') is only a deferral stub — so the
     ;; PDF would open in `pdf-view-mode' with no rendering backend and show
     ;; raw bytes.  Requiring the package up front defines the real modes.
     (require 'pdf-tools)
     (setq TeX-view-program-selection '((output-pdf "PDF Tools")))
     ;; Auto-revert any open pdf-view buffer of the just-compiled PDF,
     ;; then jump to the cursor's position via SyncTeX (also opens the
     ;; viewer on first compile).
     (add-hook 'TeX-after-compilation-finished-functions
               #'TeX-revert-document-buffer)
     (add-hook 'TeX-after-compilation-finished-functions
               (lambda (_output-file)
                 (with-current-buffer TeX-command-buffer
                   (TeX-view)))))

    ('auto
     ;; Both viewers registered; AUCTeX's selection predicate picks
     ;; per-frame at view time (handles daemon sessions with both
     ;; GUI and TTY frames open).  Skim needs the emacsclient server
     ;; for inverse search; pdf-tools doesn't, but starting it is harmless.
     ;; AUCTeX's selection format is ((TYPE PREDICATE...) VIEWER); each
     ;; predicate is a symbol indexed in `TeX-view-predicate-list' (or
     ;; -builtin), whose stored *form* is eval'd at view time — not a
     ;; function symbol that gets called.  `has-no-display-manager' is
     ;; built-in (`(not (display-graphic-p))') and does what we need.
     (when (eq system-type 'darwin)
       (setq TeX-source-correlate-start-server t)
       (setq TeX-view-program-list
             '(("Skim" "/Applications/Skim.app/Contents/SharedSupport/displayline %n %o %b")))
       (setq TeX-view-program-selection
             '(((output-pdf has-no-display-manager) "Skim")
               (output-pdf "PDF Tools"))))
     ;; Post-compile: dispatch on frame type at the moment the hook fires.
     (add-hook 'TeX-after-compilation-finished-functions
               (lambda (output-file)
                 (with-current-buffer TeX-command-buffer
                   (cond
                    ((not (display-graphic-p))
                     (pdf-preview-skim-revert output-file))
                    (t
                     (when (stringp output-file)
                       (TeX-revert-document-buffer output-file))))
                   (TeX-view)))))))

(use-package preview
  :straight nil
  :after tex
  :config)

(use-package reftex
  :straight nil
  :hook
  (LaTeX-mode . reftex-mode)
  (latex-mode . reftex-mode)
  :custom
  (reftex-plug-into-AUCTeX t))

(provide 'latex-config)
;;; latex-config.el ends here
