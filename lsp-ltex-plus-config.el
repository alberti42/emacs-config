;;; lsp-ltex-plus-config.el --- LTEX+ (ltex-ls-plus) for lsp-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Use the intended Emacs client `lsp-ltex-plus` and an externally installed
;; `ltex-ls-plus` server (provided on PATH, e.g. via zinit).
;;
;; Scope: enable only in Markdown and TeX-ish modes.
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
  (when (and (bound-and-true-p lsp-mode)
             (fboundp 'lsp-workspaces)
             (fboundp 'lsp--workspace-status))
    (seq-find #'my--lsp-ltex-plus--ltex-workspace-p
              (lsp-workspaces))))

(defun my--lsp-ltex-plus--eligible-buffer-p ()
  "Return non-nil if the current buffer should be checked by LTEX+."
  (and (buffer-file-name)
       (derived-mode-p 'markdown-mode 'gfm-mode
                       'tex-mode 'plain-tex-mode 'TeX-mode
                       'latex-mode 'LaTeX-mode)))

(defun my--lsp-ltex-plus--execute-check-async--in-current-workspace (buf)
  "Send an async `_ltex.checkDocument' for BUF using the current workspace." 
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
               ;; Ensure flymake renders the latest diagnostics even if they
               ;; arrived before flymake's first backend run.
               (when (and (bound-and-true-p flymake-mode)
                          (fboundp 'lsp-diagnostics--flymake-update-diagnostics))
                 (ignore-errors
                   (lsp-diagnostics--flymake-update-diagnostics)))
               ;; If the server supports pull diagnostics, explicitly refresh.
               (when (and (fboundp 'lsp-diagnostics--request-pull-diagnostics)
                          (bound-and-true-p lsp--cur-workspace))
                 (ignore-errors
                   (lsp-diagnostics--request-pull-diagnostics lsp--cur-workspace))))))
         :error-handler
         (lambda (err)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (setq my--lsp-ltex-plus--check-in-flight nil)
               (my--lsp-ltex-plus--debug "check error: %S" err))))
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
  (let* ((buf (or buffer (current-buffer)))
         (ws (or workspace (with-current-buffer buf (my--lsp-ltex-plus--initialized-workspace)))))
    (if (and ws (fboundp 'with-lsp-workspace))
        (with-lsp-workspace ws
          (my--lsp-ltex-plus--execute-check-async--in-current-workspace buf))
      (my--lsp-ltex-plus--execute-check-async--in-current-workspace buf))))

(defun my--lsp-ltex-plus--schedule-check (&optional buffer attempts)
  "Schedule an LTEX+ document check once LSP is ready.

BUFFER is the buffer to check (defaults to current buffer).
ATTEMPTS controls how many times we retry while waiting for LSP."
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

(defun my--lsp-ltex-plus--check-document-once ()
  "Ask LTEX+ LS to check the current document once." 
  (interactive)
  (remove-hook 'lsp-after-open-hook #'my--lsp-ltex-plus--check-document-once t)
  (when (and (fboundp 'lsp--buffer-uri)
             (fboundp 'lsp-buffer-language))
    (my--lsp-ltex-plus--schedule-check (current-buffer))))

(defun my--lsp-ltex-plus--server-maybe-check ()
  "When using emacsclient, ensure LTEX+ diagnostics are refreshed." 
  (when (my--lsp-ltex-plus--eligible-buffer-p)
    (require 'lsp-ltex-plus)
    (lsp-deferred)
    (my--lsp-ltex-plus--schedule-check (current-buffer))))

(defun my--lsp-ltex-plus-enable ()
  "Enable LTEX+ in the current buffer." 
  (require 'lsp-ltex-plus)
  ;; LTEX+ with `ltex.checkFrequency=edit` may not publish diagnostics until the
  ;; first change. Trigger a first pass explicitly on open.
  (add-hook 'lsp-after-open-hook #'my--lsp-ltex-plus--check-document-once nil t)
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
  ;; NOTE: `lsp-ltex-plus` ships with a broader default list (e.g. text-mode,
  ;; org-mode, rst-mode, etc.).
  (setq lsp-ltex-plus-active-modes
        '(markdown-mode gfm-mode
          latex-mode LaTeX-mode
          tex-mode plain-tex-mode TeX-mode))

  ;; Ensure TeX modes use a language id that LTEX+ enables/parses as LaTeX.
  ;; (LTEX+ defaults to identifiers like "latex"/"markdown"; there is no
  ;; standard "plaintex" identifier.)
  (with-eval-after-load 'lsp-mode
    (dolist (pair '((tex-mode . "latex")
                    (plain-tex-mode . "latex")
                    (TeX-mode . "latex")))
      (add-to-list 'lsp-language-id-configuration pair)))

  ;; When reusing an existing buffer via emacsclient, `lsp-after-open-hook`
  ;; may not run again. Refresh diagnostics when the server visits/switches.
  (with-eval-after-load 'server
    (add-hook 'server-visit-hook #'my--lsp-ltex-plus--server-maybe-check)
    (add-hook 'server-switch-hook #'my--lsp-ltex-plus--server-maybe-check))

  (setq lsp-ltex-plus-language "en-US")
  (setq lsp-ltex-plus-check-frequency "edit")
  ;; Make diagnostics visible.
  (setq lsp-ltex-plus-diagnostic-severity "warning")
  ;; Enable LTEX+ checks for the language IDs we use.
  (setq lsp-ltex-plus-enabled ["markdown" "latex"])
  :hook
  ((markdown-mode . my--lsp-ltex-plus-enable)
   (gfm-mode . my--lsp-ltex-plus-enable)
   (tex-mode . my--lsp-ltex-plus-enable)
   (plain-tex-mode . my--lsp-ltex-plus-enable)
   (TeX-mode . my--lsp-ltex-plus-enable)
   (latex-mode . my--lsp-ltex-plus-enable)
   (LaTeX-mode . my--lsp-ltex-plus-enable)))

(provide 'lsp-ltex-plus-config)

;;; lsp-ltex-plus-config.el ends here
