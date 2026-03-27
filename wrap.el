;;; wrap.el --- Soft and hard wrap helpers -*- lexical-binding: t; -*-

;; Code

;;; Packages:
;;
;; There are two mutually exclusive approaches to the same goal of managing long lines:
;;
;; - auto-fill-mode — hard wrap: inserts actual newlines as you type past fill-column. The line break becomes part of the file content.
;; - visual-line-mode — built-in mode for soft/visual wrap: no newlines inserted, text just appears wrapped on screen.
;;   The file content is unchanged. The built-in mode wraps lines at the window edge.
;; - visual-fill-column-mode — adds margins to the window so that visual-line-mode wraps at a specific column rather than the window edge

;;; Commentary on patched visual-fill-column
;;
;; Use a patched fork of visual-fill-column to fix a conflict with git-gutter
;; in TTY frames.
;;
;; visual-fill-column constrains text to a column width by adding fake margins
;; to the window (e.g. left margin = 20 cols to center 80 cols in a 120-col
;; window).  It recomputes these margins on every redisplay.
;;
;; git-gutter (TTY mode) displays +/-/~ indicators by reserving a left-margin
;; column.  Both packages therefore write to the same window left-margin slot.
;;
;; The upstream bug: visual-fill-column resets the left margin to 0 before
;; writing its own value.  That zero-reset wiped git-gutter's reservation on
;; every redisplay, making the gutter disappear.
;;
;; The fork fixes this by reading the current left margin first and adding to
;; it, so both packages can coexist.

;;; Code

