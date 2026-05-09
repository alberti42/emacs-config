;;; debug-left-margin.el --- Test suite for the 'margin' face patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive test suite for the Emacs patch that introduces the 'margin' face
;; (bug#80693).  Each test creates a dedicated buffer and configures specific
;; conditions so the reviewer can verify the expected visual outcome.
;;
;; Each test (with the exception of 001 and 002) can be run in one of two
;; modes:
;;
;;   - 'themed' mode: Configures the 'margin' face to match the background of
;;     the 'line-number' area.  This demonstrates the intended fix: a single,
;;     visually consistent gutter for both line numbers and annotations.
;;
;;   - 'standard' mode: Leaves the 'margin' face at its default configuration
;;     (inheriting from 'default').  This demonstrates the pre-patch behavior:
;;     the margin area beyond the end-of-buffer (EOB) reverts to the frame
;;     background, producing the visible "stripe" bug.
;;
;; All tests use the built-in 'modus-operandi' theme (included since Emacs 28).
;; That theme provides a non-default 'line-number' background out of the box,
;; making it possible to demonstrate the inconsistency using only components
;; that ship with Emacs.
;;
;; Tests are callable from "emacs -Q" with the patched build:
;;
;;   emacs -Q --load /path/to/debug-margin-face.el \
;;             --eval "(face-margin-test-NNN 'themed)"
;;
;; Replace NNN with the test name from the index below, and 'themed
;; with 'standard as needed.  The tests can also be run interactively
;; within Emacs via M-x.
;;
;; Test index (see each test's docstring for full details):
;;
;;   - face-margin-test-001   Stripe bug demo (no 'margin' customization).
;;   - face-margin-test-002   Fix demo ('margin' matches 'line-number' bg).
;;   - face-margin-test-003   2-column margin: face interaction + empty fill.
;;   - face-margin-test-004   Right margin as layout padding + visual-wrap.
;;   - face-margin-test-004b  Margin background bleed (wide left/right margins).
;;   - face-margin-test-005   'margin' font attributes (:weight, :height).
;;   - face-margin-test-006   Buffer-local 'margin' isolation (face-remap).
;;   - face-margin-test-007   Horizontal scrolling.
;;   - face-margin-test-007b  Horizontal scrolling without line-number column.
;;   - face-margin-test-008   RTL text with colored 'margin'.
;;   - face-margin-test-009   Built-in Flymake margin indicators (2-col).
;;   - face-margin-test-010a  Variable-pitch: 'margin' inherits 'variable-pitch'.
;;   - face-margin-test-010b  Variable-pitch: 'margin' uses :height 2.0.
;;   - face-margin-test-010c  Variable-pitch: 'default' uses a variable-pitch font.
;;   - face-margin-test-010d  Variable-pitch: combined stress (010c + :height 2.0).
;;   - face-margin-test-011   Margin face on truncated rows.
;;   - face-margin-test-012   SVG image in margin (bug#80693 follow-up).
;;   - face-margin-test-013   Flymake margin indicator (bug#80693 follow-up).
;;
;; Mode handling:
;;
;; Tests 001 and 002 are paired and run in fixed modes: 001 is in
;; 'standard' mode to show the stripe bug using only built-in
;; components; 002 is in 'themed' mode to show the fix.  All other
;; tests prompt for the mode interactively, or accept it as a single
;; symbol argument ('themed or 'standard).
;;
;; The script is designed to run on unpatched Emacs without crashing.  On
;; unpatched builds, the 'margin' face does not exist, so all tests
;; gracefully fall back to 'standard' mode, allowing the reviewer to
;; demonstrate the pre-patch behavior before applying the fix.

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
All margin cells use the `line-number' face background so the gutter
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
  "Load `modus-operandi' without prompting."
  (load-theme 'modus-operandi t))

(defun face-margin-test--apply-mode (mode ln-bg)
  "Set or clear the `margin' face background depending on MODE.
MODE is `themed' (default) or `standard'.  In themed mode the
background is set to LN-BG; in standard mode it is cleared so
the pre-patch stripe is visible.  No-ops when the `margin' face
does not exist (unpatched builds)."
  (when (facep 'margin)
    (if (eq mode 'standard)
        (set-face-background 'margin nil)
      (set-face-background 'margin ln-bg))))

(defun face-margin-test--mode-header (mode)
  "Return a warning string if the build is unpatched."
  (if (not (facep 'margin))
      (let ((msg (if (eq mode 'standard)
                     "\
WARNING: you are running on an unpatched version of Emacs.  The tests will be
carried out nonetheless to demonstrate Emacs' behavior before applying the patch."
                   "\
WARNING: you are running on an unpatched version of Emacs.  Your request
to execute tests in `themed' mode cannot be fulfilled with the currently
unpatched Emacs. Falling back to unpatched behavior.")))
        (message "%s" msg)
        (concat msg "\n\n"))
    ""))

(defun face-margin-test--title (title mode)
  "Return TITLE with a running mode indicator appended on the same line.
The effective mode is determined by MODE and whether the `margin' face exists."
  (let ((applied (and (eq mode 'themed) (facep 'margin))))
    (format "%s - running in %s mode (%s)\n\n"
            title
            (if applied "`themed'" "`standard'")
            (if applied "showing the fix" "showing pre-patch behavior"))))

;;; Test 001 — stripe bug demo; full explanation in the test buffer.

(defun face-margin-test-001 ()
  "Stripe bug demo: `margin' face left uncustomized.
See test buffer for full explanation."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((mode 'standard)
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-001*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert "face-margin-test-001: stripe bug demo (no 'margin' face customization)\n\n")
      (insert "\
This buffer shows the stripe bug using only built-in Emacs components.  The
modus-operandi theme (shipped with Emacs) gives the 'line-number' face a
non-default background.  The left margin is reserved and annotated the way
git-gutter and similar packages do it.

As an example, we marked odd lines with a red \"!\" indication.  The
background face is chosen to match the face background of 'line-number'.
The even rows are filled with \" \" with the same background face.

The 'margin' face is left on purpose not customized — it inherits the frame
default background.

Look at the bottom of the window, below this text.  The line-number column
continues with its theme background color, but the left margin area to its
left reverts to the frame default: a visible white stripe.

Compare with face-margin-test-002, which shows the fix.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 002 — fix demo: 'margin' face set to match line-number; full explanation in the test buffer.

(defun face-margin-test-002 ()
  "Fix demo: `margin' face set to match `line-number' background.
See test buffer for full explanation."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((mode 'themed)
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-002*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert "face-margin-test-002: fix demo ('margin' face set to match 'line-number')\n\n")
      (insert "\
Same setup as face-margin-test-001.  The only difference: the 'margin' face
background is set to match the modus-operandi 'line-number' background:

  (set-face-background 'margin (face-background 'line-number nil t))

Expected: the left margin column and the line-number column share the same
background color all the way to the bottom of the window, showing the
solution to the bug: no visible stripe.

Compare with face-margin-test-001, which shows the bug.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 003 — face interaction and empty-margin filling; full explanation in the test buffer.

(defun face-margin-test-003 (&optional mode)
  "2-column margin: face interaction and empty-margin filling.
See test buffer for full explanation.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-003*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-003: 2-column margin — face interaction and empty filling" mode))
      (insert "\
The left margin is 2 columns wide.  Annotations use :foreground only (red);
no :background is provided.

Two cases are covered:

  Odd lines: a 1-char '!' glyph occupies column 1; column 2 is empty.
    - Column 1 tests face interaction: the 'margin' background must show
      through the foreground-only glyph.
    - Column 2 tests partial empty filling: no glyph, the display engine
      must fill it with the 'margin' background.

  Even lines: no annotation at all.
    - Both columns test pure empty filling.

Also: the area below the last line of text (EOB) has no glyphs in either
column and tests the same empty-filling path.

Expected (patched): the entire 2-column left margin is uniformly colored.
'!' glyphs appear in red against the gutter background.  No stripe below EOB.

Expected (unpatched): all margin cells show the frame default background
(white), resulting in a visual inconsistency: a visible white stripe on the left
of the gray line-number column.
")
      (setq-local left-margin-width 2)
      (face-margin-test--setup-window buf)
      (set-window-margins (selected-window) 2 0)
      ;; Annotate odd lines with a single foreground-only '!' in column 1.
      ;; Column 2 is intentionally left empty to test empty-margin filling.
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

;;; Test 004 — right margin as layout padding + visual-wrap-prefix-mode; full explanation in the test buffer.

(defun face-margin-test-004 (&optional mode)
  "Right margin as layout padding + visual-wrap-prefix-mode.
See test buffer for full explanation.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-004*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-004: org-mode content + visual-wrap-prefix-mode + right margin" mode))
      (insert "\
This test simulates the technique used by focus/centering packages such as
olivetti, visual-fill-column, writeroom-mode, and darkroom: the right
window margin is reserved as empty layout padding to constrain the text
area to 75 columns.  visual-line-mode soft-wraps long lines at the right
boundary; visual-wrap-prefix-mode adds a hanging indent to continuation
lines of list items so that wrapped entries look correct.

These packages do NOT write content into the margin — writing actual glyphs
into the right margin is a distinct scenario not covered by this test. See
face-margin-test-004b for a complementary test that writes actual
annotation glyphs into both the left and right margins simultaneously.

Content below is adapted from
https://www.gnu.org/software/emacs/documentation.html

Expected (patched): list items wrap with a hanging indent.  The background
of both margin areas is uniformly colored of the same color as
line-numbers. No stripe below EOB.

Expected (unpatched): the background of both left and right margin inherits
the same default background color of the frame (white). In the left margin,
only annotated characters have a background matched to the line-numbers.

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

;;; Test 004b — annotation glyphs in the right margin; full explanation in the test buffer.

(defun face-margin-test-004b (&optional mode)
  "Test: margin background bleed.

Places annotations with distinct background colors in margins wider
than the glyphs.  Verifies that the `margin' face filling loop
prevents the annotation's background from bleeding into the rest of
the margin area.

Left Margin (4 columns): '!' with CYAN background.
Right Margin (12 columns): 'Line 2' with YELLOW background.

Optional argument MODE is `themed' (default) or `standard'."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-004b*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-004b: margin background bleed" mode))
      (insert "\
This test validates the fix for the \"Background Bleed\" inconsistency
surfaced by themes that color the gutter.

LEFT MARGIN (4 columns wide):
Odd lines contain a '!' with a CYAN background.  If the patch is working,
only the first column should be cyan; columns 2-4 must be grey.

RIGHT MARGIN (12 columns wide):
Line 2 contains 'Line 2' with a YELLOW background.  If the patch is
working, the rest of the 12-column width should be grey.

--- Why a loop is needed ---

In GUI frames, the display engine does not know the `margin' face
background when it finishes drawing the glyphs we provide.  Without an
explicit loop filling the area with `margin' glyphs, the renderer simply
extends the background of the LAST glyph it saw (the annotation) to the
rest of the rectangle.  This causes the annotation's color to \"bleed\"
horizontally across the gutter.

In TTY frames, the engine does not perform rectangle clearing; it simply
leaves unassigned cells empty.  Without the loop, these cells show the
frame's default background, creating visual \"gaps\" in the gutter.

The filling loop ensures that every character slot in the margin is
explicitly assigned the `margin' face, preventing both bleed and gaps.

Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8

--- Preexisting independent bugs ---

PREEXISTING INDEPENDENT BUG 5 (discovered in this sequence): Margin
background bleed (GUI) or gaps (TTY).  When a margin is wider than one
character and contains an annotation shorter than that width, the
background of the \"empty\" portion of the margin is inconsistent.
Addressing this bug was within the scope of the current patch and
was resolved by replacing the previous minimal \"one-glyph\" logic
with robust filling loops in both GUI and TTY branches.
")
      (setq-local left-margin-width 4)
      (setq-local right-margin-width 12))
    (switch-to-buffer buf)
    (set-window-margins (selected-window) 4 12)
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        ;; Find the "Line 1" content line.
        (search-forward "\nLine 1\n")
        (forward-line -1)
        ;; 1. Annotate Left Margin (4 cols) with Cyan background '!'
        (let ((line 1))
          (while (< line 9)
            (when (= (% line 2) 1)
              (let ((ov (make-overlay (point) (1+ (point)))))
                (overlay-put
                 ov 'before-string
                 (propertize " " 'display
                             `((margin left-margin)
                               ,(propertize "!" 'face '(:foreground "red" :background "cyan")))))))
            (setq line (1+ line))
            (forward-line 1)))

        (goto-char (point-min))
        (search-forward "\nLine 1\n")
        (forward-line -1)
        ;; 2. Annotate Right Margin (12 cols) with Yellow 'Line 2'
        (dotimes (i 3)
          (let* ((bg (if (= i 1) "yellow" ln-bg))
                 (fg (if (= i 1) "black" "blue"))
                 (ov (make-overlay (point) (1+ (point)))))
            (overlay-put
             ov 'before-string
             (propertize " "
                         'display
                         `((margin right-margin)
                           ,(propertize (format "Line %d" (1+ i))
                                        'face `(:foreground ,fg
                                                            :background ,bg))))))
          (forward-line 1)))
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))))

