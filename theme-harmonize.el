;;; theme-harmonize.el --- Synchronize package faces after theme changes -*- lexical-binding: t; -*-

;;; Code:

(defvar theme-harmonize-tty-line-number nil
  "Plist specifying TTY line-number face background color for :light and
:dark appearance. It is used to override the theme default to match the
terminal emulator's padding color (e.g. WezTerm border) so the gutter
blends with the frame edge.

When nil, this theme customization is ignored.

Example: (:light \"#eff1f5\" :dark \"#303446\") for Catppuccin.")

(defvar theme-harmonize-git-gutter-colors nil
  "Plist of git-gutter indicator colors for :light and :dark appearance.
  Each value is a plist with :added, :modified, :deleted keys.
  Example: (:light (:added \"#00aa00\" :modified \"#aaaa00\" :deleted \"#aa0000\")
            :dark  (:added \"#00ff00\" :modified \"#ffff00\" :deleted \"#ff0000\"))")

(defun theme-harmonize-theme (&rest _)
  "Synchronize package faces with the active theme.
Called after every theme change and once at startup.
Add face propagation here as new packages need harmonizing."
  ;; TTY only: override line-number background to match the terminal emulator's
  ;; padding color, so the gutter column blends with the terminal border.
  (when (not (display-graphic-p))
    (let* ((dark-p (eq (frame-parameter nil 'background-mode) 'dark))
           (line-number-bg-color (if theme-harmonize-tty-line-number
                                     (if dark-p
                                         (plist-get theme-harmonize-tty-line-number :dark)
                                       (plist-get theme-harmonize-tty-line-number :light))
                                   nil)))
      (when line-number-bg-color
        (set-face-background 'line-number line-number-bg-color))))

  ;; customize margin color after bug#80693
  (let ((bg (face-background 'line-number nil t)))
    ;; guard against the patch being installed
    (when (facep 'margin)
      (set-face-background 'margin bg)))

  ;; flymake margin indicators: set background to match the line-number face so
  ;; the indicator characters blend with the left-margin column background.
  ;; The three faces cover error, warning, and note severity levels.
  (let ((bg (face-background 'line-number nil t)))
    (when bg
      (dolist (face '(compilation-error compilation-warning compilation-info))
        (when (facep face)
          (set-face-background face bg)))))

  ;; git-gutter: blend gutter with line-number column; derive indicator colors
  ;; from the active theme's diff-indicator faces so appearance tracks the theme.
  ;; Runs for both TTY and GUI frames.
  (let ((bg (face-background 'line-number nil t)))
    (when bg
      ;; Background: match line-number so the gutter blends with the border.
      (dolist (face '(git-gutter:added git-gutter:modified git-gutter:deleted
                                       git-gutter:unchanged git-gutter:separator))
        (when (facep face)
          (set-face-background face bg)))
      ;; Foreground for indicators
      (when theme-harmonize-git-gutter-colors
        (let* ((dark-p (eq (frame-parameter nil 'background-mode) 'dark))
               (palette (if dark-p
                            (plist-get theme-harmonize-git-gutter-colors :dark)
                          (plist-get theme-harmonize-git-gutter-colors :light))))
          (dolist (pair '((git-gutter:added    . :added)
                          (git-gutter:modified . :modified)
                          (git-gutter:deleted  . :deleted)))
            (let ((color (plist-get palette (cdr pair)))
                  (face (car pair)))
              ;; Set the foreground face based to 'color
              (when (and color (facep face))
                (set-face-foreground face color))))))      
      ;; Foreground for invisible spaces: match background so no artifact shows.
      (dolist (face '(git-gutter:unchanged git-gutter:separator))
        (when (facep face)
          (set-face-foreground face bg))))))

;; Fire on every theme change (Emacs 29+).
(add-hook 'enable-theme-functions #'theme-harmonize-theme)

(provide 'theme-harmonize)
;;; theme-harmonize.el ends here
