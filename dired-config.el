;;; dired-config.el --- Dired and file manager configuration -*- lexical-binding: t; -*-

;;; Code:

(use-package dired
  :straight nil
  :init
  (when (eq system-type 'darwin)
    (setq insert-directory-program "gls"))
  :custom
  ;; reuse single dired buffer when navigating instead
  ;; of opening new buffer for each directory
  (dired-kill-when-opening-new-dired-buffer t)
  (dired-use-ls-dired t))

;; dired-narrow: live-filter the dired listing as you type.
(use-package dired-narrow
  :after dired
  :bind (:map dired-mode-map
         ("/" . dired-narrow)))

(provide 'dired-config)
;;; dired-config.el ends here
