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
  ;; Debounced save: schedule a save 5 seconds after the last file visit
  ;; rather than waiting for kill-emacs.
  (defvar recentf--save-timer nil)
  (defun recentf-save-debounced ()
    (when (timerp recentf--save-timer)
      (cancel-timer recentf--save-timer))
    (setq recentf--save-timer
          (run-with-idle-timer 5 nil #'recentf-save-list)))
  (add-hook 'find-file-hook #'recentf-save-debounced)
  (add-hook 'server-visit-hook #'recentf-save-debounced)
  )

(provide 'recentf-config)
;;; recentf-config.el ends here
