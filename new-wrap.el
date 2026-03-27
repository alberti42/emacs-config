;;; new-wrap.el --- Temporary soft wrap stubs -*- lexical-binding: t; -*-

;; Code

;; Stopgap module.
;;
;; The syntaxes hooks call `soft-wrap-enable' (and in Markdown also
;; `adaptive-wrap-prefix-mode').  If the real wrapping implementation is not
;; loaded, those hooks error during `find-file', which can cascade into other
;; startup/runtime issues.
;;
;; This file provides no-op stubs so the rest of the config can function while
;; soft-wrap is being rebuilt.

(defun soft-wrap-enable (&optional _width)
  "Stopgap: no-op soft wrap enable.

WIDTH is accepted for API compatibility." 
  (interactive "P")
  nil)

(defun soft-wrap-disable ()
  "Stopgap: no-op soft wrap disable." 
  (interactive)
  nil)

;; Markdown config enables this; provide a stub until the real dependency is
;; restored.
(defun adaptive-wrap-prefix-mode (&optional _arg)
  "Stopgap: no-op adaptive wrap prefix mode." 
  (interactive "P")
  nil)

(provide 'new-wrap)
;;; new-wrap.el ends here
