;;; mac-clipboard.el --- macOS clipboard sync via pbcopy/pbpaste -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Extends `gui-select-text' and `gui-selection-value' with pbcopy/pbpaste
;; so that clipboard sync works in TTY frames too, including mixed TTY+GUI
;; daemon sessions.  GUI frames are unaffected: the NS port handles clipboard
;; natively and the advice is a no-op there.
;;
;; Write direction (kill → clipboard):
;;   - TTY: `:after' advice on `gui-select-text' calls pbcopy.
;;   - GUI: advice is a no-op; NS port handles it natively.
;;
;; Read direction (clipboard → yank):
;;   - TTY: `:around' advice on `gui-selection-value' calls pbpaste.
;;     Reuses Emacs's own newness tracking (`gui--clipboard-selection-unchanged-p'
;;     / `gui--set-last-clipboard-selection') so that text Emacs itself just
;;     killed is not re-pasted from the clipboard.
;;   - GUI: advice delegates to the original function unchanged.
;;
;; `interprogram-cut-function' and `interprogram-paste-function' are left at
;; their default values (`gui-select-text' and `gui-selection-value').
;;
;; Implementation note: `call-process-region' is used for pbcopy instead of
;; `start-process' + `process-send-eof' because the latter does not reliably
;; close the pipe in TTY mode — pbcopy never receives EOF and hangs waiting for
;; input.  `call-process-region' is synchronous and closes stdin cleanly when
;; it returns, so pbcopy commits the content immediately.

;;; Code:

(defvar mac-clipboard--pbcopy (executable-find "pbcopy")
  "Path to pbcopy, or nil if not found.")

(defvar mac-clipboard--pbpaste (executable-find "pbpaste")
  "Path to pbpaste, or nil if not found.")

(defun mac-clipboard--after-gui-select-text (text)
  "After `gui-select-text', also write TEXT to clipboard via pbcopy in TTY Emacs."
  ;; Check for TTY Emacs 
  (when (not (display-graphic-p))
    (when mac-clipboard--pbcopy
      (with-temp-buffer
        (insert text)
        (call-process-region (point-min) (point-max) mac-clipboard--pbcopy)))))

(defun mac-clipboard--around-gui-selection-value (orig-fun)
  "Around `gui-selection-value', use pbpaste in TTY frames.
In GUI frames, delegates to ORIG-FUN unchanged.
In TTY frames, calls pbpaste and reuses Emacs's clipboard newness tracking
to avoid returning text that Emacs itself just killed."
  (if (display-graphic-p)
      ;; In GUI Emacs, use original function relying on NS functions
      (funcall orig-fun)
    ;; In TTY Emacs use pbpaste
    (when mac-clipboard--pbpaste
      (let ((text (with-temp-buffer
                    (call-process mac-clipboard--pbpaste nil t nil)
                    (when (> (buffer-size) 0)
                      (buffer-string)))))
        (unless (gui--clipboard-selection-unchanged-p text)
          (gui--set-last-clipboard-selection text)
          text)))))

;; Original functions defined in select.el
(advice-add 'gui-select-text     :after  #'mac-clipboard--after-gui-select-text)
(advice-add 'gui-selection-value :around #'mac-clipboard--around-gui-selection-value)

(provide 'mac-clipboard)
;;; mac-clipboard.el ends here
