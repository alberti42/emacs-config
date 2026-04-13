;;; lsp-python-config.el --- Python LSP configuration -*- lexical-binding: t; -*-

;;; Code:

(use-package lsp-pyright
  :straight t
  :init
  ;; basedpyright-langserver lives in the pyenv version bin, which is not
  ;; in the PATH that env-config.el imports from the shell env cache file.
  (add-to-list 'exec-path (expand-file-name "~/.pyenv/versions/py313/bin"))
  (setq lsp-pyright-langserver-command "basedpyright")
  :config
  (add-to-list 'lsp-disabled-clients 'ruff-lsp)
  (add-to-list 'lsp-disabled-clients 'ruff)

  ;; Python Interpreter and Analysis Settings
  (setq lsp-pyright-python-executable-cmd (expand-file-name "~/.pyenv/versions/py313/bin/python"))
  (setq lsp-pyright-type-checking-mode "basic")
  ;; (setq lsp-pyright-diagnostic-severity-overrides
  ;;       '(("reportOptionalSubscript" . "error")))

  ;; Settings can affect performance and stability
  (setq lsp-pyright-use-library-code-for-types nil)
  (setq lsp-pyright-diagnostic-mode "openFilesOnly")
  (setq lsp-pyright-auto-import-completions nil)
  
  ;; Disable multi-root if it's causing project detection issues
  (setq lsp-pyright-multi-root nil))

(let ((basedpyright-enable (lambda () (require 'lsp-pyright) (lsp-deferred))))
  (add-hook 'python-mode-hook basedpyright-enable)
  (add-hook 'python-ts-mode-hook basedpyright-enable))

(provide 'lsp-python-config)
;;; lsp-python-config.el ends here
