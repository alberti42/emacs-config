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
;; This module adds JSON-specific activation.

;; We hook into the major modes directly so that `lsp-deferred` can
;; trigger the loading of `lsp-mode` when a file is opened.

(add-hook 'js-json-mode-hook
          (lambda ()
            ;; lsp-mode picks a server based on a "language id".
            ;; For js-json-mode it would otherwise use "js-json",
            ;; but the JSON client activates for "json"/"jsonc".
            ;; This matters for buffers without a *.json filename
            ;; (e.g. code-block edit buffers).
            (with-eval-after-load 'lsp-mode
              (add-to-list 'lsp-language-id-configuration '(js-json-mode . "json")))
            (lsp-deferred)))

;; json-ts-mode is built-in (Emacs 29+); uses tree-sitter.
(add-hook 'json-ts-mode-hook #'lsp-deferred)

;; Once lsp-mode is loaded, we can apply specific JSON client settings if needed.
(use-package lsp-json
  :straight nil
  :after lsp-mode)

(provide 'lsp-json-config)

;;; lsp-json-config.el ends here
