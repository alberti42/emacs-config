;;; pdf-tools-config.el --- In-Emacs PDF viewer (pdf-tools) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; pdf-tools renders PDFs as images via a C helper (`epdfinfo', built
;; against poppler) and replaces DocView for `.pdf' files.  This module
;; uses `pdf-loader-install' so the C helper is built on first PDF open
;; rather than at startup.
;;
;; Continuous scroll across page boundaries is provided upstream as of
;; v1.3.0 via `pdf-view-roll-minor-mode' (still flagged experimental by
;; the maintainer).  We enable it from `pdf-view-mode-hook'; if it
;; misbehaves on a particular file, toggle it off with `M-x
;; pdf-view-roll-minor-mode'.
;;
;; External dependencies (built once, on first PDF open):
;;   - poppler, automake, autoconf, pkg-config (for epdfinfo)
;;   - on macOS: `brew install poppler automake'

;;; Code:

(use-package pdf-tools
  :straight t
  :magic ("%PDF" . pdf-view-mode)
  :hook ((pdf-view-mode . pdf-view-roll-minor-mode)
         (pdf-view-mode . (lambda () (display-line-numbers-mode -1))))
  :config
  (pdf-loader-install))

(provide 'pdf-tools-config)
;;; pdf-tools-config.el ends here
