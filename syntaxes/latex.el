;;; syntaxes/latex.el --- LaTeX syntax highlighting -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-latex t
  "Whether to enable LaTeX syntax highlighting from syntaxes/latex.el.")

(when emacs-config-syntaxes-enable-latex
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
    "Search for a number only when inside a LaTeX math environment."
    (let (found)
      (while (and (not found)
                  (re-search-forward "\\([0-9]+\\(?:\\.[0-9]*\\)?\\|\\.[0-9]+\\)" limit t))
        (save-match-data
          (save-excursion
            (goto-char (match-beginning 0))
            (when (and (fboundp 'texmathp)
                       (texmathp))
              (setq found t)))))
      found))

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
  
  (let ((hook_fnc (lambda ()
                    (setq-local fill-column 100)
                    (latex-config--setup-font-lock))))
    
    (add-hook 'LaTeX-mode-hook hook_fnc)
    (add-hook 'latex-mode-hook hook_fnc)))

(provide 'syntaxes-latex)

;;; syntaxes/latex.el ends here
