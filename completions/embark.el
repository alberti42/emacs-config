;;; embark.el --- Contextual actions via Embark -*- lexical-binding: t; -*-

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
         ("C-c C-c" . embark-collect)))

(use-package embark-consult
  :after (embark consult))

(provide 'completions-embark)
;;; embark.el ends here
