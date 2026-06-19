;;; straight-overview-config.el --- Configuration for straight-overview -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Wires the locally-developed `straight-overview' package into the
;; configuration.  `straight-overview' is a read-only overview and
;; dired-style selective-upgrade UI for straight.el-managed packages:
;; `M-x straight-overview' lists which packages are behind upstream and lets
;; you pull (and optionally rebuild) only the ones you mark.
;;
;; The package lives in its own repository; straight is pointed at the local
;; checkout for development (the canonical straight local-development recipe).
;;

;;; Code:

(use-package straight-overview
  :straight (straight-overview
             :type git
             :host github
             :local-repo "/Users/andrea/Documents/Programming/Emacs/straight-overview"
             :repo "alberti42/straight-overview")
  :commands (straight-overview)
  :init
  (let* ((cache-home (or (getenv "XDG_CACHE_HOME")
                         (expand-file-name "~/.cache")))
         (dir (expand-file-name "emacs" cache-home)))
    (make-directory dir t)
    (setq straight-overview-pinned-file (expand-file-name "straight-overview.eld" dir)))
  :custom
  ;; Rebuild pulled/restored packages immediately, so updates take effect in
  ;; the running session rather than on the next restart.
  (straight-overview-build-on-pull t))

(provide 'straight-overview-config)
;;; straight-overview-config.el ends here
