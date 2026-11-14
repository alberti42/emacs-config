;;; repro.el --- Reproduce a bidi abort in pixel measurement -*- lexical-binding: t; -*-

;; Run in a separate graphical Emacs:
;;   Emacs -Q --load /absolute/path/to/repro.el
;; Tested with macOS NS Emacs 32.0.50.  No packages are required.
;; The affected build aborts; a build that survives the call exits normally.

(run-at-time
 0.5 nil
 (lambda ()
   (switch-to-buffer (generate-new-buffer "*bidi-repro*"))
   (insert "x\n")
   (setq-local line-prefix "")
   (overlay-put (make-overlay 1 1) 'before-string "a\nb\n")
   (window-text-pixel-size nil (cons 3 -1) 3)
   (kill-emacs 0)))

;;; repro.el ends here
