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

(provide 'project-config)
;;; project-config.el ends here
