;;; lsp-json-config.el --- JSON LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; JSON LSP via vscode-json-language-server (vscode-langservers-extracted).
;; Install the server with: npm install -g vscode-langservers-extracted
;;
;; Features:
;; - Schema validation and completion
;; - Built-in schema associations for common files (package.json, tsconfig.json, ...)
;;   plus user-configured schemas via `lsp-json-schemas`
;;
;; Note: lsp-mode is the engine; `lsp-json` is the JSON client shipped inside lsp-mode.

;;; Code:

;; lsp-mode itself is configured in lsp-core.el.
;; This module only adds JSON-specific activation.

(use-package lsp-json
  :straight nil
  :after lsp-mode
  :hook ((js-json-mode . (lambda ()
                           ;; lsp-mode picks a server based on a "language id".
                           ;; For js-json-mode it would otherwise use "js-json",
                           ;; but the JSON client activates for "json"/"jsonc".
                           ;; This matters for buffers without a *.json filename
                           ;; (e.g. code-block edit buffers).
                           (add-to-list 'lsp-language-id-configuration '(js-json-mode . "json"))
                           (lsp-deferred)))
         ;; Built into Emacs (Emacs 29+); uses tree-sitter for accurate
         ;; parsing/highlighting/indentation if one has JSON treesitter grammar
         ;; installed.
         (json-ts-mode . lsp-deferred)))

(provide 'lsp-json-config)

;;; lsp-json-config.el ends here
