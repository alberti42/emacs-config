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

Annotations specify only :foreground \"red\" (no :background).  The
'margin' face is set to the modus-operandi 'line-number' background.

Without the fix, annotated cells (odd lines) show the frame default
background (white) while unannotated cells show the 'margin' background
— inconsistent.

With the fix, the 'margin' face becomes the base face for all margin
display-spec glyphs.  Unspecified attributes (background) are inherited
from 'margin', so all cells — annotated or not — show the same background.

Expected: the entire left margin column is uniformly colored from the
'margin' face.  '!' glyphs appear in red against that background.
No stripe below EOB."
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

Annotations set only :foreground (red); no :background is provided.
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

;;; Test 004 — org-mode prose, visual-wrap-prefix-mode, right margin for 75 cols
;;
;; Simulates a focus-writing scenario: right margin constrains text to 75
;; columns (as olivetti and similar packages do), visual-line-mode soft-wraps
;; long lines, and visual-wrap-prefix-mode gives list-item continuations a
;; hanging indent.  Expected: wrapped list items are properly indented; both
;; margin areas are uniformly colored; no stripe below EOB.

(defun face-margin-test-004 ()
  "Test: org-mode list items, visual-wrap-prefix-mode, right margin for 75 cols.

Simulates a realistic writing/note-taking scenario: the right window
margin is sized so the text area is exactly 75 columns wide — the same
technique used by focus/centering packages such as olivetti:

  right-margin = (max 0 (- (window-total-width) 1 75))

visual-line-mode soft-wraps long lines at the right margin.
visual-wrap-prefix-mode adds a hanging indent to continuation lines of
list items, so wrapped items look correctly indented.

Expected: list items wrap with a hanging indent aligned after '- '.
Both margin areas are uniformly colored throughout the window.
No stripe below EOB."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-004*")))
    (set-face-background 'margin ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
face-margin-test-004: org-mode content + visual-wrap-prefix-mode +
right margin.

This test simulates a realistic writing scenario: the right window
margin constrains the text area to 75 columns — the technique used by
centering and focus-writing packages such as olivetti.
visual-line-mode soft-wraps long lines at that boundary;
visual-wrap-prefix-mode adds a hanging indent to continuation lines of
list items so that wrapped entries look correct.

Content below is adapted from
https://www.gnu.org/software/emacs/documentation.html

Expected: list items wrap with a hanging indent aligned after '- '.
Both the left and right margin areas are uniformly colored.  No stripe
below EOB.

---

")
      ;; Org-mode list items long enough to wrap at 75 columns.
      ;; Content adapted from https://www.gnu.org/software/emacs/documentation.html
      (insert "\
* Reporting Bugs

- To report bugs or contribute fixes, use the built-in bug reporter \
(M-x report-emacs-bug) or send email to bug-gnu-emacs@gnu.org.  \
For security issues, see the security page before filing a public report.

- You can browse the bug database at debbugs.gnu.org.  For more information \
on contributing, see the CONTRIBUTE file distributed with Emacs; patches \
should include a ChangeLog entry in the standard GNU format.

- For all other queries, consult the Emacs-related mailing lists on \
savannah.gnu.org and the complete list of GNU mailing lists on lists.gnu.org.  \
Development discussion happens on emacs-devel@gnu.org; user questions \
belong on help-gnu-emacs@gnu.org.

- See «Get Help with GNU Software» for help with GNU software in general.  \
The Emacs Wiki at emacswiki.org is a community-maintained resource with \
tips, tutorials, and package listings.
")
      (setq-local left-margin-width 1))
    ;; Switch to the buffer before computing window-total-width so the
    ;; selected window is the one that will display the buffer.
    (switch-to-buffer buf)
    (let ((right (max 0 (- (window-total-width) 1 75))))
      (set-window-margins (selected-window) 1 right))
    (with-current-buffer buf
      (face-margin-test--annotate buf t)
      (visual-line-mode 1)
      (visual-wrap-prefix-mode 1)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))))

;;; Test 005 — 'margin' face font attributes: :weight works, :height is constrained
;;
;; The 'margin' face is the base face for all margin content.  Font variant
;; attributes (:weight, :slant) are inherited by annotation glyphs and are
;; visibly effective.  :height is inherited and fed into font realization, but
;; margin glyphs are physically constrained to the row height set by the text
;; area — so :height has no effect on line spacing.  This is correct: margin
;; annotations must never alter the spacing of the lines they annotate.

