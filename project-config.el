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
  ;; Extra root markers let a nested config file mark a project root, which
  ;; `project-try-vc' picks over an outer `.git' (it roots at the nearest
  ;; ancestor holding any marker):
  ;;
  ;;   - `pyrightconfig.json': lsp-mode derives its root from project.el, and
  ;;     basedpyright reads `pyrightconfig.json' only at that root — so this
  ;;     puts the pyright root wherever the config lives (e.g. a course dir)
  ;;     rather than the whole repo.
  ;;   - `.dir-locals.el': a subdirectory carrying one becomes its own project
  ;;     root.  Two payoffs: in a monorepo it carves independent projects out
  ;;     of subdirectories (root moves to the subdir, VCS backend inherited, so
  ;;     `project-files' stays git-aware but scoped to it); and it makes a
  ;;     plain non-VCS directory a project too — `project-try-vc' returns a
  ;;     backend-less `(vc nil ROOT)' when only the marker matches with no
  ;;     enclosing VCS.
  ;;
  ;; To customize a subdir WITHOUT making it a subproject, don't drop a
  ;; `.dir-locals.el' there — put a `("subdir" . ((mode-or-nil . ((var . val)))))'
  ;; entry in the repo-root `.dir-locals.el' instead (deepest match wins).
  (project-vc-extra-root-markers '("pyrightconfig.json" ".dir-locals.el")))

(provide 'project-config)
;;; project-config.el ends here
