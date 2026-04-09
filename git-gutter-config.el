;;; git-gutter-config.el --- Git gutter in Emacs -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; This module enables a "source control gutter" for terminal Emacs.
;;
;; Notes on UI constraints:
;; - In GUI Emacs, packages can draw indicators in the fringe (a bitmap area
;;   outside the text). Terminal frames have no fringe; indicators must be
;;   rendered as ordinary characters.
;; - The goal here is a clean, low-noise Git gutter: one thin glyph, colored by
;;   face, with stable layout (reserve the column in Git buffers).
;;
;; `git-gutter` is used instead of fringe-only variants like git-gutter-fringe.

;;; Code:

(use-package git-gutter
  :straight (git-gutter
             :host github
             :repo "alberti42/fork-git-gutter"
             :branch "fix/git-gutter-faces"
             :files ("git-gutter.el"))
  :config
  ;; Live-ish updates (idle timer).
  (setq git-gutter:update-interval 0.5)

  ;; One glyph, colored by face.  Appearance is handled by theme-harmonize.
  (setq git-gutter:modified-sign "▐")
  (setq git-gutter:added-sign "▐")
  (setq git-gutter:deleted-sign "▐")
  (setq git-gutter:visual-line t)

  ;; Keep the gutter column reserved in all buffers to avoid text shifting by
  ;; setting a fixed width of 1.
  (setq git-gutter:window-width 1)
  ;; Separator sign following the change sign; it is appended, but will be
  ;; clipped unless window-width >= 2; thus it is effectively only displayed if we reserved a larger window-width than 1; it can be used to separate the
  ;; change signs from the rest.
  (setq git-gutter:separator-sign "")
  ;; Determines whether to show the separator-sign and the unchanged-sign for
  ;; buffers with no modifications yet (no 'diffinfos).
  (setq git-gutter:always-show-separator nil)
  (setq git-gutter:unchanged-sign "")

  ;; Disable git-gutter for large files
  (advice-add 'git-gutter-mode :before-while
              (lambda (&rest _)
                (or (not (buffer-file-name))
                    (<= (buffer-size) 250000)))) ; disable for larger than 250 KB
  
  (global-git-gutter-mode 1)

  ;; Keep gutter in sync after Magit refreshes.
  (with-eval-after-load 'magit
    (add-hook 'magit-post-refresh-hook #'git-gutter:update-all-windows)))


(provide 'git-gutter-config)

;;; git-gutter-config.el ends here
