;;; treemacs-config.el --- Treemacs in terminal Emacs -*- lexical-binding: t; -*-

;; Treemacs uses `pfuture` (async helpers) at runtime; ensure it's installed.
(use-package pfuture)

(use-package treemacs
  :after pfuture
  :commands (treemacs treemacs-select-window treemacs-find-file)
  :bind (("C-c t t" . treemacs)
         ("C-c t s" . treemacs-select-window)
         ("C-c t f" . treemacs-find-file))
  :init
  ;; Persist workspaces/projects outside the config worktree.
  (setq treemacs-persist-file (emacs-config-cache-file "treemacs-persist")
        treemacs-last-error-persist-file
        (emacs-config-cache-file "treemacs-persist-at-last-error"))
  :config
  ;; Keep this light; avoid enabling optional modes by default.
  (setq treemacs-width 35)
  (setq treemacs-width-is-initially-locked nil)
  (setq treemacs-no-png-images t)
  (treemacs-filewatch-mode 1))

(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config
  (treemacs-nerd-icons-config))

(provide 'treemacs-config)
;;; treemacs-config.el ends here
