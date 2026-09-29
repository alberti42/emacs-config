;;; embark-config.el --- Contextual actions via Embark -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Embark provides contextual actions on minibuffer candidates and targets at
;; point.  The main draw is `embark-export', which sends consult-ripgrep results
;; into a proper grep-mode buffer (via embark-consult).
;;

;;; Code:

(use-package embark
  :bind (("C-\\" . embark-act)
         ("M-C-\\" . embark-dwim)
         :map minibuffer-local-map
         ("C-c C-o" . embark-export)
         ("C-c C-c" . embark-collect))
  :config
  (keymap-set embark-region-map "O" #'my/markdown-region-to-org))

(use-package embark-consult
  :after (embark consult))

(provide 'embark-config)
;;; embark-config.el ends here
