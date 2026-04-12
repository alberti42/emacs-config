;;; soft-wrap.el --- Soft wrap at fill-column -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module provides a "soft wrap" feature that aims to visually match hard
;; wrapping (M-q / fill-paragraph) without modifying buffer contents.
;;
;; Public entry points:
;; - `soft-wrap-mode'         Buffer-local minor mode; toggles soft wrapping.
;; - `global-soft-wrap-mode'  Global minor mode; enables soft-wrap-mode everywhere.
;;
;; Implementation notes:
;; - Soft wrapping is implemented using `visual-line-mode' and a window right
;;   margin so that the window's effective text width equals the target column.
;; - Continuation indentation is handled by built-in `visual-wrap-prefix-mode'
;;   when available (Emacs 30+).
;; - Margins are per-window. This module installs hooks to keep margins correct
;;   across resizes and buffer switches.
;; - The left margin is preserved by default so TTY gutters that reserve it
;;   (e.g. git-gutter) keep working. This module only manages the right margin.

;;; Code:

(require 'pp)

(defgroup soft-wrap nil
  "Soft wrap at a target column using window margins."
  :group 'convenience)

(defcustom soft-wrap-default-width nil
  "Default wrap column for `soft-wrap-mode'.

If nil, use `fill-column'. If an integer, that value is used when
`soft-wrap-mode' is enabled."
  :type '(choice (const :tag "Use fill-column" nil)
                 (integer :tag "Column" 100))
  :group 'soft-wrap)


(defcustom soft-wrap-enable-wrap-prefix t
  "Whether to enable `visual-wrap-prefix-mode' when available."
  :type 'boolean
  :group 'soft-wrap)


(defvar-local soft-wrap--saved-vars-state nil
  "Alist of (VAR . (WAS-LOCAL-P . VALUE)) for managed variables.")

(defconst soft-wrap--managed-vars
  '(word-wrap truncate-lines auto-hscroll-mode auto-fill-function)
  "List of variables whose state is managed by `soft-wrap-mode'.

Two things are handled separately rather than via this list:

`visual-wrap-prefix-mode': it is a minor mode whose disable path runs cleanup
hooks (e.g. removing text properties). Restoring the variable directly would
skip those hooks and leave artifacts. Saved in `soft-wrap--saved-visual-wrap-prefix-mode'.

Window right margin: it is per-window, not per-buffer, so it cannot be stored
as a buffer-local variable. Saved as a window parameter
`soft-wrap--saved-right-margin' on each window showing the buffer.")

(defvar-local soft-wrap--target-width nil
  "Target wrap width for the current buffer.

When nil, the current value of `fill-column' is used when enabling.")

(defvar-local soft-wrap--saved-visual-wrap-prefix-mode nil
  "Whether `visual-wrap-prefix-mode' was active before soft wrap was enabled.")

(defvar soft-wrap-mode-map (make-sparse-keymap)
  "Keymap for `soft-wrap-mode'.")

;; Disable manual horizontal trackpad/mouse scrolling while soft-wrap is active.
(define-key soft-wrap-mode-map (kbd "<wheel-left>") #'ignore)
(define-key soft-wrap-mode-map (kbd "<wheel-right>") #'ignore)

(easy-menu-define soft-wrap-mode-menu soft-wrap-mode-map
  "Menu for `soft-wrap-mode'."
  '("Soft Wrap Mode"
    ["Set wrap width..." soft-wrap-set-width]
    "---"
    ["Turn off minor mode" (soft-wrap-mode -1)]
    ["Help for minor mode" (describe-function 'soft-wrap-mode)]))

(defun soft-wrap-set-width ()
  "Interactively set the wrap width for the current buffer.

Offers `fill-column' as a choice (which makes the width track `fill-column'
dynamically) or accepts any integer."
  (interactive)
  (let* ((fc fill-column)
         (fc-choice (format "fill-column (%d)" fc))
         (input (completing-read
                 "Wrap width: "
                 (list fc-choice)
                 nil nil nil nil fc-choice))
         (new-width (if (equal input fc-choice)
                        nil
                      (let ((n (string-to-number input)))
                        (if (> n 0) n
                          (user-error "Invalid wrap width: %s" input))))))
    (setq-local soft-wrap--target-width new-width)
    (setq-local soft-wrap--warned-mismatch nil)
    (soft-wrap--refresh-buffer-windows)))

;;;###autoload
(define-minor-mode soft-wrap-mode
  "Buffer-local minor mode for visual soft wrapping at a target column.

The target column is taken from `soft-wrap-default-width' if non-nil,
otherwise from `fill-column'."
  :lighter (:eval (format " Wrap:%d" (or soft-wrap--target-width fill-column)))
  :keymap soft-wrap-mode-map
  :group 'soft-wrap
  (if soft-wrap-mode
      (soft-wrap--do-enable)
    (soft-wrap--do-disable)))

;;;###autoload
(define-globalized-minor-mode global-soft-wrap-mode
  soft-wrap-mode soft-wrap-mode
  "Global minor mode that enables `soft-wrap-mode' in every buffer."
  :group 'soft-wrap)

(define-minor-mode soft-wrap--hooks-mode
  "Internal mode that installs window hooks needed by `soft-wrap-mode'.

Not intended for direct use — `soft-wrap-mode' activates this automatically."
  :global t
  :group 'soft-wrap
  (if soft-wrap--hooks-mode
      (progn
        (add-hook 'window-state-change-functions #'soft-wrap--window-state-change))
    (remove-hook 'window-state-change-functions #'soft-wrap--window-state-change)))

(defun soft-wrap--window-target-width (_window)
  "Return the target wrap width for the current buffer."
  (or soft-wrap--target-width fill-column))

(defun soft-wrap--reserved-continuation-cols (window)
  "Return columns reserved for continuation/truncation glyphs in WINDOW."
  (let* ((fringes (window-fringes window))
         (lfringe (car fringes))
         (rfringe (nth 1 fringes)))
    (if (and (display-graphic-p (window-frame window))
             overflow-newline-into-fringe
             (not (eq lfringe 0))
             (not (eq rfringe 0)))
        0
      1)))

(defun soft-wrap--computed-max-chars-per-line (window)
  "Compute max chars per display line in WINDOW.

Mirrors the logic of Emacs' `window-max-chars-per-line' (but does not call it).
This accounts for line numbers, continuation/truncation glyph reservation, and
font metrics."
  (with-selected-window (window-normalize-window window t)
    (let* ((window-width (window-body-width window t))
           (font-width (or (window-font-width window nil)
                           (frame-char-width (window-frame window))
                           1))
           (line-number-cols
            (if (fboundp 'line-number-display-width)
                (ceiling (line-number-display-width))
              0))
           (ncols (- (/ window-width font-width) line-number-cols)))
      (- ncols (soft-wrap--reserved-continuation-cols window)))))

(defun soft-wrap--debug-data (&optional window)
  "Return a plist of soft-wrap state for debugging."
  (let* ((buf (current-buffer))
         (wins (if (and window (window-live-p window))
                   (list window)
                 (get-buffer-window-list buf nil t))))
    (list
     :buffer (buffer-name buf)
     :major-mode major-mode
     :window-system window-system
     :fill-column fill-column
     :soft-wrap-mode soft-wrap-mode
     :soft-wrap-target soft-wrap--target-width
     :visual-line-mode (bound-and-true-p visual-line-mode)
     :visual-wrap-prefix-mode (and (fboundp 'visual-wrap-prefix-mode)
                                   (bound-and-true-p visual-wrap-prefix-mode))
     :display-line-numbers-mode (bound-and-true-p display-line-numbers-mode)
     :auto-fill-function auto-fill-function
     :windows
     (mapcar
      (lambda (w)
        (list
         :window w
         :selected (eq w (selected-window))
         :window-total (window-total-width w)
         :window-body (window-body-width w)
         :computed-max-chars (soft-wrap--computed-max-chars-per-line w)
         :max-chars (window-max-chars-per-line w)
         :margins (window-margins w)
         :fringes (window-fringes w)
         :reserved-cols (soft-wrap--reserved-continuation-cols w)
         :line-number-cols (when (fboundp 'line-number-display-width)
                             (line-number-display-width w))
         :wrap-prefix-width (string-width (format-mode-line (or wrap-prefix "")))
         :line-prefix-width (string-width (format-mode-line (or line-prefix "")))))
      wins))))

(defun soft-wrap--save-window-right-margin (window)
  "Save WINDOW's current right margin as a window parameter (once only).
The value is wrapped in a list so nil (not set) is distinguished from
absence of the parameter (not yet saved)."
  (when (window-live-p window)
    (unless (window-parameter window 'soft-wrap--saved-right-margin)
      (set-window-parameter window 'soft-wrap--saved-right-margin
                            (list (cdr (window-margins window)))))))

(defun soft-wrap--restore-window-right-margin (window)
  "Restore WINDOW's right margin from the saved window parameter."
  (when (window-live-p window)
    (let ((saved (window-parameter window 'soft-wrap--saved-right-margin)))
      (when saved
        (let* ((m (window-margins window))
               (left (or (car m) 0)))
          (set-window-margins window left (car saved)))
        (set-window-parameter window 'soft-wrap--saved-right-margin nil)))))

(defun soft-wrap--adjust-window-margins (window)
  "Adjust WINDOW's right margin to hit the target wrap width."
  (when (window-live-p window)
    (let ((buf (window-buffer window)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when soft-wrap-mode
            ;; Save the original right margin before the first adjustment.
            ;; The once-only guard in the save function makes this a no-op
            ;; on subsequent calls.
            (soft-wrap--save-window-right-margin window)
            (let* ((target (soft-wrap--window-target-width window))
                   (margins (window-margins window))
                   (left (or (car margins) 0))
                   (right (or (cdr margins) 0))
                   (cur (window-max-chars-per-line window))
                   (delta (- cur target))
                   (new-right (max 0 (+ right delta))))
              (soft-wrap--trace-log "adjust: margins-at-entry=%S left=%d right=%d cur=%d target=%d new-right=%d"
                                    margins left right cur target new-right)
              (unless (= new-right right)
                (set-window-margins window left new-right)))))))))

(defun soft-wrap--refresh-buffer-windows ()
  "Refresh margins for all windows showing the current buffer."
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (soft-wrap--adjust-window-margins w)))

(defun soft-wrap--window-state-change (window)
  "Run on `window-state-change-functions'; re-adjust margins for WINDOW.
Called whenever Emacs detects a window state change (resize, split, etc.)."
  (soft-wrap--adjust-window-margins window))

(defun soft-wrap--save-state ()
  "Save the current state of managed variables."
  (setq-local soft-wrap--saved-vars-state
              (mapcar (lambda (var)
                        (cons var (cons (local-variable-p var) (symbol-value var))))
                      soft-wrap--managed-vars)))

(defun soft-wrap--restore-state ()
  "Restore the saved state of managed variables."
  (dolist (entry soft-wrap--saved-vars-state)
    (let ((var (car entry))
          (was-local (cadr entry))
          (val (cddr entry)))
      (if was-local
          (set (make-local-variable var) val)
        (kill-local-variable var))))
  (setq-local soft-wrap--saved-vars-state nil))

(defun soft-wrap--do-enable ()
  "Enable soft wrapping in the current buffer.
Saves the state of all managed variables, enables visual-line-mode and
visual-wrap-prefix-mode, and adjusts window margins to match the target width.
Called by `soft-wrap-mode' when toggled on."
  (soft-wrap--hooks-mode 1)

  (soft-wrap--save-state)
  (auto-fill-mode -1)
  (setq-local word-wrap t)
  (setq-local truncate-lines nil)
  (setq-local auto-hscroll-mode nil)

  (setq-local soft-wrap--target-width soft-wrap-default-width)
  (setq-local soft-wrap--warned-mismatch nil)

  (visual-line-mode 1)
  (when (fboundp 'visual-wrap-prefix-mode)
    (setq-local soft-wrap--saved-visual-wrap-prefix-mode
                (bound-and-true-p visual-wrap-prefix-mode))
    (when soft-wrap-enable-wrap-prefix
      (visual-wrap-prefix-mode 1)))

  ;; Keep margins correct as line-number width settles during find-file.
  (add-hook 'window-configuration-change-hook
            #'soft-wrap--refresh-buffer-windows
            'append
            'local)

  ;; Adjust all windows currently showing this buffer. The save of the original
  ;; right margin happens inside soft-wrap--adjust-window-margins.
  (soft-wrap--refresh-buffer-windows))

(defun soft-wrap--do-disable ()
  "Disable soft wrapping in the current buffer.
Restores all managed variables, disables visual-line-mode and
visual-wrap-prefix-mode, and restores window margins to their original values.
Called by `soft-wrap-mode' when toggled off."
  (setq-local soft-wrap--target-width nil)
  (setq-local soft-wrap--warned-mismatch nil)

  (remove-hook 'window-configuration-change-hook
               #'soft-wrap--refresh-buffer-windows
               'local)

  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode (if soft-wrap--saved-visual-wrap-prefix-mode 1 -1)))
  (visual-line-mode -1)

  ;; Restore managed variables (includes auto-fill-function).
  (soft-wrap--restore-state)

  ;; Restore each window's right margin to what it was before soft-wrap enabled.
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (soft-wrap--restore-window-right-margin w))

  (kill-local-variable 'soft-wrap--saved-visual-wrap-prefix-mode))

(defun soft-wrap--debug-dump (&optional window)
  "Pretty-print soft-wrap state for debugging.

When WINDOW is non-nil, include details for that window; otherwise report all
windows showing the current buffer."
  (let* ((w (when window (window-normalize-window window t)))
         (data (soft-wrap--debug-data w)))
    (with-current-buffer (get-buffer-create "*Soft Wrap Debug*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (pp data (current-buffer))))
    (message "Wrote soft-wrap debug to *Soft Wrap Debug*")))

;;; Diagnostics ----------------------------------------------------------------

(defun soft-wrap-diagnose ()
  "Print window margin diagnostic info to *soft-wrap-diag* without side effects."
  (interactive)
  (let* ((window (selected-window))
         (target (or soft-wrap--target-width fill-column))
         (margins (window-margins window))
         (left (or (car margins) 0))
         (right (or (cdr margins) 0))
         (body-px (window-body-width window t))
         (font-w (or (window-font-width window nil) (frame-char-width)))
         (body-cols (/ body-px font-w))
         (cur (soft-wrap--computed-max-chars-per-line window))
         (proposed (max 0 (- cur left target))))
    (with-current-buffer (get-buffer-create "*soft-wrap-diag*")
      (goto-char (point-max))
      (insert (format "target=%d left=%d right=%d body-px=%d font-w=%d body-cols=%d cur=%d proposed=%d emacs-max=%d\n"
                      target left right body-px font-w body-cols cur proposed
                      (window-max-chars-per-line window))))))

(define-key soft-wrap-mode-map (kbd "C-c W") #'soft-wrap-diagnose)

;;; Margin-change tracing -------------------------------------------------------
;;
;; Enable with M-x soft-wrap-trace-start, disable with M-x soft-wrap-trace-stop.
;; Every call to `set-window-margins' is logged to *soft-wrap-trace* with the
;; window, old/new margin values, and a short backtrace so you can see who is
;; responsible for each change.

(defvar soft-wrap--trace-active nil
  "Non-nil when margin-change tracing is active.")

(defun soft-wrap--trace-log (fmt &rest args)
  "Append a formatted line to *soft-wrap-trace*."
  (with-current-buffer (get-buffer-create "*soft-wrap-trace*")
    (goto-char (point-max))
    (insert (apply #'format fmt args) "\n")))

(defun soft-wrap--trace-set-window-margins (orig window &optional left right)
  "Advice around `set-window-margins' that logs every call."
  (let* ((old (window-margins window))
         (old-l (or (car old) 0))
         (old-r (or (cdr old) 0))
         (new-l (or left 0))
         (new-r (or right 0))
         (changed (or (/= old-l new-l) (/= old-r new-r))))
    (when changed
      (soft-wrap--trace-log
       "\n[set-window-margins] buf=%s  margins: (%d . %d) -> (%d . %d)"
       (buffer-name (window-buffer window))
       old-l old-r new-l new-r)
      ;; Short backtrace: skip the advice wrapper frames, show 6 meaningful frames.
      (let ((i 0))
        (mapbacktrace
         (lambda (_evald func _args _flags)
           (when (and (> i 2) (< i 10))
             (soft-wrap--trace-log "  #%d %s" i func))
           (setq i (1+ i))))))
    (funcall orig window left right)))

(defun soft-wrap--trace-hook (name)
  "Return a lambda that logs when the hook named NAME runs."
  (lambda (&rest args)
    (soft-wrap--trace-log "[hook] %s  args=%S  buf=%s"
                          name args (buffer-name (current-buffer)))))

(defvar soft-wrap--trace-hook-fns nil
  "Alist of (hook . fn) pairs added for tracing.")

(defun soft-wrap-trace-start ()
  "Start tracing all `set-window-margins' calls and soft-wrap hook entries.
Results appear in *soft-wrap-trace*."
  (interactive)
  (unless soft-wrap--trace-active
    (setq soft-wrap--trace-active t)
    (advice-add 'set-window-margins :around #'soft-wrap--trace-set-window-margins)
    ;; Trace each hook that soft-wrap registers so we can see what triggers what.
    (setq soft-wrap--trace-hook-fns nil)
    (dolist (hook '(window-configuration-change-hook
                    window-state-change-functions
                    window-buffer-change-functions))
      (let ((fn (soft-wrap--trace-hook hook)))
        (push (cons hook fn) soft-wrap--trace-hook-fns)
        (add-hook hook fn)))
    (with-current-buffer (get-buffer-create "*soft-wrap-trace*")
      (erase-buffer)
      (insert ";; soft-wrap trace started\n"))
    (message "soft-wrap tracing started → *soft-wrap-trace*")))

(defun soft-wrap-trace-stop ()
  "Stop soft-wrap margin tracing."
  (interactive)
  (when soft-wrap--trace-active
    (setq soft-wrap--trace-active nil)
    (advice-remove 'set-window-margins #'soft-wrap--trace-set-window-margins)
    (dolist (pair soft-wrap--trace-hook-fns)
      (remove-hook (car pair) (cdr pair)))
    (setq soft-wrap--trace-hook-fns nil)
    (message "soft-wrap tracing stopped")))

(provide 'soft-wrap)
;;; soft-wrap.el ends here
