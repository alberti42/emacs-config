;;; yasnippet-config.el --- Snippet engine -*- lexical-binding: t; -*-

;;; -- yasnippet: Snippet engine ----------------------------------------------

;; Originally pulled in to act as the expansion engine for lsp-mode
;; completion candidates: many LSP servers (Python, TS, etc.) return
;; "snippets" rather than plain text, e.g.
;;
;;   "my_function(${1:arg1}, ${2:arg2})"
;;
;; Without yasnippet, lsp-mode inserts the literal placeholder string or
;; just the symbol name.  With yasnippet, the candidate expands to
;; `my_function(arg1, arg2)' with `arg1' selected and TAB jumping to
;; `arg2'.  The same engine is also used by the snippet libraries under
;; `yasnippets/' for interactive expansion in editing modes.
;;
;; DIRECTORY STRUCTURE & CONTROL FILES
;;
;; To ensure snippets are correctly discovered, avoid placing any yasnippet
;; control files (e.g., .yas-parents, .yas-make-groups, .yas-metadata) directly
;; in the root of the "yasnippets" directory.
;;
;; If such a file exists in the root, yasnippet will treat that folder as a
;; single mode-specific directory (for a mode named "yasnippets") and will
;; NOT scan its subdirectories (like LaTeX-mode/ or markdown-ts-mode/).
;;
;; Folder names within "yasnippets" must match the Emacs major-mode symbol
;; exactly and are CASE-SENSITIVE (e.g., "LaTeX-mode" for AUCTeX vs.
;; "latex-mode" for the built-in mode).  Use `yas-activate-extra-mode' as seen
;; below to bridge naming gaps between different packages.
;;
;; INSERTION UX
;;
;; Snippets are *not* surfaced through auto-popup completion (no
;; `yasnippet-capf' wiring).  That route was tried and abandoned.
;;
;; Instead, `C-c y' is bound to `yas-insert-snippet': lists *all*
;; snippets for the active mode (and parents / extra-modes) in a
;; minibuffer prompt with vertico+orderless filtering.

(use-package yasnippet
  :init
  (setq yas-snippet-dirs
        (list (expand-file-name "yasnippets" emacs-config-dir)))
  ;; Skip the legacy `yas/*' aliases entirely so they don't clutter M-x.
  ;; Must be set before yasnippet loads to take effect.
  (setq yas-alias-to-yas/prefix-p nil)
  :bind ("C-c y" . yas-insert-snippet)
  :config
  (yas-global-mode 1)
  (yas-reload-all)
  ;; AUCTeX's LaTeX-mode does not derive from latex-mode; ensure it picks up
  ;; the snippets from yasnippets/latex-mode/
  (with-eval-after-load 'tex
    (add-hook 'LaTeX-mode-hook
              (lambda () (yas-activate-extra-mode 'latex-mode)))))

(provide 'yasnippet-config)

;;; yasnippet-config.el ends here
