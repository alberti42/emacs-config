;;; lsp-ltex-plus-config.el --- LTEX+ (ltex-ls-plus) for lsp-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; The OLD client `emacs-languagetool/lsp-ltex-plus', configured to mirror the
;; working `lsp-ltex-plus-config.el' (the alberti42/emacs-ltex-plus client) for
;; every feature that exists in both.  Used to test whether the old client now
;; works against a fixed `lsp-mode'.
;;
;; Scope: enable only in Markdown and TeX modes.
;;

;;; Code:

(use-package lsp-ltex-plus
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "emacs-languagetool/lsp-ltex-plus")
  :after lsp-mode
  :init
  (setq lsp-ltex-plus-language "en-US")
  (setq lsp-ltex-plus-check-frequency "edit")
  ;; Remote/Premium LanguageTool service (mirrors lsp-ltex-plus-lt-server-uri).
  (setq lsp-ltex-plus-languagetool-http-server-uri "https://api.languagetoolplus.com")
  ;; Externally installed ltex-ls-plus (zinit) + JDK 21, instead of letting the
  ;; package download its own.  `ls-path' is the install root whose bin/ holds
  ;; the launcher; `java-path' is JAVA_HOME.
  (setq lsp-ltex-plus-ls-path "/Users/andrea/.local/share/zinit/polaris")
  (setq lsp-ltex-plus-java-path "/Library/Java/JavaVirtualMachines/jdk-21.jdk/Contents/Home")
  ;; Debug visibility (mirrors lsp-ltex-plus-debug t / trace-server).
  (setq lsp-ltex-plus-trace-server "message")
  (setq lsp-log-io t)
  ;; Server-side completion off, as in the main config.
  (setq lsp-ltex-plus-completion-enabled nil)
  (setq lsp-ltex-plus-diagnostic-severity "warning")
  ;; Enable LTEX+ checks for the language IDs used by lsp-mode.
  (setq lsp-ltex-plus-enabled ["markdown" "latex" "plaintex"])
  :config
  ;; Premium credentials from the environment if not already set
  ;; (mirrors the lt-username / lt-api-key block in the main config).
  (let ((user (getenv "LANGUAGETOOL_USERNAME"))
        (key  (getenv "LANGUAGETOOL_API_KEY")))
    (when (and user (or (null lsp-ltex-plus-languagetool-org-username)
                        (string-empty-p lsp-ltex-plus-languagetool-org-username)))
      (setq lsp-ltex-plus-languagetool-org-username user))
    (when (and key (or (null lsp-ltex-plus-languagetool-org-api-key)
                       (string-empty-p lsp-ltex-plus-languagetool-org-api-key)))
      (setq lsp-ltex-plus-languagetool-org-api-key key)))
  :hook
  ((markdown-mode gfm-mode plain-tex-mode latex-mode LaTeX-mode) .
   (lambda ()
     (require 'lsp-ltex-plus)
     (lsp-deferred))))

(provide 'lsp-ltex-plus-config)

;;; lsp-ltex-plus-config.el ends here
