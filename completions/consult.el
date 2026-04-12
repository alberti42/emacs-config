;;; consult.el --- Consult commands and integrations -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Consult provides a set of high-quality narrowing commands that work well
;; with Vertico (or other completing-read UIs).
;;

;;; Code:

(use-package consult
  ;; :straight (consult
  ;;            :type git
  ;;            :host github
  ;;            :branch "fix-suppressed-hooks"
  ;;            :repo "alberti42/fork-consult")
  :bind (
         ;; Replace default switch-to-buffer with consult-buffer.
         ("C-x b" . consult-buffer)
         ;; A small, mnemonic prefix for search/navigation.
         ("C-c s b" . consult-buffer)
         ("C-c s l" . consult-line)
         ("C-c s r" . consult-ripgrep)
         ("C-c s R" . consult-ripgrep-here)
         ("C-c s i" . consult-imenu)
         ("C-c s m" . consult-mark)
         ("C-c s M" . consult-global-mark)
         ("C-c s k" . consult-keep-lines)
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
  ;; Consult filters `find-file-hook` and allow only a few hooks during previews
  ;; to maintain performance and avoid polluting session state (e.g. it does not
  ;; trigger recentf for each file consulted). However, when selecting a match,
  ;; it does switch to a buffer without re-triggering the full hook. We advice
  ;; `consult--jump' (which is the final jump function) to run the "blocked"
  ;; hooks manually.  Note: we exclude hooks that Consult *already* ran during
  ;; preview (like `save-place`) to avoid moving the point away from the match.
  ;; We have filed a PR to correct this behavior upstream. When the PR is
  ;; merged, this advice is no longer necessary.
  (defun emacs-config-consult-after-jump-run-hooks (&rest _args)
    "Run `find-file-hook' functions that were blocked during Consult preview."
    (dolist (hook find-file-hook)
      (unless (memq hook consult-preview-allowed-hooks)
        (when (and (symbolp hook) (fboundp hook))
          (funcall hook))))
    (advice-add #'consult--jump :after #'emacs-config-consult-after-jump-run-hooks))

  ;; Use our new hook API from the consult fork to ensure full initialization
  ;; (recentf, vc-refresh, etc.) when we finally select a file.
  ;; (add-hook 'consult-after-final-jump-hook #'consult-run-suppressed-hooks)
  )

  (provide 'completions-consult)
;;; consult.el ends here
