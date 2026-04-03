;;; lsp-web-config.el --- TypeScript/JavaScript LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; JS/TS LSP via typescript-language-server.
;; Install the server with: npm install -g typescript-language-server typescript
;;
;; Note: lsp-mode is the engine; `lsp-javascript` is the built-in client.

;;; Code:

;; lsp-mode itself is configured in lsp-core.el.
;; This module only adds Web-specific activation.

(use-package lsp-javascript
  :straight nil
  :after lsp-mode
  :hook ((typescript-mode . lsp-deferred)
         (js-mode . lsp-deferred)))

(provide 'lsp-web-config)

;;; lsp-web-config.el ends here
