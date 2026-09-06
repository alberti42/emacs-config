;;; syntaxes/osx-dictionary.el --- osx-dictionary display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-osx-dictionary t
  "Whether to enable osx-dictionary settings from syntaxes/osx-dictionary.el.")

(when emacs-config-syntaxes-enable-osx-dictionary
  (add-hook 'osx-dictionary-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-osx-dictionary)

;;; osx-dictionary.el ends here
