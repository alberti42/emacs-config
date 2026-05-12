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
  ;;            :local-repo  "/Users/andrea/Documents/Programming/Others/fork-lsp-mode"
  ;;            :branch "integrated"
  ;;            :repo "alberti42/fork-lsp-mode")
  :commands (lsp lsp-deferred)
  :init
  ;; Use plists for JSON (faster + lower GC pressure than hash-tables).
  ;; Requires `LSP_USE_PLISTS=true' in the environment at byte-compile time (set
  ;; in `early-init.el').  It is reported to improve the performance.
  (setq lsp-use-plists t)
  (setq lsp-keymap-prefix "C-c l")
  ;; Use flycheck for diagnostics (richer display, fringe stays fixed — no jitter).
  (setq lsp-diagnostics-provider :flycheck)
  ;; Whether to suppress "no server installed" popups for file types like plist/XML.
  (setq lsp-warn-no-matched-clients t)
  ;; All servers are managed externally (zinit/system); never prompt to
  ;; download or auto-install them via lsp-mode.  This also prevents lsp-mode
  ;; from creating empty store directories that confuse server-present? checks.
  (setq lsp-enable-suggest-server-download nil)
  ;; Whether to use file watchers
  (setq lsp-enable-file-watchers t)
  ;; Enable lsp integration with completion-at-point
  (setq lsp-completion-enable t)
  ;; Completion is handled by corfu+cape, not company-mode.  The command below
  ;; prevents lsp-mode from trying to configure company-mode for
  ;; completion. Without it, lsp-mode assumes company-mode is the completion
  ;; frontend and tries to set it up automatically — printing a warning when
  ;; it's not found.  The naming is misleading: it doesn't disable LSP
  ;; completion (CAPF is registered before this cond), it disables lsp-mode's
  ;; company auto-setup.
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
  ;; `lsp-completion-no-cache' and `lsp-completion-use-last-result' kept at
  ;; their defaults (caching enabled, last result reused on interrupt).
  ;; `cape-capf-buster' wraps `lsp-completion-at-point' in the LSP Super-Capf
  ;; below and busts the cache when the typed prefix changes, which is the right
  ;; invalidation granularity.
  :config
  (add-hook 'lsp-mode-hook #'lsp-enable-which-key-integration)

  (when nil

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
               (lsp--on-request workspace json-data)))))))))

;; lsp-diagnostics: NOT a standalone package — this is the `lsp-diagnostics.el'
;; file that ships inside the `lsp-mode' package.  We use `use-package' purely
;; for its declarative loading semantics (`:after lsp-mode' defers `require'
;; until lsp-mode is loaded).
;;
;; Force-requiring this module ensures its faces (e.g.
;; `lsp-flycheck-info-unnecessary' for "unused" diagnostics) are defined
;; before any server sends a diagnostic that references them — otherwise
;; early diagnostics trigger "Invalid face reference" warnings.
(use-package lsp-diagnostics
  ;; No package fetch — file ships inside lsp-mode; disable straight's
  ;; default auto-install behaviour for this block.
  :straight nil
  :after lsp-mode)

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

;; sideline-lsp: replace the default 💡 prefix with a glyph whose metrics
;; match the text font.  The emoji light bulb is taller than the default
;; line height, so margin labels using it would force per-line height
;; recomputation as point moves -- visible as text flicker.
(with-eval-after-load 'sideline-lsp
  (setq sideline-lsp-code-actions-prefix ""))

;; yasnippet (the snippet expansion engine consumed by lsp-mode for
;; placeholder completion candidates) is configured separately in
;; `yasnippet-config.el' and loaded from `init.el' before this module.
;; Snippet *insertion* is bound to `C-c y' (`yas-insert-snippet') —
;; intentionally not auto-popup-completion-driven; see
;; `yasnippet-config.el' for the rationale.

;;; -- LSP completion wrapper --------------------------------------------------

;; `lsp-completion-mode' (enabled per buffer when an LSP client attaches)
;; prepends `lsp-completion-at-point' to `completion-at-point-functions'.
;; We replace that bare entry with a wrapped form that adds two
;; behaviours:
;;
;; 1. `cape-capf-buster' invalidates the LSP cache whenever the typed prefix
;;    changes, forcing lsp-mode to re-issue the request on every keystroke.
;; 2. `cape-capf-properties :exclusive 'no' makes the chain fall through to
;;    subsequent CAPFs (`cape-file' inside path strings, `cape-tex' after `\',
;;    the prose Super-Capf, ...) when LSP returns no candidates.  This replaces
;;    the older `:filter-return cape-nonexclusive' advice on
;;    `lsp-completion-at-point' → exclusivity now lives next to the CAPF that
;;    needs it instead of being injected via advice.
;;
;; Commentary on `cape-capf-buster' vs. `isIncomplete'
;;
;; The LSP `textDocument/completion' response carries an `isIncomplete'
;; flag:
;;
;;   - `isIncomplete: false' → "this list is complete for this prefix;
;;     if the user types more chars you can filter it client-side, no
;;     need to ask me again."
;;   - `isIncomplete: true'  → "list is partial; come back to me on
;;     the next keystroke."
;;
;; lsp-mode honours that: with `false' it caches the response and
;; filters locally; with `true' it re-queries each keystroke.
;;
;; `cape-capf-buster' invalidates the CAPF cache whenever the typed
;; prefix changes, so wrapping `lsp-completion-at-point' in it is
;; equivalent to overriding `isIncomplete: false' from the server
;; and treating every response as `isIncomplete: true'.
;;
;; That is intentionally conservative.  Reasons we want it:
;;
;;   1. Server bugs — basedpyright, pylsp, rust-analyzer, etc. have
;;      all at various points sent `isIncomplete: false' even when
;;      their candidate list was filtered or truncated.  Trusting the
;;      flag → may miss candidates that "should" be there.
;;   2. Context vs. prefix — `isIncomplete' describes the list for
;;      the current prefix, but a single keystroke can move across a
;;      syntactic boundary (`.', string delimiter, scope change)
;;      where the correct candidate set is genuinely different from a
;;      client-side filter of the cached list.
;;   3. Cost is negligible — one extra round-trip per keystroke to a
;;      local server is sub-millisecond; far cheaper than the cost of
;;      a stale popup.
;;
;; To honour the server's hint instead, drop `cape-capf-buster' below
;; and leave `lsp-completion-no-cache' / `lsp-completion-use-last-result'
;; at their defaults.

(defun emacs-config--lsp-completion-setup ()
  "Wrap `lsp-completion-at-point' with cache busting and non-exclusivity."
  (when (fboundp 'cape-capf-buster)
    (setq-local completion-at-point-functions
                (cons
                 ;; prepend our wrapped CAPF to the front of the list
                 (cape-capf-properties
                  (cape-capf-buster #'lsp-completion-at-point)
                  :exclusive 'no)
                 ;; drop the bare lsp-completion-at-point
                 (delq #'lsp-completion-at-point
                       (copy-sequence completion-at-point-functions))))))

(add-hook 'lsp-completion-mode-hook
          #'emacs-config--lsp-completion-setup)

(provide 'lsp-core)

;;; lsp-core.el ends here
