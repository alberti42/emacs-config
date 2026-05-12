;;; right-margin-labels-poc.el --- POC: labels in the real right-margin -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Demonstrates rendering text in the dedicated `right-margin' column
;; (outside the text area), as opposed to the end-of-line stretchy-whitespace
;; trick used by sideline.el.
;;
;; Design contract:
;;
;;   This module *only writes into* the right margin.  It never calls
;;   `set-window-margins' and never touches `right-margin-width'.  Margin
;;   sizing is owned by something else (e.g. `soft-wrap-mode' in this
;;   config, Olivetti, or a manual call) -- and we cooperate by drawing
;;   inside whatever room that owner reserves.
;;
;;   As a natural consequence, if no right margin is visible on the window
;;   showing this buffer, the labels render nothing.  No special-case code
;;   is needed: the carrier overlay is always installed; whether it is
;;   *visible* depends on per-window margin width set by other code.  That
;;   matches the requested "do nothing if the margin is not set" behavior
;;   without coupling buffer state to window state.
;;
;; Rendering technique:
;;
;;   (propertize " " 'display `((margin right-margin) ,label))
;;
;; A space character is the carrier; its `display' property replaces it
;; with the label drawn in the margin column.  Attached via `before-string'
;; on a zero-length overlay at the target buffer position.
;;
;; Known limitations (motivating notes for any real implementation):
;;
;; - The margin renders on the *first visual line* of a buffer line.  If
;;   the buffer line wraps, only the top visual segment gets the label.
;; - If the margin is narrower than the label, the label is truncated.
;;   We accept this -- widening the margin is the owner's responsibility.
;;
;; Try it:
;;
;;   (require 'right-margin-labels-poc)
;;   ;; Make sure the buffer has a right margin from somewhere -- e.g.:
;;   ;;   (set-window-margins nil 0 14)
;;   ;; or open a buffer where `soft-wrap-mode' is active.
;;   M-x right-margin-labels-demo      ; scatter labels every 5 lines
;;   M-x right-margin-labels-clear     ; remove them

;;; Code:

(defvar-local right-margin-labels--overlays nil)

(defface right-margin-labels-default
  '((t :inherit shadow))
  "Default face for POC margin labels.")

(defun right-margin-labels-add (pos label &optional face)
  "Attach LABEL in the right margin at buffer position POS.
Returns the overlay.  Does not adjust margin width: if no margin is
visible on the window showing this buffer, the label simply will not
render."
  (let* ((face    (or face 'right-margin-labels-default))
         (text    (propertize label 'face face))
         (carrier (propertize " " 'display `((margin right-margin) ,text)))
         (ov      (make-overlay pos pos nil t nil)))
    (overlay-put ov 'before-string carrier)
    (overlay-put ov 'right-margin-labels t)
    (push ov right-margin-labels--overlays)
    ov))

(defun right-margin-labels-clear ()
  "Remove every POC label from the current buffer."
  (interactive)
  (mapc #'delete-overlay right-margin-labels--overlays)
  (setq right-margin-labels--overlays nil))

(defun right-margin-labels-demo ()
  "Scatter example labels every fifth line for visual demonstration.
Warns if no right margin is currently reserved on the selected window,
since the labels will be invisible in that case."
  (interactive)
  (right-margin-labels-clear)
  (let ((labels '("note" "todo" "fixme" "warn" "spell: teh"
                  "missing comma" "info: bib"))
        (i 0))
    (save-excursion
      (goto-char (point-min))
      (while (not (eobp))
        (when (zerop (mod i 5))
          (right-margin-labels-add
           (line-beginning-position)
           (nth (mod (/ i 5) (length labels)) labels)
           'warning))
        (forward-line 1)
        (cl-incf i))))
  (if (zerop (or (cdr (window-margins)) 0))
      (message "Added %d labels, but this window has no right margin; \
labels will not render.  Try: (set-window-margins nil 0 14)"
               (length right-margin-labels--overlays))
    (message "Added %d labels.  M-x right-margin-labels-clear to remove."
             (length right-margin-labels--overlays))))

(provide 'right-margin-labels-poc)

;;; right-margin-labels-poc.el ends here
