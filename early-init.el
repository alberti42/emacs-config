;;; early-init.el --- Early init -*- no-byte-compile: t; lexical-binding: t; -*-

;; Prefer loading newest version of a file (typically the non-compiled version)
(setq load-prefer-newer t)

;; Emacs ships with a built-in package manager called package.el.  Our Emacs
;; config uses straight.el instead.  If package.el also auto-enables packages
;; from ~/.config/emacs/elpa at startup, we can end up loading two different
;; copies of the same package.  That leads to confusing warnings/bugs.
(setq package-enable-at-startup nil)

;; LSP servers (and other subprocess-heavy code) generate a lot of garbage from
;; client/server JSON traffic.  The default 800KB threshold causes frequent GC
;; pauses; 100MB is the lsp-mode docs' recommendation and matches what
;; Doom/Spacemacs/Prelude ship.
;; https://emacs-lsp.github.io/lsp-mode/page/performance/
(setq gc-cons-threshold (* 100 1024 1024))

;; Tell lsp-mode to use plists instead of hash-tables for JSON deserialization.
;; Must be set before lsp-mode is byte-compiled or loaded; the flag is read at
;; compile time.  Pair with `(setq lsp-use-plists t)' in `lsp-core.el'.  This
;; setting is reported to improve performance:
;; https://emacs-lsp.github.io/lsp-mode/page/performance/
(setenv "LSP_USE_PLISTS" "true")

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

;;; early-init.el ends here
