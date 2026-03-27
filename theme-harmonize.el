;;; theme-harmonize.el --- Synchronize package faces after theme changes -*- lexical-binding: t; -*-

;;; Code:

(defvar theme-harmonize-tty-line-number nil
  "Plist specifying TTY line-number face background color for :light and
:dark appearance. It is used to override the theme default to match the
terminal emulator's padding color (e.g. WezTerm border) so the gutter
blends with the frame edge.

When nil, this theme customization is ignored.

Example: (:light \"#eff1f5\" :dark \"#303446\") for Catppuccin.")

(defun theme-harmonize-theme (&rest _)
  "Synchronize package faces with the active theme.
Called after every theme change and once at startup.
Add face propagation here as new packages need harmonizing."
  (when (not (display-graphic-p))
    ;; Override line-number background to match the terminal emulator's padding
    ;; color, so the gutter column blends with the terminal border.
    (let* ((dark-p (eq (frame-parameter nil 'background-mode) 'dark))
           (line-number-bg-color (if theme-harmonize-tty-line-number
                                     (if dark-p
                                         (plist-get theme-harmonize-tty-line-number :dark)
                                       (plist-get theme-harmonize-tty-line-number :light))
                                   nil)))
      (when line-number-bg-color
        (set-face-background 'line-number line-number-bg-color)))

    ;; git-gutter: blend gutter with line-number column; derive indicator colors
    ;; from the active theme's diff-indicator faces so appearance tracks the theme.
    (let ((bg (face-background 'line-number nil t)))
      (when bg
        ;; Background: match line-number so the gutter blends with the border.
        (dolist (face '(git-gutter:added git-gutter:modified git-gutter:deleted
                        git-gutter:unchanged git-gutter:separator))
          (when (facep face)
            (set-face-background face bg)))
        ;; Foreground for indicators: derived from standard diff-indicator faces.
        (dolist (pair '((git-gutter:added    . diff-indicator-added)
                        (git-gutter:modified . diff-indicator-changed)
                        (git-gutter:deleted  . diff-indicator-removed)))
          (when (and (facep (car pair)) (facep (cdr pair)))
            (let ((fg (face-foreground (cdr pair) nil t)))
              (when fg
                (set-face-foreground (car pair) fg)))))
        ;; Foreground for invisible spaces: match background so no artifact shows.
        (dolist (face '(git-gutter:unchanged git-gutter:separator))
          (when (facep face)
            (set-face-foreground face bg)))))))

;; Fire on every theme change (Emacs 29+).
(add-hook 'enable-theme-functions #'theme-harmonize-theme)

(provide 'theme-harmonize)
;;; theme-harmonize.el ends here
