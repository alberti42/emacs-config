;;; lsp-python-config.el --- Python LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Python LSP via lsp-pyright (configured to use basedpyright).
;; Install the server with: npm install -g basedpyright
;;

;;; Code:

(use-package lsp-pyright
  :after lsp-mode
  :init
  (setq lsp-pyright-langserver-command "basedpyright")
  :hook ((python-mode . (lambda ()
                 (require 'lsp-pyright)
                 (lsp-deferred)))))

(provide 'lsp-python-config)

;;; lsp-python-config.el ends here
