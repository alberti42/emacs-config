;;; repro-ghostel.el --- Exercise Ghostel pixel anchoring -*- lexical-binding: t; -*-

;; Run in a separate graphical Emacs with Ghostel and compat on load-path:
;;   Emacs -Q -L /path/to/compat -L /path/to/ghostel -l repro-ghostel.el
;; To test the line-count fallback, append:
;;   --eval '(setq ghostel--pixel-anchor-supported-p nil)'
;; Uses an existing Ghostel native module; never installs or downloads one.
;; The terminal has no shell process.  Its contents come from Ghostel's
;; public process-free terminal API (Ghostel 0.61 or later).
;;
;; The overlay and empty prefix below are SYNTHETIC test decorations.
;; They reproduce a display state, not an assertion that Ghostel normally
;; creates these decorations.  Window measurement is performed by Ghostel.
;; A surviving process exits normally after the measurement.

(setq debug-on-error t
      ghostel-module-auto-install nil)
(require 'ghostel)

(run-at-time
 0.5 nil
 (lambda ()
   (switch-to-buffer
    (ghostel-make-terminal "*ghostel-bidi-repro*" :size '(20 . 2)))
   (ghostel-write-output "x\r\n")
   (ghostel--redraw-now (current-buffer) t)
   (setq-local line-prefix "")
   ;; Longer than the terminal buffer, and spanning multiple display lines.
   (overlay-put (make-overlay (point-min) (point-min))
                'before-string
                (apply #'concat (make-list (+ 2 (point-max)) "a\n")))
   (ghostel--anchor-window (selected-window) t)
   (kill-emacs 0)))

;;; repro-ghostel.el ends here
