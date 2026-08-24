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
         (pdf-view-mode . (lambda () (display-line-numbers-mode -1)))
         (pdf-view-mode . pdf-tools-config--wheel-to-pdf-roll))
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

  (defvar pdf-tools-config--wheel-override t
    "Flag keying the wheel keymap in `minor-mode-overriding-map-alist'.
An entry there needs a mode symbol whose value is non-nil; this one exists so
`pdf-tools-config--wheel-to-pdf-roll' does not have to name a real minor mode.")

  (defun pdf-tools-config--wheel-to-pdf-roll ()
    "Send the vertical wheel to `mwheel-scroll' in this buffer.
`pdf-view-roll-minor-mode' points `mwheel-scroll-up-function' and its companion
at its own scroll commands, whose redisplay hook keeps `window-start', the
vscroll and `window-point' in step.  `pixel-scroll-precision' moves the first
two but never point, so redisplay recenters on the page's character and undoes
the scroll.

`pixel-scroll-precision-mode' binds the wheel in a minor-mode keymap, which
outranks `pdf-view-mode-map'; only `minor-mode-overriding-map-alist' outranks
that.  An entry there replaces the whole keymap of the mode it names, so it
names `pdf-tools-config--wheel-override' and leaves the rest of the
pixel-scroll bindings alone.

The wheel events also have to be coalesced: `mwheel-scroll' scrolls
`mouse-wheel-scroll-amount' times `event-line-count' lines, and macOS reports a
line count of 0 for the one or two pixel deltas of a gentle trackpad gesture."
    (setq-local mwheel-coalesce-scroll-events t)
    (let ((map (make-sparse-keymap)))
      (define-key map [wheel-up]   #'mwheel-scroll)
      (define-key map [wheel-down] #'mwheel-scroll)
      (push (cons 'pdf-tools-config--wheel-override map)
            minor-mode-overriding-map-alist)))

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
