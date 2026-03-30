;;; lsp-ltex-plus-config.el --- LTEX+ (ltex-ls-plus) for lsp-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Use the intended Emacs client `lsp-ltex-plus` and an externally installed
;; `ltex-ls-plus` server (provided on PATH, e.g. via zinit).
;;
;; Scope: enable in Markdown, TeX-ish, plain text, Org, and reStructuredText modes.
;;
;; Why this file exists (non-obvious bits):
;;
;; - `lsp-ltex-plus` registers an *add-on* lsp-mode client (server-id
;;   `ltex-ls-plus`). It doesn't replace other language servers you may use
;;   (e.g. texlab). So when we invoke LTEX+ specific commands, we must ensure we
;;   target the LTEX+ workspace and not some other attached server.
;;
;; - LTEX+ has a setting `ltex.checkFrequency`. With "edit" it may not publish
;;   diagnostics until the first change. To get spelling/grammar diagnostics
;;   immediately on open, we trigger the LTEX+ command `_ltex.checkDocument`
;;   once per buffer.
;;
;; - With `emacs --daemon` + `emacsclient`, killing the client window often
;;   leaves buffers alive in the daemon. When you re-open a file via
;;   emacsclient, LSP's `textDocument/didOpen` may not run again, so we also
;;   trigger the one-shot check from `server-visit-hook` / `server-switch-hook`.
;;
;; - lsp-mode renders diagnostics via Flymake/Flycheck. In some timing cases
;;   LTEX+ diagnostics can arrive before Flymake's first backend run. We nudge
;;   Flymake to render the current diagnostics after the check completes.
;;

;;; Code:

(defvar my--lsp-ltex-plus-debug nil
  "If non-nil, log LTEX+ helper messages.")

