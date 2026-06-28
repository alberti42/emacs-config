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

;; dired-clipboard: copy / cut / paste files within Dired (M-w / C-w / C-y),
;; with optional integration into the native macOS Finder clipboard.
(use-package dired-clipboard
  :straight (dired-clipboard :type git
                             :host github
                             :repo "kn66/dired-clipboard.el")
  :hook (dired-mode . dired-clipboard-mode))

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
(defun dired-sort-by-size ()            (interactive) (dired-sort-other "-lS"))
(defun dired-sort-by-size-r ()          (interactive) (dired-sort-other "-lSr"))
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

(defun dired-goto-first-file ()
  "Move point to the first non-trivial file in the Dired listing."
  (interactive)
  (goto-char (point-min))
  (dired-initial-position default-directory))

(defun dired-goto-last-file ()
  "Move point to the last file in the Dired listing."
  (interactive)
  (goto-char (point-max))
  (dired-previous-line 1))

(with-eval-after-load 'dired
  (define-key dired-mode-map [remap beginning-of-buffer] #'dired-goto-first-file)
  (define-key dired-mode-map [remap end-of-buffer]       #'dired-goto-last-file)
  (define-key dired-mode-map (kbd "O") #'dired-open-with)
  (define-key dired-mode-map (kbd ".") #'dired-omit-mode)
  ;; Sorting commands mirroring keybindings from Yazi
  (define-key dired-mode-map (kbd ", a") #'dired-sort-by-name)
  (define-key dired-mode-map (kbd ", A") #'dired-sort-by-name-r)
  (define-key dired-mode-map (kbd ", m") #'dired-sort-by-mtime)
  (define-key dired-mode-map (kbd ", M") #'dired-sort-by-mtime-r)
  (define-key dired-mode-map (kbd ", b") #'dired-sort-by-btime)
  (define-key dired-mode-map (kbd ", B") #'dired-sort-by-btime-r)
  (define-key dired-mode-map (kbd ", s") #'dired-sort-by-size)
  (define-key dired-mode-map (kbd ", S") #'dired-sort-by-size-r)  
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

;;; -- Eager visible-region refontification ------------------------------------

;;  `dired-after-readin-hook' runs while the buffer is being constructed and is
;; not yet displayed in any window, so we cannot paint the visible portion
;; synchronously here.  Defer to a 0-second idle timer: Emacs goes idle right
;; after the initial redisplay shows the buffer, at which point
;; `get-buffer-window' returns the window and `window-start' / `window-end' are
;; real.  We paint only the visible region; off-screen lines remain lazy and
;; jit-lock fills them in on scroll, so opening enormous directories still
;; doesn't stall.  Hook depth 90 runs after `nerd-icons-dired--refresh' (added
;; at depth 0) so its overlays are in place before fontification.
(defun dired-config--fontify-after-readin ()
  "Eagerly refontify the visible region after `dired-readin' completes.
Schedules a 0-second idle timer so the paint runs after the buffer
becomes a window's buffer; the hook itself fires too early to know which
window will display the buffer."
  (let ((buf (current-buffer)))
    (run-with-idle-timer
     0 nil
     (lambda ()
       (when (buffer-live-p buf)
         (when-let* ((win (get-buffer-window buf t)))
           (with-current-buffer buf
             (let ((start (window-start win))
                   (end   (window-end win t)))
               (font-lock-flush start end)
               (font-lock-ensure start end)))))))))

(add-hook 'dired-after-readin-hook #'dired-config--fontify-after-readin 90)

(provide 'dired-config)
;;; dired-config.el ends here
