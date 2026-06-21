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

;; ev: blocking "open in Emacs" for use as $EDITOR from ghostel.
;;
;; The shell `ev` function calls `ghostel_cmd ev-open-file FILE SEMAPHORE`, then
;; polls until SEMAPHORE exists.  `ev-open-file` opens the file and binds
;; C-c C-q to `ev-done`, which creates SEMAPHORE and buries the buffer —
;; unblocking the shell process without involving the Emacs server at all.
(defvar-local ev--semaphore nil
  "Semaphore path used by `ev-done' to signal editing is complete.")

(defun ev-open-file (file semaphore)
  "Open FILE for editing; C-c C-q creates SEMAPHORE to unblock the shell."
  (find-file file)
  (setq ev--semaphore semaphore)
  (local-set-key (kbd "C-c C-q") #'ev-done)
  (message "ev: edit buffer, then C-c C-q when done"))

(defun ev-done ()
  "Signal editing complete (ev EDITOR integration); bury the buffer."
  (interactive)
  (when ev--semaphore
    (write-region "" nil ev--semaphore)
    (setq ev--semaphore nil))
  (bury-buffer))

;; ghostel: fast terminal emulator backed by libghostty-vt (the Ghostty VT engine).
;; Adds Kitty keyboard protocol, mouse
;; passthrough, OSC 8 hyperlinks, 5 underline styles, and auto shell integration.
;; The native module is downloaded automatically on first use.
;; To open a new session use M-x ghostel.
(use-package ghostel
  :straight (ghostel
             :type git
             :host github
             :repo "dakra/ghostel"
             ;; Include the bundled `etc/terminfo/' tree in the straight build
             ;; dir.  Straight's default :files spec keeps only `.el' and doc
             ;; files; without this, ghostel's probe via
             ;; (expand-file-name "etc/terminfo" <resource-root>) fails and it
             ;; falls back to TERM=xterm-256color with a warning.  Preserving
             ;; the hashed subdirs is required: ghostel checks both the macOS
             ;; layout (78/xterm-ghostty) and the Linux layout
             ;; (x/xterm-ghostty).
             :files (:defaults
                     ("etc/terminfo"    "etc/terminfo/xterm-ghostty.terminfo")
                     ("etc/terminfo/67" "etc/terminfo/67/ghostty")
                     ("etc/terminfo/78" "etc/terminfo/78/xterm-ghostty")
                     ("etc/terminfo/g"  "etc/terminfo/g/ghostty")
                     ("etc/terminfo/x"  "etc/terminfo/x/xterm-ghostty")))
  :commands (ghostel)
  :custom
  (ghostel-shell shell-file-name)
  (ghostel-term "xterm-ghostty")
  :config
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
  (define-key ghostel-semi-char-mode-map (kbd "C-b") (lookup-key global-map (kbd "C-b")))
  ;; Full key passthrough for TUIs needing an exotic chord: `C-c M-d'
  ;; (ghostel-char-mode) captures *every* key — including C-c, C-b, C-g —
  ;; and forwards it to the terminal.  `M-RET' (or C-M-m / C-c C-j) is the
  ;; only way back to semi-char mode.  Note: the C-M-m -> \e\r binding below
  ;; does not apply in char mode, where C-M-m exits instead.
  :bind (:map ghostel-mode-map
              ;; Forward C-SPC (= C-@) as NUL (\C-@), the standard terminal encoding for C-SPC.
              ;; Caveat: Emacs resolves C-SPC to set-mark-command before the
              ;; mode map is consulted, so we bind C-@ instead.
              ;; ("C-@"   . (lambda () (interactive) (ghostel-send-string "\C-@")))
              ;; Forward Shift+Enter (remapped to Alt+Enter by WezTerm) as ESC+CR (\e\r).
              ("C-M-m" . (lambda () (interactive) (ghostel-send-string "\e\r")))
              ;; C-g passes through to Emacs by default in ghostel; rebind to send BEL
              ;; (\C-g = ASCII 7) so terminal apps (e.g. Claude Code) receive it.
              ("C-g"   . (lambda () (interactive) (ghostel-send-string "\C-g")))))

(with-eval-after-load 'ghostel
  (add-to-list 'ghostel-eval-cmds '("ev-open-file" ev-open-file)))

(provide 'terminal-config)
;;; terminal-config.el ends here
