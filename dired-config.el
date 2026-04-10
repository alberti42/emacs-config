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

;; Custom macOS 'Open With' functionality.
(when (eq system-type 'darwin)
  (defun dired-macos-open-with ()
    "Prompt to open the file at point with the system default or reveal it in Finder."
    (interactive)
    (unless (eq system-type 'darwin)
      (user-error "This command is only available on macOS"))
    (let* ((file (dired-get-file-for-visit))
           (options '("Open" "Reveal in Finder"))
           ;; Disable sorting to preserve the defined order
           (selected (let ((completion-extra-properties '(:display-sort-function identity)))
                       (completing-read "Action: " options nil t))))
      (cond
       ((string-equal selected "Open")
        (start-process "dired-macos-open" nil "open" file))
       ((string-equal selected "Reveal in Finder")
        (start-process "dired-macos-reveal" nil "open" "-R" file)))
      (message "Applied '%s' to %s" selected (file-name-nondirectory file))))

(with-eval-after-load 'dired
    (define-key dired-mode-map (kbd "O") #'dired-macos-open-with)))

(provide 'dired-config)
;;; dired-config.el ends here
