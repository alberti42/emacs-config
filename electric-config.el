;;; electric-config.el --- electric-pair-mode policy + region wrapping -*- lexical-binding: t; -*-

;; electric-pair-mode earns its keep in code buffers: balance-aware
;; auto-closing, type-over of an existing closer, and string/comment
;; context handling.  We keep all of that, but disable the one behavior
;; that is noise rather than an accelerator: auto-inserting a closing
;; quote (" ' `) on a bare keypress ("type one, get two").
;;
;; The region-wrap feature -- select text, type a delimiter, get the
;; selection surrounded -- lives in a separate branch of
;; `electric-pair-post-self-insert-function' that never consults the
;; inhibit predicate, so suppressing quote auto-close leaves wrapping
;; intact.  `my/wrap-region-or-self-insert' extends that same
;; wrap-or-insert idea to characters electric-pair does not treat as
;; pairs (e.g. Markdown ` and *); callers bind it to those keys.

(defvar-local my/wrap--state nil
  "Bookkeeping for repeat-to-add-a-level wrapping.
Either nil or a list (CHAR BEG-MARKER END-MARKER LEVEL): CHAR is the
delimiter, the markers bracket the whole wrapped span (BEG stays before
the opening run, END after the closing run), LEVEL is the current
delimiter count per side.  Consulted only when this command runs twice
in a row (`last-command'), so a stale entry is harmless.")

(defun my/wrap-region-or-self-insert (n &optional max-level)
  "Surround the active region with the typed delimiter, else self-insert it.
With a region active, wrap the selection in N copies of the typed
character on each side (e.g. `code`, *emphasis*; a prefix arg such as
`C-u 2 *' yields **bold** directly).  With no region, insert N literal
copies.

When MAX-LEVEL is non-nil, pressing the same key again immediately after
a wrap adds one more delimiter on each side, cycling *x* -> **x** ->
***x*** up to MAX-LEVEL delimiters (the region is gone by then -- the
buffer edit deactivated it -- so the span is tracked via markers
instead).  MAX-LEVEL nil (the default) disables cycling: one wrap only.
It is supplied at the binding site rather than read from a variable,
since each repeat is a fresh command invocation -- see the `*' binding
in syntaxes/markdown.el, which passes 3 while ` keeps the default.

Bound to same-character delimiters that `electric-pair-mode' does not
pair (Markdown ` and *).  Deliberately avoids `electric-pair-pairs',
whose entries come back as unconditional and would force an auto-paired
second delimiter on every keypress that no inhibit predicate can stop."
  (interactive "p")
  (let ((char last-command-event))
    (cond
     ;; Fresh wrap of the active region.
     ((use-region-p)
      (let ((beg-m (copy-marker (region-beginning) nil))
            (end-m (copy-marker (region-end) t)))
        (save-excursion
          (goto-char end-m) (insert-char char n)
          (goto-char beg-m) (insert-char char n))
        (goto-char end-m)
        (setq my/wrap--state (list char beg-m end-m n))))
     ;; Repeat: add one delimiter each side, upgrading the emphasis level.
     ((and max-level
           (eq last-command this-command)
           my/wrap--state
           (eq char (nth 0 my/wrap--state))
           (< (nth 3 my/wrap--state) max-level))
      (pcase-let ((`(,_ ,beg-m ,end-m ,level) my/wrap--state))
        (save-excursion
          (goto-char end-m) (insert-char char 1)
          (goto-char beg-m) (insert-char char 1))
        (goto-char end-m)
        (setq my/wrap--state (list char beg-m end-m (1+ level)))))
     ;; Plain self-insert.
     (t
      (setq my/wrap--state nil)
      (self-insert-command n char)))))

;; `electric-pair-mode' invokes this function before inserting the matching
;; closer. If the predicate returns non-nil, the closer is suppressed. It can
;; used to disable the automatic pairing for certain characters. It is currently
;; disabled.
(when nil
  (setq electric-pair-inhibit-predicate
        (lambda (char)
          (if (memq char '(?\" ?\' ?\`))
              t
            (electric-pair-default-inhibit char)))))

(electric-pair-mode 1)

(provide 'electric-config)
;;; electric-config.el ends here
