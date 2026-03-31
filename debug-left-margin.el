;;; debug-left-margin.el --- Reproduce left-margin background stripe -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Minimal reproduction case for the left-margin background stripe bug.
;;
;; The stripe appears at the bottom of the window, below point-max, when:
;;   - the left margin is reserved (e.g. by a package placing annotations),
;;   - line numbers are enabled, and
;;   - the `line-number' face has a background different from the frame default.
;;
;; The empty window rows below point-max receive no character and thus no face,
;; so they fall back to the frame default background, producing a visible stripe
;; inconsistent with the gutter column above it.
;;
;; Usage:
;;   M-x debug-left-margin-show
;;
;; This command can be run from "emacs -Q":
;;   emacs -Q --load /path/to/debug-left-margin.el --eval "(debug-left-margin-show)"

;;; Code:

(defvar debug-left-margin-gutter-background "#2257a0"
  "Background color used for the gutter column in the reproduction buffer.
Change this to any color that contrasts clearly with the frame background.")

(defvar debug-left-margin-fill-empty t
  "When non-nil, fill unannotated margin characters with a space.

This reproduces the workaround recommended by packages such as git-gutter:
fill every margin cell with a space ' ' so that the background face is
applied uniformly on all text lines.  The stripe below point-max remains
regardless.

Set this to nil to see the look without the workaround: only annotated
lines receive the background color, producing a scattered pattern of
colored characters against the frame default background.

Re-run M-x debug-left-margin-show after changing this variable.")

(defun debug-left-margin--make-sign (sign)
  "Return a propertized margin string displaying SIGN."
  (propertize " "
              'display
              `((margin left-margin)
                ,(propertize sign 'face `(:foreground "white" :background ,debug-left-margin-gutter-background)))))

(defun debug-left-margin--annotate-all (buf)
  "Annotate every line in BUF.

On odd lines place '!'; on even lines place ' ' if
`debug-left-margin-fill-empty' is non-nil, otherwise skip them."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let ((line 1))
        (while (not (eobp))
          (when (or (= (% line 2) 1) debug-left-margin-fill-empty)
            (let* ((sign (if (= (% line 2) 1) "!" " "))
                   (ov (make-overlay (point) (1+ (point)))))
              (overlay-put ov 'before-string (debug-left-margin--make-sign sign))))
          (setq line (1+ line))
          (forward-line 1))))))

(defun debug-left-margin-show ()
  "Reproduce the left-margin background stripe in a scratch buffer.

Creates a *debug-left-margin* buffer, enables line numbers with a distinct
background color, reserves the left margin, and annotates lines to simulate
what git-gutter and similar packages do."
  (interactive)
  (let ((buf (get-buffer-create "*debug-left-margin*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
This buffer demonstrates the left-margin background stripe bug in Emacs.

The left margin is used by packages such as git-gutter, lsp-mode, and
hl-diff to display per-line annotations (version-control change indicators,
LSP warnings, spell-check markers, etc.).  These packages place characters
in the left margin only on lines that have text.  Below point-max — the
position after the last character in the buffer — the window rows have no
buffer content and therefore receive no character, no face, and no
background color.  Emacs fills that area with the frame default background.

When the `line-number' face has a distinct background color (as most modern
themes provide), this creates a visible stripe at the bottom-left of the
window: the annotation column is colored above point-max but reverts to the
frame default color below it. See: screenshot-1.png.

Packages such as git-gutter recommend filling all margin cells — even those
with no annotation — with a space \" \" so that the background face is
applied uniformly on all text lines.  This is the de facto standard
recipe/workaround to cover every line up to point-max, but cannot reach the
empty window rows below it, where the stripe remains.

Note that, if we did not fill the empty lines with \" \", the inconsistency
would be even more severe: only annotated lines receive the background
color, producing a scattered pattern against the frame default background.
To see this, evaluate:

  (setq debug-left-margin-fill-empty nil)

and re-run M-x debug-left-margin-show.  See: screenshot-2.png.
")
      ;; Reserve one column for the left margin.
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)

      ;; Annotate lines before enabling line numbers to avoid triggering
      ;; expensive redisplays on each overlay creation.
      (debug-left-margin--annotate-all buf)

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
