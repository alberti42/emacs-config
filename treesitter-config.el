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
  ;; Note: markdown requires both markdown and markdown-inline from the split_parser branch.
  (setq treesit-language-source-alist
        '((json "https://github.com/tree-sitter/tree-sitter-json")
          (yaml "https://github.com/ikatyang/tree-sitter-yaml")
          (toml "https://github.com/tree-sitter-grammars/tree-sitter-toml")
          (elisp "https://github.com/Wilfred/tree-sitter-elisp")
          (typescript "https://github.com/tree-sitter/tree-sitter-typescript" "master" "typescript/src")
          (tsx "https://github.com/tree-sitter/tree-sitter-typescript" "master" "tsx/src")
          (bash "https://github.com/tree-sitter/tree-sitter-bash")
          (zsh "https://github.com/tree-sitter-grammars/tree-sitter-zsh")
          (python "https://github.com/tree-sitter/tree-sitter-python")
          (markdown "https://github.com/tree-sitter-grammars/tree-sitter-markdown" "split_parser" "tree-sitter-markdown/src")
          (markdown-inline "https://github.com/tree-sitter-grammars/tree-sitter-markdown" "split_parser" "tree-sitter-markdown-inline/src")))

  ;; Remap major modes to their tree-sitter counterparts
  (setq major-mode-remap-alist
        '((json-mode . json-ts-mode)
          (js-json-mode . json-ts-mode)
          (yaml-mode . yaml-ts-mode)
          (toml-mode . toml-ts-mode)
          (typescript-mode . typescript-ts-mode)
          (tsx-mode . tsx-ts-mode)
          (sh-mode . bash-ts-mode)
          (zsh-mode . bash-ts-mode)
          (python-mode . python-ts-mode)))

  (defun treesitter-config-reinstall-grammars ()
    "Force reinstallation of all grammars in `treesit-language-source-alist'.
Use this to update grammars to their latest versions."
    (interactive)
    (dolist (lang-source treesit-language-source-alist)
      (let ((lang (car lang-source)))
        (message "Treesitter: Reinstalling grammar for %s..." lang)
        (condition-case err
            (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) t)))
              (treesit-install-language-grammar lang))
          (error
           (message "Treesitter: Failed to install %s: %s" lang (error-message-string err)))))))

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
