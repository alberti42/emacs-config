;;; consult.el --- Consult commands and integrations -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Consult provides a set of high-quality narrowing commands that work well
;; with Vertico (or other completing-read UIs).
;;

;;; Code:

(use-package consult
  :bind (
         ;; Replace default switch-to-buffer with consult-buffer.
         ("C-x b" . consult-buffer)
         ;; Replace default bookmark-jump with consult-bookmark for live preview.
         ("C-x r b" . consult-bookmark)
         ;; A small, mnemonic prefix for search/navigation.
         ("C-c s b" . consult-buffer)
         ("C-c s l" . consult-line)
         ("C-c s r" . consult-ripgrep)
         ("C-c s R" . consult-ripgrep-here)
         ("C-c s i" . consult-imenu)
         ("C-c s o" . consult-outline)
         ("C-c s h" . consult-org-heading)
         ("C-c s a" . consult-org-agenda)
         ("C-c s m" . consult-mark)
         ("C-c s M" . consult-global-mark)
         ("C-c s k" . consult-keep-lines)
         ("C-c s y" . consult-yank-pop)
         ("C-c s c" . consult-flycheck)
         ("C-c s e" . consult-compile-error)
         ;; Replace project-find-file with fd-backed consult-fd.
         ("C-c s f" . consult-fd)
         ("C-c s F" . consult-fd-here))
  :init
  ;; Use Consult for xref UI when available.
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  ;; Navigate minibuffer history with M-up/M-down (mirrors M-p/M-n).
  (define-key minibuffer-local-map (kbd "M-<up>") #'previous-history-element)
  (define-key minibuffer-local-map (kbd "M-<down>") #'next-history-element)

  ;; Persist search histories across sessions using built-in savehist.
  (dolist (var '(consult--grep-history
                 consult--find-history
                 consult--line-history))
    (add-to-list 'savehist-additional-variables var))
  
  ;; Include hidden directories in fd search, but exclude .git.
  (setq consult-fd-args '("fd" "--hidden" "--exclude" ".git" "--color=never" "--full-path"))
  :config
  ;; Preserve recentf-list order (most-recently-opened first).
  (setq consult-source-recent-file
        (plist-put consult-source-recent-file :sort nil)))

(use-package consult-xref-stack
  :straight (consult-xref-stack
             :type git
             :host github
             :repo "brett-lempereur/consult-xref-stack")
  ;; Browse the xref back/forward history (the stack behind `xref-go-back') with
  ;; preview.  Narrow with `b'/`f' to one direction.
  :bind ("C-c s x" . consult-xref-stack))

(provide 'completions-consult)
;;; consult.el ends here
