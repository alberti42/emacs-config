;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Code:

;; markdown-mode ---------------------------------------------------------------

(use-package markdown-mode
  :straight t
  :mode (("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :custom
  ;; Fontify fenced code blocks using their language's major mode.
  (markdown-fontify-code-blocks-natively t)
  ;; Support wiki links
  (markdown-enable-wiki-links t)
  :hook ((markdown-mode gfm-mode) . markdown-config--markup-setup))

(defun markdown-config--markup-setup ()
  "Enable markup hiding for a clean reading experience.
`markdown-hide-markup' is a superset of `markdown-hide-urls', so
enabling it alone is sufficient to hide URLs, brackets, asterisks, etc."
  ;; markdown-toggle-markup-hiding does more than setq: it updates
  ;; invisibility-spec and calls markdown-reload-extensions.
  (markdown-toggle-markup-hiding 1))

;; grip-mode: live GitHub Markdown preview in browser --------------------------

(use-package grip-mode
  :straight t
  :bind (:map markdown-mode-command-map
              ("g" . grip-mode)))

(provide 'markdown-config)
;;; markdown-config.el ends here
