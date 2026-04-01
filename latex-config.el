;;; latex-config.el --- AUCTeX and LaTeX compilation -*- lexical-binding: t; -*-

(use-package tex
  :straight auctex
  :defer t
  :init
  (defun latex-config--apply-tex-root-magic-comment ()
    "Set `TeX-master' from a `% !TeX root = FILE' magic comment if present.
Scans the first 10 lines of the buffer, case-insensitively, so both
`% !TeX root' and `% !TEX root' are accepted.  Has no effect when the
comment is absent; in that case `TeX-master' remains nil and AUCTeX
will prompt at compile time."
    (save-excursion
      (goto-char (point-min))
      (let ((case-fold-search t))
        (when (re-search-forward
               "^%[[:space:]]*!TeX[[:space:]]+root[[:space:]]*=[[:space:]]*\\(.+\\)"
               (line-end-position 10) t)
          (setq-local TeX-master (string-trim (match-string-no-properties 1)))))))  
  ;; Use LuaLaTeX. LuaLaTeX only produces PDF, so no DVI viewer is ever needed.
  (setq-default TeX-engine 'luatex)
  ;; Put all auxiliary and output files (including the PDF) in ._aux/ next to
  ;; the master file. AUCTeX's built-in commands include %(output-dir) in their
  ;; templates, so this works without additional glue. The directory is created
  ;; on first compile.
  (setq TeX-output-dir "._aux")
  ;; Register the magic-comment hook before AUCTeX loads so it fires on the
  ;; very first .tex buffer. Inside :config it would be too late — AUCTeX loads
  ;; when the first LaTeX-mode buffer opens, so LaTeX-mode-hook has already run
  ;; by the time :config executes.
  (add-hook 'LaTeX-mode-hook #'latex-config--apply-tex-root-magic-comment)
  (add-hook 'TeX-mode-hook   #'latex-config--apply-tex-root-magic-comment)
  :config
  ;; Prompt for the master file when no magic comment or Local Variables are present.
  (setq-default TeX-master nil)
  ;; Show the compilation output buffer only on errors.
  (setq TeX-show-compilation nil)
  ;; Enable SyncTeX so forward and backward search work between source and PDF.
  ;; TeX-source-correlate-mode adds -synctex=1 to the compilation command.
  ;; TeX-source-correlate-start-server ensures the Emacs server is running so
  ;; that Skim's emacsclient call for backward search can reach Emacs.
  (TeX-source-correlate-mode 1)
  (setq TeX-source-correlate-method 'synctex)
  (setq TeX-source-correlate-start-server t)
  ;; Use Skim on macOS. Skim's displayline script supports SyncTeX forward
  ;; search (jump from source line to the corresponding PDF location).
  ;; Flags: -b activates Skim without stealing focus; -g opens in background.
  (when (eq system-type 'darwin)
    (setq TeX-view-program-list
          '(("Skim" "/Applications/Skim.app/Contents/SharedSupport/displayline -b -g %n %o %b")))
    (setq TeX-view-program-selection '((output-pdf "Skim")))))

(provide 'latex-config)
;;; latex-config.el ends here
