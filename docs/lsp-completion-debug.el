;;; lsp-completion-debug.el --- Append-only log of LSP completion requests -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Lightweight debug tool for diagnosing LSP completion behaviour.
;; Wraps `lsp-request-while-no-input' with an :around advice that logs
;; every textDocument/completion call and its response to a named
;; buffer.
;;
;; Usage:
;;
;;   M-x lsp-completion-debug-toggle   ; install / remove the advice
;;   M-x lsp-completion-debug-clear    ; clear the log buffer
;;
;; Open the log with `C-x b *lsp-completion-debug*'.  Any window showing
;; the buffer auto-scrolls to the latest entry.
;;
;; This file is loaded on demand; it is not wired into `init.el'.

;;; Code:

(require 'lsp-mode)
(require 'lsp-completion)
(require 'seq)
(require 'cl-lib)

(defconst lsp-completion-debug-buffer-name "*lsp-completion-debug*"
  "Name of the buffer used for the debug log.")

(defvar lsp-completion-debug--enabled nil
  "Non-nil when the debug advice is installed.")

(defun lsp-completion-debug--buffer ()
  (get-buffer-create lsp-completion-debug-buffer-name))

(defun lsp-completion-debug--append (line)
  "Append LINE (plus newline) and auto-scroll any visible windows."
  (let ((buf (lsp-completion-debug--buffer)))
    (with-current-buffer buf
      (goto-char (point-max))
      (insert line "\n"))
    (dolist (w (get-buffer-window-list buf nil 'visible))
      (set-window-point w (point-max)))))

(defun lsp-completion-debug--prefix-at-point ()
  "Return the symbol prefix between symbol-start and point."
  (let ((start (or (car (bounds-of-thing-at-point 'symbol)) (point))))
    (buffer-substring-no-properties start (point))))

(defun lsp-completion-debug--items (response)
  "Extract the items list from a CompletionList or item-vector RESPONSE."
  (cond
   ((null response) nil)
   ((lsp-completion-list? response) (lsp:completion-list-items response))
   (t response)))

(defun lsp-completion-debug--label (item)
  "Extract the label from ITEM (hash-table or plist)."
  (cond
   ((hash-table-p item) (or (gethash "label" item) "?"))
   ((listp item) (or (plist-get item :label) "?"))
   (t "?")))

(defun lsp-completion-debug--first-labels (items n)
  "Return up to N labels from ITEMS as a list of strings."
  (let ((seq (seq-take (if (vectorp items) (append items nil) items) n)))
    (mapcar #'lsp-completion-debug--label seq)))

(defun lsp-completion-debug--advice (orig-fn method params)
  "Around-advice for `lsp-request-while-no-input'.
Logs every textDocument/completion call to the debug buffer."
  (if (not (string= method "textDocument/completion"))
      (funcall orig-fn method params)
    (let* ((t0 (current-time))
           (prefix (lsp-completion-debug--prefix-at-point))
           (pos (point))
           (textdoc-pos (plist-get params :position))
           (line (and textdoc-pos (plist-get textdoc-pos :line)))
           (char (and textdoc-pos (plist-get textdoc-pos :character)))
           (response (funcall orig-fn method params))
           (elapsed-ms (* 1000.0 (float-time (time-subtract (current-time) t0))))
           (items (lsp-completion-debug--items response))
           (count (cond ((null items) 0)
                        ((vectorp items) (length items))
                        ((listp items) (length items))
                        (t 0)))
           (labels (lsp-completion-debug--first-labels items 3))
           (incomplete (and (lsp-completion-list? response)
                            (lsp:completion-list-is-incomplete response))))
      (lsp-completion-debug--append
       (format "%s  prefix=%-12S pos=%d (L%s:C%s)  →  N=%-4d %S%s  %.0fms"
               (format-time-string "%H:%M:%S.%3N" t0)
               prefix pos (or line "?") (or char "?")
               count labels
               (if incomplete "  (incomplete)" "")
               elapsed-ms))
      response)))

;;;###autoload
(defun lsp-completion-debug-toggle ()
  "Toggle the LSP completion debug advice on/off."
  (interactive)
  (if lsp-completion-debug--enabled
      (progn
        (advice-remove 'lsp-request-while-no-input
                       #'lsp-completion-debug--advice)
        (setq lsp-completion-debug--enabled nil)
        (message "lsp-completion-debug: OFF"))
    (advice-add 'lsp-request-while-no-input :around
                #'lsp-completion-debug--advice)
    (setq lsp-completion-debug--enabled t)
    (display-buffer (lsp-completion-debug--buffer))
    (message "lsp-completion-debug: ON  (buffer: %s)"
             lsp-completion-debug-buffer-name)))

;;;###autoload
(defun lsp-completion-debug-clear ()
  "Erase the debug log buffer."
  (interactive)
  (with-current-buffer (lsp-completion-debug--buffer)
    (erase-buffer)))

(provide 'lsp-completion-debug)
;;; lsp-completion-debug.el ends here
