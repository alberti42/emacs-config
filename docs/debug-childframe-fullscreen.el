;;; debug-childframe-fullscreen.el --- NS invisible child-frame resurrection reproducer -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Reproducer for an Emacs macOS (NS) port bug: a child frame that Emacs
;; has made *invisible* is forced back onto the screen when the parent
;; frame rebuilds its parent/child window relationships.  Non-native
;; `toggle-frame-fullscreen' does this -- it allocates a fresh window
;; whose initializer rebuilds the relationships.
;;
;; NOTE: *native* fullscreen does NOT reproduce the bug.  The native path
;; hands off to AppKit without allocating a new window, so the buggy
;; re-attach never runs.  You MUST keep `ns-use-native-fullscreen' nil
;; (set below) to see the bug -- this is likely why it went unnoticed.
;;
;; The child frame's `frame-visible-p' stays nil throughout, so Emacs
;; never repaints to clear it: it sits on screen as a dead,
;; non-interactive surface that C-g cannot dismiss.  This is what users of
;; child-frame completion popups (corfu, company-box, ...) see as a "stuck
;; completion popup" after entering fullscreen.
;;
;; This reproducer uses ONLY built-in primitives -- a plain child frame
;; (`make-frame' with a `parent-frame' parameter) plays the role corfu's
;; popup would, so no third-party package is needed.
;;
;; Root cause: in src/nsterm.m, -[EmacsWindow setParentChildRelationships]
;; reattaches every child frame to its parent via -addChildWindow:ordered:
;; (which also orders the child onto the screen) without checking
;; FRAME_VISIBLE_P.  That method runs on every relationship rebuild.  On
;; the NS port, frame_redisplay_p (src/frame.c) trusts FRAME_VISIBLE_P
;; alone -- there is no equivalent of the X port's FRAME_X_VISIBLE check --
;; so Emacs never repaints to clear the resurrected frame.
;;
;; Usage (run against an UNPATCHED build to see the bug):
;;
;;   emacs -Q --load /path/to/debug-childframe-fullscreen.el
;;
;; then follow the instructions printed in *scratch* (reproduced below).
;;
;;   1. M-x childframe-fullscreen-step-1-show   ; show a child frame (the popup)
;;   2. M-x childframe-fullscreen-step-2-hide   ; hide it (make-frame-invisible)
;;   3. M-x toggle-frame-fullscreen             ; STOCK command -> triggers the bug
;;   (optional) M-x childframe-fullscreen-bring-into-view
;;                                              ; if the resurrected box landed
;;                                              ; off-screen, move it into view
;;
;; Expected: the child frame stays hidden across the fullscreen transition.
;; Actual (buggy): it reappears, although `frame-visible-p' is still nil
;; (confirm with M-x childframe-fullscreen-status) and C-g cannot dismiss it.

;;; Code:

;; Non-native fullscreen is REQUIRED to reproduce the bug.  The non-native
;; path allocates a fresh EmacsWindow whose initializer rebuilds the
;; parent/child relationships (the buggy re-attach).  Native fullscreen
;; (ns-use-native-fullscreen t) hands off to AppKit without allocating a
;; new window, so the re-attach never runs and the bug does NOT appear.
(setq ns-use-native-fullscreen nil)

(defvar childframe-fullscreen--child nil
  "The child frame that stands in for a completion popup.")

(defun childframe-fullscreen--make ()
  "Create and show a child frame over the selected frame, return it."
  (let* ((parent (selected-frame))
         (buf (get-buffer-create "*childframe-popup*"))
         (child (make-frame
                 `((parent-frame . ,parent)
                   (minibuffer . nil)
                   (undecorated . t)
                   (no-accept-focus . t)
                   (no-focus-on-map . t)
                   (left . 140)
                   (top . 140)
                   (width . 26)
                   (height . 6)
                   (internal-border-width . 2)
                   (vertical-scroll-bars . nil)
                   (horizontal-scroll-bars . nil)
                   (left-fringe . 0)
                   (right-fringe . 0)
                   (background-color . "#ffcc00")
                   (visibility . t)))))
    (with-current-buffer buf
      (erase-buffer)
      (insert "POPUP CHILD FRAME\n"
              "-----------------\n"
              "contents do not matter;\n"
              "only that this frame\n"
              "exists and was shown."))
    (set-window-buffer (frame-root-window child) buf)
    ;; Keep working in the parent so the reviewer can run M-x here.
    (select-frame-set-input-focus parent)
    child))

;;;###autoload
(defun childframe-fullscreen-step-1-show ()
  "Step 1 of 2: create and SHOW a child frame over this one.

This stands in for corfu (or company-box, ...) popping up its
completion child frame.  A small yellow frame appears near the
top-left of this frame.  Its contents are irrelevant -- the bug
depends only on the fact that a child frame was created and shown.

Next: M-x childframe-fullscreen-step-2-hide"
  (interactive)
  (when (frame-live-p childframe-fullscreen--child)
    (delete-frame childframe-fullscreen--child))
  (setq childframe-fullscreen--child (childframe-fullscreen--make))
  (message "Step 1 done: child frame shown.  Next: M-x childframe-fullscreen-step-2-hide"))

