;;; latex-config.el --- AUCTeX and LaTeX compilation -*- lexical-binding: t; -*-

(use-package tex
  :straight auctex
  :defer t
  :init
  ;; Use LuaLaTeX. LuaLaTeX only produces PDF, so no DVI viewer is ever needed.
  (setq-default TeX-engine 'luatex)
  ;; Put all auxiliary and output files (including the PDF) in ._aux/ next to
  ;; the master file. AUCTeX's built-in commands include %(output-dir) in their
  ;; templates, so this works without additional glue. The directory is created
  ;; on first compile.
  (setq TeX-output-dir "._aux")
  :config
  ;; Prompt for the master file the first time; remember the answer.
  (setq-default TeX-master nil)
  ;; Show the compilation output buffer only on errors.
  (setq TeX-show-compilation nil)
  ;; Use Skim on macOS. Skim's displayline script supports SyncTeX forward
  ;; search (jump from source line to the corresponding PDF location).
  ;; Flags: -b activates Skim without stealing focus; -g opens in background.
  (when (eq system-type 'darwin)
    (setq TeX-view-program-list
          '(("Skim" "/Applications/Skim.app/Contents/SharedSupport/displayline -b -g %n %o %b")))
    (setq TeX-view-program-selection '((output-pdf "Skim")))))

(provide 'latex-config)
;;; latex-config.el ends here