(defvar-local wrap--saved-auto-fill nil
  "Value of `auto-fill-function' before soft wrap was enabled.
Used by `soft-wrap-disable' to restore hard-wrap state.")

(defvar-local wrap--vfc-refresh-timer nil
  "Idle timer used to refresh visual-fill-column width compensation.")

(use-package visual-fill-column
    :straight (visual-fill-column
               :type git
               :host codeberg
               :repo "alberti42/fork-visual-fill-column")
    ;; :commands implies deferral. It's equivalent to :defer t plus registering
    ;; autoloads for the listed commands. In our case, it registers
    ;; an autoload `visual-fill-column-mode', which loads the package on demand,
    ;; without a manual `require'.
    :commands visual-fill-column-mode)

;; Forward declaration so the native compiler knows the function exists at
;; compile time (analogous to a C header).  The real definition is loaded at
;; runtime via `require' inside `soft-wrap-enable'.
(declare-function visual-fill-column-mode "visual-fill-column")

(use-package adaptive-wrap
  :commands adaptive-wrap-prefix-mode)

(defun wrap--continuation-glyph-reserved-cols (&optional window)
  "Return columns reserved for continuation/truncation glyphs.

In most cases (including TTY frames), Emacs reserves the last column for
continuation/truncation glyphs, effectively reducing the maximum number of
buffer characters that can be displayed per visual line by 1.

In GUI frames when `overflow-newline-into-fringe' is non-nil and both fringes
are non-zero, Emacs can draw the glyphs in the fringes, reserving 0 columns." 
  (let* ((w (window-normalize-window (or window (selected-window)) t))
         (fringes (window-fringes w))
         (lfringe (car fringes))
         (rfringe (nth 1 fringes)))
    (if (and (display-graphic-p (window-frame w))
             overflow-newline-into-fringe
             (not (eq lfringe 0))
             (not (eq rfringe 0)))
        0
      1)))

(defun wrap--refresh-visual-fill-column-extra-text-width (&optional window)
  "Refresh `visual-fill-column-extra-text-width' for WINDOW.

This compensates for the line-number area and the continuation/truncation glyph
column (usually 1 in TTY).  WINDOW defaults to the window currently displaying
the buffer; if the buffer is not displayed, fall back to the selected window." 
  (let* ((w (window-normalize-window
             (or window
                 (get-buffer-window (current-buffer) 0)
                 (selected-window))
             t))
         (line-number-cols
          (when (fboundp 'line-number-display-width)
            ;; `line-number-display-width' returns 0 when line numbers are not
            ;; displayed.  Do not gate this on `display-line-numbers-mode'
            ;; because mode activation order during find-file can vary.
            (ceiling (line-number-display-width w))))
         (reserved-cols (wrap--continuation-glyph-reserved-cols w))
         (extra-right (+ reserved-cols (or line-number-cols 0))))
    (setq-local visual-fill-column-extra-text-width
                (when (> extra-right 0)
                  (cons 0 extra-right)))))

(defun soft-wrap-enable (&optional width)
  "Enable visual soft wrapping in the current buffer.

WIDTH, when non-nil, is the target wrap column (defaults to `fill-column').
Disables hard wrapping (`auto-fill-mode') if it is active."
  (interactive "P")
  ;; Save hard-wrap state so soft-wrap-disable can restore it
  (setq-local wrap--saved-auto-fill auto-fill-function)
  ;; Disable complementary mode auto-fill-mode by providing a negative argument
  (auto-fill-mode -1)
  (let ((width (if width
                    (prefix-numeric-value width) ; convert width to a number if not nil
                  fill-column                    ; choose fill-column if width is nil
                  )))
    (visual-line-mode 1) ; enable built-in visual-line-mode required by visual-fill-column-mode
    (setq-local word-wrap t) ; makes visual line breaks happen only at word boundaries (spaces, hyphens) rather than mid-word
    (setq-local truncate-lines nil) ; must be set to nil when visual-line-mode is enabled (per doc)
    (setq-local visual-fill-column-width width)
    ;; Compensate for line-number and continuation/truncation glyph columns.
    (wrap--refresh-visual-fill-column-extra-text-width)
    ;; Enable visual-fill-column-mode
    (visual-fill-column-mode 1)
    ;; During `find-file', line numbers and window state can settle after major
    ;; mode hooks run.  Refresh once on idle so the compensation matches the
    ;; final displayed window.
    (when wrap--vfc-refresh-timer
      (cancel-timer wrap--vfc-refresh-timer))
    (setq-local wrap--vfc-refresh-timer
                (run-with-idle-timer
                 0 nil
                 (lambda (buf)
                   (when (buffer-live-p buf)
                     (with-current-buffer buf
                       (setq wrap--vfc-refresh-timer nil)
                       (when (bound-and-true-p visual-fill-column-mode)
                         (wrap--refresh-visual-fill-column-extra-text-width)
                         (when (fboundp 'visual-fill-column-adjust)
                           (visual-fill-column-adjust))))))
                 (current-buffer)))))

(defun soft-wrap-disable ()
  "Disable visual soft wrapping in the current buffer."
  (interactive)
  (when wrap--vfc-refresh-timer
    (cancel-timer wrap--vfc-refresh-timer)
    (setq wrap--vfc-refresh-timer nil))
  ;; Check that the mode visual-fill-column is available
  (when (fboundp 'visual-fill-column-mode)
    ;; Disable complementary mode auto-fill-mode by providing a negative argument
    (visual-fill-column-mode -1))
  ;; Disable the built-in visual-line-mode
  (visual-line-mode -1)
  ;; Remove local variables
  (dolist (var '(word-wrap truncate-lines visual-fill-column-width visual-fill-column-extra-text-width))
    (when (local-variable-p var)
      (kill-local-variable var)))
  ;; Restore hard-wrap state if it was active before soft wrap was enabled
  (when wrap--saved-auto-fill
    (auto-fill-mode 1))
  (kill-local-variable 'wrap--saved-auto-fill))

(defun soft-wrap-toggle (&optional width)
  "Toggle visual soft wrapping in the current buffer.

If enabling, WIDTH is passed to `soft-wrap-enable'."
  (interactive "P")
  ;; Check that the mode visual-fill-column exists and is active
  (if (bound-and-true-p visual-fill-column-mode)
      (soft-wrap-disable)
    (soft-wrap-enable width)))

;;; Hard wrap (auto-fill-mode) — uses fill-column as the wrap column.

(defun hard-wrap-enable ()
  "Enable hard wrapping (auto-fill-mode) in the current buffer.

Disables soft wrapping if it is active.  The wrap column is `fill-column'."
  (interactive)
  ;; Disables the complementary visual-fill-column-mode
  (soft-wrap-disable)
  ;; Enable hard wrap mode
  (auto-fill-mode 1))

(defun hard-wrap-disable ()
  "Disable hard wrapping (auto-fill-mode) in the current buffer."
  (interactive)
  ;; Disable hard wrapping
  (auto-fill-mode -1))

(defun hard-wrap-toggle ()
  "Toggle hard wrapping (auto-fill-mode) in the current buffer."
  (interactive)
  ;; Check if hard wrapping is enabled 
  (if auto-fill-function
      (hard-wrap-disable)
    (hard-wrap-enable)))

(provide 'wrap)
;;; wrap.el ends here
