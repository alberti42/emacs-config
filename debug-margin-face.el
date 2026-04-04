;;; debug-left-margin.el --- Test suite for the 'margin' face patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive test suite for the Emacs patch that introduces the 'margin' face
;; (bug#80693).  Each test creates a dedicated buffer and configures specific
;; conditions so the reviewer can verify the expected visual outcome.
;;
;; These tests aim to demonstrate a typical usage case: a user wants to
;; configure the 'margin' face to match the background of the 'line-number'
;; area, creating a single, visually consistent gutter for both line numbers
;; and annotations.
;;
;; All tests use the built-in 'modus-operandi' theme (included with Emacs since
;; Emacs 28).  That theme gives the 'line-number' face a non-default background
;; out of the box, making it possible to demonstrate the inconsistency using
;; only components that ship with Emacs — no external packages or custom colors
;; are required.  The 'line-number' face is used strictly as a built-in
;; reference color for a themed gutter; it is not functionally linked to the
;; margins.
;;
;; Tests are callable from "emacs -Q" with the patched build:
;;
;;   emacs -Q --load /path/to/debug-left-margin.el \
;;             --eval "(face-margin-test-NNN)"
;;
;; Replace NNN with the test number (001 through 009, plus 007b).
;;
;; Tests 001 and 002 are paired: 001 shows the stripe bug using only built-in
;; components; 002 shows the fix by setting the 'margin' face background to
;; match 'line-number'.  Tests 003–009 cover additional scenarios and describe
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
MODE is `patched' (default) or `unpatched'.  In patched mode the
background is set to LN-BG; in unpatched mode it is cleared so
the pre-patch stripe is visible.  No-ops when the `margin' face
does not exist (unpatched builds)."
  (when (facep 'margin)
    (if (eq mode 'unpatched)
        (set-face-background 'margin nil)
      (set-face-background 'margin ln-bg))))

(defun face-margin-test--mode-header (mode)
  "Return a warning string if the build is unpatched."
  (if (not (facep 'margin))
      (let ((msg (if (eq mode 'unpatched)
                     "\
WARNING: you are running on an unpatched version of Emacs.  The tests will be
carried out nonetheless to demonstrate Emacs' behavior before applying the patch."
                   "\
WARNING: you are running on an unpatched version of Emacs.  Your request
to execute tests in `patched' mode cannot be fulfilled with the currently
unpatched Emacs. Falling back to unpatched behavior.")))
        (message "%s" msg)
        (concat msg "\n\n"))
    ""))

(defun face-margin-test--title (title mode)
  "Return TITLE with a running mode indicator appended on the same line.
The effective mode is determined by MODE and whether the `margin' face exists."
  (let ((patched (and (eq mode 'patched) (facep 'margin))))
    (format "%s - running in %s mode (%s)\n\n"
            title
            (if patched "`patched'" "`unpatched'")
            (if patched "showing the fix" "showing pre-patch behavior"))))

;;; Test 001 — stripe bug demo; full explanation in the test buffer.

(defun face-margin-test-001 ()
  "Stripe bug demo: `margin' face left uncustomized.
See test buffer for full explanation."
  (interactive)
  (face-margin-test--load-theme)
  (let* ((mode 'unpatched)
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
  (let* ((mode 'patched)
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

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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

Optional argument MODE is `patched' (default) or `unpatched'."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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
  "`margin' face font attributes: :weight bold and :height 1.5.
See test buffer for full explanation.

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
         (ln-bg (face-background 'line-number nil t))
         (buf (get-buffer-create "*face-margin-test-005*")))
    (face-margin-test--apply-mode mode ln-bg)
    (when (and (facep 'margin) (eq mode 'patched))
      (set-face-attribute 'margin nil :weight 'bold :height 1.5))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert (face-margin-test--mode-header mode))
      (insert (face-margin-test--title "face-margin-test-005: 'margin' as base face — font attributes and inheritance" mode))
      (insert "\
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

;;; Test 006 — buffer-local 'margin' face isolation via face-remap-add-relative; full explanation in the test buffer.

(defun face-margin-test-006 (&optional mode)
  "Buffer-local `margin' face isolation via face-remap-add-relative.
See test buffer for full explanation.

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  ;; Reset global 'margin' face so the right buffer shows a clear contrast.
  ;; The facep guard prevents a crash on unpatched builds.
  (when (facep 'margin) (set-face-background 'margin nil))
  (let* ((mode (or mode 'patched))
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
      (when (and (facep 'margin) (eq mode 'patched))
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
preexisting bugs documented in the test buffer.

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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
preexisting bugs documented in the test buffer.

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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
  "Flymake/Eglot-style margin indicators.
See test buffer for full explanation.

Optional argument MODE is `patched' (default) or `unpatched'.
Interactively, Emacs prompts to choose between patched and unpatched."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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

(provide 'debug-left-margin)
;;; debug-left-margin.el ends here
