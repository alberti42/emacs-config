;;; warning-toast.el --- Transient corner toast for Emacs warnings -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Surfaces `display-warning' messages as a transient corner popup that
;; auto-dismisses, instead of relying on the easily-missed `*Warnings*'
;; buffer.  Built on `popon' so it works in both TTY and GUI frames.
;;
;; Motivating case: flycheck's `flycheck-disable-excessive-checker' discards
;; every diagnostic and disables a checker once it exceeds
;; `flycheck-checker-error-threshold', announcing it only via a one-shot
;; `lwarn' into `*Warnings*' — invisible in normal use.
;;
;; Only warnings of level `warning-toast-min-level' and above raise a toast
;; (default `:warning', so `:debug' noise is ignored).  With
;; `warning-toast-suppress-window' enabled (the default), the redundant
;; `*Warnings*' window auto-pop is suppressed for sub-`:emergency' warnings;
;; the entry is still logged to the buffer for later inspection.
;;

;;; Code:

(require 'warnings)

;; popon: TTY+GUI overlay popups (the GUI-only `posframe' would not work in a
;; terminal).  Deferred — only needed when a warning actually fires.
(use-package popon
  :straight (popon
             :type git
             :repo "https://codeberg.org/alberti42/emacs-popon.git"
             :branch "fix/make-framebuffer-invisible-loop")
  :defer t)

(defgroup warning-toast nil
  "Transient corner popup for Emacs warnings."
  :group 'warnings)

(defcustom warning-toast-duration 5.0
  "Seconds a warning toast stays on screen before auto-dismissing."
  :type 'number)

(defcustom warning-toast-corner 'top-right
  "Corner of the selected window where the toast appears."
  :type '(choice (const top-right)
                 (const bottom-right)
                 (const top-left)
                 (const bottom-left)))

(defcustom warning-toast-max-width 60
  "Maximum width, in columns, of a warning toast."
  :type 'integer)

(defcustom warning-toast-margin '(1 . 2)
  "Breathing room kept between the toast and the window edges.
The value is a cons (NUM-ROWS . NUM-COLUMNS).  NUM-COLUMNS avoids the
composited screen line overflowing the right text boundary (which would
wrap it into empty continuation lines).  NUM-ROWS keeps the toast off the
first/last screen rows, which are often only partially visible under pixel
scrolling and would clip the popon."
  :type '(cons (integer :tag "Rows") (integer :tag "Columns")))

(defcustom warning-toast-min-level :warning
  "Minimum warning level that raises a toast.
In increasing severity: `:debug', `:warning', `:error', `:emergency'.
A warning raises a toast only if it is at least this severe."
  :type '(choice (const :debug) (const :warning)
                 (const :error) (const :emergency)))

