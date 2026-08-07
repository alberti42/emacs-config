;;; speedbar-config.el --- Speedbar file/tag browser -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Built-in Speedbar configuration.  Two tweaks over the defaults:
;;
;; - `speedbar-prefer-window' keeps Speedbar in a window of the current frame
;;   instead of popping up a separate frame (impractical for a TTY/tiling setup).
;; - `speedbar-use-images' is disabled so entries use plain-text markers rather
;;   than bitmap icons.
;;
;; In window mode (Emacs 31+), the side-window width is controlled by
;; `speedbar-window-default-width' (width on open) and
;; `speedbar-window-max-width' (width kept on reopen).
;;

;;; Code:

(use-package speedbar
  :straight nil
  :commands (speedbar)
  :config
  ;; Show Speedbar in a window of the current frame, not a separate frame.
  (setq speedbar-prefer-window t)
  ;; No bitmap icons; use plain-text markers.
  (setq speedbar-use-images nil)
  (setq speedbar-window-default-width 30
        speedbar-window-max-width 50))

(provide 'speedbar-config)
;;; speedbar-config.el ends here
