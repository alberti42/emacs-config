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
              ("C-c a" . agent-shell-prompt-compose)))

(provide 'agent-shell-config)
;;; agent-shell-config.el ends here
