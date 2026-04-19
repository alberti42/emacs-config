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

;; Prepend local/ to load-path so patched Emacs built-ins shadow the originals.
;; Note: this does NOT shadow straight-managed packages. For those, use
;; :straight nil + :load-path explicitly.
(let ((dir (file-name-directory (file-truename (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path (expand-file-name "local" dir)))

;; Default font for GUI frames (TTY frames ignore font face attributes).  Note:
;; in `nerd-icons-config.el', we call 'set-fontset-font' for Emacs GUI to map
;; the Private Use Area (#xe000–#xffff) to 'Symbols Nerd Font Mono', preventing
;; fallback to fonts with wrong glyph metrics, like JetBrainsMonoNL, which
;; causes horizontal truncation of icons in dired and elsewhere.
(set-face-attribute 'default nil :family "JetBrainsMonoNL Nerd Font Mono" :height 180 :weight 'light)

;; Make `fixed-pitch' follow the `default' face so packages that distinguish
;; mono from proportional text (e.g. org's "mixed-fonts" mode in some themes,
;; mu4e body, `mixed-pitch-mode') render in the same font as the rest of the
;; editor.  Safe today because `default' above is already monospace.
;;
;; IF `default' IS EVER SWITCHED TO A PROPORTIONAL FONT: replace this
;; `:inherit default' with an explicit `:family' / `:height' / `:weight'
;; pointing at a monospace font — otherwise org tables, src blocks, and
;; anything else relying on `fixed-pitch' will lose fixed-width rendering.
(set-face-attribute 'fixed-pitch nil :inherit 'default)

;;; early-init.el ends here
