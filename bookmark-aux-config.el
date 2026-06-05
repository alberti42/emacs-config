;;; bookmark-aux-config.el --- Wire bookmark-aux-file to project.el -*- lexical-binding: t; -*-

;; Loads the project-agnostic `bookmark-aux-file' library (mechanism only) and
;; supplies the one piece of policy this setup wants: when a project's
;; .dir-locals.el sets `bookmark-aux-file' to a *relative* path, resolve it
;; against the project root rather than the visited file's directory, so every
;; buffer in the project shares one auxiliary bookmark file.

;;; Commentary:
;;
;; Per-project setup is otherwise automatic: the library declares
;; `bookmark-aux-file' a safe local variable, so .dir-locals.el sets it
;; buffer-locally with no extra wiring.  A project just needs, e.g.:
;;
;;   ;;; .dir-locals.el
;;   ((nil . ((bookmark-aux-file . "._aux/bookmarks.eld"))))
;;
;; and all of that project's bookmarks live in <project-root>/._aux/bookmarks.eld,
;; merged with the global ones (auxiliary entries first, so a bare-name lookup
;; resolves to them; both are shown -- nothing is hidden).
;; An absolute value is honored as-is; a buffer outside any project falls back
;; to `default-directory'.

;;; Code:

(require 'project)

(when (emacs-config-load-module
       "local/bookmark-aux-file"
       "Could not load bookmark-aux-file.el; auxiliary bookmark files are disabled.")

  (defun bookmark-aux-config--resolve (raw)
    "Resolve RAW to an absolute path for `bookmark-aux-file-resolver'.
Absolute values are returned expanded.  Relative values are resolved against
the current buffer's project root (via project.el), or `default-directory'
when the buffer is not in a project."
    (if (file-name-absolute-p raw)
        (expand-file-name raw)
      (let* ((proj (project-current nil))
             (root (and proj (project-root proj))))
        (expand-file-name raw (or root default-directory)))))

  (setq bookmark-aux-file-resolver #'bookmark-aux-config--resolve)
  (bookmark-aux-file-mode 1))

(provide 'bookmark-aux-config)
;;; bookmark-aux-config.el ends here
