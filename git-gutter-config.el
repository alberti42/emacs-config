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
             ;; :local-repo "/Users/andrea/Documents/Programming/Others/git-gutter"
             :branch "fix/visual-line"
             :files ("git-gutter.el"))
  ;; git-gutter does not define `git-gutter-mode-map' (its `define-minor-mode'
  ;; form has no :keymap argument), so we bind globally.  The commands are
  ;; well-namespaced and no-op when there are no hunks.
  :bind (("C-c v p" . git-gutter:popup-hunk)
         ("C-c v n" . git-gutter:next-hunk)
         ("C-c v N" . git-gutter:previous-hunk)
         ("C-c v s" . git-gutter:stage-hunk)
         ("C-c v r" . git-gutter:revert-hunk))
  ;; `:bind' implies `:defer t', which would delay `global-git-gutter-mode'
  ;; until the first `C-c v ...' call.  Force eager load so the gutter shows
  ;; up immediately in all buffers.
  :demand t
  :config
  ;; Live-ish updates (idle timer).
  (setq git-gutter:update-interval 0)

  ;; One glyph, colored by face.  Appearance is handled by theme-harmonize.
  (setq git-gutter:modified-sign "▐")
  (setq git-gutter:added-sign "▐")
  (setq git-gutter:deleted-sign "▐")
  (setq git-gutter:visual-line t)

  ;; Use exactly 1 column for git-gutter indicators.
  (setq git-gutter:window-width 1)
  ;; Separator sign following the change sign; it is appended, but will be
  ;; clipped unless window-width >= 2; thus it is effectively only displayed if
  ;; we reserved a larger window-width than 1; it can be used to separate the
  ;; change signs from the rest.
  (setq git-gutter:separator-sign nil)
  ;; Determines whether to show the separator-sign and the unchanged-sign for
  ;; buffers with no modifications yet (no 'diffinfos).
  (setq git-gutter:always-show-separator nil)
  (setq git-gutter:unchanged-sign nil)
  
  (global-git-gutter-mode 1)

  ;; Show the hunk popup in a right-side window that persists across
  ;; `git-gutter:next-hunk' / `git-gutter:previous-hunk' calls (which
  ;; auto-refresh the popup buffer when it is alive).
  (add-to-list 'display-buffer-alist
               '("\\*git-gutter:diff\\*"
                 (display-buffer-in-side-window)
                 (side . right)
                 (window-width . 0.4)))

  ;; Keep gutter in sync after Magit refreshes.
  (with-eval-after-load 'magit
    (add-hook 'magit-post-refresh-hook #'git-gutter:update-all-windows)))


(provide 'git-gutter-config)

;;; git-gutter-config.el ends here
