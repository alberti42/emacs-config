;;; syntaxes/agent-shell.el --- agent-shell-mode display settings -*- lexical-binding: t; -*-

(defvar emacs-config-syntaxes-enable-agent-shell t
  "Whether to enable agent-shell settings from syntaxes/agent-shell.el.")

(when emacs-config-syntaxes-enable-agent-shell
  (add-hook 'agent-shell-mode-hook
            (lambda ()
              (display-line-numbers-mode -1))))

(provide 'syntaxes-agent-shell)

;;; syntaxes/agent-shell.el ends here
