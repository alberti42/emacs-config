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
  ;; Pinned to the fork while vedang/pdf-tools#361 is open: it stops `pdf-roll'
  ;; from claiming Emacs's region-highlight overlay as the one holding a page,
  ;; which left a rendered page painted over selections in other buffers.
  ;; `:files' mirrors the MELPA recipe -- without it the `build/' tree that
  ;; `pdf-tools-install' compiles `epdfinfo' from is missing.
  :straight (pdf-tools
             :type git
             :host github
             :repo "alberti42/fork-pdf-tools"
             :branch "fix/roll-region-overlay-adoption"
             :local-repo "/Users/andrea/Documents/Programming/Others/fork-pdf-tools"
             :files (:defaults "README" ("build" "Makefile") ("build" "server")))
  :magic ("%PDF" . pdf-view-mode)
  :hook ((pdf-view-mode . pdf-view-roll-minor-mode)
         (pdf-view-mode . (lambda () (display-line-numbers-mode -1))))
  ;; The vertical wheel is left to `pixel-scroll-precision-mode' (enabled
  ;; globally in `scroll-config.el'), which `pdf-view-roll-minor-mode' is built
  ;; for: it kills any buffer-local binding of that mode so the global one
  ;; applies, and `pdf-roll-pre-redisplay' recognizes the pixel-scroll commands
  ;; by name.
  ;;
  ;; The horizontal wheel is bound here because the global binding
  ;; (`scroll-config-horizontal') scrolls by columns, which an image buffer has
  ;; none of.  No minor mode binds it, so the major-mode map suffices.
  ;; `mwheel-scroll' routes it to `mwheel-scroll-left-function'
  ;; (`image-scroll-left' in an image buffer) when `mouse-wheel-tilt-scroll'
  ;; is on, and does nothing otherwise.
  :bind (:map pdf-view-mode-map
              ([next]  . pdf-tools-config-scroll-up-lines)
              ([prior] . pdf-tools-config-scroll-down-lines)
              ([wheel-left]  . mwheel-scroll)
              ([wheel-right] . mwheel-scroll))
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

  :config
  (pdf-loader-install))

(provide 'pdf-tools-config)
;;; pdf-tools-config.el ends here
