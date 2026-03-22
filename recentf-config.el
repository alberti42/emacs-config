;;; recentf-config.el --- Recent files list -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Enable and persist a list of recently visited files.
;;
;; Note: this config repo is intended to be symlinked into user-emacs-directory
;; (e.g. ~/.config/emacs). To avoid writing state into the git worktree, store
;; the recentf file under XDG cache (or ~/.cache).
;;

;;; Code:

(use-package recentf
  :straight nil
  :demand t
  :init
  (let* ((cache-home (or (getenv "XDG_CACHE_HOME")
                         (expand-file-name "~/.cache")))
         (dir (expand-file-name "emacs" cache-home)))
    (make-directory dir t)
    (setq recentf-save-file (expand-file-name "recentf" dir)))
  (setq recentf-max-saved-items 200
        recentf-max-menu-items 50
        recentf-auto-cleanup 'mode)
  :bind ("C-c r" . recentf-open)
  :config
  (recentf-mode 1)
  ;; recentf hooks into find-file-hook, which does not fire when emacsclient
  ;; visits a file whose buffer is already open.  server-visit-hook fires on
  ;; every emacsclient visit regardless, so hook recentf into that as well.
  (add-hook 'server-visit-hook #'recentf-track-opened-file)
  ;; Forces saving recentf cache file every 5 minutes
  ;; Otherwise, it would only save after 'kill-emacs
  ;; (run-at-time nil (* 5 60) #'recentf-save-list)
  )

(provide 'recentf-config)
;;; recentf-config.el ends here
