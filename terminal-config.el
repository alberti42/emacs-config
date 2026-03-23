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

(provide 'terminal-config)
;;; terminal-config.el ends here