;;;###autoload
(defun childframe-fullscreen-step-2-hide ()
  "Step 2 of 2: HIDE the child frame with `make-frame-invisible'.

The yellow frame vanishes.  This stands in for corfu dismissing
its popup: corfu calls exactly `make-frame-invisible' on its child
frame when you select a candidate or press C-g.

This sets up the bug's precondition: a child frame that is invisible
\(`frame-visible-p' returns nil) but whose `parent-frame' is still set --
which is what the relationship rebuild keys on to re-attach it.

Next: M-x toggle-frame-fullscreen  (the stock command -- it triggers
the bug all by itself)."
  (interactive)
  (if (frame-live-p childframe-fullscreen--child)
      (progn
        (make-frame-invisible childframe-fullscreen--child)
        (message "Step 2 done: child hidden, frame-visible-p = %s.  Now run: M-x toggle-frame-fullscreen"
                 (frame-visible-p childframe-fullscreen--child)))
    (message "No child frame -- run M-x childframe-fullscreen-step-1-show first")))

;;;###autoload
(defun childframe-fullscreen-status ()
  "Diagnostic: report the child frame's liveness and visibility.

Run this after M-x toggle-frame-fullscreen.  On a buggy build the
yellow frame is visible on screen yet this reports
`frame-visible-p' = nil -- Emacs believes it is hidden, which is why
nothing (C-g included) repaints to clear it."
  (interactive)
  (if (frame-live-p childframe-fullscreen--child)
      (message "child: live=t  frame-visible-p=%s  position=%S"
               (frame-visible-p childframe-fullscreen--child)
               (frame-position childframe-fullscreen--child))
    (message "child: no live child frame")))

;;;###autoload
(defun childframe-fullscreen-bring-into-view ()
  "Move the resurrected child frame to a visible spot near the top-left.

After M-x toggle-frame-fullscreen the ghost child frame's position is
recomputed during the window rebuild and can land partly or fully
off-screen (e.g. a negative top), so on a large display you may not see
it at all.  This moves it to (80, 80) relative to the parent -- near the
top-left of the fullscreen frame -- so it is on screen.  It does NOT
change the frame's (still nil) visibility: it remains the same stale
ghost, repositioned just to make the bug deterministic and reproducible
regardless of the screen settings."
  (interactive)
  (if (frame-live-p childframe-fullscreen--child)
      (progn
        (set-frame-position childframe-fullscreen--child 80 80)
        (message "child moved to %S; frame-visible-p still %s"
                 (frame-position childframe-fullscreen--child)
                 (frame-visible-p childframe-fullscreen--child)))
    (message "No child frame -- run the earlier steps first")))

;; Print the walkthrough into *scratch* on load.
(with-current-buffer (get-buffer-create "*scratch*")
  (erase-buffer)
  (insert "\
;; ============================================================
;;  NS bug reproducer: invisible child frame reappears
;;  on M-x toggle-frame-fullscreen
;; ============================================================
;;
;; WHAT THIS SHOWS
;; ---------------
;; On the macOS (NS) port, a child frame that Emacs has made invisible is
;; forced back onto the screen when the parent frame rebuilds its child
;; window relationships -- which is what toggle-frame-fullscreen does.
;; Emacs still believes the child is invisible, so it never repaints to
;; clear it; it sits there as dead, non-interactive text that C-g cannot
;; remove.  This is the \"stuck corfu/company completion popup\" seen after
;; entering fullscreen.
;;
;; Only built-in primitives are used.  A plain child frame plays the role
;; corfu's popup would; corfu itself is NOT needed.
;;
;; DO THESE IN ORDER
;; -----------------
;;
;;   1.  M-x childframe-fullscreen-step-1-show
;;       Shows a child frame over this one (the yellow box).
;;       Stand-in for corfu popping up its completion popup.
;;       The box's contents are irrelevant to the bug.
;;
;;   2.  M-x childframe-fullscreen-step-2-hide
;;       Hides it via (make-frame-invisible CHILD); the box vanishes.
;;       Stand-in for corfu dismissing its popup -- corfu calls exactly
;;       make-frame-invisible when you pick a candidate or press C-g.
;;       Precondition is now set: an INVISIBLE child frame whose
;;       parent-frame is still set (frame-visible-p -> nil).
;;
;;   3.  M-x toggle-frame-fullscreen          <-- STOCK Emacs command
;;       Triggers the bug.  Entering fullscreen rebuilds the child-window
;;       relationships and pushes the invisible box back onto the screen.
;;
;;       BUG:  the yellow box reappears even though it is still invisible.
;;             Confirm with  M-x childframe-fullscreen-status  (reports
;;             frame-visible-p = nil while the box is on screen).  C-g
;;             cannot dismiss it.
;;       OK :  with the fix, the box stays hidden across the transition.
;;
;;   (optional)  M-x childframe-fullscreen-bring-into-view
;;       If you do NOT see the box after toggling fullscreen, it is because
;;       it appears outside the visible area: its position is recomputed
;;       during the rebuild and can land off-screen (e.g. a negative top)
;;       on large displays.  Run this to reposition it into view -- it does
;;       not change the visibility (still the same invisible-but-shown
;;       ghost).  The only purpose of this command is to make the buggy
;;       behavior completely deterministic and reproducible.
;;
;; Steps 1 and 2 only reconstruct the precondition; the actual trigger is
;; the unmodified built-in toggle-frame-fullscreen.
\n"))

(switch-to-buffer "*scratch*")
(goto-char (point-min))
(message "Reproducer loaded.  Follow the steps in *scratch* (start: M-x childframe-fullscreen-step-1-show)")

;;; debug-childframe-fullscreen.el ends here
