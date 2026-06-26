;;; syntaxes/elisp.el --- Elisp settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-elisp t
  "Whether to enable Elisp settings from syntaxes/elisp.el.")

(defconst emacs-config-elisp-section-regexp
  "^;;;;* +-- +\\(.+?\\) +-+ *$"
  "Match a decorated section heading like `;;;; -- Label ----'.
Capture group 1 is the section label, with the surrounding `--' / `-'
decoration excluded.")

(when emacs-config-syntaxes-enable-elisp
  (add-hook 'emacs-lisp-mode-hook
            (lambda ()
              (setq-local fill-column 80)
              ;; Surface `;;; -- Label ----' headings as a "Sections" group in
              ;; imenu / consult-imenu, alongside the default Functions/Variables.
              (add-to-list 'imenu-generic-expression
                           (list "Sections" emacs-config-elisp-section-regexp 1)
                           t)))

  ;; Register the "Sections" group with consult-imenu so it renders as its own
  ;; group header (with a `s' narrowing key) instead of an inline prefix.
  (with-eval-after-load 'consult-imenu
    (let* ((entry (assq 'emacs-lisp-mode consult-imenu-config))
           (types (and entry (plist-get (cdr entry) :types))))
      (when (and entry (not (assq ?s types)))
        (plist-put (cdr entry) :types
                   (append types '((?s "Sections" font-lock-keyword-face))))))))

(provide 'syntaxes-elisp)
;;; syntaxes/elisp.el ends here
