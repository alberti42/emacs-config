;;; lsp-core.el --- LSP core configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Base LSP configuration used by language-specific modules.
;;

;;; Code:

(use-package lsp-mode
  :commands (lsp lsp-deferred)
  :init
  (setq lsp-keymap-prefix "C-c l")
  ;; Disable flymake's margin/fringe indicator column so it doesn't
  ;; appear and disappear with diagnostics, causing layout jitter.
  ;; Diagnostics remain visible via the modeline and lsp-ui sideline.
  (setq flymake-fringe-indicator-position nil)
  ;; Suppress "no server installed" popups for file types like plist/XML.
  (setq lsp-warn-no-matched-clients nil)
  ;; All servers are managed externally (zinit/system); never prompt to
  ;; download or auto-install them via lsp-mode.  This also prevents lsp-mode
  ;; from creating empty store directories that confuse server-present? checks.
  (setq lsp-enable-suggest-server-download nil)
  ;; Completion is handled by corfu+cape, not company-mode.
  ;; The command below prevents lsp-mode from trying to configure
  ;; company-mode for completion. Without it, lsp-mode assumes
  ;; company-mode is the completion frontend and tries to set it up
  ;; automatically — printing a warning when it's not found.  
  (setq lsp-completion-provider :none)
  ;; Performance: increase the amount of data Emacs reads from subprocesses.
  ;; This helps with LSP servers that send larger JSON payloads.
  (setq read-process-output-max (* 1024 1024))
  (add-hook 'lsp-mode-hook #'lsp-enable-which-key-integration)
  ;; Breadcrumb headers are unreliable: multiple LSP servers fighting over
  ;; header-line-format cause partial overwrites, and the header line shifts
  ;; point by one when opening a file at a specific line number.
  (setq lsp-headerline-breadcrumb-enable nil))

(use-package lsp-ui
  :after lsp-mode
  :commands lsp-ui-mode
  :init
  (add-hook 'lsp-mode-hook #'lsp-ui-mode)
  (setq lsp-ui-doc-position 'at-point))

;; yasnippet: snippet expansion used by LSP to render completion candidates
;; that have placeholders (e.g. function signatures where you fill in the
;; arguments by tabbing through them).  Without it, completions still work
;; but the whole text is inserted at once with no tab-stop navigation.
;; corfu shows the candidates; yasnippet handles the expansion of the
;; selected one.
(use-package yasnippet
  :hook (lsp-mode . yas-minor-mode))

(provide 'lsp-core)

;;; lsp-core.el ends here
