;;; treemacs-config.el --- Treemacs in terminal Emacs -*- lexical-binding: t; -*-

;; Treemacs uses `pfuture` (async helpers) at runtime; ensure it's installed.
(use-package pfuture)

(use-package treemacs
  :after pfuture
  :commands (treemacs treemacs-select-window treemacs-find-file)
  :bind (("C-c t t" . treemacs)
         ("C-c t s" . treemacs-select-window)
         ("C-c t f" . treemacs-find-file))
  :config
  ;; Keep this light; avoid enabling optional modes by default.
  (setq treemacs-width 35)
  (setq treemacs-no-png-images t))

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config
  (treemacs-nerd-icons-config))

;; Daemon warmup
;; When running `emacs --daemon`, Treemacs is autoloaded and can feel slow on
;; first use. Preload the package shortly after startup so the first interactive
;; Treemacs command is snappy.
(defun emacs-config--treemacs-warmup ()
  "Preload Treemacs packages in the background."
  (when (daemonp)
    (run-at-time
     1 nil
     (lambda ()
       (require 'treemacs nil t)
       (require 'treemacs-nerd-icons nil t)))))

(add-hook 'after-init-hook #'emacs-config--treemacs-warmup)

(provide 'treemacs-config)
;;; treemacs-config.el ends here
