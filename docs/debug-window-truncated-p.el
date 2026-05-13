;;; debug-window-truncated-p.el --- Demo for the truncation-flag patch -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Interactive demo for the local Emacs patch that adds a C primitive
;; `window-truncated-p'.  The primitive answers a single question:
;;
;;   "Did the most recent redisplay of WINDOW show any truncation
;;    indicator (left-edge hscroll glyph or right-edge truncation
;;    glyph / fringe bitmap)?"
;;
;; The patch itself only adds the flag.  Horizontal scrolling is a
;; *typical* application of that flag, not part of the patch — any
;; user can write a small Elisp piece that gates `scroll-left' /
;; `scroll-right' on the answer.  This demo uses horizontal scrolling
;; as the worked example because it is the most intuitive case.
;;
;; The demo provides two tests:
;;
;;   - `truncation-flag-test-001'  Motivation: shows the typical use case
;;                                 for the flag (gating hscroll) implemented
;;                                 WITHOUT the patch, in pure Elisp.  This
;;                                 test does NOT exercise the new primitive.
;;
;;   - `truncation-flag-test-002'  Demonstrates the patch in action: the
;;                                 same use case implemented with the new
;;                                 `window-truncated-p' primitive.
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
;; the missing primitive via `fboundp' and explains in its buffer header
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

;;; Gates --------------------------------------------------------------------

(defun truncation-flag-test--gate-mode-mirror ()
  "Pre-patch gate: mirror the logic in xdisp.c:init_iterator.
Answers \"is truncation mode active for this window?\" — *not*
\"does any line actually overflow?\".  Returns t when truncation
mode applies, even if every visible line happens to fit."
  (or truncate-lines
      (and (not (window-full-width-p))
           truncate-partial-width-windows
           (if (integerp truncate-partial-width-windows)
               (< (window-total-width) truncate-partial-width-windows)
             t))))

(defun truncation-flag-test--gate-via-flag ()
  "Post-patch gate: ask the C display engine directly.
Falls through (returns t) on un-patched Emacs so the demo can
still be run; on a patched build this returns t only when the
most recent redisplay actually emitted a truncation indicator."
  (or (not (fboundp 'window-truncated-p))
      (window-truncated-p)))

;;; Interactive commands -----------------------------------------------------

(defvar-local truncation-flag-test--gate nil
  "Function of no arguments used by the test commands to gate hscroll.")

(defun truncation-flag-test--try-scroll (direction)
  "Attempt to scroll the selected window by one column in DIRECTION.
DIRECTION is `left' or `right'.  Consults the buffer-local gate
and echoes the outcome."
  (let* ((gate truncation-flag-test--gate)
         (allowed (and gate (funcall gate))))
    (cond
     ((not gate)
      (message "No gate installed in this buffer."))
     (allowed
      (if (eq direction 'left) (scroll-left 1 t) (scroll-right 1 t))
      (message "Gate allowed scroll-%s (hscroll=%d)."
               direction (window-hscroll)))
     (t
      (message "Gate blocked scroll-%s (no truncation detected)."
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
  "Show what the buffer-local gate would currently answer."
  (interactive)
  (let ((gate truncation-flag-test--gate))
    (if (not gate)
        (message "No gate installed in this buffer.")
      (message "Gate says: %s."
               (if (funcall gate) "scroll ALLOWED" "scroll BLOCKED")))))

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
truncation-flag-test-001 — motivation (no patch used here)
==========================================================

IMPORTANT: this test does NOT exercise the new patch.  It demonstrates
the typical application that motivates the patch — gating horizontal
scrolling on whether the buffer is actually truncated — implemented
with the only tool available WITHOUT the patch: pure Elisp.

The patch itself only adds the C primitive `window-truncated-p'.  It
does not touch or add anything about horizontal scrolling.  Hscroll is
used here purely as the worked example because it makes the question
\"is anything truncated?\" easy to feel: when nothing is truncated,
scrolling sideways reveals nothing and merely drifts the column offset.

Horizontal mouse-wheel scrolling is also off by default in stock Emacs;
the demo installs buffer-local wheel bindings so a trackpad can drive
the gate.  The mode-mirror gate used here is:

    (defun truncation-flag-test--gate-mode-mirror ()
      (or truncate-lines
          (and (not (window-full-width-p))
               truncate-partial-width-windows
               ...)))

This is the cheapest pre-patch approximation: it answers \"is truncation
MODE active for this window?\" rather than \"did any line actually
overflow?\".  A faithful pure-Elisp answer would have to iterate every
visible line and call into the display engine for each one (e.g. via
`window-text-pixel-size'), which is far more expensive than a single
boolean read and still leaves edge cases around the left-edge hscroll
indicator.  We do not attempt it here.

Bindings (buffer-local):
  M-<right> / <wheel-left>   try scroll-left   (reveal text on the right)
  M-<left>  / <wheel-right>  try scroll-right  (reveal text on the left)
  M-?                        show current gate answer

Try this:

  1. Make the window narrow enough that the long lines (sample below)
     overflow.  M-? reports \"ALLOWED\" — correct: there IS truncation.
     A swipe / M-<right> scrolls and reveals hidden text.

  2. Widen the window so EVERY line fits.  M-? still reports \"ALLOWED\"
     — but this is a FALSE POSITIVE: the gate only knows that truncation
     mode is on, not that no line actually overflows.  A swipe still
     moves the column offset, silently pushing the visible content off
     the left edge with nothing on the right to reveal.

Compare with truncation-flag-test-002, which uses the patch and gets
this right.

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
  "Post-patch demo: gate horizontal scrolling via `window-truncated-p'.

Uses the new C primitive added by the patch.  Reports actual
rendered truncation, so the false-positive shown in test 001
disappears: when every visible line fits, the gate correctly
blocks the scroll.

On an unpatched build the primitive is absent.  The gate falls
through to t (always allowed), matching stock behavior; a banner
at the top of the buffer warns about this."
  (interactive)
  (let* ((patched (fboundp 'window-truncated-p))
         (buf (get-buffer-create "*truncation-flag-test-002*")))
    (with-current-buffer buf
      (read-only-mode -1)
      (erase-buffer)
      (unless patched
        (insert "\
WARNING: this Emacs build does NOT expose `window-truncated-p'.  The gate
in this test falls through and always allows scroll, matching stock
behavior.  Run this test from the patched Emacs to see the difference.

")
        )
      (insert "\
truncation-flag-test-002 — the patch in action (window-truncated-p)
===================================================================

This test exercises the new C primitive added by the patch.  It is the
same worked example as test 001 (gating horizontal scrolling on actual
truncation), but the gate now consults the display engine directly
instead of approximating in pure Elisp:

    (defun truncation-flag-test--gate-via-flag ()
      (or (not (fboundp 'window-truncated-p))
          (window-truncated-p)))

The patch itself adds nothing about horizontal scrolling — only the
flag.  Any user can write a gate like the one above; this is just one
typical application.

Bindings (buffer-local):
  M-<right> / <wheel-left>   try scroll-left   (reveal text on the right)
  M-<left>  / <wheel-right>  try scroll-right  (reveal text on the left)
  M-?                        show current gate answer

Try this:

  1. Make the window narrow enough that the long lines (sample below)
     overflow.  M-? reports \"ALLOWED\".  A swipe / M-<right> scrolls
     and reveals hidden text.

  2. Widen the window so every line fits without truncation.  M-? now
     reports \"BLOCKED\" — the false positive from test 001 is gone:
     the primitive asks the C display engine whether a truncation
     indicator was actually drawn, and the answer is no.

  3. Once the gate has BLOCKED scrolling, hscroll never advanced past 0,
     so subsequent attempts also block.  Compare with test 001, where
     the column offset may have already drifted away from 0.

Sample lines:
")
      (truncation-flag-test--insert-sample)
      (setq-local truncate-lines t)
      (setq-local truncation-flag-test--gate
                  #'truncation-flag-test--gate-via-flag)
      (truncation-flag-test--install-keys)
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(provide 'debug-window-truncated-p)

;;; debug-window-truncated-p.el ends here
