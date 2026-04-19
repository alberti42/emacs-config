;;; welcome-config.el --- Centered startup splash buffer -*- lexical-binding: t; -*-

(defconst welcome-config-image-width 400
  "Displayed width in pixels of the welcome logo.")

(defconst welcome-config-image-file
  (expand-file-name "goodies/Emacs-logo.svg" emacs-config-dir)
  "Path to the welcome logo image.")

(defun welcome-config-show-buffer ()
  "Show the *Welcome* buffer with a centered logo and title."
  (with-current-buffer (get-buffer-create "*Welcome*")
    (setq truncate-lines t)
    (let* ((buffer-read-only nil)
           (image (create-image welcome-config-image-file
                                nil nil
                                :width welcome-config-image-width))
           (size (image-size image))
           (width (car size))
           (height (cdr size))
           (top-margin (max 0 (floor (/ (- (window-height) height) 2))))
           (left-margin (max 0 (floor (/ (- (window-width) width) 2))))
           (title "Welcome to Emacs!"))
      (erase-buffer)
      (setq mode-line-format nil)
      (goto-char (point-min))
      (insert (make-string top-margin ?\n))
      (insert (make-string left-margin ?\s))
      (insert-image image)
      (insert "\n\n\n")
      (insert (make-string
               (max 0 (floor (/ (- (window-width) (string-width title)) 2)))
               ?\s))
      (insert title))
    (setq cursor-type nil)
    (read-only-mode 1)
    (switch-to-buffer (current-buffer))
    (local-set-key (kbd "q") #'kill-this-buffer)))

(setq initial-scratch-message nil)
(setq inhibit-startup-screen t)

(when (and (< (length command-line-args) 2)
           (file-readable-p welcome-config-image-file)
           (image-type-available-p 'svg))
  (add-hook 'emacs-startup-hook
            (lambda ()
              (when (display-graphic-p)
                (welcome-config-show-buffer)))))

(provide 'welcome-config)
;;; welcome-config.el ends here
