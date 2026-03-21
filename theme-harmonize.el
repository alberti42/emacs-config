;;; theme-harmonize.el --- Synchronize package faces after theme changes -*- lexical-binding: t; -*-

;;; Code:

(defvar emacs-config-harmonize-tty-line-number-light nil
  "TTY line-number face background color for light appearance.
When non-nil, overrides the theme default to match the terminal emulator's
padding color (e.g. WezTerm border) so the gutter blends with the frame edge.
Example: \"#eff1f5\" for Catppuccin Latte.")

(defvar emacs-config-harmonize-tty-line-number-dark nil
  "TTY line-number face background color for dark appearance.
When non-nil, overrides the theme default to match the terminal emulator's
padding color (e.g. WezTerm border) so the gutter blends with the frame edge.
Example: \"#303446\" for Catppuccin Frappe.")

(defun emacs-config-harmonize-theme (&rest _)
  "Synchronize package faces with the active theme.
Called after every theme change and once at startup.
Add face propagation here as new packages need harmonizing."
  (when (not (display-graphic-p))
    ;; Override line-number background to match the terminal emulator's padding
    ;; color, so the gutter column blends with the terminal border.
    (let* ((dark-p (eq (frame-parameter nil 'background-mode) 'dark))
           (color  (if dark-p
                       emacs-config-harmonize-tty-line-number-dark
                     emacs-config-harmonize-tty-line-number-light)))
      (when color
        (set-face-background 'line-number color)))
    ;; git-gutter: blend gutter column with line-number background.
    (let ((line-number-bg (face-background 'line-number nil t)))
      (when line-number-bg
        (dolist (face '(git-gutter:added
                        git-gutter:modified
                        git-gutter:deleted
                        git-gutter:unchanged
                        git-gutter:separator))
          (when (facep face)
            (set-face-background face line-number-bg)))))))

;; Fire on every theme change (Emacs 29+).
(add-hook 'enable-theme-functions #'emacs-config-harmonize-theme)

(provide 'theme-harmonize)
;;; theme-harmonize.el ends here
