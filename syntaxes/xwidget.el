;;; syntaxes/xwidget.el --- xwidget-webkit display settings -*- lexical-binding: t; -*-

;; `xwidget-webkit-mode' (xwidget.el) renders an embedded webkit view — used
;; here by typst-preview.  A line-number gutter over a web view is noise, so
;; turn it off (it is otherwise on via `global-display-line-numbers-mode').

(defvar emacs-config-syntaxes-enable-xwidget t
  "Whether to enable xwidget settings from syntaxes/xwidget.el.")

(when emacs-config-syntaxes-enable-xwidget
  (add-hook 'xwidget-webkit-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-xwidget)

;;; syntaxes/xwidget.el ends here
