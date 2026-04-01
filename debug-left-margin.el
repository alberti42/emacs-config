;;; debug-left-margin.el --- Test suite for the 'margin' face patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive test suite for the Emacs patch that introduces the 'margin' face
;; (bug#80693).  Each test creates a dedicated buffer and configures specific
;; conditions so the reviewer can verify the expected visual outcome.
;;
;; All tests are callable from "emacs -Q" with the patched build:
;;
;;   emacs -Q --load /path/to/debug-left-margin.el \
;;             --eval "(face-margin-test-NNN)"
;;
;; Replace NNN with the test number (001 through 008).
;;
;; Tests 003–008 describe their expected outcome in the buffer text so
;; you know what to look for.

;;; Code:

(defvar face-margin-test-gutter-color "#2257a0"
  "Blue used by the test suite to color the margin and line-number areas.
Change this to any color that contrasts clearly with your frame background.")

;;; Helpers

(defun face-margin-test--make-sign (sign color)
  "Return a propertized margin string showing SIGN in COLOR."
  (propertize " "
              'display
              `((margin left-margin)
                ,(propertize sign
                             'face `(:foreground "white"
                                     :background ,color)))))

(defun face-margin-test--annotate (buf color &optional fill)
  "Annotate lines in BUF with COLOR.
Odd lines receive \"!\" ; even lines receive \" \" when FILL is non-nil."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let ((line 1))
        (while (not (eobp))
          (when (or (= (% line 2) 1) fill)
            (let* ((sign (if (= (% line 2) 1) "!" " "))
                   (ov (make-overlay (point) (1+ (point)))))
              (overlay-put ov 'before-string
                           (face-margin-test--make-sign sign color))))
          (setq line (1+ line))
          (forward-line 1))))))

(defun face-margin-test--base-buffer (name text)
  "Create buffer NAME with TEXT and return it."
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert text))
    buf))

;;; Test 001 — margin face, fill all lines
;;
;; Expected: the left margin area has a uniform blue column from the first line
;; to the bottom of the window.  No stripe / color discontinuity below the last
;; line of text.

