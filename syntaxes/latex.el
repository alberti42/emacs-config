;;; syntaxes/latex.el --- LaTeX syntax highlighting -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-latex t
  "Whether to enable LaTeX syntax highlighting from syntaxes/latex.el.")

(when emacs-config-syntaxes-enable-latex

;;; -- Faces -------------------------------------------------------------------

  (defface latex-config-brace-face
    '((t :inherit font-lock-keyword-face))
    "Face for curly braces { } in LaTeX buffers.")

  (defface latex-config-bracket-face
    '((t :inherit font-lock-type-face))
    "Face for square brackets [ ] in LaTeX buffers.")

  (defface latex-config-number-face
    '((t :inherit font-lock-number-face))
    "Face used for numbers in LaTeX buffers.
To verify math-aware highlighting, you can temporarily set this to a
bright color like :foreground \"cyan\".")

;;; -- Context-Aware Matcher ---------------------------------------------------

  (defun latex-config--match-math-number (limit)
    "Search for a number only when inside a LaTeX math environment.
This uses a high-speed property check to ensure scrolling is zero-cost.
It relies on AUCTeX having already fontified the region.

NOTE: The 'ground truth' for math state is provided by `texmathp`, but
that function is computationally expensive to run on every match. To
avoid the performance penalty of running a second full parse, we instead
rely on the results of AUCTeX's initial scan (the face property).  If
inconsistencies appear in the future, introducing `texmathp` as a
fallback would be the correct fix."
    (let (found)
      (while (and (not found)
                  (re-search-forward "\\([0-9]+\\(?:\\.[0-9]*\\)?\\|\\.[0-9]+\\)" limit t))
        (let ((face (get-text-property (match-beginning 0) 'face)))
          (when (or (eq face 'font-latex-math-face)
                    (and (listp face) (memq 'font-latex-math-face face)))
            (setq found t))))
      found))

;;; -- Setup Function ----------------------------------------------------------

  (defun latex-config--setup-font-lock ()
    "Add Sublime Text-style syntax highlighting to LaTeX buffers.
Highlights all numbers, curly braces, and square brackets with distinct
faces without disturbing comments or existing markup."
    (font-lock-add-keywords
     nil
     '((latex-config--match-math-number 1 'latex-config-number-face t)
       ("[{}]" 0 'latex-config-brace-face t)
       ("[][]" 0 'latex-config-bracket-face t))
     'append))

  (defun latex-config--setup-latex-buffer ()
    "Initialize LaTeX-specific buffer settings and font-lock rules."
    (setq-local fill-column 100)
    (soft-wrap-mode 1)
    (latex-config--setup-font-lock)

    ;; Prose word-completion: merged dabbrev + in-memory dictionary
    ;; super-CAPF (defined in completions/cape.el). Surfaces
    ;; buffer-recent words alongside dictionary words in one popup,
    ;; both gated to ≥3 chars.
    (add-hook 'completion-at-point-functions
              #'emacs-config-cape-prose nil t)

    ;; Remove cape-tex in LaTeX docume
    (setq-local completion-at-point-functions
                (remove #'cape-tex completion-at-point-functions))

    ;; Route LSP / flycheck diagnostics to the real `right-margin' via sideline.
    ;; Soft-wrap already reserves the margin column; sideline reuses that space
    ;; without resizing it.
    ;;
    ;; `sideline-flycheck-setup' is added to `flycheck-mode-hook' buffer-locally
    ;; (rather than globally from `lsp-core.el') to keep blast radius confined
    ;; to LaTeX while the integration is being developed.  It fires when LSP
    ;; eventually enables flycheck-mode in this buffer.
    (setq-local sideline-backends-right '(sideline-flycheck sideline-lsp))
    (sideline-mode 1)
    (add-hook 'flycheck-mode-hook #'sideline-flycheck-setup nil t)

    ;; Preempt `lsp-ui-sideline-mode': `lsp--auto-configure' fires from several
    ;; lifecycle points (`lsp-managed-mode' setup and `lsp-after-open-hook'
    ;; workspace init), so a post-hoc disable loses the race to the next enable.
    ;; Setting `lsp-ui-sideline-enable' nil buffer-locally tells each
    ;; `lsp-ui-mode' setup to skip sideline.
    (setq-local lsp-ui-sideline-enable nil))

;;; -- Hooks -------------------------------------------------------------------

  (add-hook 'LaTeX-mode-hook #'latex-config--setup-latex-buffer)
  (add-hook 'latex-mode-hook #'latex-config--setup-latex-buffer))

(provide 'syntaxes-latex)

;;; syntaxes/latex.el ends here
