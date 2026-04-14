;;; lsp-ltex-plus-config.el --- Configuration for lsp-ltex-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module configures and activates the lsp-ltex-plus client.
;;

;;; Code:

(use-package lsp-ltex-plus
  ;; 1. Use the package name 'lsp-ltex-plus' for the recipe.
  ;; 2. Point to the 'emacs-ltex-plus' repository on GitHub.
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "alberti42/emacs-ltex-plus")

  ;; For local development, this points Emacs to the local repo checkout.
  :load-path "~/Documents/Programming/Emacs/emacs-ltex-plus"

  :config

  ;; Use credentials from the environment if they are not already set.
  (let ((user (getenv "LANGUAGETOOL_USERNAME"))
        (key  (getenv "LANGUAGETOOL_API_KEY")))
    (when (and user (string-empty-p lsp-ltex-plus-lt-username))
      (setq lsp-ltex-plus-lt-username user))
    (when (and key (string-empty-p lsp-ltex-plus-lt-api-key))
      (setq lsp-ltex-plus-lt-api-key key)))

  ;; Activate LTEX+ for the configured major modes.
  (lsp-ltex-plus-setup-hooks))

(provide 'lsp-ltex-plus-config)
;;; lsp-ltex-plus-config.el ends here
