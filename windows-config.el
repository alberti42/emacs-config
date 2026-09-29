;;; windows-config.el --- Window navigation and resizing -*- lexical-binding: t; -*-

;;; Code:

(defun windows-config--in-tmux-p ()
  "Return non-nil if the current frame is running inside a tmux session.
In daemon mode, uses the frame's `environment' parameter which reflects the
connecting client's environment.  Falls back to `getenv' for non-daemon Emacs."
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

;; Split windows, focus the new one, and show the other buffer there.
;; In `dired-mode' the new window keeps mirroring the current dired buffer.
(defun windows-config-split-right ()
  "Split window right and focus the new window.
In `dired-mode', the new window mirrors the current dired buffer;
otherwise it shows the other buffer."
  (interactive)
  (let ((dired (derived-mode-p 'dired-mode)))
    (split-window-right)
    (other-window 1)
    (unless dired
      (switch-to-buffer (other-buffer)))))

(defun windows-config-split-below ()
  "Split window below and focus the new window.
In `dired-mode', the new window mirrors the current dired buffer;
otherwise it shows the other buffer."
  (interactive)
  (let ((dired (derived-mode-p 'dired-mode)))
    (split-window-below)
    (other-window 1)
    (unless dired
      (switch-to-buffer (other-buffer)))))

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

(global-set-key (kbd "C-b x") #'delete-window)
(global-set-key (kbd "C-b %") #'windows-config-split-right)
(global-set-key (kbd "C-b \"") #'windows-config-split-below)

;; Look-up table between bindings and tmux commands
;; that directly supported in Emacs
(defconst windows-config-tmux-key-commands
  '((?c  "new-window")
    (?n  "next-window")
    (?p  "previous-window")
    (?d  "detach-client")
    (?b  "switch-client" "-T" "prefix"))
  "Mapping from C-b key character to tmux command arguments.")

(defun windows-config-tmux-forward-key ()
  "Dispatch the pressed key to the corresponding tmux command."
  (interactive)
  (when (windows-config--in-tmux-p)
    (when-let* ((entry (assq last-command-event windows-config-tmux-key-commands)))
      (apply #'call-process "tmux" nil nil nil (cdr entry)))))

;; Bind each key in the dispatch table explicitly (avoids [t] catch-all
;; which interferes with arrow key escape sequence assembly in terminals).
(dolist (entry windows-config-tmux-key-commands)
  (define-key tmux-map (vector (car entry)) #'windows-config-tmux-forward-key))


;; Window resizing: grow the current window in the given direction.
;; Uses repeat-mode: after the initial C-b C-<arrow>, keep pressing C-<arrow>
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

(global-set-key (kbd "C-b C-<right>") #'windows-config-resize-right)
(global-set-key (kbd "C-b C-<left>")  #'windows-config-resize-left)

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

(global-set-key (kbd "C-b C-<up>")   #'windows-config-resize-up)
(global-set-key (kbd "C-b C-<down>") #'windows-config-resize-down)

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
(defun windows-config--join (target side)
  "Move the selected window into a new split of TARGET on SIDE."
  (let ((source (selected-window))
        (new-win (split-window target nil side)))
    (set-window-buffer new-win (window-buffer source))
    (delete-window source)
    (select-window new-win)))

(defun windows-config-join-left ()
  "Join current window with the window to the left as a vertical split."
  (interactive)
  (when-let* ((target (window-in-direction 'left)))
    (windows-config--join target 'below)))

(defun windows-config-join-right ()
  "Join current window with the window to the right as a vertical split."
  (interactive)
  (when-let* ((target (window-in-direction 'right)))
    (windows-config--join target 'below)))

(defun windows-config-join-up ()
  "Join current window with the window above as a horizontal split."
  (interactive)
  (when-let* ((target (window-in-direction 'above)))
    (windows-config--join target 'right)))

(defun windows-config-join-down ()
  "Join current window with the window below as a horizontal split."
  (interactive)
  (when-let* ((target (window-in-direction 'below)))
    (windows-config--join target 'right)))

(global-set-key (kbd "C-b S-<left>")  #'windows-config-join-left)
(global-set-key (kbd "C-b S-<right>") #'windows-config-join-right)
(global-set-key (kbd "C-b S-<up>")    #'windows-config-join-up)
(global-set-key (kbd "C-b S-<down>")  #'windows-config-join-down)

(defvar-keymap window-join-repeat-map
  :repeat t
  "S-<left>"  #'windows-config-join-left
  "S-<right>" #'windows-config-join-right
  "S-<up>"    #'windows-config-join-up
  "S-<down>"  #'windows-config-join-down)

;; Window unjoining, the reverse of joining: take the current window out of
;; its stack and place it beside the whole stack.  The stack is the window's
;; parent in the window tree, so splitting the parent gives a window as tall
;; (or as wide) as the stack.  The split happens before the delete: in a
;; stack of two, deleting first dissolves the parent.
(defun windows-config--unjoin (side)
  "Move the selected window out of its stack to SIDE of the stack.
SIDE is one of `left', `right', `above', `below'.  For `left' and
`right' the window must be part of a vertical stack, for `above'
and `below' part of a side-by-side row."
  (let* ((win (selected-window))
         (row (memq side '(above below))))
    (unless (window-combined-p win row)
      (user-error "Window is not part of a %s" (if row "row" "stack")))
    (let ((new-win (split-window (window-parent win) nil side)))
      (set-window-buffer new-win (window-buffer win))
      (delete-window win)
      (select-window new-win))))

(defun windows-config-unjoin-left ()
  "Move current window out of its stack to the left of the stack."
  (interactive)
  (windows-config--unjoin 'left))

(defun windows-config-unjoin-right ()
  "Move current window out of its stack to the right of the stack."
  (interactive)
  (windows-config--unjoin 'right))

(defun windows-config-unjoin-up ()
  "Move current window out of its row to above the row."
  (interactive)
  (windows-config--unjoin 'above))

(defun windows-config-unjoin-down ()
  "Move current window out of its row to below the row."
  (interactive)
  (windows-config--unjoin 'below))

(global-set-key (kbd "C-b M-S-<left>")  #'windows-config-unjoin-left)
(global-set-key (kbd "C-b M-S-<right>") #'windows-config-unjoin-right)
(global-set-key (kbd "C-b M-S-<up>")    #'windows-config-unjoin-up)
(global-set-key (kbd "C-b M-S-<down>")  #'windows-config-unjoin-down)

(defvar-keymap window-unjoin-repeat-map
  :repeat t
  "M-S-<left>"  #'windows-config-unjoin-left
  "M-S-<right>" #'windows-config-unjoin-right
  "M-S-<up>"    #'windows-config-unjoin-up
  "M-S-<down>"  #'windows-config-unjoin-down)

;; Window swapping: swap the current window's buffer with an adjacent window,
;; equivalent to tmux swap-pane.  Uses windmove-swap-states-* (Emacs 28+).
(global-set-key (kbd "C-b M-<left>")  #'windmove-swap-states-left)
(global-set-key (kbd "C-b M-<right>") #'windmove-swap-states-right)
(global-set-key (kbd "C-b M-<up>")    #'windmove-swap-states-up)
(global-set-key (kbd "C-b M-<down>")  #'windmove-swap-states-down)

(defvar-keymap window-swap-repeat-map
  :repeat t
  "M-<left>"  #'windmove-swap-states-left
  "M-<right>" #'windmove-swap-states-right
  "M-<up>"    #'windmove-swap-states-up
  "M-<down>"  #'windmove-swap-states-down)

;; Send buffer: lift the current window's buffer and display it in an
;; adjacent window, leaving the layout untouched.  The source window
;; switches to its previous buffer (window-local, no global buffer-list
;; side effects); focus follows the buffer into the destination window so
;; repeated chords carry the same buffer across a chain of windows.  No
;; tmux equivalent.
(defun windows-config--send-buffer-to (direction)
  "Display current buffer in the window in DIRECTION; rotate source window.
Focus follows the buffer into the destination window.
DIRECTION is one of `left', `right', `above', `below'."
  (if-let* ((target (window-in-direction direction)))
      (windows-config--send-buffer-to-window target)
    (user-error "No window %s" direction)))

(defun windows-config--send-buffer-to-window (target)
  "Display current buffer in window TARGET; rotate source window.
Focus follows the buffer into TARGET."
  (let ((buf (current-buffer)))
    (switch-to-prev-buffer)
    (set-window-buffer target buf)
    (select-window target)))

(defun windows-config-send-buffer-left ()
  "Send current buffer to the window on the left."
  (interactive)
  (windows-config--send-buffer-to 'left))

(defun windows-config-send-buffer-right ()
  "Send current buffer to the window on the right."
  (interactive)
  (windows-config--send-buffer-to 'right))

(defun windows-config-send-buffer-up ()
  "Send current buffer to the window above."
  (interactive)
  (windows-config--send-buffer-to 'above))

(defun windows-config-send-buffer-down ()
  "Send current buffer to the window below."
  (interactive)
  (windows-config--send-buffer-to 'below))

(global-set-key (kbd "C-b C-M-<left>")  #'windows-config-send-buffer-left)
(global-set-key (kbd "C-b C-M-<right>") #'windows-config-send-buffer-right)
(global-set-key (kbd "C-b C-M-<up>")    #'windows-config-send-buffer-up)
(global-set-key (kbd "C-b C-M-<down>")  #'windows-config-send-buffer-down)

(defvar-keymap window-send-buffer-repeat-map
  :repeat t
  "C-M-<left>"  #'windows-config-send-buffer-left
  "C-M-<right>" #'windows-config-send-buffer-right
  "C-M-<up>"    #'windows-config-send-buffer-up
  "C-M-<down>"  #'windows-config-send-buffer-down)

;; Numbered windows: the long form of the arrow operations.  C-b w, C-b M-w,
;; C-b C-M-w and C-b W draw a number in every window of the frame and act on
;; the window whose number is typed, as C-b <arrow>, M-<arrow>, C-M-<arrow>
;; and S-<arrow> act on the neighbour.  Numbers follow `window-list' from the
;; frame's first window, so they do not depend on which window is selected.
(defface windows-config-window-number
  '((t :inherit isearch :weight bold))
  "Face of the numbers drawn by `windows-config--read-window'.")

(defun windows-config--number-overlay (window n)
  "Draw N at the start of WINDOW and return the overlay.
The number replaces the first character shown, so no text moves."
  (with-current-buffer (window-buffer window)
    (let* ((start (window-start window))
           (on-char (and (< start (point-max))
                         (/= (char-after start) ?\n)))
           (ov (make-overlay start (if on-char (1+ start) start)))
           (label (propertize (number-to-string n)
                              'face 'windows-config-window-number)))
      (overlay-put ov 'window window)
      (overlay-put ov (if on-char 'display 'before-string) label)
      ov)))

(defun windows-config--read-window (prompt)
  "Number the windows of the selected frame and return the one typed.
PROMPT is shown in the echo area.  A key that is not a digit quits."
  (let* ((windows (seq-take (window-list nil 'nomini (frame-first-window)) 9))
         (overlays (seq-map-indexed
                    (lambda (win i) (windows-config--number-overlay win (1+ i)))
                    windows))
         (key (unwind-protect
                  (read-key prompt)
                (mapc #'delete-overlay overlays)))
         (n (and (characterp key) (<= ?1 key ?9) (- key ?0))))
    (cond ((null n) (keyboard-quit))
          ((nth (1- n) windows))
          (t (user-error "No window %d" n)))))

(defun windows-config--read-other-window (prompt)
  "Like `windows-config--read-window' with PROMPT, but not the selected window."
  (let ((target (windows-config--read-window prompt)))
    (when (eq target (selected-window))
      (user-error "That is the selected window"))
    target))

(defun windows-config--join-side (target)
  "Return the side on which `windows-config-join-window' splits TARGET.
A TARGET left or right of the selected window is split `below', one
above or below it is split `right', as the S-<arrow> joins do.  A
diagonal TARGET is split along its longer side."
  (pcase-let ((`(,left ,top ,right ,bottom) (window-pixel-edges))
              (`(,t-left ,t-top ,t-right ,t-bottom) (window-pixel-edges target)))
    (let ((beside (or (<= t-right left) (>= t-left right)))
          (stacked (or (<= t-bottom top) (>= t-top bottom))))
      (cond ((and beside (not stacked)) 'below)
            ((and stacked (not beside)) 'right)
            ((> (window-pixel-width target) (window-pixel-height target)) 'right)
            (t 'below)))))

(defun windows-config-select-window ()
  "Select the window whose number is typed."
  (interactive)
  (select-window (windows-config--read-window "Select window: ")))

(defun windows-config-swap-window ()
  "Swap states with the window whose number is typed."
  (interactive)
  (window-swap-states nil (windows-config--read-other-window "Swap with window: ")))

(defun windows-config-send-buffer-to-window ()
  "Send current buffer to the window whose number is typed."
  (interactive)
  (windows-config--send-buffer-to-window
   (windows-config--read-other-window "Send buffer to window: ")))

(defun windows-config-join-window ()
  "Join current window with the window whose number is typed."
  (interactive)
  (let ((target (windows-config--read-other-window "Join window: ")))
    (windows-config--join target (windows-config--join-side target))))

(defun windows-config-unjoin-toward ()
  "Unjoin current window toward the typed direction.
The direction is one of l, r, u, d or an arrow; any other key quits."
  (interactive)
  (let ((side (pcase (read-key "Unjoin toward (l/r/u/d): ")
                ((or ?l 'left) 'left)
                ((or ?r 'right) 'right)
                ((or ?u 'up) 'above)
                ((or ?d 'down) 'below))))
    (if side
        (windows-config--unjoin side)
      (keyboard-quit))))

(global-set-key (kbd "C-b w")     #'windows-config-select-window)
(global-set-key (kbd "C-b M-w")   #'windows-config-swap-window)
(global-set-key (kbd "C-b C-M-w") #'windows-config-send-buffer-to-window)
(global-set-key (kbd "C-b W")     #'windows-config-join-window)
(global-set-key (kbd "C-b M-W")   #'windows-config-unjoin-toward)

;; Reversible C-x 1: press once to go single-window, again to restore.
(winner-mode +1)

(defun windows-config-toggle-delete-other-windows ()
  "Delete other windows in frame if any, or restore previous window config."
  (interactive)
  (if (and winner-mode
           (equal (selected-window) (next-window)))
      ;; if the window fills the entire frame, then undo
      (winner-undo)
    ;; otherwise delete all other windows
    (delete-other-windows)))

(global-set-key (kbd "C-x 1") #'windows-config-toggle-delete-other-windows)
(global-set-key (kbd "C-b z") #'windows-config-toggle-delete-other-windows)

(global-set-key (kbd "C-`") #'switch-to-minibuffer)

(provide 'windows-config)
;;; windows-config.el ends here
