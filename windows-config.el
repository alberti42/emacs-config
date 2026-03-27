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

;; Split windows and switch to the other buffer instead of mirroring the current one.
(defun windows-config-split-right ()
  "Split window right and show the other buffer in the new window."
  (interactive)
  (split-window-right)
  (other-window 1)
  (switch-to-buffer (other-buffer)))

(defun windows-config-split-below ()
  "Split window below and show the other buffer in the new window."
  (interactive)
  (split-window-below)
  (other-window 1)
  (switch-to-buffer (other-buffer)))

;; Change default behavior when splitting windows
(keymap-global-set "C-x 3" #'windows-config-split-right)
(keymap-global-set "C-x 2" #'windows-config-split-below)

;; Bind C-b (originally: backward-char) for tmux-map
(define-prefix-command 'tmux-map)
(global-set-key (kbd "C-b") 'tmux-map)
(with-eval-after-load 'which-key
  (add-to-list 'which-key-inhibit-regexps "^C-b$"))

(global-set-key (kbd "C-b <left>")  'windmove-left-or-tmux)
(global-set-key (kbd "C-b <right>") 'windmove-right-or-tmux)
(global-set-key (kbd "C-b <up>")    'windmove-up-or-tmux)
(global-set-key (kbd "C-b <down>")  'windmove-down-or-tmux)

(defun windows-config-tmux-split-h ()
  "Split the current tmux pane horizontally (equivalent to prefix %)."
  (interactive)
  (when (windows-config--in-tmux-p)
    (call-process "tmux" nil nil nil "split-window" "-h" "-c" "#{pane_current_path}")))

(defun windows-config-tmux-split-v ()
  "Split the current tmux pane vertically (equivalent to prefix \")."
  (interactive)
  (when (windows-config--in-tmux-p)
    (call-process "tmux" nil nil nil "split-window" "-v" "-c" "#{pane_current_path}")))

(defun windows-config-tmux-next-window ()
  "Switch to the next tmux window."
  (interactive)
  (when (windows-config--in-tmux-p)
    (call-process "tmux" nil nil nil "next-window")))

(defun windows-config-tmux-prev-window ()
  "Switch to the previous tmux window."
  (interactive)
  (when (windows-config--in-tmux-p)
    (call-process "tmux" nil nil nil "previous-window")))

(global-set-key (kbd "C-b %") #'windows-config-tmux-split-h)
(global-set-key (kbd "C-b \"") #'windows-config-tmux-split-v)
(global-set-key (kbd "C-b n") #'windows-config-tmux-next-window)
(global-set-key (kbd "C-b p") #'windows-config-tmux-prev-window)

;; windmove: navigate between windows with C-c <arrow>.
;; Always bind to the -or-tmux variants; they check the terminal environment
;; at call time so the tmux fallback only fires when actually inside tmux.
(use-package windmove
  :straight nil
  :bind (("C-b <left>"  . windmove-left-or-tmux)
         ("C-c <right>" . windmove-right-or-tmux)
         ("C-c <up>"    . windmove-up-or-tmux)
         ("C-c <down>"  . windmove-down-or-tmux)))

;; Window resizing: grow the current window in the given direction.
;; Uses repeat-mode: after the initial C-c C-<arrow>, keep pressing C-<arrow>
;; to continue resizing (timeout controlled by `repeat-exit-timeout').
;; Horizontal: arrow direction = which way the shared border moves (tmux convention).
;; When a window exists to the right, the right border is moved:
;;   C-RIGHT → right border moves right → current window grows,   window to the right shrinks.
;;   C-LEFT  → right border moves left  → current window shrinks, window to the right grows.
;; At the right edge (no window to the right), the left border is moved instead,
;; so the operations are swapped to keep arrow semantics consistent:
;;   C-RIGHT → left border moves right → current window shrinks, window to the left grows.
;;   C-LEFT  → left border moves left  → current window grows,   window to the left shrinks.
(defun windows-config-resize-right ()
  "Move the active horizontal border rightward, consistent with tmux resize-pane -R."
  (interactive)
  (if (window-in-direction 'right)
      (enlarge-window-horizontally 1)
    (shrink-window-horizontally 1)))

(defun windows-config-resize-left ()
  "Move the active horizontal border leftward, consistent with tmux resize-pane -L."
  (interactive)
  (if (window-in-direction 'right)
      (shrink-window-horizontally 1)
    (enlarge-window-horizontally 1)))

(global-set-key (kbd "C-c C-<right>") #'windows-config-resize-right)
(global-set-key (kbd "C-c C-<left>")  #'windows-config-resize-left)

;; Vertical: arrow direction = which way the shared border moves (tmux convention).
;; When a window exists below, the bottom border is moved:
;;   C-UP   → bottom border moves up   → current window shrinks, window below grows.
;;   C-DOWN → bottom border moves down → current window grows,   window below shrinks.
;; At the bottom edge (no window below), the top border is moved instead,
;; so the operations are swapped to keep arrow semantics consistent:
;;   C-UP   → top border moves up   → current window grows,   window above shrinks.
;;   C-DOWN → top border moves down → current window shrinks, window above grows.
(defun windows-config-resize-up ()
  "Move the active vertical border upward, consistent with tmux resize-pane -U."
  (interactive)
  (if (window-in-direction 'below)
      (shrink-window 1)
    (enlarge-window 1)))
(defun windows-config-resize-down ()
  "Move the active vertical border downward, consistent with tmux resize-pane -D."
  (interactive)
  (if (window-in-direction 'below)
      (enlarge-window 1)
    (shrink-window 1)))

(global-set-key (kbd "C-c C-<up>")   #'windows-config-resize-up)
(global-set-key (kbd "C-c C-<down>") #'windows-config-resize-down)

(defvar-keymap window-resize-repeat-map
  :repeat t
  "C-<right>" #'windows-config-resize-right
  "C-<left>"  #'windows-config-resize-left
  "C-<up>"    #'windows-config-resize-up
  "C-<down>"  #'windows-config-resize-down)

(repeat-mode 1)

;; Window joining: move the current window to be a split adjacent to another window.
;; Follows tmux move-pane convention:
;;   S-LEFT / S-RIGHT → vertical split (stacked) with the window in that column.
;;   S-UP   / S-DOWN  → horizontal split (side by side) with the window in that row.
(defun windows-config-join-left ()
  "Join current window with the window to the left as a vertical split."
  (interactive)
  (when-let* ((target (window-in-direction 'left)))
    (let ((source (selected-window))
          (new-win (split-window target nil 'below)))
      (set-window-buffer new-win (window-buffer source))
      (delete-window source)
      (select-window new-win))))

(defun windows-config-join-right ()
  "Join current window with the window to the right as a vertical split."
  (interactive)
  (when-let* ((target (window-in-direction 'right)))
    (let ((source (selected-window))
          (new-win (split-window target nil 'below)))
      (set-window-buffer new-win (window-buffer source))
      (delete-window source)
      (select-window new-win))))

(defun windows-config-join-up ()
  "Join current window with the window above as a horizontal split."
  (interactive)
  (when-let* ((target (window-in-direction 'above)))
    (let ((source (selected-window))
          (new-win (split-window target nil 'right)))
      (set-window-buffer new-win (window-buffer source))
      (delete-window source)
      (select-window new-win))))

(defun windows-config-join-down ()
  "Join current window with the window below as a horizontal split."
  (interactive)
  (when-let* ((target (window-in-direction 'below)))
    (let ((source (selected-window))
          (new-win (split-window target nil 'right)))
      (set-window-buffer new-win (window-buffer source))
      (delete-window source)
      (select-window new-win))))

(global-set-key (kbd "C-c S-<left>")  #'windows-config-join-left)
(global-set-key (kbd "C-c S-<right>") #'windows-config-join-right)
(global-set-key (kbd "C-c S-<up>")    #'windows-config-join-up)
(global-set-key (kbd "C-c S-<down>")  #'windows-config-join-down)

;; Window swapping: swap the current window's buffer with an adjacent window,
;; equivalent to tmux swap-pane.  Uses windmove-swap-states-* (Emacs 28+).
(global-set-key (kbd "C-c M-<left>")  #'windmove-swap-states-left)
(global-set-key (kbd "C-c M-<right>") #'windmove-swap-states-right)
(global-set-key (kbd "C-c M-<up>")    #'windmove-swap-states-up)
(global-set-key (kbd "C-c M-<down>")  #'windmove-swap-states-down)

(provide 'windows-config)
;;; windows-config.el ends here
