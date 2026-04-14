;;; syntaxes/latex.el --- LaTeX syntax highlighting -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-latex t
  "Whether to enable LaTeX syntax highlighting from syntaxes/latex.el.")

(defface latex-config-brace-face
  '((t :inherit font-lock-keyword-face))
  "Face for curly braces { } in LaTeX buffers.")

(defface latex-config-bracket-face
  '((t :inherit font-lock-type-face))
  "Face for square brackets [ ] in LaTeX buffers.")

(defface latex-config-number-face
  '((t :foreground "cyan"))
  "Face used for numbers in LaTeX buffers (Cyan for verification).")

(defun latex-config--match-math-number (limit)
  "Search for any number, currently ignoring math context for testing."
  (re-search-forward "\\([0-9]+\\(?:\\.[0-9]*\\)?\\|\\.[0-9]+\\)" limit t))

(defun latex-config--setup-font-lock ()
  "Add Sublime Text-style syntax highlighting to LaTeX buffers.
Highlights all numbers, curly braces, and square brackets with distinct
faces without disturbing comments or existing markup."
  (font-lock-add-keywords
   nil
   '((latex-config--match-math-number 1 'latex-config-number-face t)
     ;; Curly braces used for grouping / arguments
     ("[{}]" 0 'latex-config-brace-face t)
     ;; Square brackets used for optional arguments
     ("[][]" 0 'latex-config-bracket-face t))
   'append))

(when emacs-config-syntaxes-enable-latex
  (add-hook 'LaTeX-mode-hook #'latex-config--setup-font-lock))

(provide 'syntaxes-latex)

;;; syntaxes/latex.el ends here
