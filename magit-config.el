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

  ;; Take snapshot of layout and restore it on exit
  (setq magit-bury-buffer-function #'magit-restore-window-configuration)
  
  ;; Nerd icons for file entries (native support since magit 223461b).
  (when (fboundp 'magit-format-file-nerd-icons)
    (setq magit-format-file-function #'magit-format-file-nerd-icons))

  ;; Show the unpushed commits and untracked files sections expanded by default.
  (setf (alist-get 'unpushed magit-section-initial-visibility-alist) 'show)
  (setf (alist-get 'untracked magit-section-initial-visibility-alist) 'show))


;; Side-by-side diff viewer.
(when nil
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
    (define-key magit-mode-map "E" #'vdiff-magit)))

;; Forge: GitHub/GitLab integration (PRs, issues, reviews).
;;
;; NOTE: forge hard-depends on classic `markdown-mode' (its `Package-Requires'
;; lists it, and `forge-post-mode' is `define-derived-mode'd from `gfm-mode').
;; It composes/displays issue, PR, and comment bodies as GitHub-Flavored
;; Markdown.  So markdown-mode stays installed and shows autoload stubs in M-x
;; for as long as forge is enabled, even though nothing else here uses it
;; (lsp-mode renders docs via `markdown-ts-view-mode'; no preview package).
;; Dropping the dependency would require an upstream/fork change to forge
;; (re-parent `forge-post-mode' onto `markdown-ts-mode', replace the `gfm-mode'
;; display call, with a fallback for Emacs < 31) — a major rewrite, parked.
(use-package forge
  :after magit)

(provide 'magit-config)
;;; magit-config.el ends here
