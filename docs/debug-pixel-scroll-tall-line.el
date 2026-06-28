;;; debug-pixel-scroll-tall-line.el --- Demo for the bug#64252 tall-line patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive demo / reproducer for bug#64252: `pixel-scroll-precision-mode'
;; jumps and snaps back instead of gliding when it scrolls toward a display
;; line much taller than a normal line -- an inline image, or an image glued
;; on with an overlay before/after-string (the markdown-ts `"\n " + image'
;; idiom).
;;
;; The core defect is in the C primitive `window-text-pixel-size'.  To find a
;; new `window-start' a few pixels up, pixel-scroll asks it to measure the
;; pixel span *just above* the current top of the window, using the backward
;; form:
;;
;;     (window-text-pixel-size nil (cons START (- DELTA)) START nil nil nil t)
;;
;; A before/after-string anchored *at* START is displayed AT START (it belongs
;; to START's own line, inside the window), so it must NOT be counted in the
;; span above START.  Without the patch it is counted: the measured height
;; balloons to the whole tall line, pixel-scroll sets a large `vscroll' to
;; compensate, and the view lunges -- and because the next measurement repeats
;; the mistake, it snaps back and re-traverses the same image.
;;
;; The patch teaches `window-text-pixel-size' to recognise such a boundary
;; string and exclude it, exactly as it already excludes a display-property
;; image at the boundary.
;;
;; This file provides three tests:
;;
;;   - `pixel-scroll-tall-line-test-001'  The defect itself, measured live.
;;                                         Runs the backward measurement with
;;                                         and without a tall boundary string,
;;                                         prints the numbers, and tells you
;;                                         whether THIS build is patched.  No
;;                                         scrolling, no image support needed.
;;
;;   - `pixel-scroll-tall-line-test-002'  The visible symptom: scroll a tall
;;                                         after-string image up toward the top
;;                                         and watch it lurch (unpatched) or
;;                                         glide (patched).  Needs a GUI frame
;;                                         with image support.
;;
;;   - `pixel-scroll-tall-line-test-003'  Control: the SAME image attached as a
;;                                         `display' property on a real
;;                                         character.  This path was always
;;                                         measured correctly, so it scrolls
;;                                         smoothly with or without the patch --
;;                                         it isolates what the patch changes.
;;
;; Run from "emacs -Q" with the build you want to check:
;;
;;   emacs -Q --load /path/to/debug-pixel-scroll-tall-line.el \
;;             --eval "(pixel-scroll-tall-line-test-001)"
;;   emacs -Q --load /path/to/debug-pixel-scroll-tall-line.el \
;;             --eval "(pixel-scroll-tall-line-test-002)"
;;
;; Test 001 is build-agnostic: it auto-detects and explains.  It even works in
;; a terminal ("-nw"), where the numbers are in character-cell units instead of
;; pixels.  Tests 002 and 003 want a graphical frame.

;;; Code:

(require 'pixel-scroll)

;;; Helpers ------------------------------------------------------------------

(defun pixel-scroll-tall-line-test--backward-height (pos)
  "Pixel height of the span ending at POS, measured one unit backward.
This is the exact call pixel-scroll uses to size the slice of content
just above the top of the window."
  (nth 1 (window-text-pixel-size nil (cons pos -1) pos nil nil nil t)))

(defun pixel-scroll-tall-line-test--tall-image (height)
  "Return a display string showing a HEIGHT-pixel tall block.
Uses an SVG image when available, else falls back to a stack of block
characters (still a tall display element, just less pretty)."
  (if (image-type-available-p 'svg)
      (propertize
       " " 'display
       (create-image
        (format
         "<svg xmlns='http://www.w3.org/2000/svg' width='220' height='%d'>\
<rect width='100%%' height='100%%' rx='8' fill='#5b9bd5'/>\
<text x='12' y='28' font-size='20' fill='white'>tall image (%dpx)</text>\
</svg>"
         height height)
        'svg t))
    (mapconcat #'identity
               (make-list (max 1 (/ height (frame-char-height)))
                          "███████████████  (tall fallback block)")
               "\n")))

;;; Test 001 -- the measurement, with a live verdict ------------------------

(defun pixel-scroll-tall-line-test-001 ()
  "Measure the defect directly and report whether THIS build is patched.

Builds a small buffer, then measures the backward span ending on one of
its lines three ways: with nothing special there, with a tall
before-string anchored there, and with a tall after-string anchored
there.  A boundary string is displayed AT that line, so it must not
change the measured span above it.

Without the patch the before/after numbers are larger than the plain
one (the tall string leaked in).  With the patch all three are equal."
  (interactive)
  (let ((buf (get-buffer-create "*pixel-scroll-tall-line-test-001*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      ;; Lay down plain sample lines and measure on them first.
      (dotimes (i 8) (insert (format "sample line %d\n" i)))
      (switch-to-buffer buf)
      (redisplay t)
      (let* ((to (save-excursion (goto-char (point-min)) (forward-line 4) (point)))
             (str "boundary\nstring\nthree\nlines\n") ; a deliberately tall string
             (h-plain (pixel-scroll-tall-line-test--backward-height to))
             (h-before
              (let ((ov (make-overlay to to)) h)
                (overlay-put ov 'before-string str)
                (redisplay t)
                (setq h (pixel-scroll-tall-line-test--backward-height to))
                (delete-overlay ov) h))
             (h-after
              (let ((ov (make-overlay to to)) h)
                (overlay-put ov 'after-string str)
                (redisplay t)
                (setq h (pixel-scroll-tall-line-test--backward-height to))
                (delete-overlay ov) h))
             (patched (and (= h-before h-plain) (= h-after h-plain)))
             (unit (if (display-graphic-p) "px" "cell-units")))
        (erase-buffer)
        (insert (format "\
pixel-scroll-tall-line-test-001 -- the defect, measured on THIS build
=====================================================================

VERDICT: this Emacs build appears to be  %s.

What was measured
-----------------
The backward span ending at the start of \"sample line 4\", i.e. the
slice of content just ABOVE that line, measured with the exact call
pixel-scroll uses:

    (window-text-pixel-size nil (cons POS -1) POS nil nil nil t)

three times: plain, then with a tall before-string anchored at POS,
then with a tall after-string anchored at POS.  A string anchored at
POS is displayed AT POS (it is part of that line, shown inside the
window), so it must NOT enlarge the span measured ABOVE POS.

Results (in %s)
-----------------------
    plain                       : %d
    with tall before-string     : %d   %s
    with tall after-string      : %d   %s

How to read it
--------------
  * WITHOUT the patch the before/after numbers are LARGER than plain --
    the tall boundary string was wrongly folded into the slice above
    the line.  That over-measurement is what makes pixel-scroll set a
    big `vscroll' and lurch, then snap back and re-traverse the image.

  * WITH the patch all three numbers are EQUAL: the boundary string is
    excluded, just like a display-property image already was.

This is exactly the assertion in the regression test
`xdisp-tests--window-text-pixel-size-backward-boundary-string'
(test/src/xdisp-tests.el): on an unpatched build it fails with, e.g.,
`:form (equal 4 1)'.

Re-run with `M-x pixel-scroll-tall-line-test-001'.
See `pixel-scroll-tall-line-test-002' for the visible scrolling symptom."
                        (if patched "PATCHED (boundary string excluded)"
                          "UNPATCHED (boundary string counted)")
                        unit
                        h-plain
                        h-before (if (= h-before h-plain) "(equal -> good)"
                                   "(larger -> BUG)")
                        h-after  (if (= h-after h-plain) "(equal -> good)"
                                   "(larger -> BUG)")))
        (goto-char (point-min))
        (read-only-mode 1)))
    (switch-to-buffer buf)))