(defun face-margin-test-001 ()
  "Test: 'margin' face + annotate all lines (fill = t).

Expected: the left margin column is uniformly blue from the first text
line to the bottom of the window.  No stripe discontinuity below EOB."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-001*"
              "face-margin-test-001: margin face + fill all lines.

The left margin column should appear uniformly blue all the way to the
bottom of the window, including the empty rows below this text.

Set (set-face-background 'margin ...) before running, or use the
face-remap-add-relative call inside this function.

If you see a stripe at the bottom (a colored bar only in the line-number
area but not in the margin column below the text), the patch is NOT in
effect or the 'margin' face is not set.
")))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      (face-margin-test--annotate buf face-margin-test-gutter-color t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 002 — margin face, annotate only odd lines (fill = nil)
;;
;; Expected: the left margin area below EOB is uniformly blue (from the
;; 'margin' face).  On text lines, only odd-numbered lines show the "!"
;; annotation with blue background; even lines show the blue background
;; from the 'margin' face alone (a plain blue cell, no "!" character).

(defun face-margin-test-002 ()
  "Test: 'margin' face + annotate only odd lines (fill = nil).

Expected: the margin column below EOB is uniformly blue.  On text lines,
odd lines show the '!' annotation; even lines show a plain blue cell from
the 'margin' face background.  No stripe discontinuity."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-002*"
              "face-margin-test-002: margin face, only odd lines annotated.

Odd lines (1, 3, 5, ...) receive an '!' overlay in the left margin.
Even lines have no overlay, so the margin cell background comes entirely
from the 'margin' face.

Expected: all margin cells are blue.  Below EOB also blue.  No stripe.
")))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      (face-margin-test--annotate buf face-margin-test-gutter-color nil)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 003 — overlay with foreground only; 'margin' background shows through
;;
;; Expected: overlay sets only a foreground color (no :background).  The
;; 'margin' face background should be visible behind the annotation text.

(defun face-margin-test-003 ()
  "Test: overlay with :foreground only — 'margin' background shows through.

Overlays specify only a foreground color; the background is unset.
Expected: the margin column is uniformly blue (from the 'margin' face).
The '!' character appears in a contrasting foreground color against that
blue background."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-003*"
              "face-margin-test-003: overlay foreground only.

The '!' annotation in the left margin has only :foreground set (yellow).
The blue background should come entirely from the 'margin' face.

Expected: all margin cells are blue; '!' glyphs appear in yellow text.
No stripe below EOB.
")))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      ;; Annotate with foreground only (no :background).
      (save-excursion
        (goto-char (point-min))
        (let ((line 1))
          (while (not (eobp))
            (when (= (% line 2) 1)
              (let ((ov (make-overlay (point) (1+ (point)))))
                (overlay-put
                 ov 'before-string
                 (propertize " "
                             'display
                             `((margin left-margin)
                               ,(propertize "!"
                                            'face '(:foreground "yellow")))))))
            (setq line (1+ line))
            (forward-line 1))))
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 004 — right margin reserved (soft-wrap style) + 'margin' face
;;
;; Expected: both the left and right margin areas are colored blue.
;; No stripe in either area below EOB.

(defun face-margin-test-004 ()
  "Test: both left and right margins reserved; 'margin' face colors both.

Expected: left margin column is blue (with '!' annotations on odd lines).
Right margin column is also blue.  No stripe in either area below EOB."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-004*"
              "face-margin-test-004: left AND right margin, 'margin' face.

Left margin (width 1) is reserved for per-line annotations.
Right margin (width 2) is reserved as layout padding (soft-wrap style).

Expected: both margin areas appear uniformly blue from the first line to
the bottom of the window.  No stripe discontinuity in either area.
")))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1 2)
      (face-margin-test--annotate buf face-margin-test-gutter-color t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 005 — 'margin' face attributes beyond background (bold, font height)
;;
;; Expected: the 'margin' face background is applied.  Bold and height
;; attributes should have no visible effect in the margin area (the margin
;; displays spaces, not text), but Emacs must not crash or mis-render.

(defun face-margin-test-005 ()
  "Test: 'margin' face with non-background attributes (bold, height).

Sets :background, :weight bold, and :height 1.5 on the 'margin' face.
Expected: the margin area is blue.  The bold and height attributes on a
face used for space glyphs should not cause crashes or visual artifacts.

Note: font height changes in the margin area may affect row height on
GUI frames — verify no line-height inconsistency is introduced."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-005*"
              "face-margin-test-005: 'margin' face with bold + height.

The 'margin' face has :background blue, :weight bold, :height 1.5.
Expected: margin area is blue.  Row heights should be consistent.
No crash, no visual artifact.
")))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      (face-margin-test--annotate buf face-margin-test-gutter-color t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color
                               :weight 'bold
                               :height 1.5)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 006 — buffer-local 'margin' face via face-remap-add-relative
;;
;; Expected: the 'margin' face background is applied only in this buffer.
;; Other buffers visited in the same frame should not be affected.

(defun face-margin-test-006 ()
  "Test: buffer-local 'margin' face via face-remap-add-relative.

Uses face-remap-add-relative to set the 'margin' background only in this
buffer.  Expected: margin area is blue in this buffer.  Switching to
another buffer (e.g. *scratch*) should show the default margin color."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-006*"
              "face-margin-test-006: buffer-local margin face via face-remap.

The 'margin' face background is set buffer-locally via face-remap-add-relative.

Expected: left margin is blue in this buffer.  In *scratch* or any other
buffer the margin should use the default (frame background) color.
")))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      (face-margin-test--annotate buf face-margin-test-gutter-color t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 007 — horizontal scrolling
;;
;; Expected: the left margin area stays visually consistent when the window
;; is horizontally scrolled (via C-x < / C-x >).

(defun face-margin-test-007 ()
  "Test: horizontal scrolling with left margin and 'margin' face.

Expected: when scrolling horizontally (C-x < / C-x >), the left margin
column remains blue and consistently filled.  No glitches or stripe."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-007*"
              (concat
               "face-margin-test-007: horizontal scrolling.\n\n"
               (make-string 120 ?A) "\n"
               (make-string 120 ?B) "\n"
               (make-string 120 ?C) "\n"
               (make-string 120 ?D) "\n"
               "\nScroll right with C-x > and left with C-x <.\n"
               "Expected: left margin stays uniformly blue.\n"))))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (setq-local truncate-lines t)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      (face-margin-test--annotate buf face-margin-test-gutter-color t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 008 — RTL text (Hebrew)
;;
;; Expected: with right-to-left paragraph direction the margin areas are
;; still colored correctly.  No stripe, no reversed-row glitch.

(defun face-margin-test-008 ()
  "Test: RTL text with 'margin' face.

Inserts a mix of LTR and RTL text.  Expected: the left margin area is
uniformly blue for both LTR and RTL rows.  No stripe below EOB."
  (interactive)
  (let ((buf (face-margin-test--base-buffer
              "*face-margin-test-008*"
              ;; Mix of LTR and RTL lines.
              (concat
               "face-margin-test-008: RTL text.\n\n"
               "This is a left-to-right (LTR) line.\n"
               "\u05D6\u05D5\u05D4\u05D9 \u05E9\u05D5\u05E8\u05D4 \u05DE\u05D9\u05DE\u05D9\u05DF \u05DC\u05E9\u05DE\u05D0\u05DC \u05D1\u05E2\u05D1\u05E8\u05D9\u05EA.\n"
               "Another LTR line.\n"
               "\u05E9\u05D5\u05E8\u05D4 \u05E0\u05D5\u05E1\u05E4\u05EA \u05D1\u05E2\u05D1\u05E8\u05D9\u05EA.\n\n"
               "Expected: left margin column uniformly blue for all rows.\n"
               "No stripe below this text.\n"))))
    (with-current-buffer buf
      (setq-local left-margin-width 1)
      (set-window-buffer (selected-window) buf)
      (set-window-margins (selected-window) 1)
      (face-margin-test--annotate buf face-margin-test-gutter-color t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'line-number
                               :background face-margin-test-gutter-color
                               :foreground "white")
      (face-remap-add-relative 'margin
                               :background face-margin-test-gutter-color)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Manual tests (require external packages — cannot run with emacs -Q)
;;
;; The following scenarios require packages not available with emacs -Q.
;; Run them in a full Emacs session with the packages installed.
;;
;; M-1: git-gutter + modus-vivendi
;;   Load modus-vivendi, enable git-gutter-mode in a Git-tracked buffer.
;;   Set (set-face-background 'margin (face-background 'line-number)).
;;   Expected: the margin column matches the line-number background throughout,
;;   including below the last line of text.
;;
;; M-2: lsp-mode diagnostics in left margin
;;   Open a file with LSP diagnostics displayed in the left margin.
;;   Set 'margin' background to match 'line-number'.
;;   Expected: uniform margin column; no stripe below EOB.
;;
;; M-3: Olivetti / olivetti-mode (right margin as layout padding)
;;   Enable olivetti-mode (which reserves both margins for centering).
;;   Set 'margin' background to a distinct color.
;;   Expected: both margin areas colored uniformly, no stripe.

(provide 'debug-left-margin)
;;; debug-left-margin.el ends here
