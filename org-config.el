;;; org-config.el --- Org mode with LaTeX preview and Python babel -*- lexical-binding: t; -*-

;; Install Org from tecosaur's fork to get karthink's org-latex-preview
;; (auto-preview, live updates, dvisvgm SVG rendering).  The feature has not
;; yet been merged into mainline Org.  This recipe must appear before any
;; package that depends on Org.
(use-package org
  :straight `(org
              :fork (:host nil
                     :repo "https://git.tecosaur.net/tec/org-mode.git"
                     :branch "dev"
                     :remote "tecosaur")
              :files (:defaults "etc")
              :build t
              :pre-build
              (with-temp-file "org-version.el"
                (require 'lisp-mnt)
                (let ((version
                       (with-temp-buffer
                         (insert-file-contents "lisp/org.el")
                         (lm-header "version")))
                      (git-version
                       (string-trim
                        (with-temp-buffer
                          (call-process "git" nil t nil
                                        "rev-parse" "--short" "HEAD")
                          (buffer-string)))))
                  (insert
                   (format "(defun org-release () \"The release version of Org.\" %S)\n" version)
                   (format "(defun org-git-version () \"The truncate git commit hash of Org mode.\" %S)\n" git-version)
                   "(provide 'org-version)\n")))
              :pin nil)
  :defer t
  :hook
  (org-mode . org-latex-preview-mode)
  :config
  ;; Live preview: re-render fragments as you type.
  (setq org-latex-preview-live t)

  ;; Show inline images after evaluating babel blocks.
  (add-hook 'org-babel-after-execute-hook #'org-display-inline-images)

  ;; Python babel support.
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python . t)))

  ;; Don't ask for confirmation on every C-c C-c in trusted files.
  ;; Set to a function if you want selective confirmation.
  (setq org-confirm-babel-evaluate nil)

  ;; Default header args for Python: produce graphics files for matplotlib.
  (setq org-babel-default-header-args:python
        '((:results . "output file graphics")
          (:exports . "both"))))

(provide 'org-config)
;;; org-config.el ends here
