;;; terminal-config.el --- Terminal emulator configuration -*- lexical-binding: t; -*-

;; Use xterm-256color instead of default 8-color-based `eterm-color`
;; terminfo for better terminal UX
(setq term-term-name "xterm-256color")
(setq eshell-term-name "xterm-256color")

;; Initialize ESHELL to shell-file-name (which in turn is initialized to $SHELL)
(setenv "ESHELL" shell-file-name)

;; Override term to skip the prompt, using shell-file-name
;; Lazy-loading of term
(with-eval-after-load 'term
  (fset 'term--original (symbol-function 'term))
  (defun term (program)
    (interactive (list shell-file-name))
    (term--original program))

  ;; Close the window (and kill the buffer) when the terminal process exits
  (advice-add 'term-handle-exit :after
    (lambda (&rest _) (quit-window t))))

;; vterm: fast, accurate terminal emulator backed by libvterm.
(use-package vterm
  :straight t)

(provide 'terminal-config)
;;; terminal-config.el ends here
