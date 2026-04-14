;;; syntaxes/magit.el --- Magit display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-magit t
  "Whether to enable Magit settings from syntaxes/magit.el.")

(when emacs-config-syntaxes-enable-magit
  ;; Magit status, diff, log, etc.
  (add-hook 'magit-mode-hook
            (lambda ()
              ;; Enable visual-line-mode in all magit buffers by default.
              (visual-line-mode 1)
              ;; Disable line numbers in magit buffers.
              (display-line-numbers-mode -1)))

  ;; Git commit editing.
  ;; (add-hook 'git-commit-mode-hook
  ;;           (lambda ()
  ;;             ;; hide line-numbers in editing buffers
  ;;             (display-line-numbers-mode -1)
  ;;             ;; which-key intercepts key sequences to display its popup, and in
  ;;             ;; the commit buffer there seems to be a conflict with how certain
  ;;             ;; prefix keys (like C-x) are handled — likely an interaction with
  ;;             ;; git-commit-mode's keymap overrides. The exact bug depends on
  ;;             ;; which-key's timer firing mid-sequence.
  ;;             (setq-local which-key-inhibit t)))

  ;; Git rebase editing.
  ;; (add-hook 'git-rebase-mode-hook
  ;;           (lambda ()
  ;;             (display-line-numbers-mode -1)))
)

  (provide 'syntaxes-magit)
;;; syntaxes/magit.el ends here
