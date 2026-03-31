;;; syntaxes/swift.el --- Swift indentation -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-swift t
  "Whether to enable Swift settings from syntaxes/swift.el.")

(when emacs-config-syntaxes-enable-swift
  (add-hook 'swift-mode-hook
            (lambda ()
              (setq swift-mode:basic-offset 4)
              (setq indent-tabs-mode nil))))

(provide 'syntaxes-swift)

;;; syntaxes/swift.el ends here
