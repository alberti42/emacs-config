;;; early-init.el --- Early init -*- no-byte-compile: t; lexical-binding: t; -*-

;; Prefer loading newest version of a file (typically the non-compiled version)
(setq load-prefer-newer t)

;; Emacs ships with a built-in package manager called package.el.  Our Emacs
;; config uses straight.el instead.  If package.el also auto-enables packages
;; from ~/.config/emacs/elpa at startup, we can end up loading two different
;; copies of the same package.  That leads to confusing warnings/bugs.
(setq package-enable-at-startup nil)

;; Import shell environment before straight.el and package lookups run, so PATH
;; is correct from the very start.  Uses file-truename trick to work through the
;; ~/.config/emacs symlink.
(let ((dir (file-name-directory (file-truename (or load-file-name buffer-file-name)))))
  (load (expand-file-name "env-config" dir) nil 'nomessage))

;; Unset editor-selection variables so that git subprocesses (e.g. spawned
;; by Magit) never try to re-enter Emacs.  Must run unconditionally: in
;; daemon mode env-config.el is skipped, so EDITOR is already present from
;; the shell that started the daemon.  Magit sets GIT_EDITOR itself when needed.
(setq process-environment
      (seq-remove (lambda (e)
                    (member (car (split-string e "=")) '("EDITOR" "GIT_EDITOR" "VISUAL")))
                  process-environment))

;; Default font for GUI frames (TTY frames ignore font face attributes).
(set-face-attribute 'default nil :family "JetBrainsMonoNL Nerd Font Mono" :height 180 :weight 'light)

;;; early-init.el ends here
