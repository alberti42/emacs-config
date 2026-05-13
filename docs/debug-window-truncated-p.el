;;; debug-window-truncated-p.el --- Demo for the truncation-flag patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive demo for the local Emacs patch that adds two C primitives:
;;
;;   `window-truncated-on-left-p'   t if the most recent redisplay of
;;                                  WINDOW showed a truncation indicator
;;                                  on the left edge (hscroll glyph).
;;
;;   `window-truncated-on-right-p'  t if the most recent redisplay of
;;                                  WINDOW showed a truncation indicator
;;                                  on the right edge (right-edge
;;                                  truncation glyph / fringe bitmap).
;;
;; The patch itself only adds these flags.  Horizontal scrolling is a
;; *typical* application of them, not part of the patch — any user can
;; write a small Elisp piece that gates `scroll-left' / `scroll-right'
;; on the answer.  This demo uses horizontal scrolling as the worked
;; example because it is the most intuitive case.
;;
;; The demo provides two tests:
;;
;;   - `truncation-flag-test-001'  Motivation: shows the typical use case
;;                                 for the flags (gating hscroll) implemented
;;                                 WITHOUT the patch, in pure Elisp.  This
;;                                 test does NOT exercise the new primitives.
;;
;;   - `truncation-flag-test-002'  Demonstrates the patch in action: the
;;                                 same use case, gated per direction
;;                                 using the two new primitives so that
;;                                 scrolling stops at the natural extents
;;                                 on each side.
;;
;;   - `truncation-flag-test-003'  Same as test 002, but the buffer
;;                                 contains right-to-left (Hebrew) text.
;;                                 Verifies that the directional gating
;;                                 also works correctly under RTL.
;;
;; Both tests open a buffer with a mix of long and short lines and bind
;;
;;   M-<right> / <wheel-left>   try to scroll left  (reveal text on the right)
;;   M-<left>  / <wheel-right>  try to scroll right (reveal text on the left)
;;   M-?                        show what the gate would answer right now
;;
;; Horizontal mouse-wheel scrolling is not bound globally in stock Emacs;
;; the demo installs buffer-local wheel bindings so the gate can also be
;; exercised with a trackpad.  The echo area reports whether the gate
;; allowed or blocked the scroll.  Resize the window narrower / wider to
;; see how each gate reacts.
;;
;; Run from "emacs -Q" with the patched build:
;;
;;   emacs -Q --load /path/to/debug-window-truncated-p.el \
;;             --eval "(truncation-flag-test-001)" -nw
;;   emacs -Q --load /path/to/debug-window-truncated-p.el \
;;             --eval "(truncation-flag-test-002)" -nw
;;
;; The file is safe to load on stock (unpatched) Emacs: test 002 detects
;; the missing primitives via `fboundp' and explains in its buffer header
;; what would happen.

;;; Code:

;;; Sample content -----------------------------------------------------------

(defconst truncation-flag-test--short-line
  "Short line.  Fits in any reasonable window."
  "A line guaranteed to fit even in a narrow window.")

(defconst truncation-flag-test--long-line
  "Long line: the quick brown fox jumps over the lazy dog, repeatedly, with great enthusiasm and minimal regard for column counts."
  "A line long enough to overflow a typical 80-column window.")

(defun truncation-flag-test--insert-sample ()
  "Insert a few short and long lines into the current buffer."
  (dotimes (_ 3) (insert truncation-flag-test--short-line "\n"))
  (dotimes (_ 3) (insert truncation-flag-test--long-line "\n"))
  (dotimes (_ 3) (insert truncation-flag-test--short-line "\n")))

(defconst truncation-flag-test--short-line-rtl
  "שלום עולם."
  "A short Hebrew (RTL) line guaranteed to fit even in a narrow window.")

(defconst truncation-flag-test--long-line-rtl
  "שלום וברוכים הבאים לעולם של עורכי טקסט עתיקים התומכים גם בכיוון כתיבה מימין לשמאל בצורה נכונה ויעילה."
  "A long Hebrew (RTL) line that overflows a typical 80-column window.")

(defun truncation-flag-test--insert-sample-rtl ()
  "Insert short and long Hebrew (RTL) lines into the current buffer."
  (dotimes (_ 3) (insert truncation-flag-test--short-line-rtl "\n"))
  (dotimes (_ 3) (insert truncation-flag-test--long-line-rtl "\n"))
  (dotimes (_ 3) (insert truncation-flag-test--short-line-rtl "\n")))

;;; Gates --------------------------------------------------------------------

