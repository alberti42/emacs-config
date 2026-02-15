;;; lsp-ltex-config.el --- LTEX (LanguageTool) LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Grammar/spell/style checking via LTEX language server.
;;
;; This configuration is intended to run LTEX+ LS (ltex-ls-plus) so that
;; diagnostics can be produced for prose *and* for comments/strings in
;; programming buffers.
;;

;;; Code:

(defvar my--lsp-ltex-java-ok nil
  "Non-nil when JAVA_HOME is set to a compatible JDK.")

(defun my--java-home-major-version (java-home)
  "Return major Java version for JAVA-HOME, or nil." 
  (let* ((java (expand-file-name "bin/java" java-home)))
    (when (file-executable-p java)
      (let ((out (shell-command-to-string (format "%s -version 2>&1" (shell-quote-argument java)))))
        (when (string-match "\\(?:openjdk\\|java\\)\\s-+\\(?:version\\s-+\\)?\\\"\\([0-9]+\\)" out)
          (string-to-number (match-string 1 out)))))))

(use-package lsp-ltex
  :after lsp-mode
  :init
  ;; Use LTEX+ LS, installed manually under this directory as:
  ;;   <store>/latest/bin/ltex-ls
  ;; (The lsp-ltex package expects the entrypoint to be named ltex-ls.)
  (setq lsp-ltex-server-store-path
        (expand-file-name "ltex-ls-plus" lsp-server-install-dir))

  ;; Enable LTEX for markup languages and opt-in comment checking in popular
  ;; programming language buffers.
  (setq lsp-ltex-enabled
        ["bibtex" "context" "context.tex" "html" "latex" "markdown" "mdx"
         "typst" "asciidoc" "neorg" "org" "quarto" "restructuredtext" "rsweave"
         "git-commit" "python" "javascript" "javascriptreact" "typescript" "typescriptreact"])

  (setq lsp-ltex-language "en-US")
  (setq lsp-ltex-check-frequency "edit")

  ;; Ensure a compatible JAVA_HOME for Java-based tooling.
  ;;
  ;; LTEX+ LS bundles its own JDK (currently Java 21+), and our ltex-ls wrapper
  ;; forces that bundled JDK. Still, setting JAVA_HOME here keeps the Emacs
  ;; environment consistent for other tools.
  (let ((java-home (getenv "JAVA_HOME")))
    (cond
     ((not (and java-home (file-directory-p java-home)))
      (setq my--lsp-ltex-java-ok nil)
      (display-warning
       'lsp-ltex
       (concat
        "JAVA_HOME is not set (or does not point to a JDK). "
        "Set JAVA_HOME in the environment, e.g.\n\n"
        "  export JAVA_HOME=$(/usr/libexec/java_home -v 21)\n\n"
        "Then restart Emacs.")
       :warning))
     ((let ((ver (my--java-home-major-version java-home)))
        (and ver (>= ver 21)))
      (setq my--lsp-ltex-java-ok t)
      (let ((jdk-bin (expand-file-name "bin" java-home)))
        (when (file-directory-p jdk-bin)
          (add-to-list 'exec-path jdk-bin)
          (let ((path (or (getenv "PATH") "")))
            (unless (string-match-p (regexp-quote jdk-bin) path)
              (setenv "PATH" (concat jdk-bin path-separator path)))))))
     (t
      (setq my--lsp-ltex-java-ok nil)
      (display-warning
       'lsp-ltex
       (format
        "JAVA_HOME points to an incompatible Java version (need 21+): %s" java-home)
       :warning))))

  :config
  ;; Enable lsp-ltex in additional programming modes.
  (dolist (mode '(python-mode python-ts-mode
                  js-mode js-ts-mode
                  typescript-mode typescript-ts-mode tsx-ts-mode))
    (add-to-list 'lsp-ltex-active-modes mode))

  :hook
  ((org-mode markdown-mode latex-mode text-mode
             python-mode python-ts-mode
             js-mode js-ts-mode
             typescript-mode typescript-ts-mode tsx-ts-mode) .
   (lambda ()
     ;; Debounce updates while typing (buffer-local).
     (setq-local lsp-idle-delay 0.8)
     (require 'lsp-ltex)
     (when my--lsp-ltex-java-ok
       (lsp-deferred)))))

(provide 'lsp-ltex-config)

;;; lsp-ltex-config.el ends here
