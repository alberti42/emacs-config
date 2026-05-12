;;; right-margin-labels-poc.el --- POC: labels in the real right-margin -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Demonstrates rendering text in the dedicated `right-margin' column
;; (outside the text area), as opposed to the end-of-line stretchy-whitespace
;; trick used by sideline.el.
;;
;; Technique:
;;
;; 1. Reserve margin columns via `set-window-margins' on every window
;;    showing the buffer.
;; 2. For each label, create a zero-length overlay at a buffer position
;;    and attach a `before-string' whose display property routes the label
;;    into the margin:
;;
;;      (propertize " " 'display `((margin right-margin) ,label))
;;
;;    The space character is the carrier; the display spec replaces it
;;    with the label drawn in the margin column.
;;
;; Known limitations (motivating notes for any real implementation):
;;
;; - The margin renders on the *first visual line* of a buffer line.  If the
;;   buffer line wraps to several visual lines, only the top gets the label.
;; - Conflicts with anything else that owns the right margin in the same
;;   buffer (in this config: `soft-wrap-mode' uses it for centering).  Try
;;   the demo in a buffer where soft-wrap is off, e.g. a .py or .el file.
;; - Per-window state: each window showing the buffer needs its own
;;   `set-window-margins' call; new windows from `split-window' won't pick
;;   up the margin until they're synced.  This POC syncs eagerly on add and
;;   clear; a production version would hook `window-configuration-change-hook'.
;;
;; Try it:
;;
;;   (require 'right-margin-labels-poc)
;;   M-x right-margin-labels-demo      ; scatter labels every 5 lines
;;   M-x right-margin-labels-clear     ; remove them and reset margin

;;; Code:

(defvar-local right-margin-labels--overlays nil)
(defvar-local right-margin-labels--max-width 0)

(defface right-margin-labels-default
  '((t :inherit shadow))
  "Default face for POC margin labels.")

(defun right-margin-labels--apply-width ()
  "Push current `right-margin-labels--max-width' to every window on this buffer."
  (let ((w right-margin-labels--max-width))
    (dolist (win (get-buffer-window-list nil nil t))
      (set-window-margins win (or (car (window-margins win)) 0) w))))

(defun right-margin-labels-add (pos label &optional face)
  "Attach LABEL in the right margin at buffer position POS.
Returns the overlay so callers can delete it later."
  (let* ((face    (or face 'right-margin-labels-default))
         (text    (propertize label 'face face))
         (carrier (propertize " " 'display `((margin right-margin) ,text)))
         (ov      (make-overlay pos pos nil t nil)))
    (overlay-put ov 'before-string carrier)
    (overlay-put ov 'right-margin-labels t)
    (overlay-put ov 'right-margin-labels-width (string-width label))
    (push ov right-margin-labels--overlays)
    (setq right-margin-labels--max-width
          (max right-margin-labels--max-width (string-width label)))
    (right-margin-labels--apply-width)
    ov))

(defun right-margin-labels-clear ()
  "Remove every POC label from the current buffer and shrink the margin."
  (interactive)
  (mapc #'delete-overlay right-margin-labels--overlays)
  (setq right-margin-labels--overlays nil
        right-margin-labels--max-width 0)
  (dolist (win (get-buffer-window-list nil nil t))
    (set-window-margins win (or (car (window-margins win)) 0) 0)))

(defun right-margin-labels-demo ()
  "Scatter example labels every fifth line for visual demonstration."
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
  (message "Added %d labels.  M-x right-margin-labels-clear to remove."
           (length right-margin-labels--overlays)))

(provide 'right-margin-labels-poc)

;;; right-margin-labels-poc.el ends here
