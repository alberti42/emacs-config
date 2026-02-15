;;; completion.el --- Minibuffer completion UI -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Show completion candidates immediately in the minibuffer.
;; This makes prompts like `lsp-execute-code-action` feel less "TAB-driven".
;;

;;; Code:

(use-package icomplete
  :straight nil
  :init
  (setq icomplete-show-matches-on-no-input t
        icomplete-compute-delay 0
        icomplete-delay-completions-threshold 0)
  (fido-vertical-mode 1))

(provide 'completion)

;;; completion.el ends here
