;;; windows-config.el --- Window navigation and resizing -*- lexical-binding: t; -*-

;;; Code:

(defun windows-config--in-tmux-p ()
  "Return non-nil if the current frame is running inside a tmux session.
In daemon mode, uses the frame's `environment' parameter which reflects the
connecting client's environment. Falls back to `getenv' for non-daemon Emacs."
  (let ((env (frame-parameter nil 'environment)))
    (if env
        (cl-some (lambda (s) (string-prefix-p "TMUX=" s)) env)
      (and (getenv "TMUX") t))))

(defun windmove-left-or-tmux ()
  "Move focus to the window to the left, or the tmux pane to the left if at the edge."
  (interactive)
  (if (window-in-direction 'left)
      (windmove-left)
    (when (windows-config--in-tmux-p)
      (call-process-shell-command "tmux if -F '#{pane_at_left}' '' 'select-pane -L'" nil nil))))


(defun windmove-right-or-tmux ()
  "Move focus to the window to the right, or the tmux pane to the right if at the edge."
  (interactive)
  (if (window-in-direction 'right)
      (windmove-right)
    (when (windows-config--in-tmux-p)
      (call-process-shell-command "tmux if -F '#{pane_at_right}' '' 'select-pane -R'" nil nil))))

(defun windmove-up-or-tmux ()
  "Move focus to the window above, or the tmux pane above if at the edge."
  (interactive)
  (if (window-in-direction 'above)
      (windmove-up)
    (when (windows-config--in-tmux-p)
      (call-process-shell-command "tmux if -F '#{pane_at_top}' '' 'select-pane -U'" nil nil))))

(defun windmove-down-or-tmux ()
  "Move focus to the window below, or the tmux pane below if at the edge."
  (interactive)
  (if (window-in-direction 'below)
      (windmove-down)
    (when (windows-config--in-tmux-p)
      (call-process-shell-command "tmux if -F '#{pane_at_bottom}' '' 'select-pane -D'" nil nil))))

;; windmove: navigate between windows with C-c <arrow>.
;; Always bind to the -or-tmux variants; they check the terminal environment
;; at call time so the tmux fallback only fires when actually inside tmux.
(use-package windmove
  :straight nil
  :bind (("C-c <left>"  . windmove-left-or-tmux)
         ("C-c <right>" . windmove-right-or-tmux)
         ("C-c <up>"    . windmove-up-or-tmux)
         ("C-c <down>"  . windmove-down-or-tmux)))

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