(defun truncation-flag-test--gate-mode-mirror (_direction)
  "Pre-patch gate: mirror the logic in xdisp.c:init_iterator.
Answers \"is truncation mode active for this window?\" — *not*
\"does any line actually overflow?\".  Returns t when truncation
mode applies, even if every visible line happens to fit.  The
mode-mirror approach is direction-agnostic: there is no way to
tell from Elisp which edge (if any) is actually truncated.
DIRECTION is therefore ignored."
  (or truncate-lines
      (and (not (window-full-width-p))
           truncate-partial-width-windows
           (if (integerp truncate-partial-width-windows)
               (< (window-total-width) truncate-partial-width-windows)
             t))))

(defun truncation-flag-test--gate-via-flag (direction)
  "Post-patch gate: ask the C display engine for the relevant edge.
DIRECTION is `left' (scroll-left, reveal right side) or `right'
\(scroll-right, reveal left side).  Consults the corresponding
primitive added by the patch.  Falls through (returns t) on
un-patched Emacs so the demo can still be run."
  (or (not (fboundp 'window-truncated-on-left-p))
      (if (eq direction 'left)
          (window-truncated-on-right-p)
        (window-truncated-on-left-p))))

;;; Interactive commands -----------------------------------------------------

(defvar-local truncation-flag-test--gate nil
  "Function of no arguments used by the test commands to gate hscroll.")

(defun truncation-flag-test--try-scroll (direction)
  "Attempt to scroll the selected window by one column in DIRECTION.
DIRECTION is `left' or `right'.  Consults the buffer-local gate
\(passing DIRECTION) and echoes the outcome."
  (let* ((gate truncation-flag-test--gate)
         (allowed (and gate (funcall gate direction))))
    (cond
     ((not gate)
      (message "No gate installed in this buffer."))
     (allowed
      (if (eq direction 'left) (scroll-left 1 t) (scroll-right 1 t))
      (message "Gate allowed scroll-%s (hscroll=%d)."
               direction (window-hscroll)))
     (t
      (message "Gate blocked scroll-%s (no truncation on that edge)."
               direction)))))

(defun truncation-flag-test-scroll-left ()
  "Try to scroll the window one column to the left, via the demo gate."
  (interactive)
  (truncation-flag-test--try-scroll 'left))

(defun truncation-flag-test-scroll-right ()
  "Try to scroll the window one column to the right, via the demo gate."
  (interactive)
  (truncation-flag-test--try-scroll 'right))

(defun truncation-flag-test-show-gate ()
  "Show what the buffer-local gate would currently answer for both directions."
  (interactive)
  (let ((gate truncation-flag-test--gate))
    (if (not gate)
        (message "No gate installed in this buffer.")
      (message "scroll-left (reveal right): %s | scroll-right (reveal left): %s"
               (if (funcall gate 'left)  "ALLOWED" "BLOCKED")
               (if (funcall gate 'right) "ALLOWED" "BLOCKED")))))

(defun truncation-flag-test-wheel-left (event)
  "Handle a `wheel-left' EVENT: try gated scroll-left in the event's window.
Bound buffer-locally because stock Emacs does not bind horizontal
wheel events for hscroll."
  (interactive "e")
  (with-selected-window (mwheel-event-window event)
    (truncation-flag-test--try-scroll 'left)))

(defun truncation-flag-test-wheel-right (event)
  "Handle a `wheel-right' EVENT: try gated scroll-right in the event's window."
  (interactive "e")
  (with-selected-window (mwheel-event-window event)
    (truncation-flag-test--try-scroll 'right)))

(defun truncation-flag-test--install-keys ()
  "Install the demo key bindings as buffer-local overrides."
  (use-local-map (make-sparse-keymap))
  (local-set-key (kbd "M-<right>") #'truncation-flag-test-scroll-left)
  (local-set-key (kbd "M-<left>")  #'truncation-flag-test-scroll-right)
  (local-set-key (kbd "M-?")       #'truncation-flag-test-show-gate)
  ;; Mouse-wheel horizontal scrolling — not bound by default in Emacs.
  ;; Bind all three speed tiers Emacs may emit (Emacs reclassifies rapid
  ;; successive wheel events as double- then triple- variants).
  (dolist (speed '("" "double-" "triple-"))
    (local-set-key (kbd (format "<%swheel-left>"  speed))
                   #'truncation-flag-test-wheel-left)
    (local-set-key (kbd (format "<%swheel-right>" speed))
                   #'truncation-flag-test-wheel-right)))

;;; Tests --------------------------------------------------------------------

(defun truncation-flag-test-001 ()
  "Pre-patch demo: gate horizontal scrolling by mirroring truncation mode.

Reproduces what one would write in plain Elisp without the patch.
The cheap mode-mirror check has a known false-positive: when
`truncate-lines' is t but every visible line happens to fit, the
gate still says \"allowed\" and `scroll-left' silently moves the
window's column offset with nothing to reveal."
  (interactive)
  (let ((buf (get-buffer-create "*truncation-flag-test-001*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (insert "\
truncation-flag-test-001 — the problem (no patch used here)
===========================================================

When `truncate-lines' is enabled it is desirable to also enable
horizontal scrolling, so the user can conveniently reach text that is
outside the visible window.  This is what most other editors do, and
the combination of `truncate-lines' + horizontal scrolling is a
configuration that is likely adopted by many if not the majority
of users.

This buffer reproduces exactly that setup: `truncate-lines' is t and
horizontal mouse-wheel and key bindings are installed (stock Emacs
does not bind horizontal wheel events).  Scrolling is gated by the
cheapest pre-patch check available:

    (defun truncation-flag-test--gate-mode-mirror ()
      (or truncate-lines
          (and (not (window-full-width-p))
               truncate-partial-width-windows
               ...)))

The gate inspects `truncate-lines' (and `truncate-partial-width-windows')
i.e. whether truncation MODE is active.  It has no way to know
whether any line in the buffer is actually being truncated right now;
that depends on the rendered content and the current window width.

The consequence: when the window is wide enough that every line fits,
the gate still says ALLOWED.  Touching the trackpad sideways then
slides the text off-screen even though there is nothing to reveal,
exactly the annoyance most editors (I tested VS Code and Sublime)
inhibit by disabling hscroll when content is not truncated.

One could in principle close this gap from Elisp by scanning every
visible line (e.g. with `window-text-pixel-size') on each scroll event.
This test does not do that: such a scan is linear in the number of
visible lines, runs on every event, and is not worth the code and the
cost.  The next test (truncation-flag-test-002) shows the alternative:
a few lines of C plus a few lines of Elisp, virtually zero runtime
cost compared with unpatched Emacs.

Bindings (buffer-local):
  M-<right> / <wheel-left>   try scroll-left   (reveal text on the right)
  M-<left>  / <wheel-right>  try scroll-right  (reveal text on the left)
  M-?                        show current per-direction gate answers

Try this:

  1. Make the window narrow enough that the long lines (sample below)
     overflow.  M-? reports BOTH directions ALLOWED — but note this
     gate is direction-agnostic (it cannot tell left from right edges),
     so even right after opening the buffer scroll-right is reported
     ALLOWED despite hscroll=0 and no text on the left.

  2. Widen the window so EVERY line fits.  M-? still reports BOTH
     directions ALLOWED — false positive: the gate only knows the
     mode is on.  A swipe still moves the column offset, silently
     pushing the visible content off the left edge with nothing on
     the right to reveal.

Sample lines:
")
      (truncation-flag-test--insert-sample)
      (setq-local truncate-lines t)
      (setq-local truncation-flag-test--gate
                  #'truncation-flag-test--gate-mode-mirror)
      (truncation-flag-test--install-keys)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(defun truncation-flag-test-002 ()
  "Post-patch demo: gate horizontal scrolling directionally.

Uses the new C primitives added by the patch
\(`window-truncated-on-left-p' / `window-truncated-on-right-p').
Reports actual rendered truncation per edge, so scrolling stops
at the natural extents on each side and the false-positive shown
in test 001 disappears.

On an unpatched build the primitives are absent.  The gate falls
through to t (always allowed), matching stock behavior; a banner
at the top of the buffer warns about this."
  (interactive)
  (let* ((patched (fboundp 'window-truncated-on-left-p))
         (buf (get-buffer-create "*truncation-flag-test-002*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (unless patched
        (insert "\
WARNING: this Emacs build does NOT expose `window-truncated-on-left-p'
or `window-truncated-on-right-p'.  The gate in this test falls through
and always allows scroll, matching stock behavior.  Run this test from
the patched Emacs to see the difference.

"))
      (insert "\
truncation-flag-test-002 — the patch in action (directional gating)
===================================================================

This test exercises the two C primitives added by the patch.  It is
the same worked example as test 001 (gating horizontal scrolling on
actual truncation), but the gate now consults the display engine
directly, and does so per edge:

    (defun truncation-flag-test--gate-via-flag (direction)
      (or (not (fboundp 'window-truncated-on-left-p))
          (if (eq direction 'left)
              (window-truncated-on-right-p)   ; scroll-left reveals right
            (window-truncated-on-left-p))))   ; scroll-right reveals left

The two predicates are independent: each looks for one bit in the
current glyph matrix and stops on the first hit.  This means
scrolling stops at the natural extents on each side, like VS Code
and Sublime do: you cannot scroll-left past the rightmost visible
content, and you cannot scroll-right past column 0.

The patch itself adds nothing about horizontal scrolling — only the
two flags.  Any user can write a gate like the one above; this is
just one typical application.

Bindings (buffer-local):
  M-<right> / <wheel-left>   try scroll-left   (reveal text on the right)
  M-<left>  / <wheel-right>  try scroll-right  (reveal text on the left)
  M-?                        show current per-direction gate answers

Try this:

  1. Make the window narrow enough that the long lines (sample below)
     overflow.  M-? reports scroll-left ALLOWED, scroll-right BLOCKED
     (hscroll is still 0, nothing on the left to reveal).  A swipe /
     M-<right> scrolls and reveals hidden text on the right.

  2. After some M-<right> presses, M-? now reports BOTH directions
     ALLOWED: the long lines still overflow on the right, and column 0
     is now off the left.  M-<left> walks the offset back toward 0.

  3. Once hscroll returns to 0, scroll-right becomes BLOCKED again.

  4. Widen the window so every line fits.  scroll-left now also
     BLOCKS — the false positive from test 001 is gone: the primitive
     asks the C display engine whether a truncation indicator was
     actually drawn on the right edge, and the answer is no.

Sample lines:
")
      (truncation-flag-test--insert-sample)
      (setq-local truncate-lines t)
      (setq-local truncation-flag-test--gate
                  #'truncation-flag-test--gate-via-flag)
      (truncation-flag-test--install-keys)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(defun truncation-flag-test-003 ()
  "Post-patch demo with right-to-left (Hebrew) content.

Same directional gating as `truncation-flag-test-002', but the
buffer contains Hebrew text so paragraphs render visually from
right to left.  The new C primitives report which visual edge
\(left or right) was actually truncated by the display engine, so
gating Just Works under RTL: scroll-left still reveals visual
content on the visual right edge, regardless of paragraph
direction."
  (interactive)
  (let* ((patched (fboundp 'window-truncated-on-left-p))
         (buf (get-buffer-create "*truncation-flag-test-003*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (unless patched
        (insert "\
WARNING: this Emacs build does NOT expose `window-truncated-on-left-p'
or `window-truncated-on-right-p'.  The gate in this test falls through
and always allows scroll, matching stock behavior.  Run this test from
the patched Emacs to see the difference.

"))
      (insert "\
truncation-flag-test-003 — directional gating under RTL (Hebrew)
================================================================

Same setup as truncation-flag-test-002, but the buffer contains
Hebrew text so paragraphs render visually right-to-left: each long
Hebrew line begins on the visual right edge and ends on the visual
left edge.

The new C primitives report which VISUAL edge was truncated by the
display engine.  So the directional gating works identically under
RTL: a wheel-right event (which calls `scroll-left' to expose more
content on the visual right) is allowed exactly when the right edge
of the rendered output actually carries a truncation indicator,
regardless of whether the underlying paragraph is LTR or RTL.

Bindings (buffer-local):
  M-<right> / <wheel-left>   try scroll-left   (reveal visual right)
  M-<left>  / <wheel-right>  try scroll-right  (reveal visual left)
  M-?                        show current per-direction gate answers

Try this:

  1. Make the window narrow enough that the long Hebrew lines (below)
     overflow.  M-? reports scroll-left ALLOWED, scroll-right BLOCKED.
     A swipe / M-<right> scrolls visually leftward.  The right edge
     of the rendered Hebrew text is what gets revealed — i.e. the
     middle/end of the logical sentence.

  2. After some M-<right> presses, M-? reports BOTH ALLOWED: long
     lines still extend off the visual right, AND content is now
     hidden off the visual left.  M-<left> walks the offset back.

  3. Once back at hscroll 0, scroll-right is BLOCKED again.

  4. Widen the window until every Hebrew line fits.  Both directions
     BLOCK — same as in test 002.  The bidi reordering has not
     confused the predicates.

Sample lines (Hebrew, right-aligned by RTL paragraph layout):
")
      (truncation-flag-test--insert-sample-rtl)
      (setq-local truncate-lines t)
      (setq-local truncation-flag-test--gate
                  #'truncation-flag-test--gate-via-flag)
      (truncation-flag-test--install-keys)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(provide 'debug-window-truncated-p)

;;; debug-window-truncated-p.el ends here
