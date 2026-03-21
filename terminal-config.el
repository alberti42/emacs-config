;;; terminal-config.el --- Terminal emulator configuration -*- lexical-binding: t; -*-

;; Use xterm-256color instead of default 8-color-based `eterm-color`
;; terminfo for better terminal UX
(setq term-term-name "xterm-256color")
(setq eshell-term-name "xterm-256color")

;; vterm: fast, accurate terminal emulator backed by libvterm.
(use-package vterm
  :straight t)

(provide 'terminal-config)
;;; terminal-config.el ends here
