;;; debug-left-margin.el --- Reproduce left-margin background stripe -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Minimal reproduction case for the left-margin background stripe bug.
;;
;; The stripe appears at the bottom of the window, below the last line of
;; text, when:
;;   - the left margin is reserved (e.g. by a package placing annotations),
;;   - line numbers are enabled, and
;; - the `line-number' face has a background different from the frame default.
;;
;; The empty margin rows below the last line of text receive no character and
;; thus no face, so they fall back to the frame default background, producing
;; a visible stripe inconsistent with the gutter column above it.
;;
;; Usage:
;;   M-x debug-left-margin-show
;;
;; This command can be run from "emacs -Q" after loading this file:
;;   emacs -Q --load /path/to/debug-left-margin.el

;;; Code:

(defvar debug-left-margin-gutter-background "#2257a0"
  "Background color used for the gutter column in the reproduction buffer.
Change this to any color that contrasts clearly with the frame background.")

(defun debug-left-margin--annotate-line (buf line)
  "Place a '!' annotation in the left margin of LINE in BUF."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (let ((ov (make-overlay (point) (1+ (point)))))
        (overlay-put ov 'before-string
                     (propertize " "
                                 'display
                                 `((margin left-margin)
                                   ,(propertize "!" 'face `(:foreground "white" :background ,debug-left-margin-gutter-background)))))))))

(defun debug-left-margin-show ()
  "Reproduce the left-margin background stripe in a scratch buffer.

Creates a *debug-left-margin* buffer, enables line numbers with a
distinct background color, reserves the left margin, and annotates
odd lines with '!' to simulate what git-gutter and similar packages do.
The bottom of the window should show a stripe in the frame default
background color where the left margin has no annotation characters."
  (interactive)
  (let ((buf (get-buffer-create "*debug-left-margin*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
This buffer demonstrates the left-margin background stripe bug in Emacs.

The left margin is reserved by packages such as git-gutter, lsp-mode, and
hl-diff to display per-line annotations (version-control change indicators,
LSP warnings, spell-check markers, etc.).  These packages place characters
in the left margin only on lines that have text.  Below the last line of
text the margin is empty: those rows receive no character, no face, and
therefore no background color.  Emacs fills them with the frame default
background instead.

When the `line-number' face has a distinct background color (as most modern
themes provide), this creates a visible stripe at the bottom-left of the
window: the annotation column is colored above the last text line but
reverts to the frame default color below it.

The '!' characters on odd lines simulate the kind of annotation that
git-gutter, lsp-mode, and similar packages render in the left margin.
Scroll so that the last line of this text is near the middle of the window
to make the stripe clearly visible below it.
")
      ;; Reserve one column for the left margin.
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)

      ;; Annotate lines 1 and 3 to simulate per-line gutter annotations.
      (debug-left-margin--annotate-line buf 1)
      (debug-left-margin--annotate-line buf 3)

      ;; Enable line numbers.
      (display-line-numbers-mode 1)

      ;; Give line-number a background color distinct from the frame default
      ;; so the stripe is visible.  We use a hardcoded color here so the
      ;; reproduction works from emacs -Q regardless of the active theme.
      (face-remap-add-relative 'line-number :background debug-left-margin-gutter-background :foreground "white")

      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(provide 'debug-left-margin)
;;; debug-left-margin.el ends here
