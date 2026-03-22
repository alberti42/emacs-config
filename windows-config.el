;;; windows-config.el --- Window navigation and resizing -*- lexical-binding: t; -*-

;;; Code:

(defun windmove-left-or-tmux ()
  "Move focus to the window to the left, or the tmux pane to the left if at the edge."
  (interactive)
  (if (window-in-direction 'left)
      (windmove-left)
    (shell-command "tmux if -F '#{pane_at_left}' '' 'select-pane -L'")))

(defun windmove-right-or-tmux ()
  "Move focus to the window to the right, or the tmux pane to the right if at the edge."
  (interactive)
  (if (window-in-direction 'right)
      (windmove-right)
    (shell-command "tmux if -F '#{pane_at_right}' '' 'select-pane -R'")))

(defun windmove-up-or-tmux ()
  "Move focus to the window above, or the tmux pane above if at the edge."
  (interactive)
  (if (window-in-direction 'above)
      (windmove-up)
    (shell-command "tmux if -F '#{pane_at_top}' '' 'select-pane -U'")))

(defun windmove-down-or-tmux ()
  "Move focus to the window below, or the tmux pane below if at the edge."
  (interactive)
  (if (window-in-direction 'below)
      (windmove-down)
    (shell-command "tmux if -F '#{pane_at_bottom}' '' 'select-pane -D'")))

;; windmove: navigate between windows with C-c <arrow>.
;; When running inside tmux, bind to the -or-tmux variants so navigation
;; falls through to tmux pane switching at the Emacs window edge.
(use-package windmove
  :straight nil
  :config
  (let ((in-tmux (getenv "TMUX")))
    (global-set-key (kbd "C-c <left>")  (if in-tmux #'windmove-left-or-tmux  #'windmove-left))
    (global-set-key (kbd "C-c <right>") (if in-tmux #'windmove-right-or-tmux #'windmove-right))
    (global-set-key (kbd "C-c <up>")    (if in-tmux #'windmove-up-or-tmux    #'windmove-up))
    (global-set-key (kbd "C-c <down>")  (if in-tmux #'windmove-down-or-tmux  #'windmove-down))))

;; Window resizing: grow the current window in the given direction.
;; Uses repeat-mode: after the initial C-c C-<arrow>, keep pressing C-<arrow>
;; to continue resizing (timeout controlled by `repeat-exit-timeout').
(global-set-key (kbd "C-c C-<right>") #'enlarge-window-horizontally)
(global-set-key (kbd "C-c C-<left>")  #'shrink-window-horizontally)
(global-set-key (kbd "C-c C-<up>")    #'enlarge-window)
(global-set-key (kbd "C-c C-<down>")  #'shrink-window)

(defvar-keymap window-resize-repeat-map
  :repeat t
  "C-<right>" #'enlarge-window-horizontally
  "C-<left>"  #'shrink-window-horizontally
  "C-<up>"    #'enlarge-window
  "C-<down>"  #'shrink-window)

(repeat-mode 1)

(provide 'windows-config)
;;; windows-config.el ends here
