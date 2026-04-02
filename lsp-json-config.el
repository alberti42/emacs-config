;;; lsp-json-config.el --- JSON LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; JSON LSP via vscode-json-language-server (vscode-langservers-extracted).
;; Install the server with: npm install -g vscode-langservers-extracted
;;
;; Features:
;; - Schema validation and completion
;; - Auto schema detection via SchemaStore (package.json, tsconfig.json, etc.)
;;

;;; Code:

(use-package lsp-mode
  :hook ((js-json-mode  . lsp-deferred)   ; built-in (Emacs 29+)
         (json-mode     . lsp-deferred)   ; json-mode package
         (json-ts-mode  . lsp-deferred))  ; tree-sitter
  :config
  ;; Ensure js-json-mode activates the JSON client even when the buffer is not
  ;; visiting a file (lsp-mode otherwise falls back to "js-json").
  (add-to-list 'lsp-language-id-configuration '(js-json-mode . "json")))

;; lsp-mode JSON client definitions (ships with lsp-mode; not a separate package)
(use-package lsp-json
  :straight nil
  :after lsp-mode)

(provide 'lsp-json-config)

;;; lsp-json-config.el ends here
