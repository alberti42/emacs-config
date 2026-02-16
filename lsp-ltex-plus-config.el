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
    ;; LTEX+ with `ltex.checkFrequency=edit` may not publish diagnostics until
    ;; the first change. Trigger a first pass explicitly on open.
    (add-hook 'lsp-after-open-hook #'my--lsp-ltex-plus--check-document-once nil t)
    (lsp-deferred))

  (defun my--lsp-ltex-plus--eligible-buffer-p ()
    "Return non-nil if the current buffer should be checked by LTEX+." 
    (and (buffer-file-name)
         (derived-mode-p 'markdown-mode 'gfm-mode
                         'tex-mode 'plain-tex-mode 'TeX-mode
                         'latex-mode 'LaTeX-mode)))

  (defun my--lsp-ltex-plus--schedule-check (&optional attempts)
    "Schedule an LTEX+ document check once LSP is ready.

ATTEMPTS controls how many times we retry while waiting for LSP." 
    (let ((attempts (or attempts 10)))
      (run-at-time
       0.2 nil
       (lambda ()
         (cond
          ((not (my--lsp-ltex-plus--eligible-buffer-p))
           nil)
          ((and (bound-and-true-p lsp-mode)
                (fboundp 'lsp-workspaces)
                (lsp-workspaces))
           (ignore-errors
             (lsp-workspace-command-execute
              "_ltex.checkDocument"
              (vector (list :uri (lsp--buffer-uri)
                            :codeLanguageId (lsp-buffer-language))))))
          ((> attempts 0)
           (my--lsp-ltex-plus--schedule-check (1- attempts))))))))

  (defun my--lsp-ltex-plus--check-document-once ()
    "Ask LTEX+ LS to check the current document once." 
    (interactive)
    (remove-hook 'lsp-after-open-hook #'my--lsp-ltex-plus--check-document-once t)
    (when (and (fboundp 'lsp-workspace-command-execute)
               (fboundp 'lsp--buffer-uri))
      (my--lsp-ltex-plus--schedule-check)))

  (defun my--lsp-ltex-plus--server-maybe-check ()
    "When using emacsclient, ensure LTEX+ diagnostics are refreshed." 
    (when (my--lsp-ltex-plus--eligible-buffer-p)
      (require 'lsp-ltex-plus)
      (lsp-deferred)
      (my--lsp-ltex-plus--schedule-check)))

  ;; When reusing an existing buffer via emacsclient, `lsp-after-open-hook`
  ;; may not run again. Refresh diagnostics when the server visits/switches.
  (with-eval-after-load 'server
    (add-hook 'server-visit-hook #'my--lsp-ltex-plus--server-maybe-check)
    (add-hook 'server-switch-hook #'my--lsp-ltex-plus--server-maybe-check))

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
