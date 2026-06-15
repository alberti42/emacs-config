;;; lsp-rust-config.el --- Rust LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Rust via rustic-mode + rust-analyzer (lsp-mode built-in lsp-rust).
;;
;; Requires rust-analyzer on PATH:
;;   rustup component add rust-analyzer

;;; Code:

(use-package rustic
  ;; No `:after lsp-mode' — `:hook' already keeps rustic lazy (loaded via its
  ;; own `.rs' auto-mode autoload).  Dropping `:after' installs the
  ;; `rustic-mode-hook' at startup so `lsp-deferred' fires on the first Rust
  ;; buffer even if lsp-mode has not been loaded by another session yet.
  :init
  ;; Use lsp-mode (not eglot) as the LSP client.
  (setq rustic-lsp-client 'lsp-mode)
  ;; rustfmt on save.
  (setq rustic-format-on-save t)
  :hook
  (rustic-mode . lsp-deferred))

(provide 'lsp-rust-config)

;;; lsp-rust-config.el ends here
