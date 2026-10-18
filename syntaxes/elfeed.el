;;; syntaxes/elfeed.el --- Elfeed display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-elfeed t
  "Whether to enable Elfeed settings from syntaxes/elfeed.el.")

(when emacs-config-syntaxes-enable-elfeed
  ;; The entry list and the entry view.
  (dolist (hook '(elfeed-search-mode-hook elfeed-show-mode-hook))
    (add-hook hook
              (lambda ()
                (display-line-numbers-mode -1)))))

(provide 'syntaxes-elfeed)

;;; syntaxes/elfeed.el ends here
