;;; lsp-core.el --- LSP core configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Base LSP configuration used by language-specific modules.
;;

;;; Code:

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")
  ;; Performance: increase the amount of data Emacs reads from subprocesses.
  ;; This helps with LSP servers that send larger JSON payloads.
  (setq read-process-output-max (* 1024 1024))
  :hook
  (lsp-mode . lsp-enable-which-key-integration))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :hook (lsp-mode . lsp-ui-mode)
  :init
  (setq lsp-ui-doc-position 'at-point))

(provide 'lsp-core)

;;; lsp-core.el ends here
