;;; early-init.el --- Early init -*- no-byte-compile: t; lexical-binding: t; -*-
(setq load-prefer-newer t)

;; Import shell environment before straight.el and package lookups run,
;; so PATH is correct from the very start.  Uses the same file-truename
;; trick as init.el to work through the ~/.config/emacs symlink.
;; Skipped for daemon: the launcher already set up the environment.
(unless (daemonp)
  (let ((dir (file-name-directory (file-truename (or load-file-name buffer-file-name)))))
    (load (expand-file-name "env-config" dir) nil 'nomessage)))

;;; early-init.el ends here