(defun my--lsp-ltex-plus--debug (fmt &rest args)
  (when my--lsp-ltex-plus-debug
    (apply #'message (concat "[ltex+] " fmt) args)))

(defvar-local my--lsp-ltex-plus--check-in-flight nil
  "Non-nil while an LTEX+ check request is in flight for this buffer.")

(defun my--lsp-ltex-plus--ltex-workspace-p (ws)
  "Return non-nil if WS is an LTEX+ workspace." 
  ;; LTEX+ adds an lsp-mode client with server-id `ltex-ls-plus`. In buffers
  ;; where other servers are attached too (e.g. texlab), we must only execute
  ;; `_ltex.*` commands against the LTEX+ workspace.
  (when (and ws
             (fboundp 'lsp--workspace-client)
             (fboundp 'lsp--client-server-id)
             (fboundp 'lsp--workspace-status))
    (let* ((client (lsp--workspace-client ws))
           (sid (and client (lsp--client-server-id client))))
      (and (eq 'initialized (lsp--workspace-status ws))
           (memq sid '(ltex-ls-plus ltex-ls-plus-tramp))))))

(defun my--lsp-ltex-plus--initialized-workspace ()
  "Return the initialized LTEX+ workspace for the current buffer, or nil." 
  ;; lsp-mode can attach multiple workspaces to one buffer. We pick the
  ;; initialized LTEX+ one.
  (when (and (bound-and-true-p lsp-mode)
             (fboundp 'lsp-workspaces)
             (fboundp 'lsp--workspace-status))
    (seq-find #'my--lsp-ltex-plus--ltex-workspace-p
              (lsp-workspaces))))

(defun my--lsp-ltex-plus--eligible-buffer-p ()
  "Return non-nil if the current buffer should be checked by LTEX+."
  ;; Avoid running in scratch/temporary buffers.
  (and (buffer-file-name)
       (derived-mode-p 'markdown-mode 'tex-mode
                       'text-mode 'org-mode 'rst-mode)))

(defun my--lsp-ltex-plus--execute-check-async--in-current-workspace (buf)
  "Send an async `_ltex.checkDocument' for BUF using the current workspace." 
  ;; IMPORTANT: This must run in the correct workspace (see
  ;; `my--lsp-ltex-plus--execute-check-async`).
  (with-current-buffer buf
    (let ((params (list :command "_ltex.checkDocument"
                        :arguments (vector (list :uri (lsp--buffer-uri)
                                                :codeLanguageId (lsp-buffer-language))))))
      (setq my--lsp-ltex-plus--check-in-flight t)
      (cond
       ((fboundp 'lsp-request-async)
        (lsp-request-async
         "workspace/executeCommand"
         params
         (lambda (res)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (setq my--lsp-ltex-plus--check-in-flight nil)
               (my--lsp-ltex-plus--debug "check done: %s res=%S" (buffer-name) res)
               ;; Ensure Flymake renders the latest diagnostics even if they
               ;; arrived before Flymake's first backend run.
               (when (and (bound-and-true-p flymake-mode)
                          (fboundp 'lsp-diagnostics--flymake-update-diagnostics))
                 (ignore-errors (lsp-diagnostics--flymake-update-diagnostics)))
               ;; If the server supports pull diagnostics, explicitly refresh.
               (when (and (fboundp 'lsp-diagnostics--request-pull-diagnostics)
                          (bound-and-true-p lsp--cur-workspace))
                 (ignore-errors (lsp-diagnostics--request-pull-diagnostics lsp--cur-workspace))))))
         :error-handler
         (lambda (err)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (setq my--lsp-ltex-plus--check-in-flight nil)
               (my--lsp-ltex-plus--debug "check error: %S" err))))
         ;; Detached = don't cancel the request just because the buffer changed.
         :mode 'detached))
       (t
         ;; Fallback: synchronous request (may block).
         (unwind-protect
             (progn
              (my--lsp-ltex-plus--debug "no async; running sync check")
              (lsp-request "workspace/executeCommand" params)
              (when (and (fboundp 'lsp-diagnostics--request-pull-diagnostics)
                         (bound-and-true-p lsp--cur-workspace))
                (ignore-errors
                  (lsp-diagnostics--request-pull-diagnostics lsp--cur-workspace))))
          (setq my--lsp-ltex-plus--check-in-flight nil)))))))

(defun my--lsp-ltex-plus--execute-check-async (&optional buffer workspace)
  "Send an async `_ltex.checkDocument' for BUFFER (defaults to current buffer).

If WORKSPACE is non-nil, execute the request in that workspace." 
  ;; lsp-mode requests are routed to the *current* workspace. Make sure we run
  ;; the request inside the LTEX+ workspace, otherwise another server (e.g.
  ;; texlab) will receive `_ltex.checkDocument` and reject it.
  (let* ((buf (or buffer (current-buffer)))
         (ws (or workspace
                 (with-current-buffer buf (my--lsp-ltex-plus--initialized-workspace)))))
    (if (and ws (fboundp 'with-lsp-workspace))
        (with-lsp-workspace ws
          (my--lsp-ltex-plus--execute-check-async--in-current-workspace buf))
      (my--lsp-ltex-plus--execute-check-async--in-current-workspace buf))))

(defun my--lsp-ltex-plus--schedule-check (&optional buffer attempts)
  "Schedule an LTEX+ document check once LSP is ready.

BUFFER is the buffer to check (defaults to current buffer).
ATTEMPTS controls how many times we retry while waiting for LSP."
  ;; We retry because on buffer open the LTEX+ workspace may exist but still be
  ;; in 'starting state.
  (let ((buf (or buffer (current-buffer)))
        (attempts (or attempts 60)))
    (run-at-time
     0.2 nil
     (lambda ()
        (when (buffer-live-p buf)
         (with-current-buffer buf
           (cond
            ((not (my--lsp-ltex-plus--eligible-buffer-p))
             nil)
            (my--lsp-ltex-plus--check-in-flight
             nil)
            ((let ((ws (my--lsp-ltex-plus--initialized-workspace)))
               (when ws
                 (ignore-errors
                   (my--lsp-ltex-plus--execute-check-async (current-buffer) ws))
                 t)))
            ((> attempts 0)
             (my--lsp-ltex-plus--schedule-check buf (1- attempts)))
            (t nil))))))))

(defun my--lsp-ltex-plus--dispatch-code-actions (buf params ws)
  "Send a textDocument/codeAction request for BUF using PARAMS and present results.
WS is the LTEX+ workspace captured at invocation time — do not re-fetch it here,
as the workspace status may fluctuate briefly after `_ltex.checkDocument'."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (if (not ws)
          (message "[LTEX+] Workspace not available for code actions")
        (with-lsp-workspace ws
          (lsp-request-async
           "textDocument/codeAction"
           params
           (lambda (actions)
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (if (seq-empty-p actions)
                     (message "[LTEX+] No code actions at point")
                   (let ((action (lsp--select-action (seq-into actions 'vector))))
                     (when action
                       ;; Execute in the LTEX+ workspace — lsp--execute-code-action
                       ;; dispatches workspace/executeCommand which must go to LTEX+,
                       ;; not to another attached server.
                       (with-lsp-workspace ws
                         (lsp--execute-code-action action))))))))
           :error-handler (lambda (err)
                            (message "[LTEX+] Code action error: %S" err))
           :mode 'detached))))))

(defun my--lsp-ltex-plus-execute-code-action ()
  "Execute LTEX+ code action in Magit commit buffers.

`lsp-execute-code-action' uses a synchronous `lsp-request' that blocks Emacs.
While it blocks, Magit timers and Corfu completion fire new `lsp-request' calls
with the same `:sync-request' cancel token, immediately cancelling the pending
code action request before LTEX+ can respond.

This function works around both problems:
1. It is async (non-blocking), so the user is not stuck waiting.
2. It captures the code-action params (cursor position + diagnostics) immediately
   on invocation, before any async delay, so they cannot drift.
3. It pre-runs `_ltex.checkDocument' so LTEX+ has fresh diagnostics and can
   respond to codeAction without being interrupted by an ongoing grammar check."
  (interactive)
  (let* ((buf (current-buffer))
         (ws (my--lsp-ltex-plus--initialized-workspace))
         ;; Capture params NOW, while point is on the diagnostic.
         ;; Do NOT defer this to the async callback — point may have moved.
         (params (lsp--text-document-code-action-params)))
    (unless ws
      (user-error "[LTEX+] No active LTEX+ workspace in this buffer"))
    ;; Do NOT guard on empty diagnostics: LTEX+ uses its own server-side cache,
    ;; not the client diagnostic context, to generate code actions.  After
    ;; applying a correction, LTEX+ briefly clears diagnostics before
    ;; republishing — guarding here causes spurious "No diagnostics at point"
    ;; errors during that window, making the command appear broken.
    (message "[LTEX+] Checking document…")
    (with-lsp-workspace ws
      (lsp-request-async
       "workspace/executeCommand"
       (list :command "_ltex.checkDocument"
             :arguments (vector (list :uri (lsp--buffer-uri)
                                      :codeLanguageId (lsp-buffer-language))))
       (lambda (_res)
         ;; Wait briefly for LTEX+ to publish updated diagnostics, then fire.
         ;; Pass ws explicitly — re-fetching it here risks a nil return if
         ;; the workspace status briefly changes after the check completes.
         (run-at-time 0.3 nil #'my--lsp-ltex-plus--dispatch-code-actions buf params ws))
       :error-handler (lambda (_err)
                        ;; Check failed; try code actions with the params we already have.
                        (my--lsp-ltex-plus--dispatch-code-actions buf params ws))
       :mode 'detached))))

(defun my--lsp-ltex-plus--check-document-once ()
  "Ask LTEX+ LS to check the current document once." 
  (interactive)
  (remove-hook 'lsp-after-open-hook #'my--lsp-ltex-plus--check-document-once t)
  ;; We don't call `_ltex.checkDocument` directly here: we schedule it so we can
  ;; wait until the LTEX+ workspace is initialized.
  (when (and (fboundp 'lsp--buffer-uri)
             (fboundp 'lsp-buffer-language))
    (my--lsp-ltex-plus--schedule-check (current-buffer))))

(defun my--lsp-ltex-plus--server-maybe-check ()
  "When using emacsclient, ensure LTEX+ diagnostics are refreshed."
  (when (my--lsp-ltex-plus--eligible-buffer-p)
    (require 'lsp-ltex-plus)
    (setq-local lsp-auto-guess-root t)
    (setq-local lsp-enable-file-watchers nil)
    (lsp-deferred)
    (my--lsp-ltex-plus--schedule-check (current-buffer))))

(defun my--lsp-ltex-plus-enable ()
  "Enable LTEX+ in the current buffer."
  (require 'lsp-ltex-plus)
  ;; LTEX+ with `ltex.checkFrequency=edit` may not publish diagnostics until the
  ;; first change. Trigger a first pass explicitly on open.
  (add-hook 'lsp-after-open-hook #'my--lsp-ltex-plus--check-document-once nil t)
  ;; LTEX+ is a grammar/spell checker — project discovery is meaningless for it.
  ;; Silence the "not part of any project" prompt by auto-accepting the detected
  ;; root, and disable file watching so lsp-mode never scans a large directory
  ;; tree (e.g. $HOME for a loose file sitting there).
  (setq-local lsp-auto-guess-root t)
  (setq-local lsp-enable-file-watchers nil)
  ;; Override `lsp-execute-code-action' (C-c l a a) with our async wrapper for
  ;; all LTEX+ buffers.  The standard implementation uses a synchronous
  ;; `lsp-request' that can be silently cancelled by other lsp-mode features
  ;; (Corfu completion, modeline checks) sharing the same :sync-request cancel
  ;; token.  Our wrapper is non-blocking and pre-runs `_ltex.checkDocument'.
  ;;
  ;; We use `minor-mode-overriding-map-alist' rather than `local-set-key'
  ;; because minor mode keymaps (where lsp-mode-map lives) have higher lookup
  ;; priority than the buffer-local keymap, so `local-set-key' would lose.
  ;; `minor-mode-overriding-map-alist' is checked before `minor-mode-map-alist'
  ;; and therefore wins.  The entry is keyed on `lsp-mode' so it only activates
  ;; once lsp-mode is running in the buffer.
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c l a a") #'my--lsp-ltex-plus-execute-code-action)
    (push (cons 'lsp-mode map) minor-mode-overriding-map-alist))
  (lsp-deferred))

(use-package lsp-ltex-plus
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "emacs-languagetool/lsp-ltex-plus")
  ;; Don't delay hook installation: with `:after lsp-mode` the hooks would only
  ;; be added once lsp-mode is loaded, which defeats auto-start.
  :defer t
  :init
  ;; Limit the client to the modes we care about.
  (setq lsp-ltex-plus-active-modes
        '(markdown-mode gfm-mode
          latex-mode tex-mode plain-tex-mode
          text-mode org-mode rst-mode
          git-commit-mode))

  ;; Map both TeX modes to the "latex" language id that LTEX+ understands.
  ;; plain-tex-mode is what Emacs uses for .tex files without a preamble
  ;; (e.g. sub-files sourced via \input); LTEX+ has no separate "plaintex" id,
  ;; so we send those buffers as "latex" too.
  ;; git-commit-mode derives from text-mode but lsp-mode uses exact eq matching
  ;; for both :major-modes and lsp-language-id-configuration, so we need an
  ;; explicit "plaintext" entry for it.
  (with-eval-after-load 'lsp-mode
    (dolist (pair '((tex-mode . "latex")
                    (plain-tex-mode . "latex")
                    (git-commit-mode . "plaintext")))
      (add-to-list 'lsp-language-id-configuration pair)))

  ;; When reusing an existing buffer via emacsclient, `lsp-after-open-hook`
  ;; may not run again. Refresh diagnostics when the server visits/switches.
  (with-eval-after-load 'server
    (add-hook 'server-visit-hook #'my--lsp-ltex-plus--server-maybe-check)
    (add-hook 'server-switch-hook #'my--lsp-ltex-plus--server-maybe-check))

  (setq lsp-ltex-plus-language "en-US")
  (setq lsp-ltex-plus-check-frequency "edit")
  ;; LanguageTool Premium — credentials are loaded from ~/.config/envs/LanguageTools.sh
  ;; (sourced from ~/.config/envs/LanguageTools.sh; not committed to dotfiles):
  ;;   export LANGUAGETOOL_USERNAME='a.alberti82@gmail.com'
  ;;   export LANGUAGETOOL_API_KEY='<mykey>'
  (setq lsp-ltex-plus-language-tool-http-server-uri "https://api.languagetoolplus.com/v2")
  (setq lsp-ltex-plus-language-tool-org-username
        (or (getenv "LANGUAGETOOL_USERNAME") ""))
  (setq lsp-ltex-plus-language-tool-org-api-key
        (or (getenv "LANGUAGETOOL_API_KEY") ""))
  ;; JVM heap size for the underlying LTEX+ Java process (in MB).
  ;; Tune this if you see OOMs or excessive memory use.
  (setq lsp-ltex-plus-java-initial-heap-size 64)
  (setq lsp-ltex-plus-java-maximum-heap-size 512)
  ;; Make diagnostics visible.
  (setq lsp-ltex-plus-diagnostic-severity "warning")
  ;; Enable LTEX+ checks for the language IDs we use.
  (setq lsp-ltex-plus-enabled ["markdown" "latex" "org" "plaintext" "restructuredtext"])
  :hook
  ((markdown-mode . my--lsp-ltex-plus-enable)
   (tex-mode . my--lsp-ltex-plus-enable)   ; latex-mode (preamble) and plain-tex-mode (\input sub-files) both derive from tex-mode
   (text-mode . my--lsp-ltex-plus-enable)
   (org-mode . my--lsp-ltex-plus-enable)
   (rst-mode . my--lsp-ltex-plus-enable)
   (git-commit-mode . my--lsp-ltex-plus-enable)))

(provide 'lsp-ltex-plus-config)

;;; lsp-ltex-plus-config.el ends here
