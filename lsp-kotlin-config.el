;;; lsp-kotlin-config.el --- Kotlin LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Kotlin via `kotlin-ts-mode' + JetBrains' official Kotlin LSP (`kotlin-lsp').
;;
;; Requires `kotlin-lsp' on PATH:
;;   brew install JetBrains/utils/kotlin-lsp
;;
;; lsp-mode ships a built-in `kotlin-ls' client backed by fwcd's
;; `kotlin-language-server', whose latest release (1.3.13) bundles the Kotlin
;; 2.1.0 compiler and therefore rejects metadata from projects built with Kotlin
;; 2.2+ (INCOMPATIBLE_CLASS on stdlib, cascading UNRESOLVED_REFERENCE).  We
;; register a higher-priority client that launches `kotlin-lsp --stdio' instead;
;; the built-in client stays registered at priority -1 as a fallback for
;; machines where only fwcd is available.

;;; Code:

(use-package kotlin-ts-mode
  :mode ("\\.kts?\\'" . kotlin-ts-mode)
  :hook (kotlin-ts-mode . lsp-deferred))

(with-eval-after-load 'lsp-kotlin
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("kotlin-lsp" "--stdio"))
    :major-modes '(kotlin-mode kotlin-ts-mode)
    :priority 0
    :server-id 'jetbrains-kotlin-lsp
    :initialized-fn
    (lambda (workspace)
      (with-lsp-workspace workspace
        (lsp--set-configuration (lsp-configuration-section "kotlin")))))))

(provide 'lsp-kotlin-config)

;;; lsp-kotlin-config.el ends here
