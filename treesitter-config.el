;;; treesitter-config.el --- Tree-sitter grammar bootstrap -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Emacs has built-in tree-sitter support (Emacs 29+), but tree-sitter *modes*
;; (e.g. json-ts-mode) need a compiled grammar library.
;;
;; This module ensures a small set of grammars are installed.
;; It does nothing if tree-sitter is unavailable.

;;; Code:

(if (not (and (fboundp 'treesit-available-p)
              (treesit-available-p)))
    (display-warning 'treesitter "Tree-sitter is not available (not compiled in or library missing); skipping grammar bootstrap." :warning)

  (require 'treesit)

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
        (treesit-install-language-grammar lang t))))

  ;; Bootstrap missing grammars
  (dolist (lang-source treesit-language-source-alist)
    (let ((lang (car lang-source)))
      (unless (treesit-language-available-p lang)
        (message "Treesitter: Installing grammar for %s..." lang)
        (condition-case err
            (treesit-install-language-grammar lang t)
          (error
           (display-warning 'treesitter
                            (format "Failed to install tree-sitter grammar for %s: %s"
                                    lang (error-message-string err))
                            :error)))))))

(provide 'treesitter-config)
;;; treesitter-config.el ends here
