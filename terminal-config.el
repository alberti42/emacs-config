;;; terminal-config.el --- Terminal emulator configuration -*- lexical-binding: t; -*-

;; Use xterm-256color instead of default 8-color-based `eterm-color`
;; terminfo for better terminal UX
(setq term-term-name "xterm-256color")
(setq eshell-term-name "xterm-256color")

;; Initialize ESHELL to shell-file-name (which in turn is initialized to $SHELL)
(setenv "ESHELL" shell-file-name)

;; Close the window (and kill the buffer) when the terminal process exits
(with-eval-after-load 'term
  (advice-add 'term-handle-exit :after
    (lambda (&rest _) (quit-window t))))

;; vterm: fast, accurate terminal emulator backed by libvterm.
(use-package vterm
  :straight t
  :custom
  ;; like for term, set the default shell to shell-file-name (equivalent to $SHELL)
  (vterm-shell shell-file-name))

(provide 'terminal-config)
;;; terminal-config.el ends here
