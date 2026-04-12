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
  (ultra-scroll-mode 1))

;; Scroll by 5 lines (current and other window).
(let ((num-lines 5))
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
;; Horizontal scrolling is enabled only when some lines in the buffer are
;; truncated.  The guard mirrors the logic in xdisp.c.

(defun scroll-config--hscroll-applicable-p ()
  "Return non-nil when the selected window truncates long lines.
Mirrors the logic in xdisp.c init_iterator."
  (or truncate-lines
      (and (not (window-full-width-p))
           truncate-partial-width-windows
           (if (integerp truncate-partial-width-windows)
               (< (window-total-width) truncate-partial-width-windows)
             t))))

(defun scroll-config-horizontal (event &optional _arg)
  "Horizontal scroll EVENT with pixel-proportional column steps."
  (interactive "e")
  (let* ((window (mwheel-event-window event))
         (delta-info (nth 4 event))
         (direction (event-basic-type event)))
    (when (framep window) (setq window (frame-selected-window window)))
    (with-selected-window window
      (when (or (> (window-hscroll) 0)
                (> scroll-config--hscroll-residual 0)
                (scroll-config--hscroll-applicable-p))
        (if delta-info
            ;; Pixel-precise path: convert pixels → columns, carry the remainder.
            (let* ((pixels (abs (cdr delta-info)))
                   (total  (+ scroll-config--hscroll-residual pixels))
                   (char-w (frame-char-width))
                   (cols   (truncate (/ total char-w))))
              (setq scroll-config--hscroll-residual (- total (* cols char-w)))
              (unless (zerop cols)
                (if (eq direction 'wheel-left)
                    (scroll-right cols t)
                  (scroll-left cols t))))
          ;; Fallback for events without pixel data (e.g. physical tilt wheel).
          (if (eq direction 'wheel-left)
              (scroll-right 3 t)
            (scroll-left 3 t)))))))

(global-set-key (kbd "<wheel-left>")  #'scroll-config-horizontal)
(global-set-key (kbd "<wheel-right>") #'scroll-config-horizontal)

;;; -- Disable zoom bindings ---------------------------------------------------

;; Disable ctrl+scroll zoom (too fast; use keyboard to change font size instead).
(global-set-key (kbd "<C-wheel-up>") 'ignore)
(global-set-key (kbd "<C-wheel-down>") 'ignore)
(global-set-key (kbd "<C-mouse-4>") 'ignore)
(global-set-key (kbd "<C-mouse-5>") 'ignore)

(provide 'scroll-config)

;;; scroll-config.el ends here
