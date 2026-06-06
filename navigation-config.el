;;; navigation-config.el --- Cursor navigation behaviour -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Smart Home/End keys: first press jumps to beginning/end of line,
;; repeated press toggles to the first non-whitespace character or
;; last non-whitespace character respectively.
;;
;; Source: https://stackoverflow.com/a/35394552 (gavenkoa, CC BY-SA 3.0)
;;

;;; Code:

(defun my/smart-beginning-of-line ()
  "Move to the first non-whitespace character (`back-to-indentation').
If point is already there (or in the leading whitespace), move to the
beginning of the line."
  (interactive "^")
  (let ((indent (save-excursion (back-to-indentation) (point))))
    (if (> (point) indent)
        (back-to-indentation)
      (beginning-of-line))))

(defun my/smart-end-of-line ()
  "Move to the last non-whitespace character.
If point is already there (or in the trailing whitespace), move to the
end of the line."
  (interactive "^")
  (let ((last (save-excursion
                (end-of-line)
                (skip-syntax-backward " " (line-beginning-position))
                (point))))
    (if (< (point) last)
        (goto-char last)
      (end-of-line))))

;; (global-set-key [home] #'my/smart-beginning-of-line)
;; (global-set-key [end]  #'my/smart-end-of-line)
(global-set-key (kbd "C-a") #'my/smart-beginning-of-line)
(global-set-key (kbd "C-e") #'my/smart-end-of-line)

;; Register reads (`C-x r j', `C-x r SPC', `C-x r s', `C-x r i', ...) pop the
;; *Register Preview* window immediately, with command-aware filtering and
;; C-n/C-p navigation.  `insist' shows the preview and lets a second press of
;; the register name confirm the selection (plain `t' would require RET).
(setopt register-use-preview 'insist)

;; `visual-line-mode' remaps C-a/C-e to the visual-line boundaries, which are
;; determined by screen width rather than buffer content.  The two are NOT
;; symmetric: the end of a wrapped row is a useful stop (the wrap point), so C-e
;; cascades last-non-whitespace -> visual end -> physical end.  But the
;; beginning of a wrapped row sits after the display-only wrap prefix (which
;; point cannot move before), so it is not a useful target -- C-a wants the
;; physical line, which `my/smart-beginning-of-line' already does.  Hence only
;; the end command needs a visual-aware variant; C-a is left unremapped below.

(defun my/smart-end-of-visual-line ()
  "Move to the last non-whitespace character of the visual line.
On repeats, move to the end of the visual line, then to the end of the
logical line."
  (interactive "^")
  (let* ((vbol (save-excursion (beginning-of-visual-line) (point)))
         (veol (save-excursion (end-of-visual-line) (point)))
         (last (save-excursion
                 (goto-char veol)
                 (skip-syntax-backward " " vbol)
                 (point))))
    (cond
     ((< (point) last) (goto-char last))
     ((< (point) veol) (goto-char veol))
     (t (end-of-line)))))

;; `visual-line-mode-map' lives in the always-dumped `simple.el', so it is
;; present at startup and needs no `with-eval-after-load' guard.  C-e is
;; globally bound to `my/smart-end-of-line', so the visual variant is reached by
;; remapping THAT command -- not `move-end-of-line', which C-e no longer runs,
;; leaving the stock visual-line remap dead for C-e.
(define-key visual-line-mode-map [remap my/smart-end-of-line]
            #'my/smart-end-of-visual-line)

(provide 'navigation-config)

;;; navigation-config.el ends here
