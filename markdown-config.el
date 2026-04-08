;;; markdown-config.el --- Markdown reading and authoring -*- lexical-binding: t; -*-

;;; Code:

;; markdown-mode ---------------------------------------------------------------

(use-package markdown-mode
  :straight t
  :mode (("\\.md\\'"       . markdown-mode)
         ("\\.markdown\\'" . markdown-mode)
         ("README\\.md\\'" . gfm-mode))
  :custom
  ;; Enable [[wiki link]] syntax highlighting and navigation.
  (markdown-enable-wiki-links t)
  ;; Fontify fenced code blocks using their language's major mode.
  (markdown-fontify-code-blocks-natively t)
  :hook ((markdown-mode gfm-mode) . markdown-config--markup-setup))

(defun markdown-config--markup-setup ()
  "Enable markup hiding for a clean reading experience.
`markdown-hide-markup' is a superset of `markdown-hide-urls', so
enabling it alone is sufficient to hide URLs, brackets, asterisks, etc."
  ;; markdown-toggle-markup-hiding does more than setq: it updates
  ;; invisibility-spec and calls markdown-reload-extensions.
  (markdown-toggle-markup-hiding 1))

;; obsidian: Obsidian vault integration ----------------------------------------
;;
;; Set obsidian-directory to your vault, e.g.:
;;   (setq obsidian-directory "~/Documents/Obsidian")

(use-package obsidian
  :straight nil
  :load-path (lambda () (list (expand-file-name "local" emacs-config-dir)))
  :hook ((markdown-mode gfm-mode) . obsidian-mode)
  :custom
  ;; location of obsidian vault
  (obsidian-directory "~/Obsidian/Work")
  :bind (:map obsidian-mode-map
              ("C-c o f" . obsidian-follow-link-at-point)
              ("C-c o b" . obsidian-backlinks)
              ("C-c o F" . obsidian-find-file)
              ("C-c o i" . obsidian-insert-wikilink)))

;; elgrep (obsidian dependency) -----------------------------------------------
;;
;; Add lexical-binding cookie to its cache file.  Without this Emacs warns on
;; every startup about the missing cookie.
;;
;; It intercepts write-file inside elgrep-save-elgrep-data-file and prepends the
;; cookie before the file hits.

(with-eval-after-load 'elgrep
  (advice-add 'elgrep-save-elgrep-data-file :around
              (lambda (orig &rest args)
                (cl-letf* ((orig-write-file (symbol-function 'write-file))
                           ((symbol-function 'write-file)
                            (lambda (file &rest wf-args)
                              (goto-char (point-min))
                              (insert ";; -*- lexical-binding: t; -*-\n")
                              (apply orig-write-file file wf-args))))
                  (apply orig args)))))

;; grip-mode: live GitHub Markdown preview in browser --------------------------

(use-package grip-mode
  :straight t
  :bind (:map markdown-mode-command-map
              ("g" . grip-mode)))

(provide 'markdown-config)
;;; markdown-config.el ends here
