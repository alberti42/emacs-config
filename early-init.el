;;; early-init.el --- Early init -*- no-byte-compile: t; lexical-binding: t; -*-

;; Prefer loading newest version of a file (typically the non-compiled version)
(setq load-prefer-newer t)

;; Emacs ships with a built-in package manager called package.el.  Our Emacs
;; config uses straight.el instead.  If package.el also auto-enables packages
;; from ~/.config/emacs/elpa at startup, we can end up loading two different
;; copies of the same package.  That leads to confusing warnings/bugs.
(setq package-enable-at-startup nil)

;; Import shell environment before straight.el and package lookups run,
;; so PATH is correct from the very start.  Uses the same file-truename
;; trick as init.el to work through the ~/.config/emacs symlink.
;; Skipped for daemon: the launcher already set up the environment.
(unless (daemonp)
  (let ((dir (file-name-directory (file-truename (or load-file-name buffer-file-name)))))
    (load (expand-file-name "env-config" dir) nil 'nomessage)))

;; Default font for GUI frames (TTY frames ignore font face attributes).
(set-face-attribute 'default nil :family "JetBrainsMonoNL Nerd Font Mono" :height 180 :weight 'light)

;;; early-init.el ends here
