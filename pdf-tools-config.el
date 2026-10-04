;;; pdf-tools-config.el --- In-Emacs PDF viewer (pdf-tools) -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; pdf-tools renders PDFs as images via a C helper (`epdfinfo', built
;; against poppler) and replaces DocView for `.pdf' files.  This module
;; uses `pdf-loader-install' so the C helper is built on first PDF open
;; rather than at startup.
;;
;; On the fork's `feat/single-page-roll' branch `pdf-view-mode' scrolls
;; continuously across pages; `M-x pdf-view-single-page-mode' shows one
;; page at a time instead.  `pdf-view-roll-minor-mode' is obsolete there
;; and only warns.
;;
;; External dependencies (built once, on first PDF open):
;;   - poppler, automake, autoconf, pkg-config (for epdfinfo)
;;   - on macOS: `brew install poppler automake'

;;; Code:

(use-package pdf-tools
  ;; Pinned to the fork.  `merged' carries the fixes sent upstream as pull
  ;; requests; `feat/single-page-roll', built on it and on
  ;; `feat/async-render', adds rendering without waiting for the server,
  ;; continuous scrolling as the default and `pdf-view-single-page-mode'.
  ;; It is being tested here before it is merged into `merged'.
  ;; `:files' mirrors the MELPA recipe -- without it the `build/' tree that
  ;; `pdf-tools-install' compiles `epdfinfo' from is missing.
  :straight (pdf-tools
             :type git
             :host github
             :repo "alberti42/fork-pdf-tools"
             :branch "feat/single-page-roll"
             :local-repo "/Users/andrea/Documents/Programming/Others/fork-pdf-tools"
             :files (:defaults "README" ("build" "Makefile") ("build" "server"))
             ;; A rebuild reconstructs the build directory from `:files', which
             ;; drops the `epdfinfo' binary `pdf-tools-install' compiled into
             ;; it; `pdf-view-mode' then fails and PDFs open as raw bytes.
             ;; Recompile it here.  `-D' leaves the Homebrew dependencies
             ;; (poppler, automake) alone, and `autobuild' cds to its own
             ;; directory, so the relative path works from the repo root.
             :post-build ("./server/autobuild" "-D" "-i"
                          "/Users/andrea/.config/emacs/straight/build/pdf-tools/"))
  ;; `pdf-loader-install' is autoloaded: it runs at startup, before pdf-tools
  ;; is loaded, and puts entries in `auto-mode-alist' and `magic-mode-alist'
  ;; that load pdf-tools when the first PDF is visited.
  :init
  (pdf-loader-install)
  ;; The horizontal wheel is bound here because the global binding
  ;; (`scroll-config-horizontal') scrolls by columns, which an image buffer has
  ;; none of.  No minor mode binds it, so the major-mode map suffices.
  ;; `mwheel-scroll' routes it to `mwheel-scroll-left-function'
  ;; (`image-scroll-left' in an image buffer) when `mouse-wheel-tilt-scroll'
  ;; is on, and does nothing otherwise.
  ;; The vertical wheel and PageDown/PageUp need nothing here:
  ;; `pdf-roll-wheel-scroll' scrolls by the pixels a trackpad reports, and
  ;; PageDown/PageUp scroll `pdf-view-page-key-lines' lines.
  :bind (:map pdf-view-mode-map
              ([wheel-left]  . mwheel-scroll)
              ([wheel-right] . mwheel-scroll)))

(provide 'pdf-tools-config)
;;; pdf-tools-config.el ends here
