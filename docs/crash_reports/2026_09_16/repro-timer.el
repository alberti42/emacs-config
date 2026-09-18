;;; repro-timer.el --- crash display_mode_line by freeing the row it writes into  -*- lexical-binding: t; -*-
;; Evaluate this file in emacs -Q with a GUI frame; the TTY matrix code differs.
;;
;; Same bug as repro.el, reached the way the real crash reached it.
;;
;; What goes wrong:
;;   1. Redisplay calls display_mode_line to write this buffer's mode line.
;;      That function saves a pointer to one row of the window's glyph matrix
;;      and writes the mode-line text into that row, one character at a time.
;;   2. Writing the mode line means evaluating the :eval form below, which is
;;      ordinary Lisp.  This one calls sleep-for, and sleep-for runs any timer
;;      that is due before it returns.
;;   3. The timer calls set-window-vscroll.  A bigger vscroll needs more rows,
;;      so Emacs allocates a bigger row array and frees the old one.
;;   4. display_mode_line continues and writes through its saved pointer, which
;;      now points into freed memory.  Emacs crashes.
;;
;; Freed memory often still holds usable values, so the bad write can go
;; unnoticed.  To make it fail every time, start Emacs with freed memory
;; poisoned: MallocScribble=1 on macOS, MALLOC_PERTURB_=85 with glibc.
;;
;; In the real crash, step 2 was pdf-misc-size-indication in pdf-tools asking the epdfinfo
;; process for a page size and waiting in accept-process-output, and step 3 was
;; a LaTeX process sentinel that ran during that wait and scrolled the window.
;; sleep-for does the same job here as accept-process-output did there: it lets
;; other Lisp run while the mode line is only half written.
(defvar repro-win nil)
(defvar repro-count 0)

(defun repro-scroll ()
  "Scroll the window.  Called from a timer, never from the mode line."
  (when (window-live-p repro-win)
    (set-window-vscroll repro-win (+ (window-vscroll repro-win t) 2000) t)))

(defun repro-modeline ()
  "The :eval form in the mode line.  Lets a timer run while the mode line is
being written, so the timer can free the row that display_mode_line is
writing into."
  (setq repro-count (1+ repro-count))
  ;; Set up the scroll, then let the timer run.
  ;; Scroll only the first three times, so that the test ends once a fix works.
  ;; Without a fix, Emacs crashes on the first scroll and the limit never
  ;; matters.  With a fix, Emacs does not crash: it redraws the window again
  ;; instead.  Redrawing writes the mode line, which calls this function again.
  ;; If this function scrolled every time, Emacs would redraw for ever.
  (when (<= repro-count 3)
    (run-at-time 0 nil #'repro-scroll)
    ;; The timer runs here, before sleep-for returns.
    (sleep-for 0.2))
  (format "repro %d" repro-count))

(setq repro-count 0)           ; so the file can be evaluated again
(with-current-buffer (get-buffer-create "*repro*")
  (erase-buffer)
  (dotimes (_ 300) (insert "line of text\n"))
  (setq-local mode-line-format '(:eval (repro-modeline))))
(switch-to-buffer "*repro*")
(setq repro-win (selected-window))
(redisplay t)
(dotimes (_ 12)
  (pos-visible-in-window-p (point-min) repro-win t))
;; Use the window normally afterwards, so a matrix left too small would show.
(dotimes (_ 3) (redisplay t) (scroll-up 3) (redisplay t))
(message "repro-timer: %d mode-line evaluations, vscroll now %d"
         repro-count (window-vscroll repro-win t))
