;;; lsp-json.el --- JSON LSP configuration -*- lexical-binding: t; -*-

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
  ;; Enable SchemaStore: auto-detects and applies the right schema
  ;; for known files (package.json, tsconfig.json, docker-compose.yml, etc.)
  (setq lsp-json-schema-store-enabled t))

(provide 'lsp-json)

;;; lsp-json.el ends here
