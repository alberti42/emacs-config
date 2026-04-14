;;; lsp-ltex-plus-config.el --- Configuration for lsp-ltex-plus -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module configures and activates the lsp-ltex-plus client.
;;

;;; Code:

(use-package lsp-ltex-plus
  ;; Tell straight to use your local folder instead of downloading from GitHub.
  ;; This is the "canonical" way to do local development with straight.
  :straight (lsp-ltex-plus
             :type git
             :host github
             :local-repo "/Users/andrea/google-drive/dotfiles/.config/emacs/emacs-ltex-plus"
             :repo "alberti42/emacs-ltex-plus")


  :custom
  (lsp-ltex-plus-lt-server-uri "https://api.languagetoolplus.com")

  :init
  ;; Activate the global mode so it automatically hooks into all supported major modes.
  (global-lsp-ltex-plus-mode 1)

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
