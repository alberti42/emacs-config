;;; welcome-config.el --- Centered startup splash buffer -*- lexical-binding: t; -*-

(defconst welcome-config-image-width 200
  "Displayed width in pixels of the welcome logo.")

(defconst welcome-config-image-file
  (expand-file-name "goodies/Emacs-logo-alt.svg" emacs-config-dir)
  "Path to the welcome logo image.")

(defun welcome-config--render ()
  "(Re)draw the *Welcome* buffer contents for the current window size."
  (with-current-buffer (get-buffer-create "*Welcome*")
    (let* ((inhibit-read-only t)
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
      (goto-char (point-min))
      (insert-char ?\n top-margin)
      (insert (propertize " " 'display
                          `(space :align-to (- center (0.5 . ,image)))))
      (insert-image image)
      (insert "\n\n\n")
      (insert (propertize " " 'display
                          `(space :align-to (- center ,(/ (string-width title) 2)))))
      (insert title))))

(defvar welcome-config--last-frame-size nil
  "Last frame pixel size for which the welcome buffer was rendered.
Cached to skip internal window reflows (e.g. minibuffer growth) that
leave the frame itself unchanged.")

(defun welcome-config--on-size-change (frame)
  "Re-center the welcome buffer when FRAME's outer size changes."
  (when (get-buffer-window "*Welcome*" frame)
    (let ((size (cons (frame-pixel-width frame)
                      (frame-pixel-height frame))))
      (unless (equal size welcome-config--last-frame-size)
        (setq welcome-config--last-frame-size size)
        (welcome-config--render)))))

(defun show-welcome-buffer ()
  "Show the *Welcome* buffer with a centered logo and title."
  (interactive)
  (with-current-buffer (get-buffer-create "*Welcome*")
    (setq truncate-lines t)
    (setq mode-line-format nil)
    (setq cursor-type nil)
    (welcome-config--render)
    (read-only-mode 1)
    (switch-to-buffer (current-buffer))
    (local-set-key (kbd "q") #'bury-buffer)
    (add-hook 'window-size-change-functions
              #'welcome-config--on-size-change)
    ;; Swallow wheel events so the splash stays put.  `local-set-key' is not
    ;; sufficient for <wheel-up>/<wheel-down>: `pixel-scroll-precision-mode-map'
    ;; is a minor-mode map, and those win over the buffer-local map.  Install
    ;; via `minor-mode-overriding-map-alist',
    ;; which is consulted before `minor-mode-map-alist' and shadows per-buffer.
    (let ((override (make-sparse-keymap)))
      (dolist (ev '([wheel-up] [wheel-down] [wheel-left] [wheel-right]
                    [double-wheel-up] [double-wheel-down]
                    [double-wheel-left] [double-wheel-right]
                    [triple-wheel-up] [triple-wheel-down]
                    [triple-wheel-left] [triple-wheel-right]
                    [mouse-4] [mouse-5] [mouse-6] [mouse-7]))
        (define-key override ev #'ignore))
      (setq-local minor-mode-overriding-map-alist
                  (list (cons 'pixel-scroll-precision-mode override))))))

(setq inhibit-startup-screen t)

(defun welcome-config--maybe-show ()
  "Show the welcome buffer for a fresh GUI session.
Runs for both direct launches (`emacs-startup-hook') and emacsclient
frames against a running daemon (`server-after-make-frame-hook').
Skips when a file was opened, detected by the selected window landing
on anything other than *scratch* / *Welcome*."
  (when (and (display-graphic-p)
             (file-readable-p welcome-config-image-file)
             (image-type-available-p 'svg)
             (memq (current-buffer)
                   (list (get-buffer "*scratch*")
                         (get-buffer "*Welcome*"))))
    (show-welcome-buffer)))

(add-hook 'emacs-startup-hook #'welcome-config--maybe-show)
(add-hook 'server-after-make-frame-hook #'welcome-config--maybe-show)

(provide 'welcome-config)
;;; welcome-config.el ends here
