;;; jit-lock-config.el --- jit-lock: whole chunks over short invisible runs -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Since Emacs 29, `jit-lock-function' ends each chunk at the next change
;; of the `invisible' property (commit 91a79eedf6c, bug#57447), so that the
;; text in an outline fold is not fontified.  When the invisible text is
;; short and frequent, as with markup hidden by `markdown-ts-mode' (every
;; backtick of an inline code span is invisible), a chunk ends at the next
;; backtick and the backtick is a chunk of its own.  font-lock widens each
;; of these pieces to whole lines, so a line with ten code spans is
;; fontified about twenty times.  Scrolling a list whose lines hold many
;; code spans hung Emacs for several seconds: moving across 300 lines took
;; 3.01 s and 854 calls of `font-lock-fontify-region'.
;;
;; `jit-lock-config--function' is `jit-lock-function' with one change: it
;; stops at invisible text only when that text reaches the end of the
;; chunk, as a fold does.  A short invisible run no longer ends the chunk.
;; The same 300 lines take 0.098 s and 21 calls, and a fold that runs to
;; the end of the chunk still stops it.  An invisible run that ends inside
;; the chunk is fontified: at most `jit-lock-chunk-size' characters.
;;
;; The function copies `jit-lock-function' of Emacs 32.0.50 (the same in
;; Emacs 30).  After an Emacs upgrade, compare the two; remove this module
;; once Emacs has a fix.  The bug is not filed yet; notes, recipe and
;; patch are in ~/org/Work/04 Computer related/2026/
;; "2026-11-28 Emacs fix for slow scrolling due to jit-lock misbehaving.org".

;;; Code:

(require 'jit-lock)

(defun jit-lock-config--function (start)
  "Fontify current buffer starting at position START.
`jit-lock-function' with one change: stop at invisible text only when
it reaches the end of the chunk.  Installed as an `:override' advice."
  (when (and jit-lock-mode (not memory-full))
    (if (not (and jit-lock-defer-timer
                  (or (not (eq jit-lock-defer-time 0))
                      (input-pending-p))))
        ;; No deferral.
        (let* ((cend (min (point-max) (+ start jit-lock-chunk-size)))
               (vend (next-single-property-change start 'invisible nil cend)))
          ;; Presumably if we're called it means `start' is
          ;; not at EOB (nor invisible) and hence (> vend start).
          ;; Stop at invisible text only when it reaches the end of the
          ;; chunk, as a fold does.  Short invisible runs, such as hidden
          ;; markup, would cut the chunk into many small pieces.
          (when (< (next-single-property-change vend 'invisible nil cend) cend)
            (setq vend cend))
          (jit-lock-fontify-now start vend))
      ;; Record the buffer for later fontification.
      (unless (memq (current-buffer) jit-lock-defer-buffers)
        (push (current-buffer) jit-lock-defer-buffers))
      ;; Mark the area as defer-fontified so that the redisplay engine
      ;; is happy and so that the idle timer can find the places to fontify.
      (with-silent-modifications
        (put-text-property start
                           (next-single-property-change
                            start 'fontified nil
                            (min (point-max) (+ start jit-lock-chunk-size)))
                           'fontified 'defer)))))

(advice-add 'jit-lock-function :override #'jit-lock-config--function)

(provide 'jit-lock-config)
;;; jit-lock-config.el ends here
