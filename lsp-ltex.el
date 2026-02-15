;;; lsp-ltex.el --- LTEX (LanguageTool) LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Grammar/spell/style checking via LTEX Language Server.
;;

;;; Code:

(use-package lsp-ltex
  :after lsp-mode
  :init
  (setq lsp-ltex-version "16.0.0")
  (setq lsp-ltex-language "en-US")
  ;; LTEX-LS requires Java 11+. Ensure Emacs launches it with a modern JDK.
  (let* ((jdk-home (cond
                    ((file-directory-p "/opt/homebrew/opt/openjdk@17")
                     "/opt/homebrew/opt/openjdk@17")
                    ((file-directory-p "/opt/homebrew/opt/openjdk@11")
                     "/opt/homebrew/opt/openjdk@11")
                    (t nil)))
         (jdk-bin (when jdk-home (expand-file-name "bin" jdk-home))))
    (when (and jdk-bin (file-executable-p (expand-file-name "java" jdk-bin)))
      (setenv "JAVA_HOME" jdk-home)
      (add-to-list 'exec-path jdk-bin)
      (let ((path (or (getenv "PATH") "")))
        (unless (string-match-p (regexp-quote jdk-bin) path)
          (setenv "PATH" (concat jdk-bin path-separator path))))))
  :hook
  ((org-mode markdown-mode latex-mode text-mode) .
   (lambda ()
     (require 'lsp-ltex)
     (lsp-deferred))))

(provide 'lsp-ltex)

;;; lsp-ltex.el ends here