(defcustom warning-toast-suppress-window t
  "When non-nil, suppress the `*Warnings*' window auto-pop.
Sub-`:emergency' warnings are then surfaced only as a toast (and still
logged to the `*Warnings*' buffer); emergencies keep their window."
  :type 'boolean)

(defface warning-toast
  '((t :inherit (warning highlight)))
  "Face applied to the warning toast block.")

(defvar warning-toast--popon nil
  "The currently displayed toast popon, or nil.")

(defvar warning-toast--timer nil
  "Timer that dismisses the current toast, or nil.")

(defun warning-toast--type-string (type)
  "Render a warning TYPE (symbol or list) as a compact string."
  (cond ((null type) "emacs")
        ((symbolp type) (symbol-name type))
        ((listp type) (mapconcat (lambda (s) (format "%s" s)) type " "))
        (t (format "%s" type))))

(defun warning-toast--label (level)
  "Return a short header label for LEVEL."
  (pcase level
    (:emergency "⛔ Emergency")
    (:error     "✖ Error")
    (:debug     "· Debug")
    (_          "⚠ Warning")))

(defun warning-toast--wrap (text width)
  "Word-wrap TEXT to WIDTH columns; return a list of lines."
  (with-temp-buffer
    (insert text)
    (let ((fill-column (max 1 width)))
      (fill-region (point-min) (point-max) nil t))
    (split-string (buffer-string) "\n")))

(defun warning-toast--block (level type message)
  "Return the padded, equal-width text block for a LEVEL, TYPE, MESSAGE toast.
LEVEL selects the header label, TYPE is shown in brackets, and MESSAGE is
word-wrapped to `warning-toast-max-width'."
  (let* ((head (format "%s  [%s]" (warning-toast--label level)
                       (warning-toast--type-string type)))
         (body (warning-toast--wrap (string-trim (format "%s" message))
                                    (- warning-toast-max-width 2)))
         (lines (cons head body))
         (w (apply #'max 1 (mapcar #'string-width lines))))
    (mapconcat (lambda (l)
                 (concat " " l
                         (make-string (1+ (- w (string-width l))) ?\s)))
               lines "\n")))

(defun warning-toast--target-window ()
  "Pick a sensible, non-minibuffer window to anchor the toast."
  (let ((w (selected-window)))
    (if (window-minibuffer-p w)
        (or (minibuffer-selected-window) (get-largest-window) w)
      w)))

(defun warning-toast-dismiss ()
  "Dismiss the current warning toast, if any."
  (interactive)
  (when (timerp warning-toast--timer)
    (cancel-timer warning-toast--timer))
  (setq warning-toast--timer nil)
  (when (and warning-toast--popon
             (fboundp 'popon-live-p)
             (popon-live-p warning-toast--popon))
    (popon-kill warning-toast--popon))
  (setq warning-toast--popon nil))

(defun warning-toast--show (level type message)
  "Display MESSAGE (of LEVEL and TYPE) as a transient popon toast."
  (require 'popon)
  (warning-toast-dismiss)
  (let* ((text (warning-toast--block level type message))
         (lines (split-string text "\n"))
         (pw (apply #'max 1 (mapcar #'string-width lines)))
         (ph (length lines))
         (win (warning-toast--target-window))
         (bw (window-body-width win))
         (bh (window-body-height win))
         ;; `window-body-width' counts the line-number columns, but buffer
         ;; text cannot use them; subtract so the toast stays inside the
         ;; usable text area (otherwise the composited line wraps).
         (lnw (with-selected-window win
                (if (bound-and-true-p display-line-numbers)
                    (line-number-display-width)
                  0)))
         (avail (max 1 (- bw lnw)))
         (mrow (if (consp warning-toast-margin)
                   (car warning-toast-margin) warning-toast-margin))
         (mcol (if (consp warning-toast-margin)
                   (cdr warning-toast-margin) warning-toast-margin))
         (x (pcase warning-toast-corner
              ((or 'top-right 'bottom-right) (max 0 (- avail pw mcol)))
              (_ mcol)))
         (y (pcase warning-toast-corner
              ((or 'bottom-left 'bottom-right) (max 0 (- bh ph mrow)))
              (_ mrow))))
    ;; popon has no face argument; it honours text properties on the string,
    ;; and each line is already padded to PW columns so the face background
    ;; fills the whole block.
    (setq warning-toast--popon
          (popon-create (cons (propertize text 'face 'warning-toast) pw)
                        (cons x y) win))
    (setq warning-toast--timer
          (run-with-timer warning-toast-duration nil #'warning-toast-dismiss))))

(defun warning-toast--advice (orig type message &optional level buffer-name)
  "Around advice for `display-warning' (ORIG): toast the TYPE/MESSAGE warning.
ORIG is called with TYPE, MESSAGE, LEVEL and BUFFER-NAME unchanged.  A toast
is shown for LEVEL at or above `warning-toast-min-level'; when
`warning-toast-suppress-window' is non-nil the `*Warnings*' window is hushed
for sub-`:emergency' levels."
  (let ((level (or level :warning)))
    (prog1
        (if warning-toast-suppress-window
            ;; Raising the display threshold to `:emergency' stops the
            ;; `*Warnings*' window from auto-popping for lesser warnings while
            ;; leaving the buffer log (gated by `warning-minimum-log-level')
            ;; untouched.  Emergencies still meet the threshold and pop.
            (let ((warning-minimum-level :emergency))
              (funcall orig type message level buffer-name))
          (funcall orig type message level buffer-name))
      (when (and (not noninteractive)
                 (>= (warning-numeric-level level)
                     (warning-numeric-level warning-toast-min-level))
                 (not (warning-suppress-p type warning-suppress-types)))
        ;; Never let the toast machinery break warning delivery itself.
        (condition-case err
            (warning-toast--show level type message)
          (error (message "warning-toast: %s" (error-message-string err))))))))

;;;###autoload
(define-minor-mode warning-toast-mode
  "Global mode: surface Emacs warnings as transient corner toasts."
  :global t
  :group 'warning-toast
  (if warning-toast-mode
      (advice-add 'display-warning :around #'warning-toast--advice)
    (advice-remove 'display-warning #'warning-toast--advice)
    (warning-toast-dismiss)))

(warning-toast-mode 1)

(provide 'warning-toast)
;;; warning-toast.el ends here
