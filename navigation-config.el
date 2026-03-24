;;; navigation-config.el --- Cursor position jump history -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; better-jumper provides a proper forward/backward jump list, similar to
;; Vim's C-o / C-i or Sublime Text's jump history.  Jump points are recorded
;; automatically before xref/LSP jumps (go-to-definition, find-references, etc.)
;; and before isearch exits.
;;

;;; Code:

(use-package better-jumper
  :config
  (better-jumper-mode 1)
  :bind (("C-c [" . better-jumper-jump-backward)
         ("C-c ]" . better-jumper-jump-forward)))

(provide 'navigation-config)
;;; navigation-config.el ends here
