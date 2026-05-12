;;; agent-shell-config.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

;; agent-shell: interact with AI agents (Claude Code, Gemini CLI, etc.)
;; via the Agent Client Protocol (ACP) inside an Emacs shell buffer.
;; Requires shell-maker and acp as dependencies.

(use-package agent-shell
  :straight t
  :custom
  (agent-shell-show-context-usage-indicator 'detailed)
  (agent-shell-opencode-default-model-id "openai/gpt-5.4")
  (agent-shell-opencode-acp-command
   ;; The --attach option relies on a custom modification
   ;; in the branch acp-attach of opencode personal fork:
   ;; https://github.com/alberti42/fork-opencode
   '("opencode" "acp" "--attach" "http://localhost:4096"))
  :bind (:map agent-shell-mode-map
              ("M-RET" . newline)
              ("C-c a" . agent-shell-prompt-compose))
  :config
  ;; When agent-shell is launched from a dired buffer, anchor the agent at that
  ;; buffer's listed directory instead of letting the package walk up to the
  ;; project root.  Other launch contexts (file buffers, etc.) keep the
  ;; package's default projectile/project.el resolution.
  (defun my/agent-shell-cwd-dired-advice (orig-fn &rest args)
    "Around-advice for `agent-shell-cwd': use dired's dir when applicable.
Also trust the agent-shell buffer's own `default-directory' for
in-session calls — otherwise the package would re-resolve via project.el
on every ACP message and walk back up to the git root."
    (if (derived-mode-p 'dired-mode 'agent-shell-mode)
        (expand-file-name default-directory)
      (apply orig-fn args)))
  (advice-add 'agent-shell-cwd :around #'my/agent-shell-cwd-dired-advice))

(provide 'agent-shell-config)
;;; agent-shell-config.el ends here