(defun face-margin-test-005 ()
  "Test: 'margin' face as base for margin content — font attributes and inheritance.

The 'margin' face acts as the base face for all content in the margin
area.  Font attributes set on it are inherited by annotation glyphs,
so packages can configure margin typography without touching each
individual overlay.

This test sets :weight bold and :height 1.5 on 'margin'.

Expected behavior:

  :weight bold — annotation glyphs ('!') are rendered in bold.  This is
  a font-variant attribute: it selects a different font (bold), realized
  locally within the margin.  It does NOT affect the text area.

  :height 1.5 — inherited and used in font realization, but margin glyphs
  are physically constrained to the row height determined by the text area.
  Row spacing is unaffected.  This is correct: margin annotations must
  never change line spacing, since that would corrupt text layout.

Verify: '!' glyphs appear bold; line heights are uniform; text area is
unaffected; no crash."
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
face-margin-test-005: 'margin' as base face — font attributes and inheritance.

The 'margin' face is the base face for all margin content.  Font
attributes set on it propagate to annotation glyphs via inheritance.

This test sets :weight bold and :height 1.5 on the 'margin' face.

:weight bold — '!' annotation glyphs should appear bold.  Bold is a font-
variant attribute: it is realized within the margin and does not affect
the text area.

:height 1.5 — accepted without error, but margin glyphs are constrained
to the row height set by the text area.  Line spacing must not change.
This is correct: annotations must never alter the height of the lines
they annotate.

Expected: '!' glyphs are bold; line heights are uniform throughout;
text area font is unchanged; no crash.
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
;; Opens two windows side by side with identical content and annotations.
;; The left buffer applies a buffer-local margin color via
;; face-remap-add-relative; the right buffer uses the global default.
;; The global 'margin' face is not modified.
;;
;; Expected: left buffer shows colored margin; right buffer shows the
;; default (frame background) margin.  The contrast is visible without
;; any manual buffer switching.

(defun face-margin-test-006 ()
  "Test: buffer-local 'margin' face via face-remap-add-relative.

Opens two windows side by side.  Both buffers have identical content,
line numbers, and margin annotations.  Only the left buffer calls
face-remap-add-relative to set a buffer-local 'margin' background.
The global 'margin' face is not modified.

Expected: the left buffer shows a colored margin; the right buffer
shows the default (frame background) margin.  The isolation is
immediately visible without switching buffers manually."
  (interactive)
  (face-margin-test--load-theme)
  ;; Reset global 'margin' face so the right buffer shows a clear contrast.
  (set-face-background 'margin nil)
  (let* ((ln-bg (face-background 'line-number nil t))
         (buf-l (get-buffer-create "*face-margin-test-006-local*"))
         (buf-g (get-buffer-create "*face-margin-test-006-global*")))
    ;; Populate both buffers with identical structure.
    (dolist (entry `((,buf-l "LEFT  — buffer-local face-remap-add-relative (analogous to test 002)"
                             "face-remap-add-relative sets the 'margin' background\n\
buffer-locally.  Behaves like test 002: margin matches line-number,\n\
no stripe below EOB.  The global 'margin' face is not modified.")
                     (,buf-g "RIGHT — no override, global default (analogous to test 001)"
                             "No face-remap-add-relative in this buffer.  Behaves\n\
like test 001: margin reverts to frame background below EOB,\n\
producing the visible stripe.  Global 'margin' face is unchanged.")))
      (let ((buf   (nth 0 entry))
            (label (nth 1 entry))
            (desc  (nth 2 entry)))
        (with-current-buffer buf
          (read-only-mode -1)
          (erase-buffer)
          (insert (format "face-margin-test-006: buffer-local 'margin' isolation.\n\
%s\n\n%s\n\nLines 1–8 below:\n" label desc))
          (dotimes (i 8) (insert (format "Line %d\n" (1+ i))))
          (setq-local left-margin-width 1)
          (face-margin-test--annotate buf t)
          (display-line-numbers-mode 1)
          (read-only-mode 1)
          (goto-char (point-min)))))
    ;; Apply buffer-local remap only to the left buffer.
    (with-current-buffer buf-l
      (face-remap-add-relative 'margin :background ln-bg))
    ;; Display side by side: left buffer in the current window, right in a split.
    (delete-other-windows)
    (switch-to-buffer buf-l)
    (set-window-margins (selected-window) 1 0)
    (let ((win-r (split-window-right)))
      (set-window-buffer win-r buf-g)
      (with-selected-window win-r
        (set-window-margins (selected-window) 1 0)))))

;;; Test 007 — horizontal scrolling
;;
;; The left margin is a fixed area that does not participate in horizontal
;; scrolling.  Expected: the margin background stays uniformly colored as
;; the text area scrolls left and right.  No redraw glitch on scroll.

(defun face-margin-test-007 ()
  "Test: left margin stays fixed and colored during horizontal scrolling.

The left margin is a fixed area pinned to the window edge: it does not
scroll with the text.  This test verifies that the margin background
remains uniformly colored regardless of the horizontal scroll position.

Use C-e to scroll right to the end of a long line, C-a to return.

Expected: left margin stays uniformly colored throughout.
No redraw glitch or stripe at any scroll position."
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
        "The left margin is fixed and does not scroll with the text.\n"
        "Use C-e to scroll right to the end of a line, C-a to return.\n"
        "Expected: left margin stays uniformly colored at all scroll positions.\n\n"
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
