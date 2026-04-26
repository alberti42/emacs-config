;;; scroll-config.el --- Scrolling behaviour and smooth-scroll setup -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Tuned scroll parameters for both GUI and TTY, plus ultra-scroll for
;; pixel-precise glitch-free scrolling in GUI frames.
;;

;;; Code:

;;; -- Setting up pixel-precise scrolling with ultra-scroll --------------------

;; Pixel-precise, glitch-free smooth scrolling.
;; Replaces pixel-scroll-precision-mode (ultra-scroll activates it internally).
(use-package ultra-scroll
  :init
  ;; ultra-scroll requires scroll-margin 0 and works best with a low
  ;; scroll-conservatively value; it handles pixel-precise scrolling itself.
  (setq scroll-margin 0)
  (setq scroll-conservatively 101)
  (setq scroll-step 1)
  (setq scroll-preserve-screen-position t)

  ;; Smoother horizontal scrolling too
  (setq hscroll-margin 2)
  (setq hscroll-step 1)
  
  :config
  ;; Whether to hide the cursor while scrolling and restore it afterwards (default: t).
  (setq ultra-scroll-hide-cursor t)
  (setq ultra-scroll-preserve-column nil)
  (ultra-scroll-mode 1)

  ;; `pixel-scroll-precision-mode' (activated by ultra-scroll) binds
  ;; <next>/<prior> in its minor-mode map to pixel-scroll-interpolate-*,
  ;; shadowing the global bindings set below.  Unbind there so the globals win.
  (define-key pixel-scroll-precision-mode-map (kbd "<next>")  nil)
  (define-key pixel-scroll-precision-mode-map (kbd "<prior>") nil))

;; Scroll by 5 lines (current and other window).
(let ((num-lines 10))
  (pcase-dolist (`(,key . ,fn)
                 '(("C-v" . scroll-up)      ("<next>"  . scroll-up)
                   ("M-v" . scroll-down)    ("<prior>" . scroll-down)
                   ("M-<next>" . scroll-other-window)
                   ("M-<prior>" . scroll-other-window-down)))
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
;; Horizontal scroll events are suppressed when the window wraps lines,
;; because scrolling sideways would have no visible effect there.
;;
;; `scroll-config--hscroll-applicable-p' decides this by checking whether
;; truncation mode is active for the window, mirroring the logic in
;; xdisp.c:init_iterator.  It answers "is truncation mode on?" rather than
;; "does any line actually overflow?" — the latter would require scanning
;; pixel widths across every visible line on each trackpad event, which is
;; too expensive.  The false-positive (truncation on, all lines short enough
;; to fit) is harmless: the user swipes and nothing moves.
;;
;; The false-positive (truncation on, all lines short enough to fit) is
;; mildly annoying: hscroll still moves the window's column offset, so the
;; cursor appears to drift sideways even though no content is hidden.  A
;; pixel-perfect solution would require a C-level flag in the window struct
;; set by the display engine whenever it renders a truncation glyph, but that
;; is not worth the complexity here.

(defvar-local scroll-config-suppress-hscroll nil
  "When non-nil in the current buffer, suppress horizontal wheel scroll.
Set by terminal/shell mode hooks where content is already re-wrapped to
the window width by the underlying program, so hscroll has nothing to
reveal.  Decoupled from `truncate-lines' because terminal emulators
need the full window width reported to the child process; flipping
`truncate-lines' to nil would cost a column to the continuation glyph.")

(defun scroll-config--hscroll-applicable-p ()
  "Return non-nil when the selected window truncates long lines.
Mirrors the logic in xdisp.c init_iterator."
  (and
   (not scroll-config-suppress-hscroll)
   (or
    ;; Explicit per-buffer truncation: the buffer asked for truncation
    ;; regardless of window geometry.
    truncate-lines

    ;; Implicit truncation via `truncate-partial-width-windows': Emacs
    ;; automatically truncates lines in windows that do not occupy the full
    ;; frame width (i.e. side-by-side splits), to avoid confusing wrapped text.
    ;; Three sub-conditions must all hold:
    (and
     ;; 1. The window is narrower than the frame.  Full-width windows are
     ;;    exempt: `truncate-partial-width-windows' only applies to splits.
     (not (window-full-width-p))
     ;; 2. The feature is enabled at all (nil disables it entirely).
     truncate-partial-width-windows
     ;; 3. Width threshold check.  The variable can be t (truncate all
     ;;    partial-width windows unconditionally) or an integer N (truncate
     ;;    only when the window is narrower than N columns).  When it is an
     ;;    integer, a wide-enough split is still allowed to wrap.
     (if (integerp truncate-partial-width-windows)
         (< (window-total-width) truncate-partial-width-windows)
       t)))))

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
      (if (or ;; The window is already hscrolled: allow scrolling back to
           ;; column 0 even if truncation mode is no longer active.
           (> (window-hscroll) 0)
           ;; Truncation is active in this window, so horizontal
           ;; scrolling can actually reveal hidden content.
           (scroll-config--hscroll-applicable-p))
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
