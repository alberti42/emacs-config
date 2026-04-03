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

(defun face-margin-test--apply-mode (mode ln-bg)
  "Set or clear the 'margin' face background depending on MODE.
MODE is 'patched (default) or 'unpatched.  In patched mode the
background is set to LN-BG; in unpatched mode it is cleared so
the pre-patch stripe is visible.  No-ops when the 'margin' face
does not exist (unpatched builds)."
  (when (facep 'margin)
    (if (eq mode 'unpatched)
        (set-face-background 'margin nil)
      (set-face-background 'margin ln-bg))))

(defun face-margin-test--mode-header (mode)
  "Return a warning string if MODE is 'patched but the build is unpatched.
Returns an empty string when no warning is needed."
  (if (and (eq mode 'patched) (not (facep 'margin)))
      (let ((msg "WARNING: you selected 'patched mode but this Emacs build is not patched. Falling back to unpatched behavior."))
        (message "%s" msg)
        (concat msg "\n\n"))
    ""))

(defun face-margin-test--title (title mode)
  "Return TITLE with a running mode indicator appended on the same line.
The effective mode is determined by MODE and whether the 'margin' face exists."
  (let ((patched (and (eq mode 'patched) (facep 'margin))))
    (format "%s - running in %s mode (%s)\n\n"
            title
            (if patched "PATCHED" "UNPATCHED")
            (if patched "showing the fix" "showing pre-patch behavior"))))

;;; Test 001 — bug demo: modus-operandi stripe with no 'margin' face set
;;
;; Always shows the stripe regardless of MODE: the 'margin' face is cleared
;; unconditionally so the bug is visible on both patched and unpatched builds.
;; The mode parameter is accepted for API consistency and to provide build-status
;; warnings on unpatched builds.

(defun face-margin-test-001 (&optional mode)
  "Bug demo: modus-operandi + left margin, 'margin' face NOT customized.

Uses only built-in components: the modus-operandi theme (shipped with
Emacs) colors the 'line-number' face.  The left margin is reserved and
all lines are annotated.  The 'margin' face is left at its default
(inherits the frame background).

This test always shows the bug regardless of MODE: it is designed to
demonstrate the pre-patch stripe and does not depend on whether Emacs
is patched or not.

Expected: a colored stripe is visible in the line-number column below the
last line of text, but the left margin column below EOB reverts to the
frame default background — an inconsistency within the same gutter area."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
         (buf (get-buffer-create "*face-margin-test-001*")))
    ;; Always clear the 'margin' face — this is the bug scenario.
    ;; The facep guard prevents a crash on unpatched builds.
    (when (facep 'margin) (set-face-background 'margin nil))
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

As an example, we marked odd lines with a red "!" indication.  The
background face is chosen to match the face background of 'line-number'.
The even rows are filled with " " with the same background face.

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

;;; Test 002 — fix demo: same as 001 but 'margin' face set to match line-number
;;
;; Expected: the left margin column and the line-number column share the same
;; background throughout the window, including below the last line of text.
;; No stripe.

(defun face-margin-test-002 (&optional mode)
  "Fix demo: modus-operandi + left margin + 'margin' face set to 'line-number'.

Same setup as face-margin-test-001.  Additionally sets the 'margin' face
background to match the 'line-number' background from modus-operandi, using:

  (set-face-background \\='margin (face-background \\='line-number nil t))

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected (patched): the left margin column and the line-number column share
the same background color throughout the window, including below EOB.  No stripe.
Expected (unpatched): the 'margin' face is not set; the stripe remains visible.
On an unpatched build, the face does not exist and the call is skipped safely."
  (interactive (list (if (eq (read-char-choice "Mode — [p]atched or [u]npatched? " '(?p ?u)) ?u) 'unpatched 'patched)))
  (face-margin-test--load-theme)
  (let* ((mode (or mode 'patched))
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

;;; Test 003 — overlay with foreground only; 'margin' background shows through
;;
;; Expected: overlay sets only a foreground color (no :background).  The
;; 'margin' face background fills all margin cells, including those where
;; the annotation glyph has no background of its own.

(defun face-margin-test-003 (&optional mode)
  "Test: overlay with :foreground only — 'margin' background shows through.

Annotations specify only :foreground \"red\" (no :background).  The
'margin' face is set to the modus-operandi 'line-number' background.

Without the fix, annotated cells (odd lines) show the frame default
background (white) while unannotated cells show the 'margin' background
— inconsistent.

With the fix, the 'margin' face becomes the base face for all margin
display-spec glyphs.  Unspecified attributes (background) are inherited
from 'margin', so all cells — annotated or not — show the same background.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected (patched): entire left margin column uniformly colored.
'!' glyphs appear in red against that background.  No stripe below EOB.
Expected (unpatched): annotated cells (odd lines) show frame default
background; unannotated cells show 'margin' background — inconsistent."
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
      (insert (face-margin-test--title "face-margin-test-003: overlay foreground only, 'margin' background shows through" mode))
      (insert "\
Annotations set only :foreground (red); no :background is provided.
The 'margin' face background should fill all margin cells uniformly.

Expected (patched): entire left margin column uniformly colored.
'!' glyphs appear in red against that background.  No stripe below EOB.
Expected (unpatched): annotated cells show frame default background;
unannotated cells show 'margin' background — inconsistent stripe.
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

(defun face-margin-test-004 (&optional mode)
  "Test: org-mode list items, visual-wrap-prefix-mode, right margin for 75 cols.

Simulates the technique used by focus/centering packages such as
olivetti, visual-fill-column, writeroom-mode, and darkroom: the right
window margin is sized so the text area is exactly 75 columns wide,
constraining line length without inserting newlines.

  right-margin = (max 0 (- (window-total-width) 1 75))

These packages use the margin as empty layout padding — they do NOT
write content into it.  Writing actual glyphs into the right margin
via display properties (the right-margin equivalent of git-gutter) is
a distinct scenario not covered here.

visual-line-mode soft-wraps long lines at the right margin.
visual-wrap-prefix-mode adds a hanging indent to continuation lines of
list items, so wrapped items look correctly indented.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected (patched): list items wrap with a hanging indent.  Both margin
areas are uniformly colored throughout the window.  No stripe below EOB.
Expected (unpatched): stripe visible in both margin areas below EOB."
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
This test simulates the technique used by focus/centering packages
such as olivetti, visual-fill-column, writeroom-mode, and darkroom:
the right window margin is reserved as empty layout padding to
constrain the text area to 75 columns.  These packages do NOT write
content into the margin — writing actual glyphs into the right margin
is a distinct scenario not covered by this test.  visual-line-mode
soft-wraps long lines at the right boundary; visual-wrap-prefix-mode
adds a hanging indent to continuation lines of list items so that
wrapped entries look correct.

See face-margin-test-004b for a complementary test that writes actual
annotation glyphs into both the left and right margins simultaneously.

Content below is adapted from
https://www.gnu.org/software/emacs/documentation.html

Expected (patched): list items wrap with a hanging indent.  Both margin
areas are uniformly colored.  No stripe below EOB.
Expected (unpatched): stripe visible in both margin areas below EOB.

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

;;; Test 004b — content placed in the right margin
;;
;; Places "Line 1", "Line 2", "Line 3" as glyphs in the right margin on the
;; first three lines; the remaining lines leave the right margin empty.
;; Expected: the right margin is uniformly colored from the 'margin' face
;; background on all lines, whether or not a glyph is present.

(defun face-margin-test-004b (&optional mode)
  "Test: content placed in the right margin via display property.

Places \"Line 1\", \"Line 2\", \"Line 3\" in the right margin on the first
three lines.  The remaining lines leave the right margin empty.  The left
margin is annotated the same way as in test 001–003: odd lines show \"!\"
in red, even lines a blank filler.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected (patched): both margin areas uniformly colored.  Annotated and
unannotated cells share the same background.  No stripe below EOB.
Expected (unpatched): stripe visible in both margin areas below EOB."
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
      (insert (face-margin-test--title "face-margin-test-004b: content in the right margin." mode))
      (insert "\
The right margin is reserved and the first three lines receive a label
glyph (\"Line 1\", \"Line 2\", \"Line 3\") placed there via a display
property with (margin right-margin).  The remaining lines leave the
right margin empty.  The left margin is annotated with git-gutter-style
indicators: odd lines show \"!\" in red, even lines a blank filler.

Expected (patched): both margin areas uniformly colored.  Annotated and
unannotated cells share the same background.  No stripe below EOB.
Expected (unpatched): stripe visible in both margin areas below EOB.

Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8
")
      (setq-local left-margin-width 1)
      (setq-local right-margin-width 8))
    (switch-to-buffer buf)
    (set-window-margins (selected-window) 1 8)
    (with-current-buffer buf
      ;; Annotate the first three lines in the right margin.
      (save-excursion
        (goto-char (point-min))
        ;; Skip the preamble — find the "Line 1" content line.
        (search-forward "\nLine 1\n")
        (forward-line -1)
        (dotimes (i 3)
          (let ((ov (make-overlay (point) (1+ (point)))))
            (overlay-put
             ov 'before-string
             (propertize " "
                         'display
                         `((margin right-margin)
                           ,(propertize (format "Line %d" (1+ i))
                                        'face `(:foreground "blue"
                                                :background ,ln-bg))))))
          (forward-line 1)))
      (face-margin-test--annotate buf t)
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

(defun face-margin-test-005 (&optional mode)
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

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Verify: '!' glyphs appear bold; line heights are uniform; text area is
unaffected; no crash."
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

(defun face-margin-test-006 (&optional mode)
  "Test: buffer-local 'margin' face via face-remap-add-relative.

Opens two windows side by side.  Both buffers have identical content,
line numbers, and margin annotations.  Only the left buffer calls
face-remap-add-relative to set a buffer-local 'margin' background.
The global 'margin' face is not modified.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected: the left buffer shows a colored margin; the right buffer
shows the default (frame background) margin.  The isolation is
immediately visible without switching buffers manually."
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
          (insert (face-margin-test--mode-header mode))
          (insert (face-margin-test--title "face-margin-test-006: buffer-local 'margin' isolation" mode))
          (insert (format "%s\n\n%s\n\nLines 1–8 below:\n" label desc))
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

;;; Test 007 — horizontal scrolling
;;
;; The left margin is a fixed area that does not participate in horizontal
;; scrolling.  Use C-e / C-a to scroll right and left.  The buffer text
;; documents three preexisting independent bugs visible in this scenario.

(defun face-margin-test-007 (&optional mode)
  "Test: left margin and '$' truncation indicator colored during horizontal scroll.

The left margin is a fixed area pinned to the window edge: it does not
scroll with the text.  When the window is scrolled right (use C-e to
reach the end of a long line, C-a to return), Emacs places a '$'
truncation indicator at the left edge of the text area to signal that
content is hidden to the left.

This patch makes the '$' indicator inherit the 'line-number' face
background (via insert_left_trunc_glyphs in xdisp.c), so it blends with
the line-number column that occupies the same visual area.  'line-number'
is the correct choice: '$' lives in TEXT_AREA, just like line numbers.

PREEXISTING INDEPENDENT BUG (TTY only): on TTY frames, the '$'
indicator and the '!' annotation both occupy the left edge of the text
area, so '$' overwrites '!' on scrolled lines.  This bug exists in
unpatched Emacs and has not been addressed here; it requires a
dedicated patch.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected (patched): left margin remains uniformly colored at all scroll
positions.  No stripe or redraw glitch.
Expected (unpatched): stripe visible in the left margin below EOB."
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
They are documented here so that reviewers understand the
inconsistencies they observe, and so that each can be tracked
and addressed in the future with a separate dedicated discussion
(new bug report) and patch.

PREEXISTING INDEPENDENT BUG 1 (TTY only): '!' annotations disappear
on horizontally scrolled lines.  '$' is placed in TEXT_AREA[0] while
'!' lives in LEFT_MARGIN_AREA — different areas, so there is no direct
overwriting.  The likely cause is that the TTY renderer skips
LEFT_MARGIN_AREA entirely for rows flagged truncated_on_left_p.  This
may be intentional, but it is poor design: the left margin is a fixed
area and should remain visible regardless of scroll position.

PREEXISTING INDEPENDENT BUG 2: the left '$' indicator is always
rendered with DEFAULT_FACE_ID in insert_left_trunc_glyphs, regardless
of the visual context.  When a theme gives 'line-number' a non-default
background, '$' shows the buffer default background instead — a visible
inconsistency.  A proper fix must determine the correct face based on
what is actually displayed at that position (line numbers, margins).

PREEXISTING INDEPENDENT BUG 3: display table remapping does not work
for the left-edge '$'.  In produce_special_glyphs, the mirroring code
path for L2R left-edge glyphs discards both the character and the face
from the display table glyph code when no bidi mirror is found.
Additionally, the display table has only one 'truncation' slot shared
by both edges, making independent left/right styling impossible.
")
      (setq-local left-margin-width 1)
      (setq-local truncate-lines t)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 007b — horizontal scrolling WITHOUT display-line-numbers-mode
;;
;; Same as test 007 but with no line-number column.  The left margin abuts
;; the text area directly.  Bug 2 (left '$' uses DEFAULT_FACE_ID) is still
;; visible: '$' now contrasts with the 'margin' face immediately to its
;; left with no line-number column in between.

(defun face-margin-test-007b (&optional mode)
  "Test: horizontal scrolling — left margin only, no line-number column.

Same scenario as face-margin-test-007 but with display-line-numbers-mode
disabled.  The left margin abuts the text area directly; there is no
line-number column between them.

Use C-e to scroll right to the end of a long line, C-a to return.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched.

Expected (patched): left margin uniformly colored at all scroll positions.
Expected (unpatched): stripe visible in left margin below EOB."
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

;;; Test 008 — RTL text
;;
;; Expected: with right-to-left paragraph direction the margin areas are
;; still colored correctly.  No stripe, no reversed-row glitch.
;;
;; PREEXISTING INDEPENDENT BUG: the left margin area of R2L rows is
;; rendered with the default face (black on white) regardless of any
;; overlay or 'margin' face customization.  Not addressed by this patch.

(defun face-margin-test-008 (&optional mode)
  "Test: RTL text with colored 'margin' face.

Inserts a mix of LTR and RTL (Hebrew) lines.  Expected: the left margin
area is uniformly colored for both LTR and RTL rows.  No stripe below EOB.

Optional argument MODE is 'patched (default) or 'unpatched.
Interactively, Emacs will prompt to choose between patched and unpatched."
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
This test mixes LTR and RTL (Hebrew) lines to verify that the
left margin is handled correctly for both text directions.
Odd lines receive a '!' annotation (red); even lines receive a
blank filler \" \" — both with an explicit background matching the
'line-number' face, as git-gutter-style packages would do.

On LTR lines: odd lines show '!' in red, even lines show a
gray filler.  The left margin column is uniformly colored.

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

PREEXISTING INDEPENDENT BUG: on RTL (Hebrew) rows, the left margin
area is rendered with the default face (black foreground, white
background) regardless of any overlay or 'margin' face customization.
The root cause is likely that the display engine does not properly
handle LEFT_MARGIN_AREA for reversed (R2L) glyph rows.  This bug
exists in unpatched Emacs and has not been addressed here; it
requires a dedicated patch.
")
      (setq-local left-margin-width 1)
      (face-margin-test--setup-window buf)
      (face-margin-test--annotate buf t)
      (display-line-numbers-mode 1)
      (read-only-mode 1)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

;;; Test 009 — built-in Flymake (LSP-style) margin indicators
;;
;; This test uses the built-in Flymake engine to display a diagnostic error
;; in the left margin, exactly as Eglot (built-in LSP) does when configured
;; to use margins.

(defun face-margin-test-009 (&optional mode)
  "Test: built-in Flymake (LSP-style) margin indicators.

Simulates how Eglot/LSP display diagnostics in the margin using
built-in Flymake logic.

Expected (patched): the Flymake '!!' (error) indicator is correctly
backgrounded by the 'margin' face.
Expected (unpatched): the Flymake indicator has the frame default
background, creating a stripe if 'margin' is colored."
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
This test uses the built-in Flymake engine to display a diagnostic
error in the left margin, exactly as Eglot (built-in LSP) does.

Configured via:

  (setq-local flymake-margin-indicator-position 'left-margin)

Expected (patched): the Flymake error indicator blends perfectly with the
colored margin background.
Expected (unpatched): the indicator shows the frame default
background (white), causing a visual break in the gutter.
")
      ;; Configure Flymake for margins
      (setq-local flymake-margin-indicator-position 'left-margin)
      (setq-local left-margin-width 2)

      ;; Add a dummy backend that reports an error on line 15
      (let ((backend (lambda (report-fn &rest _)
                       (funcall report-fn
                                (list (flymake-make-diagnostic
                                       (current-buffer)
                                       (line-beginning-position 15)
                                       (line-end-position 15)
                                       :error "Dummy LSP error"))))))
        (add-hook 'flymake-diagnostic-functions backend nil t))

      (face-margin-test--setup-window buf)
      (flymake-mode 1)
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
