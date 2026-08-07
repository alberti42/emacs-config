;;; terminal-config.el --- Terminal emulator configuration -*- lexical-binding: t; -*-

;;;; -- Generic settings -------------------------------------------------------

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

;;;; -- Blocking editor from Emacs ---------------------------------------------

;; eb ("emacs blocking"): blocking "open in Emacs" for use as $EDITOR from ghostel.
;;
;; The `eb` script (etc/goodies/eb, symlinked onto PATH) emits ghostel's
;; OSC 52;e escape to dispatch `eb-open-file FILE SEMAPHORE`, then polls until
;; SEMAPHORE exists.  `eb-open-file` opens the file and binds C-c C-q to
;; `eb-done`, which saves and closes the buffer.  The shell is released by
;; `eb--release` (writes SEMAPHORE) — run from BOTH `eb-done` and a buffer-local
;; `kill-buffer-hook`, so killing the buffer (C-x k) instead of C-c C-q still
;; unblocks the caller rather than hanging it forever.  No Emacs server is
;; involved.  `eb-open-file` is whitelisted in `ghostel-eval-cmds` at the bottom
;; of this file.  For a non-blocking "just open it", use `ghostel_cmd find-file'.
;;
;; `eb-open-file` also records the buffer that triggered the edit (the terminal
;; the $EDITOR call came from, current when the OSC handler runs), and on release
;; re-points the windows showing the editing buffer back to it — so finishing
;; returns you to the triggering terminal instead of whatever `kill-buffer' would
;; otherwise surface via its default previous-buffer pick.  While the edit is in
;; flight the triggering buffer is a blocked, near-empty terminal, so it also
;; carries a display-only overlay banner (never touching the process buffer's
;; text) with a button back to the editing buffer; `eb--release' removes it.
(defvar-local eb--semaphore nil
  "Semaphore path used by `eb--release' to signal editing is complete.")

(defvar-local eb--origin-buffer nil
  "Buffer that triggered this `eb' edit; restored to the fore by `eb--release'.")

(defvar-local eb--banner-overlay nil
  "Overlay in the origin buffer showing the `eb' waiting banner.")

