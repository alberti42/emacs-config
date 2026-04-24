;;; buffers-config.el --- Buffer list (ibuffer) configuration -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; Replaces `list-buffers' with `ibuffer': a dired-like buffer list with
;; marking, filtering (`/'), sorting (`s'), and grouping.  Buffers are grouped
;; by `project.el' root via `ibuffer-project', and decorated with nerd-icons.
;;

;;; Code:

(use-package ibuffer
  :straight nil
  :bind ([remap list-buffers] . ibuffer)
  :custom
  (ibuffer-expert t)
  (ibuffer-show-empty-filter-groups nil)
  (ibuffer-default-sorting-mode 'recency))

;; Group buffers by project.el root.  `ibuffer-hook' (not `ibuffer-mode-hook')
;; fires on every invocation so the groups refresh as projects come and go.
(use-package ibuffer-project
  :after ibuffer
  :custom
  (ibuffer-project-use-cache t)
  :hook (ibuffer . buffers-config--apply-project-groups)
  :preface
  (defun buffers-config--apply-project-groups ()
    (setq ibuffer-filter-groups (ibuffer-project-generate-filter-groups))
    (unless (eq ibuffer-sorting-mode 'project-file-relative)
      (ibuffer-do-sort-by-project-file-relative))))

;; Nerd-font icons in the ibuffer columns (same icon font as dired/treemacs).
(use-package nerd-icons-ibuffer
  :after (ibuffer nerd-icons)
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

(provide 'buffers-config)
;;; buffers-config.el ends here
