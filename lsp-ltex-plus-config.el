;;; lsp-ltex-plus-config.el --- Configuration for lsp-ltex-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module configures and activates the lsp-ltex-plus client.
;;

;;; Code:

(require 'lsp-ltex-plus)

;;;; ── Credentials ────────────────────────────────────────────────────────────

;; Use credentials from the environment if they are not already set.
(let ((user (getenv "LANGUAGETOOL_USERNAME"))
      (key  (getenv "LANGUAGETOOL_API_KEY")))
  (when (and user (string-empty-p lsp-ltex-plus-lt-username))
    (setq lsp-ltex-plus-lt-username user))
  (when (and key (string-empty-p lsp-ltex-plus-lt-api-key))
    (setq lsp-ltex-plus-lt-api-key key)))

;;;; ── Activation ─────────────────────────────────────────────────────────────

(defun lsp-ltex-plus-enable ()
  "Enable lsp-ltex-plus for the current buffer."
  (interactive)
  (if (not (executable-find lsp-ltex-plus-ls-plus-executable))
      (message "[lsp-ltex-plus] Aborting: %s not found on PATH." lsp-ltex-plus-ls-plus-executable)
    (lsp-ltex-plus--log "Enabling LTEX+ in %s" (buffer-name))
    ;; ltex-ls-plus is not root-aware; auto-guessing avoids prompts for standalone files.
    (setq-local lsp-auto-guess-root t)
    ;; Watching is unnecessary and potentially expensive for this server.
    (setq-local lsp-enable-file-watchers nil)
    ;; UI and behavior tweaks.
    (setq-local lsp-idle-delay 0.5)
    (setq-local lsp-completion-enable nil)
    (setq-local lsp-ui-sideline-enable t)
    (setq-local lsp-modeline-code-actions-enable t)
    (lsp-deferred)))

;; Automatic hooks for supported modes.
(dolist (mode lsp-ltex-plus-major-modes)
  (let ((hook (intern (concat (symbol-name mode) "-hook"))))
    (add-hook hook #'lsp-ltex-plus-enable)))

(provide 'lsp-ltex-plus-config)
;;; lsp-ltex-plus-config.el ends here
