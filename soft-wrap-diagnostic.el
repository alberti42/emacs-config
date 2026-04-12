;;; soft-wrap-diagnostic.el --- Diagnostics and tracing for soft-wrap -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Diagnostic and tracing tools for debugging `soft-wrap-mode'.  Not loaded by
;; default.  To enable, set `soft-wrap-load-diagnostics' to t before loading
;; `soft-wrap':
;;
;;   (setq soft-wrap-load-diagnostics t)
;;   (require 'soft-wrap)
;;
;; Public entry points:
;;
;;   `soft-wrap-diagnose'       (C-c W in soft-wrap buffers)
;;     Appends a one-line margin snapshot to *soft-wrap-diag*.
;;
;;   `soft-wrap-debug-dump'
;;     Pretty-prints full soft-wrap state to *Soft Wrap Debug*.
;;
;;   `soft-wrap-trace-start' / `soft-wrap-trace-stop'
;;     Trace every `set-window-margins' call and hook entry to *soft-wrap-trace*.

;;; Code:

(require 'pp)

;;; State snapshot -------------------------------------------------------------

(defun soft-wrap--debug-data (&optional window)
  "Return a plist of soft-wrap state for the current buffer.
When WINDOW is non-nil, include details for that window only; otherwise
report all windows showing the current buffer."
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

(defun soft-wrap-debug-dump (&optional window)
  "Pretty-print soft-wrap state to *Soft Wrap Debug*.
When WINDOW is non-nil, include details for that window only; otherwise
report all windows showing the current buffer."
  (interactive)
  (let* ((w (when window (window-normalize-window window t)))
         (data (soft-wrap--debug-data w)))
    (with-current-buffer (get-buffer-create "*Soft Wrap Debug*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (pp data (current-buffer))))
    (message "Wrote soft-wrap debug to *Soft Wrap Debug*")))

;;; Quick margin diagnostic ----------------------------------------------------

(defun soft-wrap-diagnose ()
  "Append a one-line margin snapshot for the selected window to *soft-wrap-diag*."
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

;;; Margin-change tracing ------------------------------------------------------
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

(provide 'soft-wrap-diagnostic)
;;; soft-wrap-diagnostic.el ends here
