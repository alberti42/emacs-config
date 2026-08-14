;;; recentf-config.el --- Recent files list -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Enable and persist a list of recently visited files.
;;
;; Note: this config repo is intended to be symlinked into user-emacs-directory
;; (e.g. ~/.config/emacs). To avoid writing state into the git worktree, the
;; recentf file goes under `emacs-config-cache-dir' like every other
;; machine-local file this config persists.
;;

;;; Code:

(use-package recentf
  :straight nil
  :demand t
  :init
  (setq recentf-save-file (emacs-config-cache-file "recentf.eld"))
  (setq recentf-max-saved-items 200
        recentf-max-menu-items 50
        recentf-auto-cleanup 'mode
        recentf-show-messages nil ; requires Emacs 31+
        recentf-exclude
        (list (concat "\\`" (regexp-quote (file-truename temporary-file-directory)))
              "\\`/tmp/"
              "\\`/private/tmp/"              
              "\\/COMMIT_EDITMSG\\'"
              "\\`/\\(?:private\\)?var/folders/"
              (concat "\\`" (regexp-quote (expand-file-name "~/Library/Caches/")))
              ))
  :bind
  ("C-x C-r" . recentf-open)
  :config
  (recentf-mode 1)
  ;; recentf hooks into find-file-hook, which does not fire when emacsclient
  ;; visits a file whose buffer is already open.  server-visit-hook fires on
  ;; every emacsclient visit regardless, so hook recentf into that as well.
  (add-hook 'server-visit-hook #'recentf-track-opened-file)
  ;; Debounced save: schedule a save 1 second after the last file visit
  ;; rather than waiting for kill-emacs.
  (defvar recentf--save-timer nil)
  (defun recentf-save-debounced ()
    (when (timerp recentf--save-timer)
      (cancel-timer recentf--save-timer))
    (setq recentf--save-timer
          (run-with-idle-timer 0.500 nil #'recentf-save-list)))
  (add-hook 'find-file-hook #'recentf-save-debounced)
  (add-hook 'server-visit-hook #'recentf-save-debounced))

(provide 'recentf-config)
;;; recentf-config.el ends here
