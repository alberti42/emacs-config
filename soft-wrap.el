;;; soft-wrap.el --- Soft wrap at fill-column -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module provides a "soft wrap" feature that aims to visually match hard
;; wrapping (M-q / fill-paragraph) without modifying buffer contents.
;;
;; Public entry points:
;; - `soft-wrap-mode'         Buffer-local minor mode; toggles soft wrapping.
;; - `global-soft-wrap-mode'  Global minor mode; enables soft-wrap-mode everywhere.
;; - `soft-wrap-set-width'    Interactively change the wrap width for the current buffer.
;;
;; Implementation notes:
;; - Soft wrapping is implemented using `visual-line-mode' and a window right
;;   margin so that the window's effective text width equals the target column.
;; - Continuation indentation is handled by built-in `visual-wrap-prefix-mode'
;;   when available (Emacs 30+).
;; - Margins are per-window. This module installs hooks to keep margins correct
;;   across resizes and window configuration changes.
;; - The left margin is always preserved so TTY gutters that reserve it
;;   (e.g. git-gutter) keep working. This module only manages the right margin.
;; - Optional diagnostic and tracing tools live in `soft-wrap-diagnostic.el'.
;;   Load them by setting `soft-wrap-load-diagnostics' to t before loading this file.

;;; Code:

(require 'pp)

;;; Customization --------------------------------------------------------------

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


(defcustom soft-wrap-width-step 2
  "Number of columns added or removed by `soft-wrap-expand'/`soft-wrap-shrink'."
  :type 'integer
  :group 'soft-wrap)

