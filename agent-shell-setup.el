;;; agent-shell-setup.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

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
  ;; Hand OpenCode the launching buffer's `default-directory' as its working
  ;; directory, rather than letting the package walk up to the project root.
  ;; No dired special-casing: dired buffers behave like any other buffer, so
  ;; agent-shell's stock file-picking workflow works there.  This also covers
  ;; in-session calls (the agent-shell buffer's own `default-directory'), so the
  ;; package doesn't re-resolve via project.el on every ACP message.
  (defun my/agent-shell-cwd-function ()
    "Return the current buffer's `default-directory'."
    (expand-file-name default-directory))
  (setq agent-shell-cwd-function #'my/agent-shell-cwd-function)

  ;; Session reuse: `agent-shell-project-buffers' decides which existing shells
  ;; belong to "the current project".  Stock matches on strict `equal' of
  ;; `agent-shell-cwd' — but since we now feed `agent-shell-cwd' the buffer's
  ;; `default-directory', a code/dired buffer in /proj/sub/ would never match a
  ;; shell started at /proj/, so DWIM falls through to "Start new agent:".
  ;; Match on the real project root instead (project.el), decoupled from cwd, so
  ;; any buffer within a project reuses that project's shell regardless of which
  ;; subdirectory it sits in.
  (defun my/agent-shell--project-root ()
    "Return the current buffer's project root, else its `default-directory'."
    (expand-file-name
     (if-let* ((proj (project-current)))
         (project-root proj)
       default-directory)))
  (defun my/agent-shell-project-buffers (&rest _)
    "Match agent shells in the same project as the current buffer."
    (let ((root (my/agent-shell--project-root)))
      (seq-filter (lambda (buffer)
                    (equal root (with-current-buffer buffer
                                  (my/agent-shell--project-root))))
                  (agent-shell-buffers))))
  (advice-add 'agent-shell-project-buffers :override
              #'my/agent-shell-project-buffers))

(provide 'agent-shell-setup)
;;; agent-shell-setup.el ends here