(defun eb--release ()
  "Signal the waiting shell (write the `eb' semaphore) if still pending.
Also restore `eb--origin-buffer' in any window showing the editing buffer, so
finishing returns to the triggering terminal.  Idempotent: safe to call from
both `eb-done' and `kill-buffer-hook'."
  (when eb--semaphore
    (write-region "" nil eb--semaphore nil 'no-message)
    (setq eb--semaphore nil))
  ;; Runs from `kill-buffer-hook' before `kill-buffer' reassigns the windows, so
  ;; re-pointing them here wins: `kill-buffer' then sees no window on the dying
  ;; buffer and leaves the origin in place.
  (when (buffer-live-p eb--origin-buffer)
    (with-current-buffer eb--origin-buffer
      (when (overlayp eb--banner-overlay)
        (delete-overlay eb--banner-overlay)
        (setq eb--banner-overlay nil)))
    (dolist (win (get-buffer-window-list (current-buffer) nil t))
      (set-window-buffer win eb--origin-buffer))
    (setq eb--origin-buffer nil)))

(defun eb--waiting-banner (composer)
  "Return the banner string shown in a blocked origin buffer.
The button switches to COMPOSER, the buffer being edited."
  (concat
   "\n"
   (propertize " Waiting for the editor to finish… " 'face 'warning)
   "\n "
   (buttonize (format "[ Switch to %s ]" (buffer-name composer))
              #'pop-to-buffer composer)
   "\n"))

(defun eb--add-banner (origin composer)
  "Overlay ORIGIN with a banner linking to COMPOSER while the edit blocks.
The overlay only affects display, never the buffer's text, so it is safe on a
live terminal buffer; `eb--release' deletes it when editing finishes."
  (when (buffer-live-p origin)
    (with-current-buffer origin
      (when (overlayp eb--banner-overlay)
        (delete-overlay eb--banner-overlay))
      (let ((ov (make-overlay (point-max) (point-max))))
        (overlay-put ov 'after-string (eb--waiting-banner composer))
        (setq eb--banner-overlay ov)))))

(defun eb-open-file (file semaphore)
  "Open FILE as a blocking $EDITOR buffer; SEMAPHORE unblocks the waiting shell.
C-c C-q saves and finishes; killing the buffer also unblocks the shell."
  (let ((origin (current-buffer)))
    (find-file file)
    (setq eb--semaphore semaphore)
    (setq eb--origin-buffer origin)
    (eb--add-banner origin (current-buffer)))
  ;; A private, buffer-local keymap inheriting the major mode's map.  NOT
  ;; `local-set-key', which mutates the *shared* major-mode keymap (e.g.
  ;; `markdown-ts-mode-map') and would leak C-c C-q into every buffer of that
  ;; mode.
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map (current-local-map))
    (define-key map (kbd "C-c C-q") #'eb-done)
    (use-local-map map))
  ;; Safety net: any buffer death releases the shell, not just C-c C-q.
  (add-hook 'kill-buffer-hook #'eb--release nil t)
  (message "eb: edit, then C-c C-q (or kill the buffer) when done"))

(defun eb-done ()
  "Finish editing (eb $EDITOR integration): save, then kill the buffer.
Killing runs `eb--release' via `kill-buffer-hook', unblocking the shell."
  (interactive)
  (when (and buffer-file-name (buffer-modified-p))
    (save-buffer))
  (kill-buffer))

;;;; -- Ghostel setup ----------------------------------------------------------

;; ghostel: fast terminal emulator backed by libghostty-vt (the Ghostty VT engine).
;; Adds Kitty keyboard protocol, mouse
;; passthrough, OSC 8 hyperlinks, 5 underline styles, and auto shell integration.
;; The native module is downloaded automatically on first use.
;; To open a new session use M-x ghostel.
(use-package ghostel
  ;; Use ghostel's canonical MELPA recipe — do NOT hand-roll a :straight recipe
  ;; with a custom :files.  The MELPA recipe is `(:defaults "etc" "src"
  ;; "vendor" ...)', which ships the bundled `etc/' tree ghostel needs at
  ;; runtime: `etc/terminfo/' (else TERM falls back to xterm-256color) and
  ;; `etc/shell/' (the auto shell integration; without it ghostel never sets
  ;; ZDOTDIR, so `ghostel_cmd', directory tracking, and OSC 133 prompt
  ;; navigation silently no-op).  A hand-written :files that omits any of these
  ;; re-breaks them.  `straight-use-package-by-default' resolves this to the
  ;; recipe repositories (MELPA), so just `:straight t'.
  :straight t
  :commands (ghostel)
  :custom
  (ghostel-shell shell-file-name)
  (ghostel-term "xterm-ghostty")
  :config
  ;; Full key passthrough for TUIs needing an exotic chord: `C-c M-d'
  ;; (ghostel-char-mode) captures *every* key — including C-c, C-b, C-g —
  ;; and forwards it to the terminal.  `M-RET' (or C-M-m / C-c C-j) is the
  ;; only way back to semi-char mode.
  ;;
  ;; ghostel's default input mode is the minor mode `ghostel-semi-char-mode',
  ;; and *its* keymap (`ghostel-semi-char-mode-map') shadows the major-mode map.
  ;; That minor-mode map is built at load time by
  ;; `ghostel--define-terminal-keys', which binds every C-<letter> not listed in
  ;; `ghostel-keymap-exceptions' to a lambda that forwards the ASCII control
  ;; code to the terminal.  `add-to-list' here is too late to affect the
  ;; already-built map, so we rebind C-b directly in both maps to the global
  ;; tmux-map prefix (windows-config.el) so C-b <arrow> etc. work.  The
  ;; add-to-list call is kept for any future rebuild of the map.
  (add-to-list 'ghostel-keymap-exceptions "C-b")
  (define-key ghostel-mode-map           (kbd "C-b") (lookup-key global-map (kbd "C-b")))
  (define-key ghostel-semi-char-mode-map (kbd "C-b") (lookup-key global-map (kbd "C-b"))))

(with-eval-after-load 'ghostel
  (add-to-list 'ghostel-eval-cmds '("eb-open-file" eb-open-file)))

(provide 'terminal-config)
;;; terminal-config.el ends here
