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

;; various extra for dired-mode; especially for hiding files
(use-package dired-x
  :straight nil
  :after dired
  :custom
  (dired-omit-files (rx bos "." (not (any "."))))
  (dired-omit-verbose nil)
  :hook (dired-mode . dired-omit-mode))

;; dired-narrow: live-filter the dired listing as you type.
(use-package dired-narrow
  :after dired
  :bind (:map dired-mode-map
              ("/" . dired-narrow)))

(defun dired-reveal-file (file)
  "Open Dired on FILE's directory with point on FILE."
  (interactive "fReveal file: ")
  (dired-jump nil (expand-file-name file)))

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

(defun dired-sort-by-name ()            (interactive) (dired-sort-other "-l"))
(defun dired-sort-by-name-r ()          (interactive) (dired-sort-other "-lr"))
(defun dired-sort-by-mtime ()           (interactive) (dired-sort-other "-lt"))
(defun dired-sort-by-mtime-r ()         (interactive) (dired-sort-other "-ltr"))
(defun dired-sort-by-btime ()
  "Sort by birth (creation) time, newest first.  Requires GNU ls >= 8.25."
  (interactive) (dired-sort-other "-l --sort=time --time=birth"))
(defun dired-sort-by-btime-r ()
  "Sort by birth (creation) time, oldest first.  Requires GNU ls >= 8.25."
  (interactive) (dired-sort-other "-lr --sort=time --time=birth"))
(defun dired-sort-by-ext ()             (interactive) (dired-sort-other "-lX"))
(defun dired-sort-by-ext-r ()           (interactive) (dired-sort-other "-lXr"))

(with-eval-after-load 'dired
  (define-key dired-mode-map (kbd "O") #'dired-open-with)
  (define-key dired-mode-map (kbd ".") #'dired-omit-mode)
  ;; Sorting commands mirroring keybindings from Yazi
  (define-key dired-mode-map (kbd ", a") #'dired-sort-by-name)
  (define-key dired-mode-map (kbd ", A") #'dired-sort-by-name-r)
  (define-key dired-mode-map (kbd ", m") #'dired-sort-by-mtime)
  (define-key dired-mode-map (kbd ", M") #'dired-sort-by-mtime-r)
  (define-key dired-mode-map (kbd ", b") #'dired-sort-by-btime)
  (define-key dired-mode-map (kbd ", B") #'dired-sort-by-btime-r)
  (define-key dired-mode-map (kbd ", e") #'dired-sort-by-ext)
  (define-key dired-mode-map (kbd ", E") #'dired-sort-by-ext-r))

;;; -- Font-locking -----------------------------------------------------------

;; diredfl: richer font-locking with distinct faces for size, date, permission
;; bits, directories, symlinks, executables, compressed files, etc.  Works in
;; both GUI and TTY.
(use-package diredfl
  :hook (dired-mode . diredfl-mode))

;;; -- Nerd icons --------------------------------------------------------------

(use-package nerd-icons-dired
  :after nerd-icons
  :hook (dired-mode . nerd-icons-dired-mode)
  :config
  ;; Upstream wraps each icon in (propertize s 'display s) to fix a visual
  ;; artifact when hl-line-mode is active: without it, the icon overlay retains
  ;; the default frame background rather than inheriting the hl-line highlight
  ;; color.  The wrapper causes a side-effect: Emacs defers face evaluation on
  ;; first display, so icons appear colorless until a redisplay is triggered
  ;; (e.g. highlight or g).  We don't use hl-line-mode, so the workaround is
  ;; unnecessary and we drop it here.
  (defun nerd-icons-dired--add-overlay (pos string)
    "Add overlay to display STRING at POS."
    (let ((ov (make-overlay (1- pos) pos)))
      (overlay-put ov 'nerd-icons-dired-overlay t)
      (overlay-put ov 'evaporate t)
      (overlay-put ov 'after-string string))))

(provide 'dired-config)
;;; dired-config.el ends here
