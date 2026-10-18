;;; markdown-ts-appear-config.el --- Reveal Markdown source at point -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `markdown-ts-appear' (Thysrael) is a minor mode over `markdown-ts-mode'
;; that shows the Markdown source of the element at point and the rendered
;; appearance everywhere else.  The package is on MELPA; straight is pointed
;; instead at the local checkout of the fork
;; `~/Programming/Others/fork-markdown-ts-appear', which carries the
;; `experiment/latex-to-svg-integration' branch that hands math previews to
;; `latex-to-svg-for-markdown'.  straight builds whatever branch that checkout
;; is on, not `:branch'.
;;
;; `markdown-config.el' already turns `latex-to-svg-for-markdown-mode' on
;; from `markdown-ts-mode-hook'.  The package attaches its reveal policy to
;; an adaptor enabled that way, so `markdown-ts-appear-enable-math-preview'
;; stays nil here; setting it to t would make the package enable the adaptor
;; itself, without the buffer-local settings `markdown-config.el' gives it.
;;
;; Tables stay with `pretty-tables-for-markdown' (`markdown-config.el'):
;; `markdown-ts-appear-table-style' is `raw', so the package draws no tables.

;;; Code:

(use-package markdown-ts-appear
  :straight (markdown-ts-appear
             :branch "main"
             ;; :local-repo "~/Programming/Others/fork-markdown-ts-appear"             
             :type git
             :host github
             :repo "Thysrael/markdown-ts-appear")             
  :custom
  (markdown-ts-appear-table-style 'raw)
  :hook (markdown-ts-mode-hook . markdown-ts-appear-mode))

(provide 'markdown-ts-appear-config)
;;; markdown-ts-appear-config.el ends here
