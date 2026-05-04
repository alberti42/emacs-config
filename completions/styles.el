;;; styles.el --- Completion styles defaults -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module configures completion styles (matching) shared by minibuffer and
;; in-buffer completion. Orderless, if enabled, further adjusts these settings.
;;

;;; Code:

;; Baseline styles; Orderless (if loaded) will override `completion-styles'.
(setq completion-styles '(basic partial-completion)
      completion-category-defaults nil
      completion-category-overrides
      '((file (styles basic partial-completion))))

;; Make `completion-category-overrides' actually override.
;;
;; `completion--styles' (minibuffer.el) appends the global `completion-styles'
;; after the override styles, so e.g. `(file (styles basic partial-completion))'
;; effectively becomes `(basic partial-completion orderless)' — orderless still
;; runs as a fallback. That's surprising; an explicit per-category override
;; should mean "use these styles only".
(define-advice completion--styles
    (:around (orig metadata) override-replaces)
  (let* ((cat (completion-metadata-get metadata 'category))
         (over (completion-category-get cat 'styles)))
    (if over (cdr over) (funcall orig metadata))))

(provide 'completions-styles)
;;; styles.el ends here
