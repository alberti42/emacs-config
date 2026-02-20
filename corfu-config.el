;;; corfu-config.el --- In-buffer completion UI (Corfu) -*- lexical-binding: t; -*-

;; Corfu is a completion-at-point UI (in-buffer), not a minibuffer completion UI.
(use-package corfu
  :init
  (setq corfu-auto t
        corfu-auto-delay 0.1
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-preselect 'prompt
        corfu-quit-no-match 'separator)
  :config
  (global-corfu-mode 1))

;; TTY support for Corfu.
(use-package corfu-terminal
  :if (not window-system)
  :after corfu
  :config
  (corfu-terminal-mode 1))

(provide 'corfu-config)
;;; corfu-config.el ends here
