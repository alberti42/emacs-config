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
  (dired-dwim-target t)
  (dired-use-ls-dired t)
  (delete-by-moving-to-trash t))

;; dired-narrow: live-filter the dired listing as you type.
(use-package dired-narrow
  :after dired
  :bind (:map dired-mode-map
         ("/" . dired-narrow)))

(defun dired-open-with ()
  "Open or reveal the file at point using OS-level commands.
Prompts for an action: open with the system default application,
or reveal in the system file manager."
  (interactive)
  (let* ((file     (dired-get-file-for-visit))
         (options  '("Open" "Reveal in file manager"))
         ;; Disable sorting to preserve the defined order.
         (selected (let ((completion-extra-properties '(:display-sort-function identity)))
                     (completing-read "Action: " options nil t))))
    (cond
     ((string-equal selected "Open")
      (open-file-with-os-default file))
     ((string-equal selected "Reveal in file manager")
      (reveal-file file)))
    (message "Applied '%s' to %s" selected (file-name-nondirectory file))))

(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "O") #'dired-open-with))

(provide 'dired-config)
;;; dired-config.el ends here
