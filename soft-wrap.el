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

;; Andrea not clear what it does; what does it mean that it keeps the current left margin? Otherwise? We change it arbitrarily?
(defcustom soft-wrap-preserve-left-margin t
  "Whether to preserve the existing left window margin.

When non-nil, soft-wrap keeps the current left margin and only changes
the right margin. This is useful in TTY where other packages may reserve
the left margin for gutters. When nil, soft-wrap uses a left margin of
0."
  :type 'boolean
  :group 'soft-wrap)

(defcustom soft-wrap-enable-wrap-prefix t
  "Whether to enable `visual-wrap-prefix-mode' when available."
  :type 'boolean
  :group 'soft-wrap)

(defcustom soft-wrap-verify-width t
  "Whether to verify the resulting wrap width and warn on mismatch."
  :type 'boolean
  :group 'soft-wrap)

;; Andrea: the nane is ridicolously long
(defcustom soft-wrap-reset-right-margin-in-non-soft-wrap-buffers t
  "Whether to reset a window's right margin for non-soft-wrap buffers.

This prevents right margins set for one buffer from leaking into other buffers
when a window is reused."
  :type 'boolean
  :group 'soft-wrap)

;; Andrea: what is the default? I think we should save it by default.
(defvar-local soft-wrap--saved-auto-fill nil
  "Value of `auto-fill-function' before soft wrap was enabled.")

(defvar-local soft-wrap--target-width nil
  "Target wrap width for the current buffer.

When nil, the current value of `fill-column' is used when enabling.")

(defvar-local soft-wrap--warned-mismatch nil
  "Automatically set to non-nil after first warning about a wrap-width mismatch.")

(defvar-local soft-wrap--saved-visual-wrap-prefix-mode nil
  "Whether `visual-wrap-prefix-mode' was active before soft wrap was enabled.")

(defvar soft-wrap-mode-map (make-sparse-keymap)
  "Keymap for `soft-wrap-mode'.")

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
  :group 'soft-wrap)

(define-minor-mode soft-wrap--hooks-mode
  "Internal mode that installs window hooks needed by `soft-wrap-mode'.

Not intended for direct use — `soft-wrap-mode' activates this automatically."
  :global t
  :group 'soft-wrap
  (if soft-wrap--hooks-mode
      (progn
        (add-hook 'window-state-change-functions #'soft-wrap--window-state-change)
        (when (boundp 'window-buffer-change-functions)
          (add-hook 'window-buffer-change-functions #'soft-wrap--window-buffer-change)))
    (remove-hook 'window-state-change-functions #'soft-wrap--window-state-change)
    (remove-hook 'window-buffer-change-functions #'soft-wrap--window-buffer-change)))

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
                (ceiling (line-number-display-width window))
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

(defun soft-wrap--adjust-window-margins (window)
  "Adjust WINDOW's right margin to hit the target wrap width."
  (when (window-live-p window)
    (let ((buf (window-buffer window)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (when nil ; soft-wrap-mode
            (let* ((target (soft-wrap--window-target-width window))
                   (margins (window-margins window))
                   (left (if soft-wrap-preserve-left-margin (or (car margins) 0) 0))
                   (right (or (cdr margins) 0))
                   (cur (soft-wrap--computed-max-chars-per-line window))
                   (window-too-narrow (< cur target))
                   (delta (- cur target))
                   (new-right (max 0 (+ right delta))))
              (unless (= new-right right)
                (set-window-margins window left new-right))
              (when (and soft-wrap-verify-width (not window-too-narrow))
                ;; Verify against Emacs' computed value and apply a single
                ;; corrective adjustment if needed.
                (let* ((after (window-max-chars-per-line window))
                       (cur-right (or (cdr (window-margins window)) 0)))
                  (when (/= after target)
                    (let* ((correction (- after target))
                           (corrected-right (max 0 (+ cur-right correction))))
                      (unless (= corrected-right cur-right)
                        (set-window-margins window left corrected-right)
                        (setq after (window-max-chars-per-line window)))))
                  (when (and (not soft-wrap--warned-mismatch)
                             (/= after target))
                    (setq-local soft-wrap--warned-mismatch t)
                    (display-warning
                     'soft-wrap
                     (concat
                      "soft-wrap: could not reach target width.\n"
                      (format "target=%s computed-cur=%s after=%s margins=%S\n"
                              target cur after (window-margins window))
                      (pp-to-string (soft-wrap--debug-data window)))
                     :warning)))))))))))

(defun soft-wrap--refresh-buffer-windows ()
  "Refresh margins for all windows showing the current buffer."
  (dolist (w (get-buffer-window-list (current-buffer) nil t))
    (soft-wrap--adjust-window-margins w)))

(defun soft-wrap--window-state-change (window)
  "Hook: keep soft-wrap margins correct for WINDOW."
  (soft-wrap--adjust-window-margins window))

(defun soft-wrap--window-buffer-change (window &rest _args)
  "Hook: keep margins correct when WINDOW changes buffers."
  (when (window-live-p window)
    (let ((buf (window-buffer window)))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          (if soft-wrap-mode
              (progn
                (unless (bound-and-true-p visual-line-mode)
                  (visual-line-mode 1))
                (setq-local word-wrap t)
                (setq-local truncate-lines nil)
                (when (and soft-wrap-enable-wrap-prefix
                           (fboundp 'visual-wrap-prefix-mode))
                  (visual-wrap-prefix-mode 1))
                (soft-wrap--adjust-window-margins window))
            ;; Not a soft-wrap buffer: ensure we don't leak right margins.
            (when soft-wrap-reset-right-margin-in-non-soft-wrap-buffers
              (let* ((m (window-margins window))
                     (left (if soft-wrap-preserve-left-margin (or (car m) 0) 0))
                     (right (or (cdr m) 0)))
                (when (> right 0)
                  (set-window-margins window left 0))))))))))

(defun soft-wrap--do-enable ()
  "Enable soft wrapping in the current buffer (internal helper)."
  (soft-wrap--hooks-mode 1)
  (setq-local soft-wrap--saved-auto-fill auto-fill-function)
  (auto-fill-mode -1)

  (setq-local soft-wrap--target-width
              (or soft-wrap-default-width fill-column))
  (setq-local soft-wrap--warned-mismatch nil)

  (visual-line-mode 1)
  (setq-local word-wrap t)
  (setq-local truncate-lines nil)
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

  ;; Adjust immediately if already displayed; otherwise window-buffer-change
  ;; will handle the first display.
  (soft-wrap--refresh-buffer-windows))

(defun soft-wrap--do-disable ()
  "Disable soft wrapping in the current buffer (internal helper)."
  (setq-local soft-wrap--target-width nil)
  (setq-local soft-wrap--warned-mismatch nil)

  (remove-hook 'window-configuration-change-hook
               #'soft-wrap--refresh-buffer-windows
               'local)

  (when (fboundp 'visual-wrap-prefix-mode)
    (visual-wrap-prefix-mode (if soft-wrap--saved-visual-wrap-prefix-mode 1 -1)))
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

(provide 'soft-wrap)
;;; soft-wrap.el ends here