;;; Test 002 -- the visible scrolling symptom -------------------------------

(defun pixel-scroll-tall-line-test-002 ()
  "Scroll a tall after-string image toward the top and watch the behavior.

This is the user-visible symptom.  A tall image is attached as an
overlay after-string on a line partway down the buffer (the markdown-ts
idiom).  Enable a slow trackpad/wheel scroll upward and bring that image
toward the top of the window.

  * WITHOUT the patch: as the image reaches the top the view jumps onto
    it and snaps back, re-traversing it -- you cannot carry it smoothly
    off the top.

  * WITH the patch: the image is revealed once, smoothly, and scrolling
    continues past it.

Note: the fully smooth result also relies on the two Lisp commits in the
series (forcing the window start); this test shows the combined,
user-visible behavior.  Test 001 isolates the C measurement precisely."
  (interactive)
  (let ((buf (get-buffer-create "*pixel-scroll-tall-line-test-002*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (unless (display-graphic-p)
        (insert "\
NOTE: you are in a terminal frame.  Image display and pixel-precise
scrolling are limited here; run this test in a GUI frame for the real
effect.  (Test 001 works fine in the terminal.)

"))
      (insert "\
pixel-scroll-tall-line-test-002 -- the visible symptom
======================================================

A tall image is attached below as an overlay after-string (\"\\n \" +
image), the way markdown-ts shows inline images.  `pixel-scroll-precision-mode'
is enabled in this buffer.

Try this:

  1. Put point near the bottom and scroll UP slowly with the trackpad
     (or the mouse wheel) so the image rises toward the top of the window.

  2. WITHOUT the patch: as the image reaches the top, the view lunges
     onto it and snaps back, traversing the image twice; near the very
     top it will not settle.

  3. WITH the patch: the image is revealed once and scrolling glides on.

Scroll back and forth across the image a few times -- the defect is most
obvious when the image is crossing the top edge.

(If you also want the low-level proof, run
 M-x pixel-scroll-tall-line-test-001.)

----------------------------------------------------------------------
")
      (dotimes (i 30) (insert (format "filler line %02d -- scroll me\n" i)))
      (let ((anchor (point)))
        (insert "=== the tall image is anchored at the end of THIS line ===\n")
        (let ((ov (make-overlay (1- (point)) (1- (point)))))
          (overlay-put ov 'after-string
                       (concat "\n " (pixel-scroll-tall-line-test--tall-image 200))))
        (ignore anchor))
      (dotimes (i 30) (insert (format "filler line %02d -- scroll me\n" (+ i 30))))
      (pixel-scroll-precision-mode 1)
      (goto-char (point-max)))
    (switch-to-buffer buf)))

;;; Test 003 -- the control (display property, always correct) --------------

(defun pixel-scroll-tall-line-test-003 ()
  "Control: the same image as a `display' property on a real character.

A display-property image at the window-start boundary was ALWAYS measured
correctly (walking onto it overshoots, and existing code backs off).  So
this case scrolls smoothly with or without the patch -- it shows what the
patch does NOT need to change, and confirms the defect is specific to
overlay before/after-strings."
  (interactive)
  (let ((buf (get-buffer-create "*pixel-scroll-tall-line-test-003*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (unless (display-graphic-p)
        (insert "NOTE: run in a GUI frame for image display.\n\n"))
      (insert "\
pixel-scroll-tall-line-test-003 -- the control (display property)
=================================================================

Here the tall image is a `display' property on a real character (not an
overlay before/after-string).  Scroll up across it as in test 002.

Expected: smooth on BOTH patched and unpatched builds.  This is the
case the old code already handled, so it isolates the difference: only
the before/after-string path (test 002) misbehaves without the patch.

----------------------------------------------------------------------
")
      (dotimes (i 30) (insert (format "filler line %02d -- scroll me\n" i)))
      (let ((p (point)))
        (insert "X  <- a tall display-property image sits on the X above-left\n")
        (let ((ov (make-overlay p (1+ p))))
          (overlay-put ov 'display
                       (if (image-type-available-p 'svg)
                           (create-image
                            "<svg xmlns='http://www.w3.org/2000/svg' width='220' height='200'>\
<rect width='100%' height='100%' rx='8' fill='#70ad47'/>\
<text x='12' y='28' font-size='20' fill='white'>display prop (200px)</text></svg>"
                            'svg t)
                         "DISPLAY-PROP-IMAGE"))))
      (dotimes (i 30) (insert (format "filler line %02d -- scroll me\n" (+ i 30))))
      (pixel-scroll-precision-mode 1)
      (goto-char (point-max)))
    (switch-to-buffer buf)))

(provide 'debug-pixel-scroll-tall-line)

;;; debug-pixel-scroll-tall-line.el ends here
