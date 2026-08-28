;;; project-config.el --- Project management settings -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Configures project.el behavior.
;;

;;; Code:

;; Treat git submodules as independent projects rather than merging
;; them into the parent repo's project root.
(use-package project
  :straight nil
  :custom
  (project-vc-merge-submodules nil)
  ;; `.dir-locals.el' is an extra root marker: `project-try-vc' roots at the
  ;; nearest ancestor holding a marker, so a subdirectory carrying one becomes
  ;; its own project root and wins over an outer `.git'.  Two payoffs: in a
  ;; monorepo it carves independent projects out of subdirectories (root moves
  ;; to the subdir, VCS backend inherited, so `project-files' stays git-aware
  ;; but scoped to it); and it makes a plain non-VCS directory a project too —
  ;; `project-try-vc' returns a backend-less `(vc nil ROOT)' when only the
  ;; marker matches with no enclosing VCS.
  ;;
  ;; lsp-mode derives its workspace root from project.el, so a marker is also
  ;; how a language server gets scoped: basedpyright reads `pyrightconfig.json'
  ;; at that root only.  `pyrightconfig.json' itself is not a marker — a config
  ;; dropped in a directory to tame the server for loose files there would swallow
  ;; every subdirectory below it into one project.  It is not needed for that job
  ;; either: with no marker in play `lsp--suggest-project-root' falls back to
  ;; `default-directory', which for a file sitting in that directory is the
  ;; directory itself, so the server finds the config anyway.
  ;;
  ;; To customize a subdir WITHOUT making it a subproject, don't drop a
  ;; `.dir-locals.el' there — put a `("subdir" . ((mode-or-nil . ((var . val)))))'
  ;; entry in the repo-root `.dir-locals.el' instead (deepest match wins).
  (project-vc-extra-root-markers '(".dir-locals.el")))

(provide 'project-config)
;;; project-config.el ends here
