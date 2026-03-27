;;; new-wrap.el --- Soft wrap helpers (new implementation) -*- lexical-binding: t; -*-

;; Code

;; Soft wrap implementation.
;;
;; Goals:
;; - Constrain visual wrapping to a target column (defaults to `fill-column').
;; - Preserve indentation on continuation lines using built-in
;;   `visual-wrap-prefix-mode' (Emacs 30+).
;; - Keep compatibility with TTY gutters that reserve the left margin
;;   (e.g. git-gutter-tty): preserve the existing left margin and only manage
;;   the right margin.
;; - Make enable/disable safe to call from major-mode hooks.

;; Note: We intentionally solve for the wrap width using
;; `window-max-chars-per-line' as the ground truth.  This accounts for line
;; numbers, the TTY continuation glyph column, and font metrics in GUI.

(defvar-local soft-wrap--saved-auto-fill nil
  "Value of `auto-fill-function' before soft wrap was enabled.")

(defvar-local soft-wrap--enabled nil
  "Non-nil when soft wrapping is enabled in the current buffer.")

(defvar-local soft-wrap--target-width nil
  "Target wrap width for the current buffer.

When nil, the current value of `fill-column' is used when enabling." )

(defvar-local soft-wrap--refresh-timer nil
  "Idle timer used to refresh margins after enable.")

(defvar soft-wrap--hooks-installed nil
  "Whether global soft-wrap hooks are installed.")

(defun soft-wrap--window-target-width (_window)
  "Return the target wrap width for the current buffer." 
  (or soft-wrap--target-width fill-column))

(defun soft-wrap--adjust-window-margins (window)
  "Adjust WINDOW's right margin to hit the target wrap width."
  (when (window-live-p window)
    (let ((buf (window-buffer window)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when soft-wrap--enabled
            (let* ((target (soft-wrap--window-target-width window))
                   (margins (window-margins window))
                   (left (or (car margins) 0))
                   (right (or (cdr margins) 0))
                   (iters 0)
                   (done nil))
              ;; Iteratively adjust to deal with rounding and late layout.
              (while (and (not done) (< iters 6))
                (let* ((cur (window-max-chars-per-line window))
                       (delta (- cur target))
                       (new-right (max 0 (+ right delta))))
                  (cond
                   ((= cur target)
                    (setq done t))
                   ((= new-right right)
                    ;; Can't make progress (e.g. window too narrow).
                    (setq done t))
                   (t
                    (setq right new-right)
                    (set-window-margins window left right)
                    (setq iters (1+ iters)))))))))))))

(defun soft-wrap--window-state-change (window)
  "Hook: keep soft-wrap margins correct for WINDOW." 
  (soft-wrap--adjust-window-margins window))

(defun soft-wrap--install-hooks ()
  "Install global hooks used by soft wrap." 
  (unless soft-wrap--hooks-installed
    (add-hook 'window-state-change-functions #'soft-wrap--window-state-change)
    (setq soft-wrap--hooks-installed t)))

(defun soft-wrap-enable (&optional width)
  "Enable visual soft wrapping in the current buffer.

WIDTH, when non-nil, is the target wrap column (defaults to `fill-column').
Disables hard wrapping (`auto-fill-mode') if it is active." 
  (interactive "P")
  (soft-wrap--install-hooks)
  (setq-local soft-wrap--saved-auto-fill auto-fill-function)
  (auto-fill-mode -1)

  (setq-local soft-wrap--target-width
              (if width (prefix-numeric-value width) fill-column))
  (setq-local soft-wrap--enabled t)

  (visual-line-mode 1)
  (setq-local word-wrap t)
  (setq-local truncate-lines nil)
  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode 1))

  ;; Initial adjustment for the current window.
  (soft-wrap--adjust-window-margins (selected-window))

  ;; During find-file / redisplay, line numbers and window layout can settle
  ;; after mode hooks run.  Refresh once on idle.
  (when soft-wrap--refresh-timer
    (cancel-timer soft-wrap--refresh-timer))
  (setq-local soft-wrap--refresh-timer
              (run-with-idle-timer
               0 nil
               (lambda (buf)
                 (when (buffer-live-p buf)
                   (with-current-buffer buf
                     (setq soft-wrap--refresh-timer nil)
                     (when soft-wrap--enabled
                       (dolist (w (get-buffer-window-list buf nil t))
                         (soft-wrap--adjust-window-margins w))))))
               (current-buffer)))
  nil)

(defun soft-wrap-disable ()
  "Disable visual soft wrapping in the current buffer."
  (interactive)
  (when soft-wrap--refresh-timer
    (cancel-timer soft-wrap--refresh-timer)
    (setq soft-wrap--refresh-timer nil))

  (setq-local soft-wrap--enabled nil)
  (setq-local soft-wrap--target-width nil)

  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode -1))
  (visual-line-mode -1)

  ;; Restore right margin to 0 while preserving any reserved left margin.
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (let* ((m (window-margins w))
           (left (or (car m) 0)))
      (set-window-margins w left 0)))

  ;; Remove local variables.
  (dolist (var '(word-wrap truncate-lines))
    (when (local-variable-p var)
      (kill-local-variable var)))

  ;; Restore hard-wrap state if it was active before soft wrap was enabled.
  (when soft-wrap--saved-auto-fill
    (auto-fill-mode 1))
  (kill-local-variable 'soft-wrap--saved-auto-fill)
  nil)

;; Markdown config enables this; provide a stub until the real dependency is
;; restored.
(defun adaptive-wrap-prefix-mode (&optional _arg)
  "Stopgap: no-op adaptive wrap prefix mode." 
  (interactive "P")
  nil)

(provide 'new-wrap)
;;; new-wrap.el ends here
