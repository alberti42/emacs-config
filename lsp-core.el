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
  ;; Use flycheck for diagnostics (richer display, fringe stays fixed — no jitter).
  (setq lsp-diagnostics-provider :flycheck)
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
  ;; Whether to display breadcrumb headers.  Note: multiple LSP servers may
  ;; fight over header-line-format, resulting in conflicts and partial
  ;; overwrites.
  (setq lsp-headerline-breadcrumb-enable t)
  ;; auto-guess-root makes lsp-mode use project.el to detect the workspace root
  ;; instead of using cache.
  (setq lsp-auto-guess-root t)
  ;; without-session stops lsp-mode from consulting/updating the session file
  ;; `~/.config/emacs/.lsp-session-v1' at all. The session file becomes
  ;; irrelevant and stops growing.
  (setq lsp-guess-root-without-session t)
  ;; ElDoc: show LSP hover info in the echo area (signature only).
  ;; lsp-eldoc-render-all nil keeps it to one line; full docs are available
  ;; on demand via lsp-ui-doc-glance (C-c l h g).
  (setq lsp-eldoc-enable-hover t)
  ;; If this is set to nil, eldoc will show only the symbol information.
  (setq lsp-eldoc-render-all nil)
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

;; flycheck: lsp-mode's flycheck integration already passes :id code? to
;; flycheck-error-new (see lsp-diagnostics--flycheck-start), so diagnostic
;; codes (e.g. "reportPossiblyUnbound") are natively available in flycheck
;; via flycheck-error-id — no override needed here.
(use-package flycheck
  :init
  ;; left-fringe: fringes are always present in GUI frames (no layout jitter)
  ;; and degrade gracefully in TTY.
  (setq flycheck-indication-mode 'left-fringe))

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
  ;; Hover docs are handled by ElDoc (echo area); use glance (C-c l h g) for
  ;; the full child-frame popup on demand.
  (setq lsp-ui-doc-show-with-cursor nil)
  (setq lsp-ui-doc-show-with-mouse nil)

  ;; Sideline: show diagnostics and code-action hints inline, but not hover —
  ;; that would duplicate what ElDoc already shows in the echo area.
  (setq lsp-ui-sideline-enable t)
  (setq lsp-ui-sideline-show-hover t)
  (setq lsp-ui-sideline-show-diagnostics t)
  (setq lsp-ui-sideline-show-code-actions t)
  :bind (:map lsp-ui-mode-map
              ("C-c l h g" . lsp-ui-doc-glance)))

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
  :init
  (setq yas-snippet-dirs
        (list (expand-file-name "yasnippets" emacs-config-dir)))
  :config
  (yas-global-mode 1)
  (yas-reload-all)
  ;; AUCTeX's LaTeX-mode does not derive from latex-mode; ensure it picks up
  ;; the snippets from yasnippets/latex-mode/
  (with-eval-after-load 'tex
    (add-hook 'LaTeX-mode-hook
              (lambda () (yas-activate-extra-mode 'latex-mode))))
  ;; Ensure gfm-mode picks up markdown-mode snippets.
  (with-eval-after-load 'markdown-mode
    (add-hook 'gfm-mode-hook
              (lambda () (yas-activate-extra-mode 'markdown-mode)))))

(provide 'lsp-core)

;;; lsp-core.el ends here
