;;; lnum-debug.el --- Diagnose dynamic line-number display width changes -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Standalone diagnostic for understanding why `line-number-display-width'
;; changes during scrolling, independent of soft-wrap or any other package.
;;
;; Usage:
;;   M-x load-file RET /path/to/lnum-debug.el
;;   M-x lnum-debug-start    (in the buffer where the jitter occurs)
;;   ... scroll past the boundary where the width changes ...
;;   M-x lnum-debug-stop
;;   Check *lnum-debug* for the log.
;;
;; What is traced:
;;
;;   post-command-hook  — fires after every command; detects the exact command
;;                        that causes `line-number-display-width' to change.
;;
;;   variable watcher   — fires on any Lisp-level write to
;;                        `display-line-numbers-width' (the configuration
;;                        variable).  If this fires, the change is driven by
;;                        Lisp.  If it does not fire but post-command-hook
;;                        detects a rendered-width change, the C redisplay
;;                        engine is responsible.

;;; Code:

(defvar lnum-debug--active nil
  "Non-nil when lnum-debug tracing is active.")

(defvar-local lnum-debug--last-rendered nil
  "Last value of `line-number-display-width' seen in this buffer.")

(defun lnum-debug--log (fmt &rest args)
  "Append a formatted line to *lnum-debug*."
  (with-current-buffer (get-buffer-create "*lnum-debug*")
    (goto-char (point-max))
    (insert (apply #'format fmt args) "\n")))

(defun lnum-debug--post-command ()
  "Post-command hook: log when the rendered line-number width changes."
  (let ((w (line-number-display-width)))
    (unless (equal w lnum-debug--last-rendered)
      (lnum-debug--log
       "[rendered] %S → %S  cmd=%S  buf=%s  display-line-numbers-width=%S"
       lnum-debug--last-rendered w this-command
       (buffer-name) display-line-numbers-width)
      (let ((i 0))
        (mapbacktrace
         (lambda (_evald func _args _flags)
           (when (and (> i 1) (< i 9))
             (lnum-debug--log "  #%d %s" i func))
           (setq i (1+ i)))))
      (setq lnum-debug--last-rendered w))))

(defun lnum-debug--var-watcher (symbol newval operation buffer)
  "Variable watcher: log every Lisp-level write to `display-line-numbers-width'."
  (lnum-debug--log
   "\n[variable] %S → %S  op=%S  buf=%s"
   (and (buffer-live-p buffer) (buffer-local-value symbol buffer))
   newval operation (buffer-name buffer))
  (let ((i 0))
    (mapbacktrace
     (lambda (_evald func _args _flags)
       (when (and (> i 1) (< i 9))
         (lnum-debug--log "  #%d %s" i func))
       (setq i (1+ i))))))

(defun lnum-debug-start ()
  "Start tracing line-number display width changes in the current buffer.
Results appear in *lnum-debug*."
  (interactive)
  (unless lnum-debug--active
    (setq lnum-debug--active t)
    (setq-local lnum-debug--last-rendered (line-number-display-width))
    (add-hook 'post-command-hook #'lnum-debug--post-command nil :local)
    (add-variable-watcher 'display-line-numbers-width #'lnum-debug--var-watcher)
    (with-current-buffer (get-buffer-create "*lnum-debug*")
      (erase-buffer)
      (insert (format ";; lnum-debug started  buf=%s  initial rendered-width=%S  display-line-numbers-width=%S\n"
                      (buffer-name (other-buffer (current-buffer) t))
                      (lnum-debug--last-rendered-in (other-buffer (current-buffer) t))
                      (buffer-local-value 'display-line-numbers-width
                                          (other-buffer (current-buffer) t)))))
    (message "lnum-debug started → *lnum-debug*")))

(defun lnum-debug--last-rendered-in (buf)
  "Return `lnum-debug--last-rendered' from BUF, or nil."
  (and (buffer-live-p buf)
       (buffer-local-value 'lnum-debug--last-rendered buf)))

(defun lnum-debug-stop ()
  "Stop line-number width tracing."
  (interactive)
  (when lnum-debug--active
    (setq lnum-debug--active nil)
    (remove-hook 'post-command-hook #'lnum-debug--post-command :local)
    (remove-variable-watcher 'display-line-numbers-width #'lnum-debug--var-watcher)
    (message "lnum-debug stopped")))

(message "lnum-debug loaded — M-x lnum-debug-start / lnum-debug-stop")

(provide 'lnum-debug)
;;; lnum-debug.el ends here
