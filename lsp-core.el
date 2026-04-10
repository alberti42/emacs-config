;;; lsp-core.el --- LSP core configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Base LSP configuration used by language-specific modules.
;;

;;; Code:

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")
  ;; Disable flymake's margin/fringe indicator column so it doesn't
  ;; appear and disappear with diagnostics, causing layout jitter.
  ;; Diagnostics remain visible via the modeline and lsp-ui sideline.
  (setq flymake-fringe-indicator-position nil)
  ;; Suppress "no server installed" popups for file types like plist/XML.
  (setq lsp-warn-no-matched-clients nil)
  ;; All servers are managed externally (zinit/system); never prompt to
  ;; download or auto-install them via lsp-mode.  This also prevents lsp-mode
  ;; from creating empty store directories that confuse server-present? checks.
  (setq lsp-enable-suggest-server-download nil)
  ;; Completion is handled by corfu+cape, not company-mode.
  ;; The command below prevents lsp-mode from trying to configure
  ;; company-mode for completion. Without it, lsp-mode assumes
  ;; company-mode is the completion frontend and tries to set it up
  ;; automatically — printing a warning when it's not found.  
  (setq lsp-completion-provider :none)
  ;; Performance: increase the amount of data Emacs reads from subprocesses.
  ;; This helps with LSP servers that send larger JSON payloads.
  (setq read-process-output-max (* 1024 1024))
  ;; Breadcrumb headers are unreliable: multiple LSP servers fighting over
  ;; header-line-format cause partial overwrites, and the header line shifts
  ;; point by one when opening a file at a specific line number.
  (setq lsp-headerline-breadcrumb-enable nil)
  :config
  (add-hook 'lsp-mode-hook #'lsp-enable-which-key-integration)

  (defun lsp--parser-on-message (json-data workspace)
    "Patched lsp--parser-on-message to prioritize 'method' (Kind-First routing).
This prevents server-initiated requests from being misrouted as responses
to client requests when IDs collide."
    ;; Silently catch and log any errors during message processing. This prevents
    ;; a single malformed message from crashing the entire LSP client.
    (with-demoted-errors "Error processing message %S."
      (with-lsp-workspace workspace
        ;; Bind local variables for the current message.
        (-let* ((client (lsp--workspace-client workspace))
                ;; 1. DETERMINE MESSAGE TYPE (The "Kind-First" Logic)
                ;; This is the core of the patch. It checks for a 'method' field
                ;; first to identify server-initiated messages before checking
                ;; for an 'id' to identify responses.
                (message-type (cond
                               ;; A) If a 'method' field exists, it's from the server.
                               ((lsp:json-message-method? json-data)
                                ;; If it also has an 'id', it's a REQUEST that expects a response.
                                ;; Otherwise, it's a NOTIFICATION.
                                (if (lsp:json-message-id? json-data) 'request 'notification))
                               ;; B) If no 'method' but an 'id' exists, it's a response from the server
                               ;;    to a request previously sent by the client (Emacs).
                               ((lsp:json-message-id? json-data)
                                ;; If it has an 'error' field, it's an error response.
                                (if (lsp:json-message-error? json-data) 'response-error 'response))
                               ;; C) Default to 'notification' if none of the above match.
                               (t 'notification)))
                (id (--when-let (gethash "id" json-data)
                      ;; The ID from the server is often a string, so we convert it to a number
                      ;; to match the numeric IDs Emacs tracks for its own requests.
                      (if (stringp it) (string-to-number it) it)))
                ;; 3. EXTRACT MESSAGE DATA
                ;; This extracts the primary payload ('result') of a response message.
                ;; For requests, this will be nil, as they have 'params' instead.
                (data (gethash "result" json-data)))
          ;; 4. DISPATCH BASED ON MESSAGE TYPE
          ;; Finally, call the appropriate lsp-mode handler based on the
          ;; message type determined in step 1.
          (pcase message-type
            ('response
             (cl-assert id)
             (-let [(callback _ method _ before-send) (gethash id (lsp--client-response-handlers client))]
               (when (lsp--log-io-p method)
                 (lsp--log-entry-new
                  (lsp--make-log-entry method id data 'incoming-resp
                                       (lsp--ms-since before-send))
                  workspace))
               (when callback
                 (remhash id (lsp--client-response-handlers client))
                 (funcall callback (lsp:json-response-result json-data)))))
            ('response-error
             (cl-assert id)
             (-let [(_ callback method _ before-send) (gethash id (lsp--client-response-handlers client))]
               (when (lsp--log-io-p method)
                 (lsp--log-entry-new
                  (lsp--make-log-entry method id (lsp:json-response-error-error json-data)
                                       'incoming-resp (lsp--ms-since before-send))
                  workspace))
               (when callback
                 (remhash id (lsp--client-response-handlers client))
                 (funcall callback (lsp:json-response-error-error json-data)))))
            ('notification
             (lsp--on-notification workspace json-data))
            ('request (lsp--on-request workspace json-data))))))))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :init
  ;; lsp-mode automatically enables lsp-ui-mode unless lsp-auto-configure is nil.
  (setq lsp-ui-doc-enable nil)

  ;; Positioning based on frame capabilities:
  ;; - GUI: Supports child-frames and pixel math, enabling true 'at-point' floating.
  ;; - TTY: Lacks child-frames; lsp-ui falls back to a standard window split.
  ;;        We explicitly set 'top' for TTY to avoid the failed 'at-point' math
  ;;        and keep the behavior predictable and transparent.
  (setq lsp-ui-doc-position (if (display-graphic-p) 'at-point 'top))

  ;; Use child-frames where available (GUI).
  (setq lsp-ui-doc-use-childframe t)
  ;; Automatically show doc when cursor is over a symbol.
  (setq lsp-ui-doc-show-with-cursor t)
  (setq lsp-ui-doc-show-with-mouse t))

;; yasnippet: Snippet engine for interactive LSP expansions.
;;
;; While yasnippet is a standalone template system, its primary role here is
;; to act as the "expansion engine" for lsp-mode completion candidates.
;;
;; Many LSP servers (Python, TS, etc.) return "snippets" for completions
;; rather than plain text. For example, a function completion might be:
;;   "my_function(${1:arg1}, ${2:arg2})"
;;
;; Without yasnippet:
;;   LSP inserts the literal string "my_function(${1:arg1}, ${2:arg2})" or
;;   just "my_function", forcing you to manually type the arguments.
;;
;; With yasnippet:
;;   The text is inserted as "my_function(arg1, arg2)", your cursor is
;;   placed on "arg1", and hitting TAB jumps you directly to "arg2".
;;
;; Integration Flow:
;; 1. Corfu displays candidates.
;; 2. You select one that is a snippet (marked with a [S] icon).
;; 3. lsp-mode passes the snippet string to yasnippet for expansion.
;; 4. yasnippet handles the interactive tab-stops and placeholders.
(use-package yasnippet
  :hook (lsp-mode . yas-minor-mode))

(provide 'lsp-core)

;;; lsp-core.el ends here
