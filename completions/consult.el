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
         ;; A small, mnemonic prefix for search/navigation.
         ("C-c s b" . consult-buffer)
         ("C-c s l" . consult-line)
         ("C-c s r" . consult-ripgrep)
         ("C-c s R" . emacs-config-ripgrep-here)
         ("C-c s i" . consult-imenu)
         ("C-c s m" . consult-mark)
         ("C-c s k" . consult-keep-lines)
         ;; Replace project-find-file with fd-backed consult-fd.
         ("C-x p f" . consult-fd)
         ("C-x p F" . emacs-config-find-file-here))
  :init
  ;; Use Consult for xref UI when available.
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  ;; Persist search histories across sessions using built-in savehist.
  (dolist (var '(consult--grep-history
                 consult--find-history
                 consult--line-history))
    (add-to-list 'savehist-additional-variables var))
  
  ;; Include hidden directories in fd search, but exclude .git.
  (setq consult-fd-args '("fd" "--hidden" "--exclude" ".git" "--color=never" "--full-path")))

(provide 'completions-consult)
;;; consult.el ends here
