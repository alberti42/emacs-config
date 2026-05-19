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
  ;; project root.  Trust the agent-shell buffer's own `default-directory' for
  ;; in-session calls too — otherwise the package would re-resolve via
  ;; project.el on every ACP message and walk back up to the git root.  Other
  ;; launch contexts (file buffers, etc.) fall through to the package's default
  ;; projectile/project.el resolution by returning nil.
  (defun my/agent-shell-cwd-function ()
    "Return dired/agent-shell buffer's `default-directory', else nil."
    (when (derived-mode-p 'dired-mode 'agent-shell-mode)
      (expand-file-name default-directory)))
  (setq agent-shell-cwd-function #'my/agent-shell-cwd-function)

  ;; The package's `agent-shell-project-buffers' matches shells to the current
  ;; project via strict `equal' on `agent-shell-cwd', which conflates "agent's
  ;; working directory" with "project identity".  With the dired anchoring
  ;; above, a shell anchored at /proj/sub/ no longer matches a code buffer in
  ;; /proj/, so DWIM falls through to "Start new agent:" instead of reusing the
  ;; existing shell.  Loosen the predicate: a shell counts as belonging to the
  ;; current project if its cwd lives anywhere within the project root.
  (defun my/agent-shell-project-buffers (&rest _)
    "Match shells whose cwd is anywhere within the current project root."
    (let ((project-root (agent-shell-cwd)))
      (seq-filter (lambda (buffer)
                    (let ((shell-cwd (with-current-buffer buffer
                                       (agent-shell-cwd))))
                      (or (equal project-root shell-cwd)
                          (file-in-directory-p shell-cwd project-root))))
                  (agent-shell-buffers))))
  (advice-add 'agent-shell-project-buffers :override
              #'my/agent-shell-project-buffers)

  ;; History navigation: preserve the full in-progress prompt.  shell-maker sets
  ;; `comint-get-old-input' to a function that grabs a single `forward-sexp', so
  ;; multi-word/multi-line prompts are truncated when comint stashes them on the
  ;; first C-up.  Override to capture the entire input region; comint's built-in
  ;; `comint-restore-input' then brings the full text back when C-down
  ;; overshoots the newest history entry.
  (defun my/agent-shell-get-old-input ()
    "Return the entire pending input from process-mark to point-max."
    (when-let ((proc (get-buffer-process (current-buffer))))
      (buffer-substring-no-properties (process-mark proc) (point-max))))
  (add-hook 'agent-shell-mode-hook
            (lambda ()
              (setq-local comint-get-old-input
                          #'my/agent-shell-get-old-input))))

(provide 'agent-shell-config)
;;; agent-shell-config.el ends here
