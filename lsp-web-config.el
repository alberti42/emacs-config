;;; lsp-web-config.el --- TypeScript/JavaScript LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; JS/TS LSP via typescript-language-server.
;; Install the server with: npm install -g typescript-language-server typescript
;;

;;; Code:

(use-package typescript-mode
  :hook (typescript-mode . lsp-deferred))

(use-package js
  :straight nil
  :hook (js-mode . lsp-deferred))

(provide 'lsp-web-config)

;;; lsp-web-config.el ends here
