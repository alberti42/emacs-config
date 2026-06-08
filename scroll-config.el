;;; scroll-config.el --- Scrolling behaviour and smooth-scroll setup -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Tuned scroll parameters for both GUI and TTY.  The vertical smooth-scroll
;; backend is selectable via `scroll-config-smooth-scroll' (ultra-scroll /
;; built-in pixel-scroll / none); see the selection section below.
;;

;;; Code:

;;; -- Smooth-scroll backend selection -----------------------------------------
;;
;; Three interchangeable vertical-scroll backends, chosen via
;; `scroll-config-smooth-scroll'.  The choice also decides whether
;; `scroll-margin' may be non-zero:
;;
;;   `ultra-scroll' — pixel-precise, glitch-free GUI scrolling.  REQUIRES
;;                    `scroll-margin' = 0; a non-zero margin makes redisplay
;;                    recenter mid-gesture (see the package README #3), so the
;;                    margin is pinned to 0 under this backend.
;;   `pixel'        — built-in `pixel-scroll-precision-mode'.  Smooth, and
;;                    tolerates `scroll-margin' > 0 (it lets redisplay recenter
;;                    lazily rather than pinning point at the edge), at the cost
;;                    of an occasional recenter "hop" near buffer edges.
;;   nil            — no smooth scrolling; the wheel steps by lines.
;;
;; Horizontal wheel scrolling (further below) is independent of this choice.

(defvar scroll-config-smooth-scroll nil
  "Vertical smooth-scroll backend: `ultra-scroll', `pixel', or nil.
