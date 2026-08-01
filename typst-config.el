;;; typst-config.el --- Typst editing via typst-ts-mode -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Tree-sitter major mode for Typst (https://typst.app) from meow_king's
;; `typst-ts-mode' (https://codeberg.org/meow_king/typst-ts-mode/).
;; Emacs 29+.
;;
;; The typst tree-sitter grammar (uben0's) is bootstrapped centrally in
;; `treesitter-config.el' via `treesit-language-source-alist', so this module
;; only wires up the mode itself; it does not install a grammar.
;;
;; Two distinct preview paths:
;;
;;   1. Compiled-PDF preview (`typst-ts-preview', `typst-ts-compile').  These
;;      shell out to the `typst' CLI, so they require it on PATH:
;;        brew install typst
;;      The compiled PDF is opened through `pdf-preview' (shared with
;;      latex-config.el), honouring `pdf-preview-viewer' (Skim on macOS by
;;      default) instead of upstream's `browse-url' default.
;;
;;   2. Live preview with source<->preview jumping (`typst-preview-mode',
;;      below), backed by the tinymist server over a websocket.  Requires the
;;      `tinymist' binary on PATH; the easiest way to get it is
;;      `M-x typst-ts-lsp-download-binary' (typst-ts-mode fetches a release),
;;      or `cargo install --git https://github.com/Myriad-Dreamin/tinymist
;;      --locked tinymist-cli'.
;;
;; Editing, navigation, and highlighting work without either binary.
;;
;; In-mode bindings (from `typst-ts-mode-map'):
;;   C-c C-c    typst-ts-compile
;;   C-c C-S-c  typst-ts-compile-and-preview
;;   C-c C-p    typst-ts-preview          (compiled PDF)
;;   C-c C-w    typst-ts-watch-mode
;;   C-c C-l    typst-preview-mode        (live tinymist preview)
;;   C-c C-j    typst-preview-send-position (jump source -> live preview)

;;; Code:

(require 'pdf-preview)

(use-package typst-ts-mode
  :straight (typst-ts-mode
             :type git
             :repo "https://codeberg.org/meow_king/typst-ts-mode.git")
  :mode ("\\.typ\\'" . typst-ts-mode)
  :custom
  ;; Open the compiled PDF through the shared viewer selector rather than
  ;; upstream's `browse-url' default.
  (typst-ts-preview-function #'pdf-preview-open)
  ;; Highlight fenced raw code blocks with the embedded language's grammar.
  ;; Must be set before the first typst buffer is opened (which the :custom
  ;; block guarantees, since it runs at load time).
  (typst-ts-enable-raw-blocks-highlight t)
  ;; Hide the compilation buffer on a successful `typst compile'.
  (typst-ts-compile-hide-compilation-buffer-if-success t))

;;;; Keep the compile buffer out of the window layout ---------------------------
;;
;; On a successful compile, typst-ts-mode's finish function calls
;; `delete-windows-on' the *typst-compilation* buffer.  If that buffer had been
;; shown in one of the frame's windows (e.g. it replaced the live-preview
;; window), deleting that window collapses a multi-window layout down to a
;; single window with the source — the reported annoyance.
;;
;; Fix it the same way `compile-config.el' quiets ordinary builds: keep the
;; compilation buffer out of the window tree entirely, so there is no window
;; for `delete-windows-on' to remove and the layout is preserved.
;; `compilation-start' displays with `(allow-no-window . t)', which is what
;; makes `display-buffer-no-window' effective; a plain `display-buffer' (used
;; in the error handler below) passes no such flag, so it falls through to the
;; normal actions and still pops the buffer up.

(defun typst-config--compile-buffer-p (buffer)
  "Non-nil when BUFFER is a typst-ts compilation buffer."
  (and (buffer-live-p (get-buffer buffer))
       (eq (buffer-local-value 'major-mode (get-buffer buffer))
           'typst-ts-compilation-mode)))

(defun typst-config--no-window-p (buffer _alist)
  "`display-buffer-alist' condition matching typst-ts compilation BUFFER."
  (typst-config--compile-buffer-p buffer))

(add-to-list 'display-buffer-alist
             '(typst-config--no-window-p (display-buffer-no-window)))

(defun typst-config--show-compile-on-error (buffer msg)
  "Pop up the hidden typst compilation BUFFER only when the build failed.
MSG is the `compilation-finish-functions' status string."
  (when (and (typst-config--compile-buffer-p buffer)
             (not (string-prefix-p "finished" (string-trim msg))))
    (display-buffer buffer)))

(add-hook 'compilation-finish-functions #'typst-config--show-compile-on-error)

;;;; Live preview via tinymist -------------------------------------------------
;;
;; `typst-preview.el' (havarddj) drives tinymist's incremental HTML preview
;; over a websocket: live updates on every keystroke, plus bidirectional
;; source<->preview jumping (the SyncTeX-like feature that the compiled-PDF
;; path cannot offer, since typst PDFs carry no position map).

(use-package websocket
  :defer t)

(use-package typst-preview
  :straight (typst-preview
             :type git
             :host github
             :repo "havarddj/typst-preview.el")
  :after typst-ts-mode
  :commands (typst-preview-mode typst-preview-start)
  :init
  ;; Start tinymist and open the browser as soon as `typst-preview-mode' is on.
  (setq typst-preview-autostart t
        typst-preview-open-browser-automatically t)
  :custom
  (typst-preview-executable "tinymist")
  (typst-preview-partial-rendering t)
  ;; Invert preview colours to match the OS light/dark appearance.
  (typst-preview-invert-colors "auto")
  ;; "xwidget" renders the preview in an in-Emacs webkit buffer (requires an
  ;; Emacs built --with-xwidgets); "default" would route through `browse-url'
  ;; to the system browser instead.
  (typst-preview-browser "xwidget")
  :bind (:map typst-ts-mode-map
              ("C-c C-l" . typst-preview-mode)
              :map typst-preview-mode-map
              ("C-c C-j" . typst-preview-send-position)))

(provide 'typst-config)
;;; typst-config.el ends here