;;; Test 005 — 'margin' face font attributes (:weight, :height); full explanation in the test buffer.

(defun face-margin-test-005 (&optional mode)
  "`margin' face font attributes: :weight bold and :height 2.0.
See test buffer for full explanation.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-005*")))
    (face-margin-test--apply-mode mode ln-bg)
    (when (and (facep 'margin) (eq mode 'themed))
      (set-face-attribute 'margin nil :weight 'bold :height 2.0))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-005: 'margin' as base face — font attributes and inheritance" mode))
      (insert "\
The 'margin' face is the base face for all margin content.  Font
attributes set on it propagate to annotation glyphs via inheritance.

This test sets :weight bold and :height 2.0 on the 'margin' face.

:weight bold — '!' annotation glyphs should appear bold.  Bold is a font-
variant attribute: it is realized within the margin and does not affect
the text area.

:height 2.0 — this attribute propagates to the annotation glyphs.  In
GUI frames, this is visually evident (the '!' character will appear taller).
In TTY frames, font height attributes are generally a no-op.

Expected: '!' glyphs are bold (and taller in GUI); line heights for the
rest of the text area remain uniform; no crash.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 006 — buffer-local 'margin' face isolation via face-remap-add-relative; full explanation in the test buffer.

(defun face-margin-test-006 (&optional mode)
  "Buffer-local `margin' face isolation via face-remap-add-relative.
See test buffer for full explanation.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  ;; Reset global 'margin' face so the right buffer shows a clear contrast.
  ;; The facep guard prevents a crash on unpatched builds.
  (when (facep 'margin) (set-face-background 'margin nil))
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf-l (get-buffer-create "*face-margin-test-006-local*"))
         (buf-g (get-buffer-create "*face-margin-test-006-global*")))
    ;; Populate both buffers with identical structure.
    (dolist (entry `((,buf-l "\
LEFT — buffer-local face-remap-add-relative (analogous to test 002)
",
                             "\
face-remap-add-relative sets the 'margin' background buffer-locally.
Behaves like test 002: margin matches line-number, no stripe below EOB.
The global 'margin' face is not modified.
")
                     (,buf-g "\
RIGHT — no override, global default (analogous to test 001)
",
                             "\
No face-remap-add-relative in this buffer.  Behaves like test 001: margin
reverts to frame background below EOB, producing the visible white stripe.
Global 'margin' face is unchanged.
")))
      (let ((buf   (nth 0 entry))
            (label (nth 1 entry))
            (desc  (nth 2 entry)))
        (with-current-buffer buf
          (read-only-mode -1)
          (erase-buffer)
          (insert (face-margin-test--mode-header mode))
          (insert (face-margin-test--title "face-margin-test-006: buffer-local 'margin' isolation" mode))
          (insert (format "%s\n%s\nLines 1–8 below:\n" label desc))
          (dotimes (i 8) (insert (format "Line %d\n" (1+ i))))
          (setq-local left-margin-width 1)
          (face-margin-test--annotate buf t)
          (display-line-numbers-mode 1)
          (read-only-mode 1)
          (goto-char (point-min)))))
    ;; Apply buffer-local remap only to the left buffer.
    (with-current-buffer buf-l
      (when (and (facep 'margin) (eq mode 'themed))
        (face-remap-add-relative 'margin :background ln-bg)))
    ;; Display side by side: left buffer in the current window, right in a split.
    (delete-other-windows)
    (switch-to-buffer buf-l)
    (set-window-margins (selected-window) 1 0)
    (let ((win-r (split-window-right)))
      (set-window-buffer win-r buf-g)
      (with-selected-window win-r
        (set-window-margins (selected-window) 1 0)))))

;;; Test 007 — horizontal scrolling; preexisting bugs documented in the test buffer.

(defun face-margin-test-007 (&optional mode)
  "Left margin during horizontal scrolling;
preexisting bugs documented in the test buffer."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-007*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-007: horizontal scrolling" mode))
      (insert "\
This test verifies that the left margin stays uniformly colored
during horizontal scrolling.  The left margin is a fixed area
pinned to the window edge: it does not scroll with the text.

Use C-e to scroll right to the end of a long line, C-a to return.

Expected (patched): left margin uniformly colored at all scroll
positions.  No stripe or redraw glitch.

Expected (unpatched): stripe visible in left margin below EOB.

"
              (make-string 120 ?A) "\n"
              (make-string 120 ?B) "\n"
              (make-string 120 ?C) "\n"
              (make-string 120 ?D) "\n"
              (make-string 120 ?E) "\n\n"
              "\
See also face-margin-test-007b for the same scenario without
display-line-numbers-mode.

--- Preexisting independent bugs surfaced by this test ---

Scrolling right exposes three bugs that are related to the area
covered by this patch but are out of scope and left unchanged.
They are documented here for two reasons:

- for the mere documentation purpose: the results of the present
  investigation are not lost, and it leaves open the possibility in the
  future to address these bugs with separate bug reports.

- to provide an explanation of certain visual inconsistencies in the
  layout that were preexisting this patch and independent of it.

PREEXISTING INDEPENDENT BUG 1 (TTY only): '!' annotations disappear
on horizontally scrolled lines.  This is independent of the '$'
indicator; it occurs because the display engine skips margin-bound
display properties during the initial hscroll seek phase.  By the time
the seek reaches the first visible text character, the margin content
has already been bypassed.  This bug exists in unpatched Emacs and has
not been addressed here.

PREEXISTING INDEPENDENT BUG 2: the left '$' indicator is rendered with
a hardcoded DEFAULT_FACE_ID in xdisp.c:insert_left_trunc_glyphs.  When a
theme gives 'line-number' a non-default background, '$' shows the
buffer default background instead — a visible inconsistency.  A proper
fix requires the function to detect the visual context (line numbers
or margins) and inherit the background of the element it abuts.

PREEXISTING INDEPENDENT BUG 3: display table remapping face loss.
In xdisp.c:produce_special_glyphs, the code path for mirrored
truncation glyphs (used for the left-edge indicator) initializes a
local face_id from the basic default face.  This local variable
effectively discards any face information specified in the display
table entry.  Additionally, the display table has only one
'truncation' slot shared by both edges, making independent styling
impossible.
")
      (setq-local left-margin-width 1)
      (setq-local truncate-lines t)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 007b — horizontal scrolling without line-number column; full explanation in the test buffer.

(defun face-margin-test-007b (&optional mode)
  "Horizontal scrolling without line-number column;
preexisting bugs documented in the test buffer."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-007b*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-007b: horizontal scrolling, no line-number column." mode))
      (insert "\
Same as test 007, but display-line-numbers-mode is disabled.
The left margin abuts the text area directly.

Use C-e to scroll right to the end of a long line, C-a to return.

Expected (patched): left margin uniformly colored at all scroll positions.

Expected (unpatched): stripe visible in left margin below EOB.

"
              (make-string 120 ?A) "\n"
              (make-string 120 ?B) "\n"
              (make-string 120 ?C) "\n"
              (make-string 120 ?D) "\n"
              (make-string 120 ?E) "\n\n"
              "\
--- Preexisting independent bugs (see test 007 for full details) ---

The same three preexisting bugs documented in test 007 apply here.
Notably: on TTY frames, '!' annotations disappear on horizontally
scrolled lines; and display table remapping has no effect on the
left-edge '$'.

The DEFAULT_FACE_ID background of '$' (bug 2 in test 007) is less
visually disruptive here: without a line-number column, '$' is
contiguous with the text area and its default background produces
a consistent appearance.
")
      (setq-local left-margin-width 1)
      (setq-local truncate-lines t)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      ;; display-line-numbers-mode intentionally NOT enabled here.
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 008 — RTL text; preexisting R2L margin bug documented in the test buffer.

(defun face-margin-test-008 (&optional mode)
  "RTL text with colored `margin' face;
preexisting R2L bug documented in the test buffer.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-008*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-008: RTL text" mode))
      (insert "\
This test mixes LTR and RTL (Hebrew) lines to verify that the left margin
is handled correctly for both text directions.  Odd lines receive a '!'
annotation (red); even lines receive a blank filler \" \" — both with an
explicit background matching the 'line-number' face, simulating what the
user would likely do to create a visually consistent style.

On LTR lines: odd lines show '!' in red, even lines show a gray filler.
The left margin column is uniformly colored.

On Hebrew (RTL) lines: see the bug note below.

")
      ;; odd  (line 11) — LTR, annotated
      (insert "This is a left-to-right (LTR) line.\n")
      ;; even (line 12) — Hebrew
      (insert "\u05D6\u05D5\u05D4\u05D9 \u05E9\u05D5\u05E8\u05D4 "
              "\u05DE\u05D9\u05DE\u05D9\u05DF \u05DC\u05E9\u05DE\u05D0\u05DC "
              "\u05D1\u05E2\u05D1\u05E8\u05D9\u05EA.\n")
      ;; odd  (line 13) — Hebrew, annotated: "Another right-to-left line"
      (insert "\u05E2\u05D5\u05D3 \u05E9\u05D5\u05E8\u05D4 \u05DE\u05D9\u05DE\u05D9\u05DF "
              "\u05DC\u05E9\u05DE\u05D0\u05DC.\n")
      ;; even (line 14) — LTR
      (insert "Another LTR line.\n")
      ;; odd  (line 15) — Hebrew, annotated
      (insert "\u05E9\u05D5\u05E8\u05D4 \u05E0\u05D5\u05E1\u05E4\u05EA "
              "\u05D1\u05E2\u05D1\u05E8\u05D9\u05EA.\n")
      ;; even (line 16) — LTR
      (insert "Yet another LTR line.\n\n")
      (insert "\
Expected: left margin uniformly colored for all rows.
No stripe below EOB.

PREEXISTING INDEPENDENT BUG 4: on RTL (Hebrew) rows, the left margin
area is rendered with the default face (black foreground, white
background) regardless of any overlay or 'margin' face customization.
The root cause appears to lie in the TTY renderer (dispnew.c and
term.c): while the display engine correctly produces margin glyphs
with the intended face for reversed rows, the TTY output phase appears
to neglect these faces when flattening the window matrix or
calculating the physical output.  This bug exists in unpatched Emacs
and has not been addressed here.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 009 — Flymake/Eglot-style margin indicators; full explanation in the test buffer.

(defun face-margin-test-009 (&optional mode)
  "Flymake/Eglot-style margin indicators.  See test buffer for full explanation.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-009*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-009: built-in Flymake margin indicators (Eglot/LSP style)" mode))
      (insert "\
This test simulates how Eglot (built-in LSP) displays diagnostics in
the margin using Flymake's display logic.

This scenario is technically identical to face-margin-test-003 (face
merging between the 'margin' face and a foreground-only overlay), but
validates the behavior for a 2-column margin, which is the standard width
for built-in diagnostic indicators.

Instead of running the full Flymake engine, we manually create an
overlay with the exact display property Flymake uses:

  '((margin left-margin) \"!!\")

The indicator face specifies only :foreground \"red\".

Expected (patched): the red '!!' indicator is correctly backgrounded by
the 'margin' face, blending into the gutter.

Expected (unpatched): the indicator shows the frame default
background (white), creating a visual break in the gutter.
")
      ;; Manual simulation of Flymake/LSP margin indicator
      (setq-local left-margin-width 2)
      (set-window-margins (selected-window) 2 0)

      (let ((ov (make-overlay (point-min) (1+ (point-min)))))
        (overlay-put ov 'before-string
                     (propertize " " 'display
                                 `((margin left-margin)
                                   ,(propertize "!!" 'face '(:foreground "red"))))))

      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (redisplay t)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 010 — Variable-pitch font interactions; full explanation in the test buffer.
;;
;; Four command-line entry points are provided, one per scenario:
;;
;;   (face-margin-test-010a)  -- `margin' inherits from `variable-pitch'
;;   (face-margin-test-010b)  -- `margin' uses :height 2.0
;;   (face-margin-test-010c)  -- `default' uses a variable-pitch font
;;   (face-margin-test-010d)  -- combined stress: `default' variable-pitch
;;                               AND `margin' :height 2.0 (sanity check that
;;                               the bug surfaced by 010c is not from the
;;                               margin stretch math)
;;
;; Each delegates to `face-margin-test--010', which is the shared worker.

(defvar face-margin-test--saved-default-family nil
  "Original :family of the `default' face, captured on first run of
`face-margin-test--010'.  Used to restore the frame default after
scenario 3 has mutated it.")

(defun face-margin-test--010 (mode scenario suffix)
  "Worker for `face-margin-test-010a/b/c/d'.
MODE is `themed' or `standard'.  SCENARIO is 1, 2, 3, or 4.  SUFFIX
is appended to the buffer name (e.g. \"a\", \"b\", \"c\", \"d\")."
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (vp-family (face-attribute 'variable-pitch :family nil 'default))
         (buf (get-buffer-create (format "*face-margin-test-010%s*" suffix))))
    ;; Capture the pristine default :family on first invocation so we can
    ;; revert scenario 3 on subsequent runs.
    (unless face-margin-test--saved-default-family
      (setq face-margin-test--saved-default-family
            (face-attribute 'default :family)))
    (face-margin-test--apply-mode mode ln-bg)
    ;; Reset attributes from prior runs so each invocation starts clean.
    (when (facep 'margin)
      (set-face-attribute 'margin nil
                          :family 'unspecified
                          :height 'unspecified
                          :inherit 'default))
    (when (stringp face-margin-test--saved-default-family)
      (set-face-attribute 'default nil
                          :family face-margin-test--saved-default-family))
    ;; Apply the chosen scenario in `themed' mode only.
    (when (eq mode 'themed)
      (pcase scenario
        (1 (when (facep 'margin)
             (set-face-attribute 'margin nil
                                 :inherit '(variable-pitch default))))
        (2 (when (facep 'margin)
             (set-face-attribute 'margin nil :height 2.0)))
        (3 (when (stringp vp-family)
             (set-face-attribute 'default nil :family vp-family)))
        (4 (when (stringp vp-family)
             (set-face-attribute 'default nil :family vp-family))
           (when (facep 'margin)
             (set-face-attribute 'margin nil :height 2.0)))))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title
               (format "face-margin-test-010%s: variable-pitch interactions (scenario %d)"
                       suffix scenario)
               mode))
      (insert
       (pcase scenario
         (1 "\
Scenario 1: the `margin' face inherits from `variable-pitch'.  The
frame `default' face is unchanged.
")
         (2 "\
Scenario 2: the `margin' face uses :height 2.0.  The frame `default'
face is unchanged.

This widens what test 005 already covered: 005 sets :height 2.0 on
a 1-column margin, where exactly one glyph fits and the stretch path
is not really tested.  Here the margin is 4 columns wide, so the
stretch glyph must fill columns 2-4 with the larger-height face.
")
         (3 "\
Scenario 3: the frame `default' face uses a variable-pitch font.
`margin' inherits from `default' and is therefore variable-pitch too.
")
         (4 "\
Scenario 4 (combined stress): the frame `default' face uses a
variable-pitch font AND the `margin' face uses :height 2.0.

This test exists as a sanity check on top of 010c.  In 010c we
observed an inconsistency in the line-number rendering (see the
`PREEXISTING INDEPENDENT BUG 6' note below); 010d amplifies the
margin's contribution by making margin glyphs 2x taller.  If the
line-number gap were caused by the margin stretch-glyph arithmetic,
this combined stress would amplify it.  If instead the gap looks
identical in shape and size to 010c, that confirms the gap is
unrelated to the margin code path.
")))
      (insert "\

The left margin is 4 columns wide.  Odd lines carry a single `!'
annotation in column 1 (foreground only).  Columns 2-4 are empty and
must be filled by the stretch glyph.  Even lines carry no glyph at
all — the full 4-column area relies on the stretch alone.

What to look for:

- The 4-column margin area is uniformly colored across its full width
  on every row (including `!' rows, empty rows, and the area below
  EOB).

- No fragment of the line-number column or frame-default background
  appears inside the margin (no \"gap\" from a too-narrow stretch).

- The `margin' background does not overflow into the line-number
  column (no \"overflow\" from a too-wide stretch).

The point of this test is to verify that the stretch math is
independent of the `margin' face's font metrics.  Compare against
test 003, which tests the same layout with the default font.

Lines below:
")
      (when (memq scenario '(3 4))
        (insert "\
--- Preexisting independent bugs surfaced by this test ---

PREEXISTING INDEPENDENT BUG 6 (surfaced by 010c, cross-checked by
010d): when the frame `default' face uses a variable-pitch font,
the `line-number' face background does not tile uniformly across
all rows.  Gaps appear where line-heights vary (e.g., on rows above
the first numbered line and on the cursor row onward), exposing
the white frame default through what should be a continuous gray
column.

This bug is in the `line-number' rendering path (text area, not
margin) and is independent of the `margin' face patch.  In this
buffer, the 4-column margin to the LEFT of the line-number column
remains uniformly colored on every row, confirming that the margin
fill is doing its job.

"))
      (when (= scenario 4)
        (insert "\
010d-specific note: comparing this buffer to 010c, the line-number
gap should look the same in shape and size despite margin glyphs
being 2x taller here.  That equivalence is the evidence ruling out
the margin stretch-glyph arithmetic as the cause.

"))
      (dotimes (i 8)
        (insert (format "Line %d\n" (1+ i))))
      (setq-local left-margin-width 4))
    (switch-to-buffer buf)
    (set-window-margins (selected-window) 4 0)
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (search-forward "Lines below:\n")
        (let ((line 1))
          (while (and (not (eobp)) (<= line 8))
            (when (= (% line 2) 1)
              (let ((ov (make-overlay (point) (1+ (point)))))
                (overlay-put
                 ov 'before-string
                 (propertize " " 'display
                             `((margin left-margin)
                               ,(propertize "!"
                                            'face '(:foreground "red")))))))
            (setq line (1+ line))
            (forward-line 1))))
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))))

(defun face-margin-test-010a (&optional mode)
  "Variable-pitch test, scenario 1: `margin' inherits from `variable-pitch'.
Optional MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--010 (or mode 'themed) 1 "a"))

(defun face-margin-test-010b (&optional mode)
  "Variable-pitch test, scenario 2: `margin' uses :height 2.0.
Optional MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--010 (or mode 'themed) 2 "b"))

(defun face-margin-test-010c (&optional mode)
  "Variable-pitch test, scenario 3: `default' uses a variable-pitch font.
Optional MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--010 (or mode 'themed) 3 "c"))

(defun face-margin-test-010d (&optional mode)
  "Variable-pitch test, scenario 4: combined stress.
`default' uses a variable-pitch font AND `margin' uses :height 2.0.
Sanity check that the line-number gap surfaced by 010c is not from
the margin stretch-glyph arithmetic.
Optional MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--010 (or mode 'themed) 4 "d"))

;;; Test 011 — Margin face on truncated rows; fix demo.

(defun face-margin-test-011 (&optional mode)
  "Margin face on truncated rows.

Demonstrates the fix for the margin-fill on truncated rows.  When
`truncate-lines' is non-nil and a buffer line is too long to fit
in the text area, the row's left and right margin areas now
inherit the `margin' face background.  Before the fix, they
reverted to the frame default background.

Optional MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-011*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title
               "face-margin-test-011: margin face not applied on truncated rows"
               mode))
      (insert "\
This test demonstrates the fix for margin-fill on truncated rows.

When `truncate-lines' is non-nil and a buffer line is too long to
fit in the text area, the row's left and right margin areas now
inherit the `margin' face background, just like non-truncated rows.
A truncation indicator appears at the right edge on those rows.

Setup: 4-column left margin, 4-column right margin, truncate-lines
enabled.  The buffer below alternates short lines (which do not
truncate) with long lines of repeated `L' characters (which do).

Expected (patched, themed mode): both 4-column margins are
uniformly gray on EVERY row, including the truncated ones.

Expected (unpatched, themed mode): short rows have gray margins;
truncated rows have white margins.  Before the fix, the row-extension
code path that fills the margin areas was only invoked from inside
the TTY/no-fringe arm of the truncation handling in `display_line';
on GUI frames with a non-zero fringe, that arm was bypassed.  The
fix lifts the margin-fill out of that arm and places it after the
if/else-if chain, so it runs uniformly for all three truncation
paths (TTY truncation glyph, GUI newline-overflow-into-fringe, and
GUI regular truncation where the indicator is drawn as a fringe
bitmap).

Lines below:
")
      (insert "Short line A\n")
      (insert "Short line B\n")
      (insert (make-string 200 ?L) "\n")
      (insert "Short line C\n")
      (insert (make-string 200 ?L) "\n")
      (insert "Short line D\n")
      (insert (make-string 200 ?L) "\n")
      (insert "Short line E\n")
      (setq-local left-margin-width 4)
      (setq-local right-margin-width 4)
      (setq-local truncate-lines t))
    (switch-to-buffer buf)
    (set-window-margins (selected-window) 4 4)
    (with-current-buffer buf
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))))

;;; Test 012 — SVG image in margin: background should inherit `margin' face.

(defun face-margin-test-012 (&optional mode)
  "SVG image in left margin: background should match `margin' face.

Reproducer for the follow-up issue reported by Juri Linkov on
bug#80693 after the `margin' face landed: SVG images placed in the
margin via overlays were rendered with the default-face background
instead of inheriting the `margin' face background, producing visible
\"holes\" in the gutter.

The fix lives in `handle_single_display_spec' (xdisp.c): when a
display spec lands in a margin area, the iterator's face id is reset
to the realized `margin' face before dispatching on the value's type,
so images, stretches and xwidgets all share the gutter background
that strings already inherited via `face_at_pos'.

Three lines, each carrying parallel annotations in BOTH the left and
right margins (same `outline-open.svg' on each side, same variant per
line).  The fix is symmetric — the C condition is `it->area !=
TEXT_AREA' — so left and right should behave identically.

  Line 1: bare image spec — demonstrates the basic fix.  Background
          must be the gutter gray; the SVG triangle is filled via
          `currentColor', which resolves to the `margin' face's
          foreground.  To make this verifiable, the test temporarily
          sets `margin' :foreground to BLUE — a colour neither the
          `default' face nor `line-number' uses under modus-operandi,
          so a blue triangle on line 1 is positive evidence that
          `currentColor' really did pick up the `margin' face.

  Line 2: image spec with `:foreground \"red\"' — demonstrates the
          documented channel for overriding a `currentColor' SVG's
          colour.  Background must still be the gutter gray; the
          triangle must be RED, overriding the `margin' face's blue.

  Line 3: carrier propertized with `face '(:foreground \"yellow\")',
          bare image spec — demonstrates a deliberate LIMITATION of
          the C fix.  Before the fix, the carrier's face flowed into
          `it->face_id' and reached `lookup_image', so a
          `currentColor' SVG would render yellow.  The fix overwrites
          `it->face_id' with the realized `margin' face, so the
          carrier's foreground is discarded; the triangle renders BLUE
          (margin's foreground), not yellow.  Packages that previously
          coloured a margin SVG via the carrier must move that intent
          onto the image spec (channel shown by line 2).

Expected (themed mode, FIX in place), each line shows the same
triangle in BOTH margins:
  Line 1: triangle BLUE   (margin's foreground)
  Line 2: triangle RED    (image-spec :foreground wins)
  Line 3: triangle BLUE   (carrier :foreground is ignored — limitation)

Expected (themed mode, FIX absent): line 1 shows a white square
inside the gray gutter (the bug).  Line 2 likely also shows the white
square: `:foreground' on the SVG only paints the path, not the
surrounding rectangle, so the wrong rectangle fill is independent of
the `:foreground' override.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (svg (image-search-load-path "outline-open.svg"))
         (buf (get-buffer-create "*face-margin-test-012*")))
    (face-margin-test--apply-mode mode ln-bg)
    ;; Make `margin' :foreground distinguishable from `default' so we
    ;; can see whether currentColor really resolves to the margin face.
    (when (and (facep 'margin) (eq mode 'themed))
      (set-face-foreground 'margin "blue"))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title
               "face-margin-test-012: SVG image in margin (bug#80693 follow-up)"
               mode))
      (insert "\
This buffer demonstrates a possible C-level fix for the SVG-in-margin
background inconsistency reported by Juri Linkov.  See the docstring
of `face-margin-test-012' for the full explanation.

Look at the three annotated lines below.  Each line carries the same
SVG in BOTH the left and right margin, to verify that the fix is
symmetric on left/right.  In themed mode the test sets `margin'
:foreground to BLUE so the source of `currentColor' is visible.

Line 1: bare SVG → triangle should be BLUE (margin's foreground)
Line 2: SVG with `:foreground \"red\"' on the spec → triangle RED
Line 3: carrier with `:foreground \"yellow\"', bare SVG → triangle
        BLUE (NOT yellow) — limitation of the C fix; the carrier
        face is no longer a usable method for SVG colour in margins
")
      (setq-local left-margin-width 2)
      (setq-local right-margin-width 2))
    (switch-to-buffer buf)
    (set-window-margins (selected-window) 2 2)
    (with-current-buffer buf
      (save-excursion
        (goto-char (point-min))
        (search-forward "Line 1: ")
        (beginning-of-line)
        ;; Line 1 — bare image spec, both margins.
        (let ((ov (make-overlay (point) (1+ (point)))))
          (overlay-put
           ov 'before-string
           (propertize " " 'display
                       `((margin left-margin)
                         ,(create-image svg)))))
        (let ((ov (make-overlay (point) (1+ (point)))))
          (overlay-put
           ov 'after-string
           (propertize " " 'display
                       `((margin right-margin)
                         ,(create-image svg)))))
        (forward-line 1)
        ;; Line 2 — image spec with :foreground "red", both margins.
        (let ((ov (make-overlay (point) (1+ (point)))))
          (overlay-put
           ov 'before-string
           (propertize " " 'display
                       `((margin left-margin)
                         ,(create-image svg nil nil
                                        :foreground "red")))))
        (let ((ov (make-overlay (point) (1+ (point)))))
          (overlay-put
           ov 'after-string
           (propertize " " 'display
                       `((margin right-margin)
                         ,(create-image svg nil nil
                                        :foreground "red")))))
        (forward-line 1)
        ;; Line 3 — carrier face :foreground "yellow", bare image spec,
        ;; both margins.  Demonstrates the limitation: the carrier face
        ;; is discarded by the C fix, so the triangle should render BLUE
        ;; on both sides, not yellow.
        (let ((ov (make-overlay (point) (1+ (point)))))
          (overlay-put
           ov 'before-string
           (propertize " "
                       'face '(:foreground "yellow")
                       'display
                       `((margin left-margin)
                         ,(create-image svg)))))
        (let ((ov (make-overlay (point) (1+ (point)))))
          (overlay-put
           ov 'after-string
           (propertize " "
                       'face '(:foreground "yellow")
                       'display
                       `((margin right-margin)
                         ,(create-image svg))))))
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))))

;;; Test 013 — flymake margin indicator: explicit `:inherit default'
;;;            overrides `margin' face background.

(defun face-margin-test-013 (&optional mode)
  "Real flymake margin indicator test (bug#80693 follow-up).

This test calls the real `flymake--bs-display' — the function
flymake.el uses to build its margin display spec — for each of the
three diagnostic types (error, warning, note) and renders the
returned spec as an overlay `before-string'.  No simulation: this
is the exact code path flymake-mode goes through to produce a
margin indicator.

The bug Juri Linkov reported: flymake's per-character face is built
as `:inherit (... default)'.  The `default' element of that chain
brings `default's :background into the realized face attributes.
When the displayed string is then merged on top of `MARGIN_FACE_ID'
via `face_at_string_position', the inherited :background wins — so
the indicator renders with the frame default background, not the
margin background.  The bug is independent of the SVG/image C fix
that landed for the image branch; it is in the string branch and
is purely a flymake.el issue.

Two side-by-side blocks share the same buffer:

  BUG block (lines 1-3): real `flymake--bs-display'.  In themed
    mode each indicator should appear with the frame default
    background (white), breaking the gutter's continuity.

  FIX block (lines 4-6): local mirror of `flymake--bs-display' with
    Juri's one-line change applied — `:inherit (... default)' →
    `:inherit (... margin)'.  Each indicator's background blends
    into the margin gutter.

Optional argument MODE is `themed' (default) or `standard'.
Interactively, Emacs prompts to choose between themed and standard."
  (interactive (list (if (eq (read-char-choice "Mode — [t]hemed or [s]tandard? " '(?t ?s)) ?s) 'standard 'themed)))
  (require 'flymake)
  (require 'compile)
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'themed))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-013*")))
    (face-margin-test--apply-mode mode ln-bg)
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title
               "face-margin-test-013: flymake margin indicator (bug#80693 follow-up)"
               mode))
      (insert "\
This buffer demonstrates the flymake-margin-background bug Juri Linkov
reported.  Each line below carries a real `flymake--bs-display'
indicator in the left margin (calling flymake's own code, not a
reproduction).  See the docstring of `face-margin-test-013' for the
full explanation.

BUG (current flymake): indicator background should match the gutter
                       gray; instead it shows the frame default.

  Line 1: flymake-error
  Line 2: flymake-warning
  Line 3: flymake-note

FIX (Juri's proposed flymake.el patch — `:inherit (... default)' →
     `:inherit (... margin)'): indicator blends into the gutter.

  Line 4: flymake-error
  Line 5: flymake-warning
  Line 6: flymake-note
")
      (setq-local left-margin-width 2))
    (switch-to-buffer buf)
    (set-window-margins (selected-window) 2 0)
    (with-current-buffer buf
      (cl-flet ((bs-display-fixed (type)
                  ;; Local mirror of `flymake--bs-display' with Juri's
                  ;; one-line change applied: `:inherit (... default)'
                  ;; → `:inherit (... margin)'.  Everything else is a
                  ;; verbatim copy of the relevant branch of
                  ;; flymake--bs-display.
                  (let* ((indicator (get type 'flymake-margin-string))
                         (value (if (symbolp indicator)
                                    (symbol-value indicator)
                                  indicator))
                         (valuelist (if (listp value) value (list value)))
                         (indicator-car (car valuelist)))
                    (when (and (stringp indicator-car)
                               flymake-margin-indicator-position)
                      `((margin ,flymake-margin-indicator-position)
                        ,(propertize indicator-car
                                     'face `(:inherit (,(cdr valuelist)
                                                       margin))))))))
        (save-excursion
          (goto-char (point-min))
          ;; BUG block — real flymake--bs-display.
          (search-forward "Line 1: ")
          (beginning-of-line)
          (dolist (type '(flymake-error flymake-warning flymake-note))
            (let ((spec (flymake--bs-display type 'margins)))
              (when spec
                (let ((ov (make-overlay (point) (1+ (point)))))
                  (overlay-put
                   ov 'before-string
                   (propertize "!" 'display spec)))))
            (forward-line 1))
          ;; FIX block — local mirror with Juri's change.
          (goto-char (point-min))
          (search-forward "Line 4: ")
          (beginning-of-line)
          (dolist (type '(flymake-error flymake-warning flymake-note))
            (let ((spec (bs-display-fixed type)))
              (when spec
                (let ((ov (make-overlay (point) (1+ (point)))))
                  (overlay-put
                   ov 'before-string
                   (propertize "!" 'display spec)))))
            (forward-line 1))))
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))))

(provide 'debug-left-margin)
;;; debug-left-margin.el ends here