See the commentary above for the trade-offs.  Changing this requires
restarting Emacs (or re-loading `scroll-config').")

(defvar scroll-config-scroll-margin 4
  "Lines of context to keep at the window edges.
Drives both `scroll-margin' (cursor movement, isearch — honoured only when
the active backend allows a non-zero margin; `ultra-scroll' forces it to 0)
and the numeric `recenter-positions' stops for `C-l', which honour this
value independently of `scroll-margin' under every backend.")

;; Settings shared by all backends.
(setq scroll-conservatively 101)
(setq scroll-step 1)
(setq scroll-preserve-screen-position t)
(setq hscroll-margin 2)
(setq hscroll-step 1)

;; `scroll-margin' governs cursor movement and isearch.  ultra-scroll cannot
;; tolerate a non-zero value, so pin it to 0 under that backend only.
(setq scroll-margin (if (eq scroll-config-smooth-scroll 'ultra-scroll)
                        0
                      scroll-config-scroll-margin))

;; `C-l' (recenter-top-bottom) cycles middle -> N lines from top -> N from
;; bottom.  Numeric positions leave context at the edges even when
;; `scroll-margin' is 0, so this gives top/bottom context under ultra-scroll
;; too.
(setq recenter-positions
      (list 'middle
            scroll-config-scroll-margin
            (- scroll-config-scroll-margin)))

(defun scroll-config--tame-pixel-scroll-map ()
  "Stop `pixel-scroll-precision-mode-map' shadowing the PgUp/PgDn globals.
Both smooth backends enable `pixel-scroll-precision-mode', whose map binds
<next>/<prior> to pixel-scroll-interpolate-*; unbind them there so the
line-step globals set below win."
  (define-key pixel-scroll-precision-mode-map (kbd "<next>")  nil)
  (define-key pixel-scroll-precision-mode-map (kbd "<prior>") nil))

(pcase scroll-config-smooth-scroll
  ('ultra-scroll
   ;; Pixel-precise, glitch-free smooth scrolling.  Activates
   ;; `pixel-scroll-precision-mode' internally.
   (use-package ultra-scroll
     :config
     ;; Hide the cursor while scrolling and restore it afterwards.
     (setq ultra-scroll-hide-cursor t)
     (setq ultra-scroll-preserve-column nil)
     (ultra-scroll-mode 1)
     (scroll-config--tame-pixel-scroll-map)))
  ('pixel
   ;; Built-in smooth scrolling; coexists with scroll-margin > 0.
   (require 'pixel-scroll)
   (pixel-scroll-precision-mode 1)
   (scroll-config--tame-pixel-scroll-map))
  (_ nil))

;; Scroll by 5 lines (current and other window).
(let ((num-lines 10))
  (pcase-dolist (`(,key . ,fn)
                 '(("C-v" . scroll-up)      ("<next>"  . scroll-up)
                   ("M-v" . scroll-down)    ("<prior>" . scroll-down)
                   ("M-<next>"  . scroll-other-window)
                   ("M-<prior>" . scroll-other-window-down)
                   ("C-M-v"   . scroll-other-window)
                   ("C-M-S-v" . scroll-other-window-down)))
    (global-set-key (kbd key) (lambda () (interactive) (funcall fn num-lines)))))

;; Horizontal trackpad/mouse scrolling (Magic Trackpad, Magic Mouse).
;; ultra-scroll only covers vertical; we replicate its pixel-delta approach here.
;; The NS port encodes pixel amounts in (nth 4 event) as (COLS . PIXELS), same as
;; vertical events.  We accumulate fractional column remainders so sub-character-width
;; movements are not silently dropped.
(defvar scroll-config--hscroll-residual 0
  "Accumulated sub-column pixel remainder for smooth horizontal scrolling.")

;;; -- Smart horizontal scrolling ----------------------------------------------
;;
;; Horizontal scroll events are gated per-direction so that scrolling stops
;; at the natural extents of the visible content: no scrolling past column 0
;; on the left, and no scrolling once all text on the right is visible.
;;
;; `window-truncated-on-left-p' / `window-truncated-on-right-p' are C
;; primitives added in the local truncation-flag patch; they report whether
;; the most recent redisplay actually drew a truncation indicator on the
;; corresponding edge.  Using these is preferable to `(> (window-hscroll) 0)'
;; for the "scroll back to 0" case because they handle right-to-left
;; paragraph direction correctly.

(defvar-local scroll-config-suppress-hscroll nil
  "When non-nil in the current buffer, suppress horizontal wheel scroll.
Set by terminal/shell mode hooks where content is already re-wrapped to
the window width by the underlying program, so hscroll has nothing to
reveal.  Decoupled from `truncate-lines' because terminal emulators
need the full window width reported to the child process; flipping
`truncate-lines' to nil would cost a column to the continuation glyph.")

(defun scroll-config--hscroll-allowed-p (direction)
  "Return non-nil when a wheel event in DIRECTION can reveal content.
DIRECTION is the wheel event symbol: `wheel-left' (scrolls right,
revealing text on the left) or `wheel-right' (scrolls left, revealing
text on the right)."
  (and (not scroll-config-suppress-hscroll)
       (or (not (fboundp 'window-truncated-on-left-p))
           (if (eq direction 'wheel-left)
               (window-truncated-on-left-p)
             (window-truncated-on-right-p)))))

(defun scroll-config-horizontal (event &optional _arg)
  "Horizontal scroll EVENT with pixel-proportional column steps."
  (interactive "e")
  (let* (;; mwheel-event-window may return a frame when the pointer is over the
         ;; internal border; normalise to a window below.
         (window (mwheel-event-window event))
         ;; On the NS port (macOS) the 5th event slot carries a cons
         ;; (COLS . PIXELS) with the raw pixel delta from the trackpad.
         ;; Its presence signals that pixel-precise scrolling is possible.
         (delta-info (nth 4 event))
         ;; wheel-left / wheel-right — tells us which direction to scroll.
         (direction (event-basic-type event)))
    (when (framep window) (setq window (frame-selected-window window)))
    (with-selected-window window
      (if (scroll-config--hscroll-allowed-p direction)
          (if delta-info
              (let* ((raw-pixels (abs (cdr delta-info)))
                     (raw-cols   (abs (car delta-info))))
                (if (> raw-pixels 0)
                    ;; --- Pixel-precise path (trackpad / Magic Mouse) ---
                    ;; The trackpad reports sub-character pixel deltas.  We
                    ;; accumulate the remainder across events so that slow
                    ;; swipes are not silently dropped; each event contributes
                    ;; its full pixel count to the running total, and only
                    ;; whole columns are forwarded to scroll-left/scroll-right.
                    (let* ((total  (+ scroll-config--hscroll-residual raw-pixels))
                           (char-w (frame-char-width))
                           (cols   (truncate (/ total char-w))))
                      ;; Carry the sub-column remainder into the next event.
                      (setq scroll-config--hscroll-residual (- total (* cols char-w)))
                      (unless (zerop cols)
                        (if (eq direction 'wheel-left)
                            (scroll-right cols t)
                          (scroll-left cols t))))
                  ;; --- Column-delta path ---
                  ;; The NS port encoded the gesture as column units directly
                  ;; (cdr is 0.0); use the car value without pixel conversion.
                  ;; No sub-column remainder to carry.
                  (let ((cols (round raw-cols)))
                    (setq scroll-config--hscroll-residual 0)
                    (unless (zerop cols)
                      (if (eq direction 'wheel-left)
                          (scroll-right cols t)
                        (scroll-left cols t))))))
            ;; --- Fallback path (physical tilt wheel, no pixel data) ---
            ;; No pixel delta available; step by a fixed number of columns.
            (if (eq direction 'wheel-left)
                (scroll-right 3 t)
              (scroll-left 3 t)))
        ;; Suppressed: the window wraps lines, so horizontal scrolling would
        ;; have no visible effect.  Clear any accumulated residual so a stale
        ;; carry from a previous window cannot leak through.
        (setq scroll-config--hscroll-residual 0)))))

;; Bind all three speed tiers (Emacs reclassifies rapid successive wheel events
;; as double- then triple- variants, like it does for mouse clicks).
(dolist (dir '("left" "right"))
  (dolist (speed '("" "double-" "triple-"))
    (global-set-key (kbd (format "<%swheel-%s>" speed dir))
                    #'scroll-config-horizontal)))

;;; -- Disable zoom bindings ---------------------------------------------------

;; Disable ctrl+scroll zoom (too fast; use keyboard to change font size instead).
(global-set-key (kbd "<C-wheel-up>") 'ignore)
(global-set-key (kbd "<C-wheel-down>") 'ignore)
(global-set-key (kbd "<C-mouse-4>") 'ignore)
(global-set-key (kbd "<C-mouse-5>") 'ignore)

(provide 'scroll-config)

;;; scroll-config.el ends here
