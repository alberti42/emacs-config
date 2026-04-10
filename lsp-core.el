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
        (condition-case err
            (condition-case quit-err
                (progn
              ;; Bind local variables for the current message.
              (-let* ((client (lsp--workspace-client workspace))
                      (method (lsp-mode-debug--json-get json-data "method"))
                      (raw-id (lsp-mode-debug--json-get json-data "id"))
                      (has-method (not (null method)))
                      (has-id (not (null raw-id)))
                      (has-error (not (null (lsp-mode-debug--json-get json-data "error"))))
                      ;; 1. DETERMINE MESSAGE TYPE (The "Kind-First" Logic)
                      (message-type (cond
                                     (has-method (if has-id 'request 'notification))
                                     (has-id (if has-error 'response-error 'response))
                                     (t 'notification)))
                      ;; 2. NORMALIZE ID
                      (id (and raw-id (if (stringp raw-id) (string-to-number raw-id) raw-id)))
                      ;; 3. EXTRACT MESSAGE DATA (responses only)
                      (data (and (memq message-type '(response response-error))
                                 (lsp-mode-debug--json-get json-data "result"))))

                (lsp-mode-debug--log
                 "on-message: kind=%s has-method=%s method=%S has-id=%s raw-id=%S id=%S has-error=%s obj=%S"
                 message-type has-method method has-id raw-id id has-error (type-of json-data))

                ;; 4. DISPATCH BASED ON MESSAGE TYPE
                (pcase message-type
                  ('response
                   (cl-assert id)
                   (let ((handler (gethash id (lsp--client-response-handlers client))))
                     (lsp-mode-debug--log "dispatch response: id=%S handler=%s" id (if handler "yes" "no"))
                     (-let [(callback _ cb-method _ before-send) handler]
                       (when (lsp--log-io-p cb-method)
                         (lsp--log-entry-new
                          (lsp--make-log-entry cb-method id data 'incoming-resp
                                               (lsp--ms-since before-send))
                          workspace))
                       (cond
                        ((null callback)
                         (lsp-mode-debug--log "response: id=%S has no callback; dropped" id))
                        (t
                         (remhash id (lsp--client-response-handlers client))
                         (lsp-mode-debug--log "response: calling callback id=%S method=%S" id cb-method)
                         (funcall callback (lsp-mode-debug--json-get json-data "result")))))))
                  ('response-error
                   (cl-assert id)
                   (let ((handler (gethash id (lsp--client-response-handlers client))))
                     (lsp-mode-debug--log "dispatch response-error: id=%S handler=%s" id (if handler "yes" "no"))
                     (-let [(_ callback cb-method _ before-send) handler]
                       (when (lsp--log-io-p cb-method)
                         (lsp--log-entry-new
                          (lsp--make-log-entry cb-method id (lsp-mode-debug--json-get json-data "error")
                                               'incoming-resp (lsp--ms-since before-send))
                          workspace))
                       (cond
                        ((null callback)
                         (lsp-mode-debug--log "response-error: id=%S has no callback; dropped" id))
                        (t
                         (remhash id (lsp--client-response-handlers client))
                         (lsp-mode-debug--log "response-error: calling callback id=%S method=%S" id cb-method)
                         (funcall callback (lsp-mode-debug--json-get json-data "error")))))))
                  ('notification
                   (lsp-mode-debug--log "dispatch notification: method=%S" method)
                   (lsp--on-notification workspace json-data))
                  ('request
                   (lsp-mode-debug--log "dispatch request: id=%S method=%S" raw-id method)
                    (lsp--on-request workspace json-data)))))
              (quit
               (lsp-mode-debug--log "QUIT in on-message: method=%S raw-id=%S" 
                                    (lsp-mode-debug--json-get json-data "method")
                                    (lsp-mode-debug--json-get json-data "id"))
               (signal (car quit-err) (cdr quit-err))))
          (error
           (lsp-mode-debug--log "exception while handling message: %S" err)
           (lsp-mode-debug--log "exception json type=%S json=%S" (type-of json-data) json-data)
           (signal (car err) (cdr err))))))))

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
