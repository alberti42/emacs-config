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
  ;; ultra-scroll (in `scroll-config.el') is a global mode that binds
  ;; wheel events via its own minor-mode keymap.  Its consume-and-do-nothing
  ;; behavior in image buffers leaves PDFs unscrollable by trackpad, and
  ;; binding into `pdf-view-mode-map' loses (major-mode map < minor-mode
  ;; map in keymap precedence).  `minor-mode-overriding-map-alist' wins
  ;; over any minor-mode map, so use that to redirect wheel events to
  ;; the default `mwheel-scroll' inside PDF buffers only.
  :hook (pdf-view-mode . pdf-tools-config--bypass-ultra-scroll)
  :bind (:map pdf-view-mode-map
              ([next]  . pdf-tools-config-scroll-up-lines)
              ([prior] . pdf-tools-config-scroll-down-lines))
  :preface
  (defcustom pdf-tools-config-page-key-step 5
    "How many line-scrolls PageDown/PageUp perform in `pdf-view-mode'.
Use `n'/`p' for whole-page jumps."
    :type 'integer
    :group 'pdf-tools)

  (defun pdf-tools-config-scroll-up-lines ()
    "Scroll down a few lines, simulating repeated arrow-down presses."
    (interactive)
    (dotimes (_ pdf-tools-config-page-key-step)
      (pdf-view-next-line-or-next-page 1)))

  (defun pdf-tools-config-scroll-down-lines ()
    "Scroll up a few lines, simulating repeated arrow-up presses."
    (interactive)
    (dotimes (_ pdf-tools-config-page-key-step)
      (pdf-view-previous-line-or-previous-page 1)))

  (defun pdf-tools-config--bypass-ultra-scroll ()
    "Override ultra-scroll's wheel bindings in this buffer."
    (let ((map (make-sparse-keymap)))
      (define-key map [wheel-up]    #'mwheel-scroll)
      (define-key map [wheel-down]  #'mwheel-scroll)
      (define-key map [wheel-left]  #'mwheel-scroll)
      (define-key map [wheel-right] #'mwheel-scroll)
      (push (cons 'ultra-scroll-mode map) minor-mode-overriding-map-alist)))
  :custom
  ;; `pdf-annot-latex-header' defaults via an initializer that reads
  ;; `org-format-latex-header'.  tecosaur's org-latex-preview fork
  ;; (pinned in `org-config.el') reorganized that variable out of
  ;; existence, so the initializer crashes inside `pdf-tools-install'.
  ;; Provide a literal preamble to bypass the initializer.
  (pdf-annot-latex-header
   "\\documentclass{article}
\\usepackage[usenames]{color}
\\pagestyle{empty}
\\setlength{\\textwidth}{12cm}")
  :config
  (pdf-loader-install))

(provide 'pdf-tools-config)
;;; pdf-tools-config.el ends here
