;;; lsp-rust-config.el --- Rust LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Rust via rustic-mode + rust-analyzer (lsp-mode built-in lsp-rust).
;;
;; Requires rust-analyzer on PATH:
;;   rustup component add rust-analyzer

;;; Code:

(use-package rustic
  :after lsp-mode
  :init
  ;; Use lsp-mode (not eglot) as the LSP client.
  (setq rustic-lsp-client 'lsp-mode)
  ;; rustfmt on save.
  (setq rustic-format-on-save t)
  :hook
  (rustic-mode . lsp-deferred))

(provide 'lsp-rust-config)

;;; lsp-rust-config.el ends here
