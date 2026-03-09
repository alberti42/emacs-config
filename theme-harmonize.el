;;; theme-harmonize.el --- Synchronize package faces after theme changes -*- lexical-binding: t; -*-

;;; Code:

(defun emacs-config-harmonize-theme (&rest _)
  "Synchronize package faces with the active theme.
Called after every theme change and once at startup.
Add face propagation here as new packages need harmonizing."
  (when (not (display-graphic-p))
    (let ((line-number-bg (face-background 'line-number nil t)))
      (when line-number-bg
        ;; git-gutter: blend gutter column with line-number background.
        (dolist (face '(git-gutter:added
                        git-gutter:modified
                        git-gutter:deleted
                        git-gutter:unchanged
                        git-gutter:separator))
          (when (facep face)
            (set-face-background face line-number-bg)))))))

;; Fire on every theme change (Emacs 29+).
(add-hook 'enable-theme-functions #'emacs-config-harmonize-theme)

;; Apply immediately for the theme already loaded at startup.
(emacs-config-harmonize-theme)

(provide 'theme-harmonize)
;;; theme-harmonize.el ends here
