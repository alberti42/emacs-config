;;; cape-config.el --- Extra CAPF sources (Cape) -*- lexical-binding: t; -*-

;; Cape extends Emacs' completion-at-point (CAPF) with extra sources.
;; Keep these as fallbacks by appending them.
(use-package cape
  :init
  (add-to-list 'completion-at-point-functions #'cape-file t)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev t)
  :config
  ;; lsp-completion-at-point is exclusive by default: when it returns a
  ;; non-nil result Emacs stops trying further CAPFs, so cape-file never
  ;; runs for file paths (e.g. ~/Documents/).  Wrapping it with :exclusive
  ;; no lets Emacs fall through to cape-file when LSP has no candidates.
  (defun my/cape-lsp-nonexclusive-setup ()
    (setq-local completion-at-point-functions
                (mapcar (lambda (f)
                          (if (eq f 'lsp-completion-at-point)
                              (cape-capf-properties f :exclusive 'no)
                            f))
                        completion-at-point-functions)))
  (add-hook 'lsp-completion-mode-hook #'my/cape-lsp-nonexclusive-setup))

(provide 'cape-config)
;;; cape-config.el ends here
