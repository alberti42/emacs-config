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
;; Theme loading is intentionally omitted here while a replacement for
;; Catppuccin is being evaluated.  Add a `zac--apply-theme` call or a
;; `zac-appearance-change-hook` handler once a theme is chosen.

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

(defun zac--apply-cursor-color ()
  "Set cursor color for GUI frames. Safe to call from hooks."
  (when (display-graphic-p)
    (set-cursor-color "#cad3f5")))

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

  ;; Cursor color override (GUI only).
  (zac--apply-cursor-color)

  ;; Match line-number background to WezTerm's padding color for the current
  ;; appearance, so the gutter column blends with the terminal border.
  (when (not (display-graphic-p))
    (let ((appearance (zac--read-appearance)))
      (set-face-background 'line-number
                           (if (equal appearance "0")
                               "#303446"  ; light (Catppuccin Latte)
                             "#24273a")))) ; dark (Catppuccin Macchiato)

  ;; Propagate the updated line-number background to git-gutter and any other
  ;; package faces registered in theme-harmonize.
  (when (fboundp 'emacs-config-harmonize-theme)
    (emacs-config-harmonize-theme)))


(defun zac-watch-start ()
  "Start watching zsh-appearance-control's appearance file."
  (interactive)
  (unless (fboundp 'file-notify-add-watch)
    (message "zac: file notifications not supported; applying once")
    (setq zac--watch nil)
    (zac--apply-appearance)
    nil)
  (zac--apply-appearance)
  ;; Re-apply cursor color after the initial frame is fully set up (GUI
  ;; startup: display-graphic-p may be nil or frame parameters not yet
  ;; final when init.el runs).
  (add-hook 'window-setup-hook #'zac--apply-cursor-color)
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
