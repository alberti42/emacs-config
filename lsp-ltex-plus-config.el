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
             :local-repo "/Users/andrea/Documents/Programming/Emacs/emacs-ltex-plus"
             :repo "alberti42/emacs-ltex-plus")


  :custom
  (lsp-ltex-plus-language "en-US")
  (lsp-ltex-plus-lt-server-uri "https://api.languagetoolplus.com")
  (lsp-ltex-plus-lt-server-uri nil)
  (lsp-ltex-plus-diagnostic-severity "warning")
  (lsp-ltex-plus-debug nil)
  (lsp-ltex-plus-show-latency nil)
  (lsp-ltex-plus-trace-server "message")
  (lsp-ltex-plus-multi-root t)
  (lsp-ltex-plus-apply-kind-first-patch t)
  (lsp-ltex-plus-check-programming-languages t)
  (lsp-ltex-plus-show-progress nil)

  :init
  ;; Install hooks for all supported major modes. The full package load
  ;; lazily — only when a relevant mode is first enabled
  (lsp-ltex-plus-install-hooks
   ;; :exclude '(org-mode)
   ;; :extend-to '((emacs-lisp-mode     "lisp"             t))
   )

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
