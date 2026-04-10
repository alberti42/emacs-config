;;; lsp-ltex-plus-config.el --- Configuration for lsp-ltex-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module configures and activates the lsp-ltex-plus client.
;;

;;; Code:

(use-package lsp-ltex-plus
  :straight (:type git
             :local-repo emacs-config-dir
             :files ("lsp-ltex-plus.el"))
  :config
  ;;;; ── Credentials ────────────────────────────────────────────────────────────

  ;; Use credentials from the environment if they are not already set.
  (let ((user (getenv "LANGUAGETOOL_USERNAME"))
        (key  (getenv "LANGUAGETOOL_API_KEY")))
    (when (and user (string-empty-p lsp-ltex-plus-lt-username))
      (setq lsp-ltex-plus-lt-username user))
    (when (and key (string-empty-p lsp-ltex-plus-lt-api-key))
      (setq lsp-ltex-plus-lt-api-key key)))

  ;;;; ── Setup ──────────────────────────────────────────────────────────────────

  ;; Activate LTEX+ for the configured major modes.
  (lsp-ltex-plus-setup-hooks))

(provide 'lsp-ltex-plus-config)
;;; lsp-ltex-plus-config.el ends here
