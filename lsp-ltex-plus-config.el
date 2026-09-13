;;; lsp-ltex-plus-config.el --- Configuration for lsp-ltex-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module configures and activates the lsp-ltex-plus client.
;;

;;; Code:

(use-package lsp-ltex-plus
  ;; Tell straight to use your local folder instead of downloading from GitHub.
  ;; This is the "canonical" way to do local development with straight.
  ;; Straight builds whatever branch that checkout is on; the name below
  ;; documents which one that is meant to be.
  :straight (lsp-ltex-plus
             :type git
             :host github
             :local-repo "/Users/andrea/Documents/Programming/Emacs/emacs-ltex-plus"
             :branch "simplify-settings"
             :repo "alberti42/emacs-ltex-plus")

  :custom
  (lsp-ltex-plus-language "en-US")
  ;; Online LanguageTool with the Premium credentials from the environment
  ;; (see :config below); set to nil for the local server only.
  (lsp-ltex-plus-lt-server-uri "https://api.languagetoolplus.com")
  (lsp-ltex-plus-debug nil)
  (lsp-ltex-plus-diagnostics-provider 'flycheck)
  (lsp-ltex-plus-diagnostic-severity "warning")
  (lsp-ltex-plus-ltex-ls-log-level "warning")
  ;; A Premium account allows larger requests than the free service.
  (lsp-ltex-plus-max-request-size 60000)
  (lsp-ltex-plus-completion-enabled nil)
  (lsp-ltex-plus-check-programming-languages nil)

  :init
  ;; Install hooks for all supported major modes. The full package loads lazily
  ;; — only when a relevant mode is first enabled.
  (lsp-ltex-plus-enable-for-modes
   ;; :exclude '(org-mode)
   :extend-to '((agent-shell-viewport-edit-mode "markdown" nil)))

  :config
  ;; Use credentials from the environment if they are not already set.
  (let ((user (getenv "LANGUAGETOOL_USERNAME"))
        (key  (getenv "LANGUAGETOOL_API_KEY")))
    (when (and user (or (null lsp-ltex-plus-lt-username) (string-empty-p lsp-ltex-plus-lt-username)))
      (setq lsp-ltex-plus-lt-username user))
    (when (and key (or (null lsp-ltex-plus-lt-api-key) (string-empty-p lsp-ltex-plus-lt-api-key)))
      (setq lsp-ltex-plus-lt-api-key key))))

(provide 'lsp-ltex-plus-config)
;;; lsp-ltex-plus-config.el ends here
