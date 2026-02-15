;;; lsp-ltex-plus-config.el --- LTEX+ (ltex-ls-plus) for lsp-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Use the intended Emacs client `lsp-ltex-plus` and an externally installed
;; `ltex-ls-plus` server (provided on PATH, e.g. via zinit).
;;
;; Scope: enable only in Markdown and TeX modes.
;;

;;; Code:

(use-package lsp-ltex-plus
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "emacs-languagetool/lsp-ltex-plus")
  :after lsp-mode
  :init
  (setq lsp-ltex-plus-language "en-US")
  (setq lsp-ltex-plus-check-frequency "edit")
  ;; Make diagnostics visible.
  (setq lsp-ltex-plus-diagnostic-severity "warning")
  ;; Enable LTEX+ checks for the language IDs used by lsp-mode.
  ;; - markdown-mode/gfm-mode => "markdown"
  ;; - latex-mode/LaTeX-mode  => "latex"
  ;; - plain-tex-mode         => "plaintex"
  (setq lsp-ltex-plus-enabled ["markdown" "latex" "plaintex"])
  :hook
  ((markdown-mode gfm-mode plain-tex-mode latex-mode LaTeX-mode) .
   (lambda ()
     (require 'lsp-ltex-plus)
     (lsp-deferred))))

(provide 'lsp-ltex-plus-config)

;;; lsp-ltex-plus-config.el ends here