(defcustom soft-wrap-default-centered nil
  "Whether `soft-wrap-mode' starts with centred layout enabled.

When non-nil, every buffer entering `soft-wrap-mode' has its body
centred horizontally by default — an olivetti-inspired layout
implemented on top of soft-wrap's column-accurate width calculation.
Toggle at runtime with `soft-wrap-centered'.  For per-mode opt-in
(e.g. centred Markdown but right-only everywhere else), call
`(soft-wrap-centered 1)' in the relevant mode hook after enabling
`soft-wrap-mode'."
  :type 'boolean
  :group 'soft-wrap)


;;; Internal state ------------------------------------------------------------

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

(defvar-local soft-wrap--refresh-timer nil
  "Pending idle timer for a debounced margin refresh, or nil if none.
Set by `soft-wrap--schedule-refresh' and cleared when it fires or when
`soft-wrap-mode' is disabled.")

(defvar-local soft-wrap--centered nil
  "Non-nil to centre the body horizontally.
Toggle interactively with `soft-wrap-centered'.

When nil (the default), only the right margin is grown to hit the
target wrap width.  When non-nil, both margins are grown symmetrically
so the body is centred in the window; the saved (pre-`soft-wrap-mode')
left margin is preserved as the inner floor, so gutters reserved on the
left (e.g. by `git-gutter') keep working.")

;;; Mode definitions ----------------------------------------------------------

(defvar soft-wrap-mode-map (make-sparse-keymap)
  "Keymap for `soft-wrap-mode'.")

;; Disable manual horizontal trackpad/mouse scrolling while soft-wrap is active.
(define-key soft-wrap-mode-map (kbd "<wheel-left>") #'ignore)
(define-key soft-wrap-mode-map (kbd "<wheel-right>") #'ignore)
(define-key soft-wrap-mode-map (kbd "C-c }") #'soft-wrap-expand)
(define-key soft-wrap-mode-map (kbd "C-c {") #'soft-wrap-shrink)

(defvar soft-wrap-width-repeat-map
  (let ((map (make-sparse-keymap)))
    (define-key map "}" #'soft-wrap-expand)
    (define-key map "{" #'soft-wrap-shrink)
    map))
(put 'soft-wrap-expand 'repeat-map 'soft-wrap-width-repeat-map)
(put 'soft-wrap-shrink 'repeat-map 'soft-wrap-width-repeat-map)

(easy-menu-define soft-wrap-mode-menu soft-wrap-mode-map
  "Menu for `soft-wrap-mode'."
  '("Soft Wrap Mode"
    ["Set wrap width..." soft-wrap-set-width]
    ["Expand wrap area" soft-wrap-expand]
    ["Shrink wrap area" soft-wrap-shrink]
    ["Centred layout" soft-wrap-centered
     :style toggle :selected soft-wrap--centered]
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

(defun soft-wrap-expand (&optional step)
  "Widen the wrap area by STEP columns (default `soft-wrap-width-step').
Seeds `soft-wrap--target-width' from `fill-column' on first use so
the wrap width becomes independent of `fill-column'."
  (interactive "P")
  (unless soft-wrap-mode
    (user-error "Soft-wrap-mode is not active in this buffer"))
  (let ((delta (or step soft-wrap-width-step)))
    (setq-local soft-wrap--target-width
                (+ (or soft-wrap--target-width fill-column) delta))
    (setq-local soft-wrap--warned-mismatch nil)
    (soft-wrap--refresh-buffer-windows)
    (message "Soft-wrap width: %d" soft-wrap--target-width)))

(defun soft-wrap-shrink (&optional step)
  "Narrow the wrap area by STEP columns (default `soft-wrap-width-step').
Seeds `soft-wrap--target-width' from `fill-column' on first use so
the wrap width becomes independent of `fill-column'."
  (interactive "P")
  (unless soft-wrap-mode
    (user-error "Soft-wrap-mode is not active in this buffer"))
  (let* ((delta (or step soft-wrap-width-step))
         (new (- (or soft-wrap--target-width fill-column) delta)))
    (when (<= new 0)
      (user-error "Wrap width would be %d; must be positive" new))
    (setq-local soft-wrap--target-width new)
    (setq-local soft-wrap--warned-mismatch nil)
    (soft-wrap--refresh-buffer-windows)
    (message "Soft-wrap width: %d" soft-wrap--target-width)))

;;;###autoload
(defun soft-wrap-centered (&optional arg)
  "Toggle centred layout while `soft-wrap-mode' is active.

When enabled, the body is centred horizontally by growing both window
margins symmetrically — an olivetti-inspired layout, but built on
soft-wrap's column-accurate width calculation.  The buffer's
pre-existing left margin (e.g. the column reserved for `git-gutter')
is preserved as the inner floor, so gutters keep working.

With no ARG, toggle.  With a positive ARG, enable centring; with a
non-positive ARG, disable it.  This makes the command usable as both
an interactive toggle and an explicit setter in mode hooks, e.g.
  (add-hook \\='markdown-mode-hook
            (lambda () (soft-wrap-mode 1) (soft-wrap-centered 1)))"
  (interactive "P")
  (unless soft-wrap-mode
    (user-error "Soft-wrap-mode is not active in this buffer"))
  (setq-local soft-wrap--centered
              (cond
               ((null arg) (not soft-wrap--centered))
               ((and (numberp arg) (> arg 0)) t)
               (t nil)))
  (soft-wrap--refresh-buffer-windows)
  (when (called-interactively-p 'interactive)
    (message "Soft-wrap centring %s"
             (if soft-wrap--centered "enabled" "disabled"))))

;;;###autoload
(define-minor-mode soft-wrap-mode
  "Buffer-local minor mode for visual soft wrapping at a target column.

The target column is taken from `soft-wrap-default-width' if non-nil,
otherwise from `fill-column'."
  :lighter (:eval (format " Wrap:%d%s"
                          (or soft-wrap--target-width fill-column)
                          (if soft-wrap--centered "·" "")))
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
        (add-hook 'window-state-change-functions #'soft-wrap--window-state-change)
        (advice-add 'split-window :around #'soft-wrap--around-split-window)
        (add-variable-watcher 'fill-column #'soft-wrap--fill-column-watcher))
    (remove-hook 'window-state-change-functions #'soft-wrap--window-state-change)
    (advice-remove 'split-window #'soft-wrap--around-split-window)
    (remove-variable-watcher 'fill-column #'soft-wrap--fill-column-watcher)))

;;; Width calculation ---------------------------------------------------------

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

;;; Window margin management --------------------------------------------------

(defun soft-wrap--save-window-margins (window)
  "Save WINDOW's current left and right margins as window parameters.
Each side is saved at most once; subsequent calls are no-ops.  Values
are wrapped in a list so nil (not set) is distinguished from absence of
the parameter (not yet saved)."
  (when (window-live-p window)
    (let ((m (window-margins window)))
      (unless (window-parameter window 'soft-wrap--saved-left-margin)
        (set-window-parameter window 'soft-wrap--saved-left-margin
                              (list (car m))))
      (unless (window-parameter window 'soft-wrap--saved-right-margin)
        (set-window-parameter window 'soft-wrap--saved-right-margin
                              (list (cdr m)))))))

(defun soft-wrap--restore-window-margins (window)
  "Restore WINDOW's left and right margins from the saved window parameters."
  (when (window-live-p window)
    (let ((sl (window-parameter window 'soft-wrap--saved-left-margin))
          (sr (window-parameter window 'soft-wrap--saved-right-margin)))
      (when (or sl sr)
        (let* ((m (window-margins window))
               (left  (if sl (car sl) (car m)))
               (right (if sr (car sr) (cdr m))))
          (set-window-margins window left right))
        (set-window-parameter window 'soft-wrap--saved-left-margin nil)
        (set-window-parameter window 'soft-wrap--saved-right-margin nil)))))

(defun soft-wrap--adjust-window-margins (window)
  "Adjust WINDOW's margins to hit the target wrap width.
By default only the right margin is grown.  When the buffer-local
`soft-wrap--centered' is non-nil, both margins grow symmetrically; the
saved (pre-mode) left margin is preserved as the inner floor."
  (when (window-live-p window)
    (let ((buf (window-buffer window)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when soft-wrap-mode
            ;; Save the original margins before the first adjustment.
            ;; The once-only guard in the save function makes this a no-op
            ;; on subsequent calls.
            (soft-wrap--save-window-margins window)
            (let* ((target (soft-wrap--window-target-width window))
                   (saved-left  (or (car (window-parameter
                                          window 'soft-wrap--saved-left-margin))
                                    0))
                   (saved-right (or (car (window-parameter
                                          window 'soft-wrap--saved-right-margin))
                                    0))
                   (margins (window-margins window))
                   (cur-left  (or (car margins) 0))
                   (cur-right (or (cdr margins) 0)))
              ;; Reset to saved margins first so `window-max-chars-per-line'
              ;; reports the natural body width.  No redisplay happens
              ;; between the two `set-window-margins' calls, so the user
              ;; sees a single visible margin change.
              (unless (and (= cur-left saved-left) (= cur-right saved-right))
                (set-window-margins window saved-left saved-right))
              (let* ((natural (window-max-chars-per-line window))
                     (delta (- natural target))
                     (new-left  saved-left)
                     (new-right saved-right))
                (when (> delta 0)
                  (if soft-wrap--centered
                      (let* ((half  (/ delta 2))
                             (other (- delta half)))
                        (setq new-left  (+ saved-left  half))
                        (setq new-right (+ saved-right other)))
                    (setq new-right (+ saved-right delta))))
                (when (fboundp 'soft-wrap--trace-log)
                  (soft-wrap--trace-log
                   "adjust: saved=%S cur=%S target=%d natural=%d delta=%d new=%S centered=%S"
                   (cons saved-left saved-right)
                   (cons cur-left cur-right)
                   target natural delta
                   (cons new-left new-right)
                   soft-wrap--centered))
                (set-window-margins window new-left new-right)))))))))

(defun soft-wrap--refresh-buffer-windows ()
  "Refresh margins for all windows showing the current buffer."
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (soft-wrap--adjust-window-margins w)))

(defun soft-wrap--window-state-change (window)
  "Run on `window-state-change-functions'; re-adjust margins for WINDOW.
Called whenever Emacs detects a window state change (resize, split, etc.)."
  (soft-wrap--adjust-window-margins window))

(defun soft-wrap--schedule-refresh (buffer)
  "Schedule one deferred margin refresh for BUFFER, debouncing repeats.
The refresh is run from an idle timer rather than synchronously so it
fires after the triggering assignment has committed; while a timer is
already pending no second one is queued, so a burst of sets in a single
command collapses to one refresh."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (unless soft-wrap--refresh-timer
        (setq soft-wrap--refresh-timer
              (run-with-idle-timer 0 nil #'soft-wrap--deferred-refresh buffer))))))

(defun soft-wrap--deferred-refresh (buffer)
  "Run the deferred margin refresh scheduled for BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq soft-wrap--refresh-timer nil)
      (when soft-wrap-mode
        (soft-wrap--refresh-buffer-windows)))))

(defun soft-wrap--fill-column-watcher (_symbol newval operation where)
  "Refresh soft-wrap margins when `fill-column' actually changes.
Installed as a variable watcher so every path that sets `fill-column'
\(\\[set-fill-column], `setq-local', `setopt', `.dir-locals.el', ...)
keeps the wrap width in sync — not just the interactive command.

Runs for real assignments only (OPERATION `set'), so transient `let'
bindings by fill commands are ignored.  At watcher time the symbol still
holds the old value, so comparing it against NEWVAL skips no-op
reassignments.  Acts only in the buffer being changed (WHERE, or the
current buffer for a global set) when `soft-wrap-mode' is active and the
width tracks `fill-column' (`soft-wrap--target-width' nil); a width
pinned via `soft-wrap-set-width'/`soft-wrap-expand' is left alone."
  (when (eq operation 'set)
    (let ((buf (or where (current-buffer))))
      (when (and (buffer-live-p buf)
                 (buffer-local-value 'soft-wrap-mode buf)
                 (null (buffer-local-value 'soft-wrap--target-width buf))
                 (not (eql newval (buffer-local-value 'fill-column buf))))
        (soft-wrap--schedule-refresh buf)))))

;;; Buffer state save/restore -------------------------------------------------

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

;;; Enable/disable ------------------------------------------------------------

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
  (setq-local soft-wrap--centered soft-wrap-default-centered)
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

  (when soft-wrap--refresh-timer
    (cancel-timer soft-wrap--refresh-timer)
    (setq soft-wrap--refresh-timer nil))

  (remove-hook 'window-configuration-change-hook
               #'soft-wrap--refresh-buffer-windows
               'local)

  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode (if soft-wrap--saved-visual-wrap-prefix-mode 1 -1)))
  (visual-line-mode -1)

  ;; Restore managed variables (includes auto-fill-function).
  (soft-wrap--restore-state)

  ;; Restore each window's margins to what they were before soft-wrap enabled.
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (soft-wrap--restore-window-margins w))

  (kill-local-variable 'soft-wrap--saved-visual-wrap-prefix-mode)
  (kill-local-variable 'soft-wrap--centered))

;;; Split-window compatibility -------------------------------------------------

(defun soft-wrap--around-split-window (orig-fn &optional window size side pixelwise)
  "Temporarily clear soft-wrap margins so `split-window' succeeds.
Without this, large margins make Emacs think the window is too narrow
to split.  In centred mode both margins are cleared; otherwise only
the right margin is touched and the user's original left margin (e.g.
a column reserved for `git-gutter') is preserved across the split.
After the split, the window-state-change hook recalculates margins for
both resulting windows."
  (let* ((win (or window (selected-window)))
         (buf (window-buffer win))
         (active (and (buffer-live-p buf)
                      (buffer-local-value 'soft-wrap-mode buf)))
         (centered (and active
                        (buffer-local-value 'soft-wrap--centered buf)))
         (margins (when active (window-margins win)))
         (old-left  (when active (or (car margins) 0)))
         (old-right (when active (or (cdr margins) 0)))
         (saved-left (when active
                       (or (car (window-parameter
                                 win 'soft-wrap--saved-left-margin))
                           old-left)))
         (touched (and active
                       (or (> old-right 0)
                           (and centered (> old-left saved-left))))))
    (when touched
      (set-window-margins win (if centered 0 saved-left) 0))
    (unwind-protect
        (funcall orig-fn window size side pixelwise)
      (when (and touched (window-live-p win))
        (soft-wrap--adjust-window-margins win)))))

;;; Optional diagnostics -------------------------------------------------------

(defcustom soft-wrap-load-diagnostics nil
  "When non-nil, load `soft-wrap-diagnostic.el' alongside this file.
Set this before loading `soft-wrap' to enable the diagnostic module."
  :type 'boolean
  :group 'soft-wrap)

(when soft-wrap-load-diagnostics
  (let ((diag (expand-file-name "soft-wrap-diagnostic.el"
                                (file-name-directory (or load-file-name
                                                         buffer-file-name)))))
    (when (file-exists-p diag)
      (load diag nil t))))

(provide 'soft-wrap)
;;; soft-wrap.el ends here
