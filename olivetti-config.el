;;; olivetti-config.el --- Olivetti centred-prose mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Configures `olivetti-mode' for prose buffers.  Activation is per-mode in
;; the relevant `syntaxes/*.el' file; this module only sets up the package.
;;
;; Olivetti centres text by growing BOTH window margins symmetrically until
;; the body width matches a target column.  Upstream commits 0e5d2649 and
;; 342df5a9 make it preserve any pre-existing margin widths rather than
;; resetting them to zero, so the global `left-margin-width' reserved for
;; git-gutter (see init.el) is no longer clobbered.

;;; Code:

(use-package olivetti
  :straight t
  :commands (olivetti-mode)
  :custom
  ;; nil tracks `fill-column' (body width = fill-column + 2).
  (olivetti-body-width nil)
  ;; Plain margins; no fringe "page-edge" decoration.
  (olivetti-style nil)
  ;; Save/restore `visual-line-mode' state across olivetti-mode toggles.
  (olivetti-recall-visual-line-mode-entry-state t))

(provide 'olivetti-config)
;;; olivetti-config.el ends here
