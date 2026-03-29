;;; magit-config.el --- Magit and Git forge configuration -*- lexical-binding: t; -*-

;;; Code:

(use-package magit
  :bind
  ("C-c g" . magit-status)
  ("C-c M-g" . magit-dispatch)
  :config
  ;; Show fine-grained word-level diffs within a hunk.
  (setq magit-diff-refine-hunk 'all)

  ;; Set location of git executable to speed up magit
  (setq magit-git-executable (executable-find "git"))

  ;; Ask before saving modified repository buffers.
  (setq magit-save-repository-buffers t)

  ;; Open the status buffer in a dedicated full-frame window.
  (setq magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1)
  
  ;; Nerd icons for file entries (native support since magit 223461b).
  (when (fboundp 'magit-format-file-nerd-icons)
    (setq magit-format-file-function #'magit-format-file-nerd-icons))

  ;; Show the unpushed commits section expanded by default.
  (setf (alist-get 'unpushed magit-section-initial-visibility-alist) 'show))

;; Disable line numbers and which-key in commit and rebase editing buffers.
(add-hook 'git-commit-mode-hook (lambda ()
                                  ;; hide line-numbers in editing buffers
                                  (display-line-numbers-mode -1)
                                  ;; which-key intercepts key
                                  ;; sequences to display its popup,
                                  ;; and in the commit buffer there
                                  ;; seems to be a conflict with how
                                  ;; certain prefix keys (like C-x)
                                  ;; are handled — likely an
                                  ;; interaction with
                                  ;; git-commit-mode's keymap
                                  ;; overrides. The exact bug depends
                                  ;; on which-key's timer firing
                                  ;; mid-sequence.
                                  (setq-local which-key-inhibit t)
                                  ;; text-mode-hook enables soft-wrap with fill-column=100.
                                  ;; Disable it here; git-commit-mode enforces its own 72-column
                                  ;; hard-wrap convention via auto-fill-mode anyway.
                                  (when (fboundp 'soft-wrap-mode)
                                    (soft-wrap-mode -1))))
(add-hook 'git-rebase-mode-hook (lambda () (display-line-numbers-mode -1)))

;; Side-by-side diff viewer.
(use-package vdiff
  :config
  (define-key vdiff-mode-map (kbd "C-c v") vdiff-mode-prefix-map)
  (define-key vdiff-3way-mode-map (kbd "C-c v") vdiff-mode-prefix-map))

;; Magit integration for vdiff (replaces ediff bindings with vdiff).
;; Local copy of unmaintained upstream (https://github.com/justbur/emacs-vdiff-magit,
;; last commit 2022) with a patch for magit-get-revision-buffer removal.
;; See local/vdiff-magit.el for details.
(use-package vdiff-magit
  :straight nil
  :load-path (lambda () (list (expand-file-name "local" emacs-config-dir)))
  :after (vdiff magit)
  :config
  (transient-suffix-put 'magit-dispatch "e" :description "vdiff (dwim)")
  (transient-suffix-put 'magit-dispatch "e" :command 'vdiff-magit-dwim)
  (transient-suffix-put 'magit-dispatch "E" :description "vdiff")
  (transient-suffix-put 'magit-dispatch "E" :command 'vdiff-magit)
  (define-key magit-mode-map "e" #'vdiff-magit-dwim)
  (define-key magit-mode-map "E" #'vdiff-magit))

;; Forge: GitHub/GitLab integration (PRs, issues, reviews).
(use-package forge
  :after magit)

(provide 'magit-config)
;;; magit-config.el ends here
