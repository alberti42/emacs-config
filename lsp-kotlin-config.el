;;; lsp-kotlin-config.el --- Kotlin LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Kotlin via `kotlin-ts-mode' + `kotlin-language-server' (lsp-mode built-in
;; `lsp-kotlin').
;;
;; Requires `kotlin-language-server' on PATH:
;;   brew install kotlin-language-server

;;; Code:

(use-package kotlin-ts-mode
  :mode ("\\.kts?\\'" . kotlin-ts-mode)
  :hook (kotlin-ts-mode . lsp-deferred))

(provide 'lsp-kotlin-config)

;;; lsp-kotlin-config.el ends here
