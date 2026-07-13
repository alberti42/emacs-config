;;; agent-shell-setup.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

;; agent-shell: interact with AI agents (Claude Code, Gemini CLI, etc.)
;; via the Agent Client Protocol (ACP) inside an Emacs shell buffer.
;; Requires shell-maker and acp as dependencies.

(use-package agent-shell
  :straight (agent-shell
             :type git
             ;;:host github
             :local-repo "~/Documents/Programming/Others/fork-agent-shell"
             ;; :branch "fork/angle-bracket-link-destinations"
             ;; :branch "fork/angle-bracket-link-destinations"
             :branch "merged"
             ;; :branch "main"
             :repo "xenodium/agent-shell")
  :custom
  (agent-shell-show-context-usage-indicator 'detailed)
  (agent-shell-session-restore-verbosity 'full)
  ;; (agent-shell-anthropic-default-model-id "claude-opus-4-6")
  (agent-shell-opencode-default-model-id "openai/gpt-5.5")
  (agent-shell-opencode-acp-command '("opencode" "acp"))
  :bind (:map agent-shell-mode-map
              ("M-RET" . newline)
              ("C-c e" . agent-shell-prompt-compose))
  :config
  ;; Hand the coding agent the launching buffer's `default-directory' as its
  ;; working directory, rather than letting the package walk up to the project
  ;; root.  This also covers in-session calls (the agent-shell buffer's own
  ;; `default-directory'), so the package doesn't re-resolve via project.el on
  ;; every ACP message.
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
              #'my/agent-shell-project-buffers)

  ;; Don't let the `agent-shell' launcher paste the active region/context into
  ;; a new shell's first prompt -- opening a shell should just open it.  The
  ;; launcher routes context through `agent-shell--dwim', so bind the sources
  ;; to nil for that function's dynamic extent.  `agent-shell-send-dwim' (and
  ;; the other `agent-shell-send-*' commands) gather context *outside* that
  ;; extent, so they keep the full `agent-shell-context-sources' behavior.
  (defun my/agent-shell--dwim-without-context (orig-fn &rest args)
    "Run ORIG-FN (`agent-shell--dwim') without carrying automatic context."
    (let ((agent-shell-context-sources nil))
      (apply orig-fn args)))
  (advice-add 'agent-shell--dwim :around
              #'my/agent-shell--dwim-without-context))

(use-package agent-shell-math-renderer
  :straight (agent-shell-math-renderer
             :type git
             :branch "main"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/agent-shell-math-renderer")
  :after agent-shell
  :config
  (setq agent-shell-math-renderer-enabled t)
  (setq agent-shell-math-renderer-render-submitted-prompts t)
  (setq agent-shell-math-renderer-render-on-non-graphic t)
  (setq agent-shell-math-renderer-font-scale 1.0)
  (setq agent-shell-math-renderer-appended-preamble
        "\\usepackage{physics}
\\usepackage[only,llbracket,rrbracket]{stmaryrd}
\\usepackage{siunitx}
\\usepackage{mathtools}
\\sisetup{
detect-weight=true,
exponent-product={\\times},
output-decimal-marker={.},
print-unity-mantissa=false,
}"))

(provide 'agent-shell-setup)
;;; agent-shell-setup.el ends here
