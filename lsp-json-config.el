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
;; Commentary:
;; - lsp-mode is the engine (session/workspaces, protocol plumbing, process management, requests/responses).
;; - clients/lsp-json.el is a plugin for that engine: it calls lsp-register-client to tell lsp-mode how to start the JSON server,
;;   and when to use it.

;;; Code:

(use-package lsp-mode
  :hook ((js-json-mode  . lsp-deferred)   ; built-in (Emacs 29+)
         (json-mode     . lsp-deferred)   ; json-mode package
         (json-ts-mode  . lsp-deferred))  ; tree-sitter
  :config
  ;; lsp-mode decides which server to start using a "language id" string.
  ;; For js-json-mode, lsp-mode would otherwise use "js-json", but the JSON
  ;; language server client only activates for "json" (and "jsonc").
  ;; This mainly matters for buffers that are not visiting a *.json file, e.g.
  ;; code-block edit buffers created by Markdown/Org helpers.
  (add-to-list 'lsp-language-id-configuration '(js-json-mode . "json")))

;; lsp-mode JSON client definitions (ships with lsp-mode; not a separate package)
(use-package lsp-json
  :straight nil
  :after lsp-mode)

(provide 'lsp-json-config)

;;; lsp-json-config.el ends here
