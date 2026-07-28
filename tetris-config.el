;;; tetris-config.el --- Tetris game tuning -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Configuration for the built-in `tetris' game -- specifically the fall
;; speed, which stock Emacs makes far too slow and, worse, nearly
;; impossible to tune via the obvious variable.
;;
;; WHY THE OBVIOUS KNOB DOESN'T WORK.  `tetris-start-game' picks its timer
;; period with
;;
;;     (or (tetris-get-tick-period) tetris-default-tick-period)
;;
;; and `tetris-get-tick-period' calls `tetris-update-speed-function', whose
;; stock value `tetris-default-update-speed-function' ALWAYS returns a
;; number:
;;
;;     (defun tetris-default-update-speed-function (_shapes rows)
;;       (/ 20.0 (+ 50.0 rows)))
;;
;; Because that `or' branch is never nil, `tetris-default-tick-period' is
;; effectively dead code -- setting it changes nothing.  The stock curve
;; starts at 20/50 = 0.4 s per row-drop and only accelerates as *cleared
;; rows* pile up (it ignores dropped shapes entirely): it does not reach
;; 0.2 s until 50 lines are cleared.  That is why Tetris "feels slow" -- it
;; is a game-logic default, not Emacs's single-threaded event loop.
;;
;; THE FIX.  We replace `tetris-update-speed-function' with our own curve
;; that (a) starts at `tetris-config-tick-period', (b) accelerates with both
;; dropped shapes and cleared rows, and (c) never drops below
;; `tetris-config-min-tick-period'.

;;; Code:

(defvar tetris-config-tick-period 0.05
  "Initial Tetris fall interval, in seconds.  Smaller is faster.")

(defvar tetris-config-min-tick-period 0.01
  "Fastest Tetris fall interval, in seconds.  The speed curve floors here.")

(defun tetris-config-update-speed-function (shapes rows)
  "Return the Tetris fall interval for SHAPES dropped and ROWS cleared.
Starts at `tetris-config-tick-period' and accelerates with play, unlike the
stock curve which only speeds up on cleared lines and starts at a fixed
0.4 s regardless of `tetris-default-tick-period'."
  (max tetris-config-min-tick-period
       (* tetris-config-tick-period
          (/ 50.0 (+ 50.0 rows (* 0.5 shapes))))))

(use-package tetris
  :straight nil
  :defer t
  :commands (tetris)
  :config
  ;; Kept for completeness (it is the fallback when the speed function
  ;; returns non-numeric), but the real control is the function below.
  (setq tetris-default-tick-period tetris-config-tick-period)
  (setq tetris-update-speed-function #'tetris-config-update-speed-function))

(provide 'tetris-config)
;;; tetris-config.el ends here
