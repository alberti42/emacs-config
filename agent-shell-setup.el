;;; agent-shell-setup.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

;; agent-shell: interact with AI agents (Claude Code, Gemini CLI, etc.)
;; via the Agent Client Protocol (ACP) inside an Emacs shell buffer.
;; Requires shell-maker and acp as dependencies.

(use-package agent-shell
  ;; :straight (agent-shell
  ;;            :type git
  ;;            ;;:host github
  ;;            :local-repo "~/Documents/Programming/Others/fork-agent-shell"
  ;;            ;; :branch "fork/angle-bracket-link-destinations"
  ;;            ;; :branch "fork/angle-bracket-link-destinations"
  ;;            :branch "merged"
  ;;            ;; :branch "main"
  ;;            :repo "xenodium/agent-shell")
  :custom
  (agent-shell-show-context-usage-indicator 'detailed)
  (agent-shell-session-restore-verbosity 'full)
  ;; (agent-shell-anthropic-default-model-id "claude-opus-4-6")
  (agent-shell-opencode-default-model-id "openai/gpt-5.5")
  (agent-shell-opencode-acp-command '("opencode" "acp"))
  (agent-shell-preferred-agent-config '(preselect . pi))
  :bind (:map agent-shell-mode-map
              ("M-RET" . newline)
              ("C-c e" . agent-shell-prompt-compose))
  :config
  ;; Use the project root as the agent's working directory (monorepo
  ;; subprojects are pinned via `project-vc-extra-root-markers', so project.el
  ;; already resolves a marked subdirectory to its own root).  With a
  ;; project-root cwd shared by every buffer in the project, stock session
  ;; reuse (which matches on `equal' of `agent-shell-cwd') already groups them,
  ;; so no `agent-shell-project-buffers' override is needed.
  ;;
  ;; The custom bits both exist to match the exact cwd string `pi-acp' filters
  ;; on.  Pi runs via Node `process.cwd()', which resolves symlinks, so it
  ;; records sessions under the *physical* path; `file-truename' canonicalizes
  ;; here so a symlinked `default-directory' (e.g. through ~/.config/dotfiles)
  ;; still matches.  `directory-file-name' strips the trailing slash Pi omits.
  ;; Once pi-acp normalizes its cwd match, this whole function can be dropped
  ;; and `agent-shell-cwd-function' left nil.
  (defun my/agent-shell-cwd-function ()
    "Return the project root (else `default-directory') canonicalized.

Resolves symlinks and drops the trailing slash so the path matches what
Pi records for its sessions."
    (directory-file-name
     (file-truename
      (if-let* ((proj (project-current)))
          (project-root proj)
        default-directory))))
  (setq agent-shell-cwd-function #'my/agent-shell-cwd-function)

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
