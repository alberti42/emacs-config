;;; latex-config.el --- AUCTeX and LaTeX compilation -*- lexical-binding: t; -*-

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
                                 ((string= name "pdflatex") 'pdflatex)
                                 ((string= name "latex")    'default)
                                 (t nil))))
              (when engine
                (setq-local TeX-engine engine))))))))

  
  ;; Use LuaLaTeX. LuaLaTeX only produces PDF, so no DVI viewer is ever needed.
  (setq-default TeX-engine 'default)
  
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
  :config

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

  ;; Automatically open the viewer after successful compilation.
  ;; On macOS, explicitly revert the PDF in Skim before the SyncTeX
  ;; forward-search jump so that the refreshed document is shown even
  ;; when Skim's "Watch for file changes" is disabled.  The revert is
  ;; a no-op if the document is not yet open (first compilation).
  (add-hook 'TeX-after-compilation-finished-functions
            (lambda (output-file)
              (with-current-buffer TeX-command-buffer
                (when (and (eq system-type 'darwin) (stringp output-file))
                  (call-process "osascript" nil 0 nil
                                "-e"
                                (format "tell application \"Skim\" \
to revert (documents whose path is \"%s\")"
                                        (expand-file-name output-file))))
                (TeX-view))))

  ;; Enable SyncTeX so forward search (C-c C-v) embeds position information.
  ;; TeX-source-correlate-mode adds -synctex=1 to the compilation command.
  (TeX-source-correlate-mode 1)
  (setq TeX-source-correlate-method 'synctex)

  ;; macOS: use Skim as the PDF viewer.
  ;; Skim's displayline script drives SyncTeX forward search (Emacs → Skim).
  ;; Flags: -b shows the reading bar to indicate the target line in the PDF;
  ;;        -g keeps Skim in the background (does not bring it to the foreground).
  ;; TeX-source-correlate-start-server is set here because it is only needed
  ;; for Skim's emacsclient callback (backward search: Skim → Emacs).
  (when (eq system-type 'darwin)
    (setq TeX-source-correlate-start-server t) ; always start server for inverse search
    (setq TeX-view-program-list
          '(("Skim" "/Applications/Skim.app/Contents/SharedSupport/displayline -b %n %o %b")))
    (setq TeX-view-program-selection '((output-pdf "Skim")))))

(provide 'latex-config)
;;; latex-config.el ends here
