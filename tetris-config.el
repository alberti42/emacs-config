;;; tetris-config.el --- Tetris game tuning -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Configuration for the built-in `tetris' game.  The two speed knobs are:
;;
;;   * `tetris-default-tick-period' -- the initial fall interval, in seconds.
;;     Smaller = faster.  Stock default is 0.3.
;;
;;   * `tetris-update-speed-function' -- called on every score change with
;;     (SHAPES ROWS); if it returns a number, that becomes the new timer
;;     period.  Stock `tetris-default-update-speed-function' ramps the speed
;;     up as more shapes are dropped.
;;
;; Here we keep the stock acceleration behaviour but expose the starting
;; speed through `tetris-config-tick-period' so it is easy to tweak.

;;; Code:

(defvar tetris-config-tick-period 0.3
  "Initial fall interval for Tetris, in seconds.  Smaller is faster.")

(use-package tetris
  :straight nil
  :defer t
  :commands (tetris)
  :config
  ;; Starting fall speed.  The stock update-speed-function accelerates from
  ;; here as the score grows.
  (setq tetris-default-tick-period tetris-config-tick-period))

(provide 'tetris-config)
;;; tetris-config.el ends here
