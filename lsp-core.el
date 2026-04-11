;;; lsp-core.el --- LSP core configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Base LSP configuration used by language-specific modules.
;;

;;; Code:

(use-package lsp-mode
  ;; :straight (lsp-mode
  ;;            :type git
  ;;            :host github
  ;;            :branch "show-diagnostic-codes"
  ;;            :repo "alberti42/fork-lsp-mode"
  ;;            )
  :commands (lsp lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")
  ;; Disable flymake's margin/fringe indicator column so it doesn't
  ;; appear and disappear with diagnostics, causing layout jitter.
  ;; Diagnostics remain visible via the modeline and lsp-ui sideline.
  (setq flymake-fringe-indicator-position nil)
  ;; Whether to suppress "no server installed" popups for file types like plist/XML.
  (setq lsp-warn-no-matched-clients t)
  ;; All servers are managed externally (zinit/system); never prompt to
  ;; download or auto-install them via lsp-mode.  This also prevents lsp-mode
  ;; from creating empty store directories that confuse server-present? checks.
  (setq lsp-enable-suggest-server-download t)
  ;; Whether to use file watchers
  (setq lsp-enable-file-watchers t)
  ;; Completion is handled by corfu+cape, not company-mode.
  ;; The command below prevents lsp-mode from trying to configure
  ;; company-mode for completion. Without it, lsp-mode assumes
  ;; company-mode is the completion frontend and tries to set it up
  ;; automatically — printing a warning when it's not found.  
  (setq lsp-completion-provider :none)
  ;; Performance: increase the amount of data Emacs reads from subprocesses.
  ;; This helps with LSP servers that send larger JSON payloads.
  (setq read-process-output-max (* 4 1024 1024))
  ;; Breadcrumb headers are unreliable: multiple LSP servers fighting over
  ;; header-line-format cause partial overwrites, and the header line shifts
  ;; point by one when opening a file at a specific line number.
  (setq lsp-headerline-breadcrumb-enable t)
  :config
  (add-hook 'lsp-mode-hook #'lsp-enable-which-key-integration)

  (defun lsp-core--json-get (obj key)
    "Return value for KEY in OBJ (hash-table or plist).

KEY is the JSON object key as a string, e.g. method or id."
    (cond
     ((hash-table-p obj)
      (gethash key obj))
     ((listp obj)
      (or (plist-get obj (intern (concat ":" key)))
          (plist-get obj (intern key))))
     (t nil)))

  (defun lsp--parser-on-message (json-data workspace)
    "Patched lsp--parser-on-message to prioritize 'method' (Kind-First routing).
This prevents server-initiated requests from being misrouted as responses
to client requests when IDs collide."
    ;; Silently catch and log any errors during message processing. This prevents
    ;; a single malformed message from crashing the entire LSP client.
    (with-demoted-errors "Error processing message %S."
      (with-lsp-workspace workspace
        (let* ((client (lsp--workspace-client workspace))
               (method (lsp-core--json-get json-data "method"))
               (raw-id (lsp-core--json-get json-data "id"))
               (has-method (not (null method)))
               (has-id (not (null raw-id)))
               (has-error (not (null (lsp-core--json-get json-data "error"))))
               ;; Kind-First routing: if a method exists, it's a server-initiated
               ;; message (request/notification) regardless of ID collisions.
               (message-type (cond
                              (has-method (if has-id 'request 'notification))
                              (has-id (if has-error 'response-error 'response))
                              (t 'notification)))
               ;; Normalize response IDs only (client-generated ids are numeric).
               (id (and (memq message-type '(response response-error))
                        raw-id
                        (if (stringp raw-id) (string-to-number raw-id) raw-id))))
          (pcase message-type
            ('response
             (when id
               (let ((handler (gethash id (lsp--client-response-handlers client))))
                 (when handler
                   (let ((callback (nth 0 handler))
                         (cb-method (nth 2 handler))
                         (before-send (nth 4 handler))
                         (result (lsp-core--json-get json-data "result")))
                     (when (lsp--log-io-p cb-method)
                       (lsp--log-entry-new
                        (lsp--make-log-entry cb-method id result 'incoming-resp
                                             (lsp--ms-since before-send))
                        workspace))
                     (when callback
                       (remhash id (lsp--client-response-handlers client))
                       (funcall callback result)))))))
            ('response-error
             (when id
               (let ((handler (gethash id (lsp--client-response-handlers client))))
                 (when handler
                   (let ((err-callback (nth 1 handler))
                         (cb-method (nth 2 handler))
                         (before-send (nth 4 handler))
                         (err (lsp-core--json-get json-data "error")))
                     (when (lsp--log-io-p cb-method)
                       (lsp--log-entry-new
                        (lsp--make-log-entry cb-method id err 'incoming-resp
                                             (lsp--ms-since before-send))
                        workspace))
                     (when err-callback
                       (remhash id (lsp--client-response-handlers client))
                       (funcall err-callback err)))))))
            ('notification
             (lsp--on-notification workspace json-data))
            ('request
             (lsp--on-request workspace json-data))))))))

;; lsp-diagnostics--flymake-update-diagnostics builds flymake diagnostics from
;; the LSP diagnostic objects but only extracts :message, silently dropping
;; :code? (the rule name, e.g. "reportPossiblyUnbound").  Without the code,
;; there is no way to write a precise `# pyright: ignore[<rule>]' comment
;; directly from the error message.  This override is identical to the
;; original except it also binds :code? and appends "[code]" to the text when
;; the server supplies one.
(defun lsp-core--flymake-update-diagnostics-with-code ()
  "Like `lsp-diagnostics--flymake-update-diagnostics' but appends the diagnostic code.
Patched so the rule name (e.g. reportPossiblyUnbound) is visible in the
flymake message, enabling precise `pyright: ignore[]' suppression comments."
  (funcall lsp-diagnostics--flymake-report-fn
           (-some->> (lsp-diagnostics t)
             (gethash (lsp--fix-path-casing buffer-file-name))
             (--map (-let* (((&Diagnostic :message :severity? :code?
                                          :range (range &as &Range
                                                        :start (&Position :line start-line :character)
                                                        :end (&Position :line end-line))) it)
                            ((start . end) (lsp--range-to-region range))
                            (text (if code?
                                      (format "%s [%s]" message code?)
                                    message)))
                      (when (= start end)
                        (if-let* ((region (flymake-diag-region (current-buffer)
                                                               (1+ start-line)
                                                               character)))
                            (setq start (car region)
                                  end (cdr region))
                          (lsp-save-restriction-and-excursion
                            (goto-char (point-min))
                            (setq start (line-beginning-position (1+ start-line)))
                            (setq end (line-end-position (1+ end-line))))))
                      (flymake-make-diagnostic (current-buffer)
                                               start end
                                               (cl-case severity?
                                                 (1 :error)
                                                 (2 :warning)
                                                 (t :note))
                                               text))))
           :region (cons (point-min) (point-max))))

(with-eval-after-load 'lsp-diagnostics
  (advice-add 'lsp-diagnostics--flymake-update-diagnostics
              :override #'lsp-core--flymake-update-diagnostics-with-code))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :init
  ;; lsp-mode automatically enables lsp-ui-mode unless lsp-auto-configure is nil.
  (setq lsp-ui-doc-enable t)

  ;; Positioning based on frame capabilities:
  ;; - GUI: Supports child-frames and pixel math, enabling true 'at-point' floating.
  ;; - TTY: Lacks child-frames; lsp-ui falls back to a standard window split.
  ;;        We explicitly set 'top' for TTY to avoid the failed 'at-point' math
  ;;        and keep the behavior predictable and transparent.
  (setq lsp-ui-doc-position 'at-point)

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
