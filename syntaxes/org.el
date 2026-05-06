;;; syntaxes/org.el --- org-mode syntax settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-org t
  "Whether to enable org-mode settings from syntaxes/org.el.")

(when emacs-config-syntaxes-enable-org
  (add-hook 'org-mode-hook
            (lambda ()
              (setq-local fill-column 100)
              (soft-wrap-mode 1)

              ;; Prose word-completion: merged dabbrev + in-memory
              ;; dictionary super-CAPF (defined in completions/cape.el).
              ;; Surfaces buffer-recent words alongside dictionary words
              ;; in one popup, both gated to ≥3 chars.
              (add-hook 'completion-at-point-functions
                        #'emacs-config-cape-prose nil t))))

(provide 'syntaxes-org)
;;; syntaxes/org.el ends here
