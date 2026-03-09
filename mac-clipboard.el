;;; mac-clipboard.el --- macOS clipboard sync for TTY Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Syncs the Emacs kill ring with the macOS system clipboard when running in a
;; terminal (TTY).  Only the write direction is wired: kills and copies flow to
;; the system clipboard via pbcopy; C-y uses the Emacs kill ring exclusively
;; and never spawns a subprocess.  Use `clipboard-yank' when an explicit OS
;; clipboard paste is needed.
;;
;; Implementation note: `call-process-region' is used instead of
;; `start-process' + `process-send-eof' because the latter does not reliably
;; close the pipe in TTY mode — pbcopy never receives EOF and hangs waiting for
;; input.  `call-process-region' is synchronous and closes stdin cleanly when
;; it returns, so pbcopy commits the content immediately.
;;
;; Based on pbcopy.el by Daniel Nelson (https://github.com/jeffgran/pbcopy.el),
;; itself derived from xclip.el by Leo Shidai Liu.  Rewritten to remove the
;; paste direction and the terminal-init-xterm-hook re-registration, which
;; caused a pbpaste subprocess to be spawned on every C-y.

;;; Code:

(defun mac-clipboard--write (text &optional _push)
  "Write TEXT to the macOS system clipboard via pbcopy.
Uses `call-process-region' for synchronous, reliable pipe closure — unlike
`start-process', which does not flush stdin consistently in TTY mode."
  (when (executable-find "pbcopy")
    (with-temp-buffer
      (insert text)
      (call-process-region (point-min) (point-max) "pbcopy"))))

(defun mac-clipboard-enable ()
  "Enable kill-ring → system clipboard sync."
  (setq interprogram-cut-function #'mac-clipboard--write)
  (setq interprogram-paste-function nil))

;; Re-run on each new xterm-compatible TTY frame (covers emacsclient -t):
;; terminal-init-xterm-hook fires after terminal capabilities are set up.
(add-hook 'terminal-init-xterm-hook #'mac-clipboard-enable)
(mac-clipboard-enable)

(provide 'mac-clipboard)
;;; mac-clipboard.el ends here
