;;; harper-config.el --- Harper grammar checker via Eglot -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Harper 2.0 (Automattic) grammar checker via `harper-ls' + Eglot.
;;
;; Upstream docs:
;;   https://writewithharper.com/docs/integrations/language-server
;;
;; Requires the `harper-ls' binary on PATH (install separately, e.g.
;; `cargo install harper-ls' or via a package manager).
;;
;; This module runs Harper on Eglot intentionally — Eglot is the setup
;; recommended by upstream, and keeping it separate from the lsp-mode
;; stack makes side-by-side comparisons with lsp-ltex-plus easier.

;;; Code:

(use-package eglot
  :straight nil                         ; built-in since Emacs 29
  :commands (eglot eglot-ensure)
  :config
  ;; Register harper-ls for `text-mode' and any mode derived from it
  ;; (covers markdown-mode, org-mode, LaTeX-mode, tex-mode, message-mode, …).
  ;; Eglot matches `eglot-server-programs' entries against derived modes.
  (add-to-list 'eglot-server-programs
               '(text-mode . ("harper-ls" "--stdio")))

  ;; If Eglot sends an unsupported :language-id for a given major mode
  ;; and diagnostics never appear, replace the entry above with an
  ;; explicit language-id, e.g.:
  ;;   '((org-mode :language-id "plaintext") . ("harper-ls" "--stdio"))
  ;; See the "gotcha" note in upstream docs.
  
  ;; Auto-start Eglot for prose buffers.  `text-mode-hook' fires for
  ;; every derived mode via `run-mode-hooks', so one hook is enough.
  (add-hook 'text-mode-hook #'eglot-ensure))

;; Optional workspace configuration.  All values below are the defaults
;; documented upstream — uncomment and edit to override.
;;
;; (setq-default eglot-workspace-configuration
;;               '(:harper-ls (:userDictPath ""
;;                             :workspaceDictPath ""
;;                             :fileDictPath ""
;;                             :linters (:SpellCheck t
;;                                       :SpelledNumbers :json-false
;;                                       :AnA t
;;                                       :SentenceCapitalization t
;;                                       :UnclosedQuotes t
;;                                       :WrongQuotes :json-false
;;                                       :LongSentences t
;;                                       :RepeatedWords t
;;                                       :Spaces t
;;                                       :Matcher t
;;                                       :CorrectNumberSuffix t)
;;                             :codeActions (:ForceStable :json-false)
;;                             :markdown (:IgnoreLinkTitle :json-false)
;;                             :diagnosticSeverity "hint"
;;                             :isolateEnglish :json-false
;;                             :dialect "American"
;;                             :maxFileLength 120000
;;                             :ignoredLintsPath ""
;;                             :excludePatterns [])))

(provide 'harper-config)
;;; harper-config.el ends here
