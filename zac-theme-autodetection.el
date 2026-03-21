;;; zac-theme-autodetection.el --- Appearance sync via zsh-appearance-control -*- lexical-binding: t; -*-

;; This module integrates Emacs with zsh-appearance-control:
;; https://github.com/alberti42/zsh-appearance-control
;;
;; zsh-appearance-control writes a single-character state file named
;; "appearance" in a cache directory:
;; - "1" => dark
;; - "0" => light
;;
;; We watch that file via Emacs file notifications.  When it changes, apply
;; any registered appearance hooks (cursor color, transparent background, etc.)
;;
;; Theme loading is delegated to `zac-load-theme-function', a user-supplied
;; callback set externally (e.g. in themes-config.el).  This keeps theme
;; selection decoupled from the appearance-detection machinery.

;;; Commentary:
;;
;; Usage:
;; - Load this file from init.el.
;; - The watcher starts automatically on load.
;;
;; Environment:
;; - If $ZAC_CACHE_DIR is set, we read "$ZAC_CACHE_DIR/appearance".
;; - Otherwise we read "$XDG_CACHE_HOME/zac/appearance" or "~/.cache/zac/appearance".

;;; Code:

(require 'subr-x)

(defvar zac--watch nil)

(defvar zac-load-theme-function nil
  "Function called by `zac--apply-appearance' to load the appropriate theme.
It receives one argument: the appearance string (\"0\" = light, \"1\" = dark).
Example:
  (setq zac-load-theme-function
        (lambda (appearance)
          (load-theme (if (equal appearance \"0\")
                          \\='modus-operandi
                        \\='modus-vivendi-tinted) t)))")

(defun zac--appearance-file ()
  (expand-file-name
   "appearance"
   (or (getenv "ZAC_CACHE_DIR")
       (expand-file-name "zac" (or (getenv "XDG_CACHE_HOME")
                                   (expand-file-name "~/.cache"))))))

(defun zac--read-appearance ()
  (when (file-readable-p (zac--appearance-file))
    (string-trim
     (with-temp-buffer
       (insert-file-contents (zac--appearance-file))
       (buffer-string)))))

(defun zac--apply-appearance ()
  ;; Keep default background transparent/unspecified for terminal + GUI consistency.
  ;; IMPORTANT: use the symbol `unspecified` (not the string "unspecified-bg").
  ;; In GUI frames the string is treated as a color name and produces an error.
  ;; (set-face-attribute 'default nil :background 'unspecified)
  ;; Note: mode-line backgrounds are intentionally left at theme defaults to
  ;; preserve contrast between the mode-line and surrounding buffers.
  ;; Keep the next two lines commented out
  ;; (set-face-attribute 'mode-line nil :background 'unspecified)
  ;; (set-face-attribute 'mode-line-inactive nil :background 'unspecified)

  ;; Load the appropriate theme based on OS appearance via user-supplied callback.
  ;; emacs-config-harmonize-theme fires automatically via enable-theme-functions
  ;; inside load-theme, so no explicit call is needed here.
  (let ((appearance (zac--read-appearance)))
    (when zac-load-theme-function
      (funcall zac-load-theme-function appearance))))


(defun zac-watch-start ()
  "Start watching zsh-appearance-control's appearance file."
  (interactive)
  (unless (fboundp 'file-notify-add-watch)
    (message "zac: file notifications not supported; applying once")
    (setq zac--watch nil)
    (zac--apply-appearance)
    nil)
  (zac--apply-appearance)
  ;; Re-apply appearance settings for any new frame (emacsclient / daemon mode).
  (add-hook 'after-make-frame-functions
            (lambda (frame)
              (with-selected-frame frame
                (zac--apply-appearance))))
  (when (fboundp 'file-notify-add-watch)
    (unless zac--watch
      (setq zac--watch
            (file-notify-add-watch
             (zac--appearance-file)
             '(change)
             (lambda (_event)
               (zac--apply-appearance))))))
  nil)

(defun zac-watch-stop ()
  "Stop watching zsh-appearance-control's appearance file."
  (interactive)
  (when zac--watch
    (file-notify-rm-watch zac--watch)
    (setq zac--watch nil)))

;; Start watcher automatically.
(zac-watch-start)

(provide 'zac-theme-autodetection)

;;; zac-theme-autodetection.el ends here
