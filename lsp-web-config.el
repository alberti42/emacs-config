;;; lsp-web-config.el --- TypeScript/JavaScript LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; JS/TS LSP via typescript-language-server.
;; Install the server with: npm install -g typescript-language-server typescript
;;
;; Note: lsp-mode is the engine; `lsp-javascript` is the built-in client.

;;; Code:

;; lsp-mode itself is configured in lsp-core.el.
;; This module adds Web-specific activation.

;; We hook into the major modes directly so that `lsp-deferred` can
;; trigger the loading of `lsp-mode` when a file is opened.

(use-package typescript-mode
  :hook (typescript-mode . lsp-deferred))

(use-package js
  :straight nil
  :hook (js-mode . lsp-deferred))

;; Once lsp-mode is loaded, we can apply specific JS/TS client settings if needed.
(use-package lsp-javascript
  :straight nil
  :after lsp-mode)

(provide 'lsp-web-config)

;;; lsp-web-config.el ends here
