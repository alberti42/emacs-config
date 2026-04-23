;;; lsp-elisp-config.el --- Elisp LSP configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Elisp LSP via elisp-ls (Ellsp).
;;
;; Installation:
;; 1. Install Eask (build tool):
;;    brew install eask-cli
;;
;; 2. Install Ellsp (language server):
;;    git clone https://github.com/elisp-lsp/ellsp ~/.local/share/ellsp
;;    cd ~/.local/share/ellsp
;;    eask install
;;    eask exec bin/install-ellsp
;;
;; 3. Link the binary to your PATH (e.g., ~/.local/bin):
;;    ln -s ~/.local/share/ellsp/bin/ellsp ~/.local/bin/ellsp
;;

;;; Code:

;; Ellsp is the only real option out there and it's alpha-stage — mostly
;; completions and docstring hover, and it largely duplicates what Emacs already
;; gives us natively (eldoc, completion-at-point, xref). We keep this package
;; disabled for now; we can always reassess it in the future.

(when nil
  (use-package lsp-ellsp
    :straight (lsp-ellsp :type git :host github :repo "elisp-lsp/lsp-ellsp")
    :init
    (add-hook 'emacs-lisp-mode-hook
              (lambda ()
                (require 'lsp-ellsp)
                (lsp-deferred)))))

(provide 'lsp-elisp-config)

;;; lsp-elisp-config.el ends here
