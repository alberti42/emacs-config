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
  ;;            :branch "protect-frozen-regions-in-emphasis"
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
              #'my/agent-shell--dwim-without-context)

  ;; Run our forked pi-acp instead of the npm-global one.  The fork adds a
  ;; `session_info_changed' -> ACP `session_info_update' bridge: when the
  ;; agent renames its own session (the `set_session_name' extension tool
  ;; calling `pi.setSessionName'), pi emits `session_info_changed' on its RPC
  ;; event stream, which upstream pi-acp drops.  The fork forwards it as a
  ;; `session_info_update' carrying the new title, so agent-shell can react.
  ;; Invoked via `node <dist>' (rather than the `pi-acp' bin on PATH) so the
  ;; switch is explicit, self-contained, and trivially reversible; the fork's
  ;; bundle externalizes `@agentclientprotocol/sdk', resolved from the fork's
  ;; own node_modules.  Rebuild after editing the fork: `npm run build'.
  (setq agent-shell-pi-acp-command
        (list "node"
              (expand-file-name
               "~/Documents/Programming/Others/fork-pi-acp/dist/index.js")))

  ;; Reflect the ACP session title in the shell buffer name, e.g.
  ;; "Pi Agent @ <session title>" instead of "Pi Agent @ <project>".
  ;; agent-shell already stores the title (from the ACP `session_info_update')
  ;; into session state and emits `session-title-changed'; we subscribe to it
  ;; per shell and rename the buffer to <prefix><title>.  Until the agent sets
  ;; an explicit name, agent-shell seeds the title from the first user prompt,
  ;; so the buffer name tracks that first, then updates when the tool fires.
  (defun my/agent-shell-sync-buffer-name (event)
    "Rename the shell buffer to \"<Agent> Agent @ <session title>\".
EVENT is the `session-title-changed' payload; its `(:data :title)' holds
the new title.  Runs with the shell buffer current (see
`agent-shell--emit-event'), so `agent-shell--state' is in scope."
    (when-let* ((title (map-nested-elt event '(:data :title)))
                (agent (map-nested-elt agent-shell--state
                                       '(:agent-config :buffer-name)))
                (prefix (agent-shell--buffer-name-prefix agent)))
      (shell-maker-set-buffer-name (current-buffer) (concat prefix title))))

  (add-hook 'agent-shell-mode-hook
            (lambda ()
              (agent-shell-subscribe-to
               :shell-buffer (current-buffer)
               :event 'session-title-changed
               :on-event #'my/agent-shell-sync-buffer-name))))

;; The `latex-to-svg' rendering engine (this renderer's dependency) is
;; registered and configured centrally in `latex-to-svg-config.el', which
;; init.el loads first.  Here we only turn the front-end on.
(use-package agent-shell-math-renderer
  :straight (agent-shell-math-renderer
             :type git
             ;; The latex-to-svg delegation lives on this branch, not `main'
             ;; (which stays the self-contained pre-refactor version until the
             ;; library is fully published/tested).  Track the branch here.
             :branch "refactor/latex-to-svg"
             :local-repo "/Users/andrea/Documents/Programming/Emacs/agent-shell-math-renderer")
  :after agent-shell
  :config
  (setq agent-shell-math-renderer-enabled t)
  (setq agent-shell-math-renderer-render-submitted-prompts t))

(provide 'agent-shell-setup)
;;; agent-shell-setup.el ends here
