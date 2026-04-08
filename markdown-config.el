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
  :hook ((markdown-mode gfm-mode) . markdown-config--markup-setup))

(defun markdown-config--markup-setup ()
  "Enable markup hiding for a clean reading experience.
`markdown-hide-markup' is a superset of `markdown-hide-urls', so
enabling it alone is sufficient to hide URLs, brackets, asterisks, etc."
  ;; markdown-toggle-markup-hiding does more than setq: it updates
  ;; invisibility-spec and calls markdown-reload-extensions.
  (markdown-toggle-markup-hiding 1))

;; Wikilink visual rendering ---------------------------------------------------
;;
;; obsidian.el handles navigation (follow-link, backlinks, find-file); this is
;; purely cosmetic: hide [[ ]] delimiters so only the display text is visible.
;; Integrated with font-lock so jit-lock refontifies incrementally.
;;
;; [[Target|Display Text]] → shows "Display Text"
;; [[Page]]                → shows "Page"

(defconst markdown-config--wikilink-keywords
  '(("\\[\\[\\([^]|]+\\)|\\([^]]+\\)\\]\\]"   ; [[Target|Display Text]]
     (0 (progn
          (put-text-property (match-beginning 0) (match-beginning 2) 'display "")
          (put-text-property (match-end 2)       (match-end 0)       'display "")
          nil)))
    ("\\[\\[\\([^]|]+\\)\\]\\]"               ; [[Page]]
     (0 (progn
          (put-text-property (match-beginning 0) (match-beginning 1) 'display "")
          (put-text-property (match-end 1)       (match-end 0)       'display "")
          nil))))
  "Font-lock keywords that hide [[ and ]] wikilink delimiters.")

(defun markdown-config--setup-wikilinks ()
  "Register wikilink font-lock keywords in the current buffer.
Respects `markdown-hide-markup': keywords are added only when hiding is on,
mirroring how markdown-mode handles standard [text](url) links."
  ;; Tell font-lock to manage the 'display property so it clears and
  ;; re-applies it correctly during incremental refontification.
  (setq-local font-lock-extra-managed-props
              (append font-lock-extra-managed-props '(display)))
  (when markdown-hide-markup
    (font-lock-add-keywords nil markdown-config--wikilink-keywords t)))

(defun markdown-config--sync-wikilinks (&rest _)
  "Sync wikilink keywords with the current `markdown-hide-markup' state.
Advises `markdown-toggle-markup-hiding' so toggling standard markup
hiding also toggles wikilink hiding."
  (if markdown-hide-markup
      (font-lock-add-keywords nil markdown-config--wikilink-keywords t)
    (font-lock-remove-keywords nil markdown-config--wikilink-keywords))
  (font-lock-flush))

(dolist (hook '(markdown-mode-hook gfm-mode-hook))
  (add-hook hook #'markdown-config--setup-wikilinks))

(advice-add 'markdown-toggle-markup-hiding :after #'markdown-config--sync-wikilinks)

;; obsidian: Obsidian vault integration ----------------------------------------
;;
;; Set obsidian-directory to your vault, e.g.:
;;   (setq obsidian-directory "~/Documents/Obsidian")

(use-package obsidian
  :straight t
  :hook ((markdown-mode gfm-mode) . obsidian-mode)
  :bind (:map obsidian-mode-map
              ("C-c o f" . obsidian-follow-link-at-point)
              ("C-c o b" . obsidian-backlinks)
              ("C-c o F" . obsidian-find-file)
              ("C-c o i" . obsidian-insert-wikilink)))

;; grip-mode: live GitHub Markdown preview in browser --------------------------

(use-package grip-mode
  :straight t
  :bind (:map markdown-mode-command-map
              ("g" . grip-mode)))

(provide 'markdown-config)
;;; markdown-config.el ends here
