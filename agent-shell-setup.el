;;; agent-shell-setup.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

;; agent-shell: interact with AI agents (Claude Code, Gemini CLI, etc.)
;; via the Agent Client Protocol (ACP) inside an Emacs shell buffer.
;; Requires shell-maker and acp as dependencies.

(use-package agent-shell
  ;; :straight (agent-shell
  ;;            :type git
  ;;            :local-repo "~/Programming/Others/fork-agent-shell")
  :custom
  (agent-shell-show-context-usage-indicator 'detailed)
  (agent-shell-session-restore-verbosity 'full)
  (agent-shell-agent-shell-openai-default-model-id "openai-codex/gpt-5.6-sol")
  (agent-shell-anthropic-default-model-id "anthropic/claude-opus-5-5")
  (agent-shell-opencode-default-model-id "openai/gpt-5.5")
  (agent-shell-opencode-acp-command '("opencode" "acp"))
  (agent-shell-preferred-agent-config '(preselect . pi))
  ;; Open a shell with an empty prompt, not one holding the line at point.
  (agent-shell-context-sources nil)
  :bind ((:map agent-shell-mode-map
               ("M-RET" . newline)
               ("C-c e" . agent-shell-prompt-compose))
         (:map project-prefix-map
               ("a" . agent-shell)))
  :init
  ;; Add `agent-shell' to the menu of `project-switch-project' (C-x p p); the
  ;; menu takes its key from the binding in `project-prefix-map'.  In :init,
  ;; not :config: :config runs only once agent-shell is loaded.
  (with-eval-after-load 'project
    (add-to-list 'project-switch-commands '(agent-shell "Agent shell") t))
  :config
  ;; Start agents in the project root, else in `default-directory', as stock
  ;; agent-shell does, but with symlinks resolved: Pi records its sessions
  ;; under the resolved path.
  (defun my/agent-shell-cwd-function ()
    "Return the project root (else `default-directory') canonicalized.

Resolves symlinks so the path matches what Pi records for its sessions."
    (file-name-as-directory
     (file-truename
      (if-let* ((proj (project-current)))
          (project-root proj)
        default-directory))))
  (setq agent-shell-cwd-function #'my/agent-shell-cwd-function)
  ;; Send directories without the trailing slash Emacs adds, as `pwd' would
  ;; write them; Pi needs no trailing slash because it finds a project's
  ;; sessions by comparing this string.
  (setq agent-shell-path-resolver-function #'directory-file-name)

  ;; Run pi-acp from upstream main, built in a local checkout, which includes
  ;; the fix in PR #126.  The released version 0.0.34 does not include the fix
  ;; yet. When a new release is available, update with `npm update -g pi-acp'
  ;; and remove this custom command.
  (setq agent-shell-pi-acp-command
        (list "node"
              (expand-file-name
               "~/Programming/Others/fork-pi-acp/dist/index.js")))

  ;; Reflect the ACP session title in the shell buffer name, e.g.  "Pi Agent @
  ;; <session title>" instead of "Pi Agent @ <project>".  agent-shell already
  ;; stores the title (from the ACP `session_info_update') into session state
  ;; and emits `session-title-changed'; we subscribe to it per shell and rename
  ;; the buffer to <prefix><title>.  Until the agent sets an explicit name,
  ;; agent-shell seeds the title from the first user prompt, so the buffer name
  ;; tracks that first, then updates when the tool fires.
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

;; The `latex-to-svg-backend' rendering engine (this renderer's dependency) is
;; registered and configured centrally in `latex-to-svg-config.el', which
;; init.el loads first.  Here we only turn the front-end on.
(use-package agent-shell-math-renderer
  :straight (agent-shell-math-renderer
             :type git
             ;; Development happens on `develop'; `main' is fast-forwarded
             ;; to it at each release.
             :branch "develop"
             :local-repo "~/Programming/Emacs/agent-shell-math-renderer")
  :after agent-shell
  ;; Rendering is driven by the buffer-local `agent-shell-math-renderer-mode',
  ;; which must be turned on from `agent-shell-mode-hook'.
  :hook (agent-shell-mode . agent-shell-math-renderer-mode)
  :config
  ;; Re-tint and rescale cached equations on a theme switch or a frame font
  ;; change; the mode itself only tracks redisplay and buffer-local zoom.
  (add-hook 'enable-theme-functions
            #'agent-shell-math-renderer-on-appearance-change)
  (add-hook 'after-setting-font-hook
            #'agent-shell-math-renderer-on-appearance-change)
  (setq agent-shell-math-renderer-render-submitted-prompts t)
  ;; Size multipliers on top of the engine's global `latex-to-svg-backend-font-scale':
  ;; display equations a bit larger than inline.
  (setq agent-shell-math-renderer-inline-rescale 1.0)
  (setq agent-shell-math-renderer-display-rescale 1.0)
  (setq agent-shell-math-renderer-padding-display '(10 0 10 0))
  ;; Select the default engine
  (setq agent-shell-math-renderer-engine 'texres))

(provide 'agent-shell-setup)
;;; agent-shell-setup.el ends here
