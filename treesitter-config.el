;;; treesitter-config.el --- Tree-sitter grammar bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Emacs has built-in tree-sitter support (Emacs 29+), but tree-sitter *modes*
;; (e.g. json-ts-mode) need a compiled grammar library.
;;
;; This module ensures a small set of grammars are installed.
;; It does nothing if tree-sitter is unavailable.

;;; Code:

(require 'cl-lib)

(use-package treesit
  :straight nil
  :if (and (fboundp 'treesit-available-p)
           (treesit-available-p))
  :config
  ;; Define grammar sources
  (setq treesit-language-source-alist
        '((json "https://github.com/tree-sitter/tree-sitter-json")))

  (defun treesitter-config-reinstall-grammars ()
    "Force reinstallation of all grammars in `treesit-language-source-alist'.
Use this to update grammars to their latest versions."
    (interactive)
    (dolist (lang-source treesit-language-source-alist)
      (let ((lang (car lang-source)))
        (message "Treesitter: Reinstalling grammar for %s..." lang)
        ;; We use cl-letf to skip the confirmation prompt if it exists in this
        ;; Emacs version.  This ensures that the installation remains
        ;; non-interactive.
        (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
          (treesit-install-language-grammar lang)))))

  ;; Bootstrap missing grammars
  (dolist (lang-source treesit-language-source-alist)
    (let ((lang (car lang-source)))
      (unless (treesit-language-available-p lang)
        (message "Treesitter: Installing grammar for %s..." lang)
        (condition-case err
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
              (treesit-install-language-grammar lang))
          (error
           (display-warning 'treesitter
                            (format "Failed to install tree-sitter grammar for %s: %s"
                                    lang (error-message-string err))
                            :error)))))))

;; Warn if tree-sitter is unavailable
(unless (and (fboundp 'treesit-available-p)
             (treesit-available-p))
  (display-warning 'treesitter "Tree-sitter is not available (not compiled in or library missing); skipping grammar bootstrap." :warning))

(provide 'treesitter-config)
;;; treesitter-config.el ends here
