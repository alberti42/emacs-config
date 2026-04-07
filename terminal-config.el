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
;; To open a new session use C-u M-x vterm (or C-u M-x vterm-other-window).
;; Without the prefix, both commands reuse the existing *vterm* buffer.
(use-package vterm
  :straight t
  :custom
  ;; like for term, set the default shell to shell-file-name (equivalent to $SHELL)
  (vterm-shell shell-file-name)
  :config
  ;; C-b is our tmux-map prefix (windows-config.el).  Adding it here prevents
  ;; vterm from swallowing the key before Emacs sees it as a prefix, so
  ;; C-b <arrow> and other C-b * bindings work inside a vterm buffer.
  ;; customize-set-variable (not setq) is needed to trigger vterm's :set handler
  ;; which rebuilds the keymap.
  (customize-set-variable 'vterm-keymap-exceptions
    (cons "C-b" vterm-keymap-exceptions))
  :bind (:map vterm-mode-map
         ;; Forward C-SPC (= C-@) as NUL (\C-@), the standard terminal encoding for C-SPC.
         ;; Must use "C-@" in :bind — "C-SPC" is not intercepted by vterm-mode-map as
         ;; Emacs resolves it to set-mark-command from global-map before reaching it.
         ;; Also, vterm-send-key must be avoided: it goes through vterm--update in the
         ;; C module which re-encodes using the active escape mode, producing CSI-u
         ;; sequences (^[[64;5u).
         ("C-@"        . (lambda () (interactive) (vterm-send-string "\C-@")))
         ;; Forward Shift+Enter (remapped to Alt+Enter by WezTerm) as ESC+CR (\e\r),
         ;; the standard terminal encoding for Meta+Enter. Using vterm-send-key with
         ;; "<return>" does not work because vterm-send-return bypasses vterm-send-key
         ;; entirely and sends raw bytes, so we send the escape sequence directly.
         ("C-M-m"      . (lambda () (interactive) (vterm-send-string "\e\r")))
         ;; Forward C-g as BEL (\C-g = ASCII 7) so terminal apps (e.g. Claude
         ;; Code) receive it.  In vterm-mode keyboard-quit has nothing to quit,
         ;; so yielding this binding is safe.
         ("C-g"        . (lambda () (interactive) (vterm-send-string "\C-g")))))

;; ev: blocking "open in Emacs" for use as $EDITOR from vterm.
;;
;; The shell `ev` function calls `vterm_cmd ev-open-file FILE SEMAPHORE`, then
;; polls until SEMAPHORE exists.  `ev-open-file` opens the file and binds
;; C-c C-c to `ev-done`, which creates SEMAPHORE and buries the buffer —
;; unblocking the shell process without involving the Emacs server at all.
(defvar-local ev--semaphore nil
  "Semaphore path used by `ev-done' to signal editing is complete.")

(defun ev-open-file (file semaphore)
  "Open FILE for editing; C-c C-c creates SEMAPHORE to unblock the shell."
  (find-file file)
  (setq ev--semaphore semaphore)
  (local-set-key (kbd "C-c C-c") #'ev-done)
  (message "ev: edit buffer, then C-c C-c when done"))

(defun ev-done ()
  "Signal editing complete (ev EDITOR integration); bury the buffer."
  (interactive)
  (when ev--semaphore
    (write-region "" nil ev--semaphore)
    (setq ev--semaphore nil))
  (bury-buffer))

(with-eval-after-load 'vterm
  (add-to-list 'vterm-eval-cmds '("ev-open-file" ev-open-file)))

;; ghostel: fast terminal emulator backed by libghostty-vt (the Ghostty VT engine).
;; Roughly 2x faster throughput than vterm; adds Kitty keyboard protocol, mouse
;; passthrough, OSC 8 hyperlinks, 5 underline styles, and auto shell integration.
;; The native module is downloaded automatically on first use.
;; To open a new session use M-x ghostel.
(use-package ghostel
  :straight (ghostel
             :type git
             :host github
             :repo "dakra/ghostel")
  :custom
  (ghostel-shell shell-file-name)
  :config
  ;; ghostel-mode-map is a defvar built at load time from ghostel-keymap-exceptions;
  ;; updating the list after load has no effect on the already-built map.
  ;; We must directly remove the C-b binding so it falls through to the global
  ;; tmux-map prefix (windows-config.el) and C-b <arrow> etc. work.
  (add-to-list 'ghostel-keymap-exceptions "C-b")  ; effective for future reloads
  (define-key ghostel-mode-map (kbd "C-b") nil)
  :bind (:map ghostel-mode-map
         ;; Forward C-SPC (= C-@) as NUL (\C-@), the standard terminal encoding for C-SPC.
         ;; Same caveat as vterm: Emacs resolves C-SPC to set-mark-command before the
         ;; mode map is consulted, so we bind C-@ instead.
         ("C-@"   . (lambda () (interactive) (ghostel-send-string "\C-@")))
         ;; Forward Shift+Enter (remapped to Alt+Enter by WezTerm) as ESC+CR (\e\r).
         ("C-M-m" . (lambda () (interactive) (ghostel-send-string "\e\r")))
         ;; C-g passes through to Emacs by default in ghostel; rebind to send BEL
         ;; (\C-g = ASCII 7) so terminal apps (e.g. Claude Code) receive it.
         ("C-g"   . (lambda () (interactive) (ghostel-send-string "\C-g")))))

(with-eval-after-load 'ghostel
  (add-to-list 'ghostel-eval-cmds '("ev-open-file" ev-open-file)))

(provide 'terminal-config)
;;; terminal-config.el ends here
