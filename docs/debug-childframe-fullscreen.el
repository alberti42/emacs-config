;;; debug-childframe-fullscreen.el --- NS invisible child-frame resurrection reproducer -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Reproducer for an Emacs macOS (NS) port bug: a child frame that Emacs
;; has made *invisible* is brought back onto the screen whenever the
;; parent frame rebuilds its parent/child window relationships -- e.g. on
;; `toggle-frame-fullscreen' (and likewise when a monitor is connected or
;; disconnected, or the undecorated status is toggled).
;;
;; The child frame's `frame-visible-p' stays nil throughout, so Emacs
;; never repaints to clear it: it sits on screen as a dead,
;; non-interactive surface that C-g cannot dismiss.  This is what users of
;; child-frame completion popups (corfu, company-box, ...) see as a "stuck
;; completion popup" after, for example, waking a laptop on a new monitor.
;;
;; This reproducer uses ONLY built-in primitives -- `make-frame' with a
;; `parent-frame' parameter, `make-frame-invisible', and
;; `toggle-frame-fullscreen' -- so it needs no third-party packages.
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
;; then either run the whole sequence automatically:
;;
;;   M-x childframe-fullscreen-run
;;
;; or step through it manually (more deterministic for a report):
;;
;;   M-x childframe-fullscreen-step-1-show         ; yellow popup appears
;;   M-x childframe-fullscreen-step-2-hide         ; popup disappears (hidden)
;;   M-x childframe-fullscreen-step-3-fullscreen   ; popup REAPPEARS in fullscreen
;;
;; Expected: the popup stays hidden across the fullscreen transition.
;; Actual (buggy): it reappears as dead, non-interactive text even though
;; (frame-visible-p childframe-fullscreen--child) returns nil.

;;; Code:

;; The bug reproduces with both native and non-native fullscreen (and on
;; monitor hot-plug, which is fullscreen-independent).  Non-native is
;; selected here because it is 100% deterministic and needs no Space
;; animation; remove this line to test the native path.
(setq ns-use-native-fullscreen nil)

(defvar childframe-fullscreen--child nil
  "Child frame standing in for a completion popup.")

(defun childframe-fullscreen--make ()
  "Create and show a child frame over the selected frame."
  (when (frame-live-p childframe-fullscreen--child)
    (delete-frame childframe-fullscreen--child))
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
                   (width . 24)
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
      (insert "GHOST POPUP\n-----------\ncandidate-1\ncandidate-2\ncandidate-3"))
    (set-window-buffer (frame-root-window child) buf)
    (setq childframe-fullscreen--child child)))

(defun childframe-fullscreen-step-1-show ()
  "Step 1: show the child frame (a completion popup appearing)."
  (interactive)
  (childframe-fullscreen--make)
  (message "Step 1 done: child shown.  Next: M-x childframe-fullscreen-step-2-hide"))

(defun childframe-fullscreen-step-2-hide ()
  "Step 2: hide the child frame (dismissing the popup, e.g. with C-g)."
  (interactive)
  (when (frame-live-p childframe-fullscreen--child)
    (make-frame-invisible childframe-fullscreen--child))
  (message "Step 2 done: hidden, frame-visible-p = %s.  Next: M-x childframe-fullscreen-step-3-fullscreen"
           (and (frame-live-p childframe-fullscreen--child)
                (frame-visible-p childframe-fullscreen--child))))

(defun childframe-fullscreen-step-3-fullscreen ()
  "Step 3: toggle fullscreen.  BUG: the hidden child frame reappears."
  (interactive)
  (toggle-frame-fullscreen)
  (run-with-timer
   1.5 nil
   (lambda ()
     (message
      "Step 3 done: fullscreen toggled.  frame-visible-p(child) = %s.  BUG if the yellow popup is visible."
      (and (frame-live-p childframe-fullscreen--child)
           (frame-visible-p childframe-fullscreen--child))))))

(defun childframe-fullscreen-run ()
  "Run the full sequence automatically with pauses."
  (interactive)
  (childframe-fullscreen-step-1-show)
  (run-with-timer 2 nil #'childframe-fullscreen-step-2-hide)
  (run-with-timer 4 nil #'childframe-fullscreen-step-3-fullscreen))

;; Drop instructions into *scratch* on load.
(with-current-buffer (get-buffer-create "*scratch*")
  (erase-buffer)
  (insert ";; NS invisible child-frame resurrection -- reproducer\n"
          ";;\n"
          ";; Automatic:  M-x childframe-fullscreen-run\n"
          ";;\n"
          ";; Manual (recommended for the report):\n"
          ";;   1. M-x childframe-fullscreen-step-1-show        ; yellow popup appears\n"
          ";;   2. M-x childframe-fullscreen-step-2-hide        ; popup disappears (invisible)\n"
          ";;   3. M-x childframe-fullscreen-step-3-fullscreen  ; popup REAPPEARS in fullscreen,\n"
          ";;                                                   ; though frame-visible-p is nil\n"
          ";;\n"
          ";; Expected: the popup stays hidden across the fullscreen transition.\n"
          ";; Actual:   it reappears as dead, non-interactive text.\n"))

(switch-to-buffer "*scratch*")
(message "Reproducer loaded.  See *scratch*, or run M-x childframe-fullscreen-run")

;;; debug-childframe-fullscreen.el ends here
