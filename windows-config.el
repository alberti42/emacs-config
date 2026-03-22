;;; windows-config.el --- Window navigation and resizing -*- lexical-binding: t; -*-

;;; Code:

;; windmove: navigate between windows with C-c <arrow>.
(use-package windmove
  :straight nil
  :bind (("C-c <left>"  . windmove-left)
         ("C-c <right>" . windmove-right)
         ("C-c <up>"    . windmove-up)
         ("C-c <down>"  . windmove-down)))

;; Window resizing: grow the current window in the given direction.
(bind-keys ("C-c C-<right>" . enlarge-window-horizontally)
           ("C-c C-<left>"  . shrink-window-horizontally)
           ("C-c C-<up>"    . enlarge-window)
           ("C-c C-<down>"  . shrink-window))

(provide 'windows-config)
;;; windows-config.el ends here
