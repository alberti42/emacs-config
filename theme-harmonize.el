;;; theme-harmonize.el --- Synchronize package faces after theme changes -*- lexical-binding: t; -*-

;;; Code:

(defvar theme-harmonize-line-number-bg nil
  "Plist specifying line-number face background color for :light and :dark
appearance.  Applied to both TTY and GUI frames so the gutter column, left
margin, and fringes share a single consistent color regardless of frame type.

When nil, this theme customization is ignored.

Example: (:light \"#eff1f5\" :dark \"#303446\") for Catppuccin.")

(defvar theme-harmonize-git-gutter-colors nil
  "Plist of git-gutter indicator colors for :light and :dark appearance.
  Each value is a plist with :added, :modified, :deleted keys.
  Example: (:light (:added \"#00aa00\" :modified \"#aaaa00\" :deleted \"#aa0000\")
            :dark  (:added \"#00ff00\" :modified \"#ffff00\" :deleted \"#ff0000\"))")

(defun theme-harmonize-theme (&rest _)
  "Synchronize package faces with the active theme.
Called after every theme change and on new frame creation.
Add face propagation here as new packages need harmonizing."
  ;; Override line-number background for both TTY and GUI to ensure a single
  ;; consistent visual style (e.g. Catppuccin) regardless of frame type.
  ;; This also prevents daemon mode from producing different results depending
  ;; on whether the triggering frame was a TTY or GUI client.
  (let* ((dark-p (eq (frame-parameter nil 'background-mode) 'dark))
         (line-number-bg-color (when theme-harmonize-line-number-bg
                                 (if dark-p
                                     (plist-get theme-harmonize-line-number-bg :dark)
                                   (plist-get theme-harmonize-line-number-bg :light)))))
    (when line-number-bg-color
      (set-face-background 'line-number line-number-bg-color)))

  ;; Propagate line-number background to margin (bug#80693) and fringes so all
  ;; three columns share the same color in both TTY and GUI frames.
  (let ((bg (face-background 'line-number nil t)))
    (when (facep 'margin)
      (set-face-background 'margin bg))
    (when (facep 'fringe)
      (set-face-background 'fringe bg)))

  ;; flycheck fringe indicators: set background to match the line-number face so
  ;; the indicator bitmaps blend with the left fringe/margin column background.
  ;; The three faces cover error, warning, and info severity levels.
  (let ((bg (face-background 'line-number nil t)))
    (when bg
      (dolist (face '(flycheck-fringe-error flycheck-fringe-warning flycheck-fringe-info))
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

;; Fire on new frame creation so that emacsclient GUI frames (connecting to a
;; daemon that may have initialized without a graphical frame) and TTY frames
;; opened alongside an existing GUI session both receive the correct faces.
(add-hook 'after-make-frame-functions
          (lambda (frame)
            (with-selected-frame frame
              (theme-harmonize-theme))))

(provide 'theme-harmonize)
;;; theme-harmonize.el ends here
