;;; lsp-tex-config.el --- TeX/LaTeX LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; LaTeX via texlab (lsp-mode built-in lsp-tex).
;;
;; Requires texlab on PATH:
;;   brew install texlab
;;
;; AUCTeX keeps ownership of build, viewer (Skim), and SyncTeX forward/inverse
;; search; texlab is scoped to code intelligence (completion, navigation,
;; hover, diagnostics).  LTEX+ remains attached as an add-on grammar checker.

;;; Code:

(use-package lsp-tex
  :straight nil  ; built into lsp-mode
  :after lsp-mode
  :hook ((LaTeX-mode . lsp-deferred)
         (latex-mode . lsp-deferred)
         (plain-tex-mode . lsp-deferred)))

(provide 'lsp-tex-config)
;;; lsp-tex-config.el ends here
