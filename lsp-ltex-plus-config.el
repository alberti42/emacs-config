;;; lsp-ltex-plus-config.el --- LTEX+ (ltex-ls-plus) for lsp-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Use the intended Emacs client `lsp-ltex-plus` and an externally installed
;; `ltex-ls-plus` server (provided on PATH, e.g. via zinit).
;;
;; Scope: enable only in Markdown and TeX-ish modes.
;;

;;; Code:

(use-package lsp-ltex-plus
  :straight (lsp-ltex-plus
             :type git
             :host github
             :repo "emacs-languagetool/lsp-ltex-plus")
  ;; Don't delay hook installation: with `:after lsp-mode` the hooks would only
  ;; be added once lsp-mode is loaded, which defeats auto-start.
  :defer t
  :init
  ;; Limit the client to the modes we care about.
  ;; NOTE: `lsp-ltex-plus` ships with a broader default list (e.g. text-mode,
  ;; org-mode, rst-mode, etc.).
  (setq lsp-ltex-plus-active-modes
        '(markdown-mode gfm-mode
          latex-mode LaTeX-mode
          tex-mode plain-tex-mode TeX-mode))

  ;; Ensure TeX modes use a language id that LTEX+ enables/parses as LaTeX.
  ;; (LTEX+ defaults to identifiers like "latex"/"markdown"; there is no
  ;; standard "plaintex" identifier.)
  (with-eval-after-load 'lsp-mode
    (dolist (pair '((tex-mode . "latex")
                    (plain-tex-mode . "latex")
                    (TeX-mode . "latex")))
      (add-to-list 'lsp-language-id-configuration pair)))

  (defun my--lsp-ltex-plus-enable ()
    "Enable LTEX+ in the current buffer." 
    (require 'lsp-ltex-plus)
    (lsp-deferred))

  (setq lsp-ltex-plus-language "en-US")
  (setq lsp-ltex-plus-check-frequency "edit")
  ;; Make diagnostics visible.
  (setq lsp-ltex-plus-diagnostic-severity "warning")
  ;; Enable LTEX+ checks for the language IDs we use.
  (setq lsp-ltex-plus-enabled ["markdown" "latex"])
  :hook
  ((markdown-mode gfm-mode
                  tex-mode plain-tex-mode TeX-mode
                  latex-mode LaTeX-mode) .
   my--lsp-ltex-plus-enable))

(provide 'lsp-ltex-plus-config)

;;; lsp-ltex-plus-config.el ends here
