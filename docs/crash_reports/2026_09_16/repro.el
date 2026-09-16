;;; repro.el --- crash display_mode_line by freeing the row it writes into  -*- lexical-binding: t; -*-
;; Run:  Emacs -Q -l repro.el   (needs a GUI frame; TTY matrices are different)
;;
;; What goes wrong:
;;   1. pos-visible-in-window-p needs to know how tall the mode line is, so it
;;      calls display_mode_line.  That function saves a pointer to one row of
;;      the window's glyph matrix and writes the mode-line text into that row,
;;      one character at a time.
;;   2. Writing the mode line means evaluating the :eval form below.  This one
;;      calls set-window-vscroll.
;;   3. A bigger vscroll needs more rows, so Emacs allocates a bigger row array
;;      and frees the old one.
;;   4. display_mode_line continues and writes through its saved pointer, which
;;      now points into freed memory.  Emacs crashes.
;;
;; repro-timer.el is the same bug, reached through a timer, which is how the
;; real crash happened.
;;
;; Freed memory often still holds usable values, so the bad write can go
;; unnoticed.  MallocScribble=1 fills freed memory with 0x55, so it fails at
;; once:
;;   MallocScribble=1 lldb -b -o run -- Emacs -Q -l repro.el
(defvar repro-win nil)
(defvar repro-count 0)
(defun repro-modeline ()
  (setq repro-count (1+ repro-count))
  ;; Scroll only the first three times, so that the test ends once a fix works.
  ;; Without a fix, Emacs crashes on the first scroll and the limit never
  ;; matters.  With a fix, Emacs does not crash: it redraws the window again
  ;; instead.  Redrawing writes the mode line, which calls this function again.
  ;; If this function scrolled every time, Emacs would redraw for ever.
  (when (<= repro-count 3)
    (set-window-vscroll repro-win (+ (window-vscroll repro-win t) 2000) t))
  (format "repro %d" repro-count))
(with-current-buffer (get-buffer-create "*repro*")
  (dotimes (_ 300) (insert "line of text\n"))
  (setq-local mode-line-format '(:eval (repro-modeline))))
(switch-to-buffer "*repro*")
(setq repro-win (selected-window))
(redisplay t)
(dotimes (_ 12)
  (pos-visible-in-window-p (point-min) repro-win t))
;; Use the window normally afterwards, so a matrix left too small would show.
(dotimes (_ 3) (redisplay t) (scroll-up 3) (redisplay t))
(message "repro: survived %d mode-line evaluations, vscroll now %d"
         repro-count (window-vscroll repro-win t))
(kill-emacs 0)
