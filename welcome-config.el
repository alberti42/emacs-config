;;; welcome-config.el --- Centered startup splash buffer -*- lexical-binding: t; -*-

(defconst welcome-config-image-width 200
  "Displayed width in pixels of the welcome logo.")

(defconst welcome-config-image-file
  (expand-file-name "goodies/Emacs-logo-alt.svg" emacs-config-dir)
  "Path to the welcome logo image.")

(defun show-welcome-buffer ()
  "Show the *Welcome* buffer with a centered logo and title."
  (interactive)
  (with-current-buffer (get-buffer-create "*Welcome*")
    (setq truncate-lines t)
    (let* ((buffer-read-only nil)
           (image (create-image welcome-config-image-file
                                nil nil
                                :width welcome-config-image-width))
           ;; Horizontal centering uses `space :align-to', so Emacs does the
           ;; pixel math internally — char-unit calculations from `image-size'
           ;; mis-center on Retina/HiDPI.  For vertical centering we still
           ;; need a line count, derived from the pixel height.
           (img-height-px (cdr (image-size image t)))
           (img-lines (ceiling (/ (float img-height-px) (frame-char-height))))
           (top-margin (max 0 (floor (/ (- (window-text-height) img-lines) 2))))
           (title "Welcome to Emacs!"))
      (erase-buffer)
      (setq mode-line-format nil)
      (goto-char (point-min))
      (insert-char ?\n top-margin)
      (insert (propertize " " 'display
                          `(space :align-to (- center (0.5 . ,image)))))
      (insert-image image)
      (insert "\n\n\n")
      (insert (propertize " " 'display
                          `(space :align-to (- center ,(/ (string-width title) 2)))))
      (insert title))
    (setq cursor-type nil)
    (read-only-mode 1)
    (switch-to-buffer (current-buffer))
    (local-set-key (kbd "q") #'bury-buffer)
    ;; Swallow wheel events so the splash stays put.  Covers GUI wheel
    ;; (vertical + horizontal, with double/triple accelerated variants) and
    ;; TTY mouse-4..7.  Local bindings override `ultra-scroll' /
    ;; `pixel-scroll-precision-mode' globals.
    (dolist (ev '([wheel-up] [wheel-down] [wheel-left] [wheel-right]
                  [double-wheel-up] [double-wheel-down]
                  [double-wheel-left] [double-wheel-right]
                  [triple-wheel-up] [triple-wheel-down]
                  [triple-wheel-left] [triple-wheel-right]
                  [mouse-4] [mouse-5] [mouse-6] [mouse-7]))
      (local-set-key ev #'ignore))))

(setq initial-scratch-message nil)
(setq inhibit-startup-screen t)

(when (and (< (length command-line-args) 2)
           (file-readable-p welcome-config-image-file)
           (image-type-available-p 'svg))
  (add-hook 'emacs-startup-hook
            (lambda ()
              (when (display-graphic-p)
                (show-welcome-buffer)))))

(provide 'welcome-config)
;;; welcome-config.el ends here
