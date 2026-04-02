;;; debug-left-margin.el --- Test suite for the 'margin' face patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive test suite for the Emacs patch that introduces the 'margin' face
;; (bug#80693).  Each test creates a dedicated buffer and configures specific
;; conditions so the reviewer can verify the expected visual outcome.
;;
;; All tests use the built-in 'modus-operandi' theme (included with Emacs since
;; Emacs 28).  That theme gives the 'line-number' face a non-default background
;; out of the box, making it possible to demonstrate the inconsistency using
;; only components that ship with Emacs — no external packages or custom colors
;; are required.
;;
;; Tests are callable from "emacs -Q" with the patched build:
;;
;;   emacs -Q --load /path/to/debug-left-margin.el \
;;             --eval "(face-margin-test-NNN)"
;;
;; Replace NNN with the test number (001 through 008).
;;
;; Tests 001 and 002 are paired: 001 shows the stripe bug using only built-in
;; components; 002 shows the fix by setting the 'margin' face background to
;; match 'line-number'.  Tests 003–008 cover additional scenarios and describe
;; their expected outcome in the buffer text.

;;; Code:

;;; Helpers

(defun face-margin-test--make-sign (sign face-spec)
  "Return a propertized margin string showing SIGN styled with FACE-SPEC."
  (propertize " "
              'display
              `((margin left-margin)
                ,(propertize sign 'face face-spec))))

(defun face-margin-test--annotate (buf &optional fill)
  "Annotate lines in BUF with git-gutter-style indicators.
All margin cells use the 'line-number' face background so the gutter
column looks uniform.  Odd lines show \"!\" in red; even lines receive
a blank filler when FILL is non-nil."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let* ((ln-bg (face-background 'line-number nil t))
             (line 1))
        (while (not (eobp))
          (cond
           ((= (% line 2) 1)
            (let ((ov (make-overlay (point) (1+ (point)))))
              (overlay-put
               ov 'before-string
               (face-margin-test--make-sign
                "!" `(:foreground "red" :background ,ln-bg)))))
           (fill
            (let ((ov (make-overlay (point) (1+ (point)))))
              (overlay-put
               ov 'before-string
               (face-margin-test--make-sign
                " " `(:background ,ln-bg))))))
          (setq line (1+ line))
          (forward-line 1))))))

(defun face-margin-test--setup-window (buf &optional right-width)
  "Set margins on the selected window for BUF.
LEFT is always 1.  RIGHT-WIDTH defaults to 0."
  (set-window-buffer (selected-window) buf)
  (set-window-margins (selected-window) 1 (or right-width 0)))

(defun face-margin-test--load-theme ()
  "Load modus-operandi without prompting."
  (load-theme 'modus-operandi t))

;;; Test 001 — bug demo: modus-operandi stripe with no 'margin' face set
;;
;; Shows the inconsistency using only built-in Emacs components.
;; 'modus-operandi' colors the 'line-number' face; the margin area below EOB
;; reverts to the frame default, producing a visible stripe.
;;
;; Expected: a colored stripe appears below the last line of text in the
;; line-number column but NOT in the left margin column.

(defun face-margin-test-001 ()
  "Bug demo: modus-operandi + left margin, 'margin' face NOT customized.

Uses only built-in components: the modus-operandi theme (shipped with
Emacs) colors the 'line-number' face.  The left margin is reserved and
all lines are annotated.  The 'margin' face is left at its default
(inherits the frame background).

Expected: a colored stripe is visible in the line-number column below the
last line of text, but the left margin column below EOB reverts to the
frame default background — an inconsistency within the same gutter area."
  (interactive)
  (face-margin-test--load-theme)
  ;; Reset the 'margin' face to its built-in default so this test
  ;; demonstrates unmodified behavior regardless of what previous tests
  ;; set.  The set-face-background call also triggers face cache
  ;; re-realization, which is required for the theme's 'line-number'
  ;; face to appear correctly.
  (set-face-background 'margin nil)
  (let ((buf (get-buffer-create "*face-margin-test-001*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-001: stripe bug demo (no 'margin' face customization).

This buffer shows the stripe bug using only built-in Emacs components.
The modus-operandi theme (shipped with Emacs) gives the 'line-number'
face a non-default background.  The left margin is reserved and annotated
the way git-gutter and similar packages do it.  The 'margin' face is not
customized — it inherits the frame default background.

Look at the bottom of the window, below this text.  The line-number
column continues with its theme background color, but the left margin
column to its left reverts to the frame default: a visible stripe.

Compare with face-margin-test-002, which shows the fix.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      ;; Do NOT customize the 'margin' face — this is the bug scenario.
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 002 — fix demo: same as 001 but 'margin' face set to match line-number
;;
;; Expected: the left margin column and the line-number column share the same
;; background throughout the window, including below the last line of text.
;; No stripe.

(defun face-margin-test-002 ()
  "Fix demo: modus-operandi + left margin + 'margin' face set to 'line-number'.

Same setup as face-margin-test-001.  Additionally sets the 'margin' face
background to match the 'line-number' background from modus-operandi, using:

  (set-face-background \\='margin (face-background \\='line-number nil t))

Expected: the left margin column and the line-number column share the
same background color throughout the window, including below EOB.
No stripe."
  (interactive)
  (face-margin-test--load-theme)
  (set-face-background 'margin (face-background 'line-number nil t))
  (let ((buf (get-buffer-create "*face-margin-test-002*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-002: fix demo ('margin' face set to match 'line-number').

Same setup as face-margin-test-001.  The only difference: the 'margin'
face background is set to match the modus-operandi 'line-number' background:

  (set-face-background 'margin (face-background 'line-number nil t))

Expected: the left margin column and the line-number column share the
same background color all the way to the bottom of the window.  No stripe.

Compare with face-margin-test-001, which shows the bug.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 003 — overlay with foreground only; 'margin' background shows through
;;
;; Expected: overlay sets only a foreground color (no :background).  The
;; 'margin' face background fills all margin cells, including those where
;; the annotation glyph has no background of its own.

(defun face-margin-test-003 ()
  "Test: overlay with :foreground only — 'margin' background shows through.

Annotations specify only :foreground.  The 'margin' face background
(set to the modus-operandi 'line-number' background) should be visible
uniformly in all margin cells.

Expected: the entire left margin column is colored from the 'margin'
face.  The '+' glyph appears in the overlay foreground color against
that background.  No stripe below EOB."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-003*")))
    (set-face-background 'margin ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-003: overlay foreground only, 'margin' background shows through.

Annotations set only :foreground (green); no :background is provided.
The 'margin' face background should fill all margin cells uniformly.

Expected: entire left margin column colored from 'margin' face.
'!' glyphs appear in red against that background.  No stripe below EOB.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
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
                                            'face '(:foreground "red")))))))
            (setq line (1+ line))
            (forward-line 1))))
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 004 — both left and right margins; 'margin' face colors both
;;
;; Expected: both margin areas are colored uniformly by the 'margin' face.
;; No stripe in either area below EOB.

(defun face-margin-test-004 ()
  "Test: left AND right margins reserved; 'margin' face colors both.

Left margin (width 1) is reserved for per-line annotations.
Right margin (width 2) is reserved as layout padding (as done by
soft-wrap or centering packages).  The 'margin' face background is set
to match the modus-operandi 'line-number' background.

Expected: both margin areas appear uniformly colored from the first line
to the bottom of the window.  No stripe in either area below EOB."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-004*")))
    (set-face-background 'margin ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-004: left AND right margin, 'margin' face colors both.

Left margin (width 1): per-line annotations (git-gutter style).
Right margin (width 2): layout padding (soft-wrap / centering style).

Expected: both margin areas are uniformly colored (same as line-number
background) from the first line to the bottom of the window.  No stripe.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf 2)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 005 — 'margin' face attributes beyond background (bold, height)
;;
;; Expected: background is applied.  Non-background attributes (bold,
;; height) should not crash Emacs or cause line-height inconsistencies.

(defun face-margin-test-005 ()
  "Test: 'margin' face with non-background attributes (bold, :height 1.5).

Sets :background, :weight bold, and :height 1.5 on the 'margin' face.
Expected: margin area is colored.  Row heights should be consistent —
no line-height anomaly from non-background attributes on space glyphs.

Note for GUI frames: verify no per-row height change is introduced."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-005*")))
    (set-face-background 'margin ln-bg)
    (set-face-attribute 'margin nil :weight 'bold :height 1.5)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-005: 'margin' face with bold + :height 1.5.

The 'margin' face has :background (from line-number), :weight bold,
and :height 1.5.  Margin cells contain space glyphs, so bold and height
should have no visible text effect, but Emacs must not crash.

Expected: margin area is colored.  Row heights are consistent.
No crash, no visual artifact from the non-background attributes.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 006 — buffer-local 'margin' face via face-remap-add-relative
;;
;; Expected: the 'margin' background is applied only in this buffer.
;; Other buffers in the same frame use the global (default) 'margin' face.

(defun face-margin-test-006 ()
  "Test: buffer-local 'margin' face via face-remap-add-relative.

Uses face-remap-add-relative for a buffer-local override instead of the
global set-face-background.  Expected: margin area is colored only in
this buffer.  Switching to *scratch* shows the default margin color."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-006*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-006: buffer-local 'margin' via face-remap-add-relative.

The 'margin' face background is set buffer-locally via face-remap-add-relative.
The global 'margin' face is not modified.

Expected: left margin is colored in this buffer.
Switching to *scratch* (or any other buffer) shows the default margin color.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (face-remap-add-relative 'margin :background ln-bg)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 007 — horizontal scrolling
;;
;; Expected: the left margin stays visually consistent when the window is
;; horizontally scrolled (C-x < / C-x >).

(defun face-margin-test-007 ()
  "Test: horizontal scrolling with colored left margin.

Expected: when scrolling horizontally (C-x < / C-x >), the left margin
column remains uniformly colored.  No glitches or stripe on scroll."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-007*")))
    (set-face-background 'margin ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert
       (concat
        "face-margin-test-007: horizontal scrolling.\n\n"
        "Scroll right with C-x > and left with C-x <.\n"
        "Expected: left margin stays uniformly colored on scroll.\n\n"
        (make-string 120 ?A) "\n"
        (make-string 120 ?B) "\n"
        (make-string 120 ?C) "\n"
        (make-string 120 ?D) "\n"
        (make-string 120 ?E) "\n"))
      (setq-local left-margin-width 1)
      (setq-local truncate-lines t)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 008 — RTL text
;;
;; Expected: with right-to-left paragraph direction the margin areas are
;; still colored correctly.  No stripe, no reversed-row glitch.

(defun face-margin-test-008 ()
  "Test: RTL text with colored 'margin' face.

Inserts a mix of LTR and RTL (Hebrew) lines.  Expected: the left margin
area is uniformly colored for both LTR and RTL rows.  No stripe below EOB."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-008*")))
    (set-face-background 'margin ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert
       (concat
        "face-margin-test-008: RTL text.\n\n"
        "This is a left-to-right (LTR) line.\n"
        "\u05D6\u05D5\u05D4\u05D9 \u05E9\u05D5\u05E8\u05D4 "
        "\u05DE\u05D9\u05DE\u05D9\u05DF \u05DC\u05E9\u05DE\u05D0\u05DC "
        "\u05D1\u05E2\u05D1\u05E8\u05D9\u05EA.\n"
        "Another LTR line.\n"
        "\u05E9\u05D5\u05E8\u05D4 \u05E0\u05D5\u05E1\u05E4\u05EA "
        "\u05D1\u05E2\u05D1\u05E8\u05D9\u05EA.\n\n"
        "Expected: left margin uniformly colored for all rows.\n"
        "No stripe below this text.\n"))
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Manual tests (require external packages — cannot run with emacs -Q)
;;
;; The following scenarios require packages not available with emacs -Q.
;; Run them in a full Emacs session with the packages installed.
;;
;; M-1: git-gutter + modus-operandi (end-to-end realistic scenario)
;;   Load modus-operandi.  Enable git-gutter-mode in a Git-tracked buffer.
;;   Add to your config:
;;     (set-face-background 'margin (face-background 'line-number nil t))
;;   Expected: the margin column matches the line-number background throughout,
;;   including below the last line of text.
;;
;; M-2: lsp-mode diagnostics in left margin
;;   Open a file with LSP diagnostics displayed in the left margin.
;;   Apply the same set-face-background call as M-1.
;;   Expected: uniform margin column; no stripe below EOB.
;;
;; M-3: Olivetti / olivetti-mode (right margin as layout padding)
;;   Enable olivetti-mode (which reserves both margins for centering).
;;   Set 'margin' background to a distinct color.
;;   Expected: both margin areas colored uniformly; no stripe.

(provide 'debug-left-margin)
;;; debug-left-margin.el ends here
