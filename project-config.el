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
  (project-vc-merge-submodules nil))

;; Recognize directories containing `.dir-locals.el' as projects.
;;
;; The default detector `project-try-vc' only matches VCS roots, so a folder
;; that is not under git/hg/etc. is invisible to `project.el' even when it
;; otherwise looks like a self-contained project. Adding `.dir-locals.el' as a
;; marker is a lightweight way to opt a directory in without having to `git
;; init' it.
;;
;; `project-vc-extra-root-markers' does NOT help here: it only refines detection
;; inside an existing VCS repo, not outside one.
;;
;; The `transient' tag in the returned cons cell is `project.el''s term for a
;; project without a VCS backend — just a plain directory treated as a root.
;; File listing, root resolution, and `C-x p' commands still work; only the
;; VC-specific operations (branch, diff, log) don't apply. Transient projects
;; are not persisted to the known-projects list automatically; use
;; `project-remember-project' (or `C-x p p' once) if you want it to stick.
(defun project-config-try-dir-locals (dir)
  "Return a transient project rooted at the nearest `.dir-locals.el' above DIR."
  (when-let ((root (locate-dominating-file dir ".dir-locals.el")))
    (cons 'transient (expand-file-name root))))

(add-hook 'project-find-functions #'project-config-try-dir-locals 90)

(provide 'project-config)
;;; project-config.el ends here
