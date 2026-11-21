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
  :init
  ;; The known-project list defaults to `project-list-file' inside
  ;; `user-emacs-directory' -- a symlink into the dotfiles worktree here.  It
  ;; is state, not cache: the list is what this user happened to open, and no
  ;; scan reproduces it.
  (setq project-list-file
        (emacs-config-state-file "projects"
                                 (expand-file-name "projects"
                                                   user-emacs-directory)))
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
  (project-vc-extra-root-markers '(".dir-locals.el"))
  :config
  (advice-add 'project-find-dir :override #'project-config-find-dir))

(defun project-config--list-dirs (root ignores)
  "Return the directories under ROOT, relative and ending in a slash.
IGNORES is a list of patterns in the form `project-ignores' returns.
ROOT itself is left out, and so is every directory named in
`vc-directory-exclusion-list': IGNORES excludes only what is inside such
a directory (`*/.git/*'), which for files is the same thing."
  (let ((default-directory (file-name-as-directory root))
        (command (format "%s -L . %s -type d -print0"
                         find-program
                         (xref--find-ignores-arguments ignores "./")))
        dirs)
    (with-temp-buffer
      ;; A subdirectory that cannot be read makes find exit non-zero; the
      ;; directories it printed are still used, and its errors are dropped.
      (process-file-shell-command command nil '(t nil))
      (dolist (dir (split-string (buffer-string) "\0" t))
        (unless (or (equal dir ".")
                    (member (file-name-nondirectory dir)
                            vc-directory-exclusion-list))
          (push (concat (string-remove-prefix "./" dir) "/") dirs))))
    (sort dirs #'string<)))

(defun project-config-find-dir ()
  "Start Dired in a directory inside the current project.
Replaces `project-find-dir'.  In a project without version control,
the candidates are read from the file system, so empty directories and
directories holding only subdirectories are offered too.  Directories
named in `vc-directory-exclusion-list' are skipped.  In a project under
version control, the candidates are the directories of `project-files',
as in `project-find-dir'."
  (interactive)
  (require 'xref)
  (let* ((project (project-current t))
         (root (project-root project))
         (completion-ignore-case read-file-name-completion-ignore-case)
         (all-dirs
          (cons "./"
                (if (and (eq (car project) 'vc) (cadr project))
                    (let ((project-files-relative-names t))
                      (delq nil (delete-dups
                                 (mapcar #'file-name-directory
                                         (project-files project)))))
                  (project-config--list-dirs
                   root (project-ignores project root)))))
         (default-directory root)
         (dir (project--read-file-name
               project "Dired" all-dirs nil 'file-name-history
               (project--find-default-from default-directory project))))
    (dired dir)))

(provide 'project-config)
;;; project-config.el ends here
