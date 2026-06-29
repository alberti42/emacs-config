;;; agent-shell-setup.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

;; agent-shell: interact with AI agents (Claude Code, Gemini CLI, etc.)
;; via the Agent Client Protocol (ACP) inside an Emacs shell buffer.
;; Requires shell-maker and acp as dependencies.

(use-package agent-shell
  ;; Tell straight to use your local folder instead of downloading from GitHub.
  ;; This is the "canonical" way to do local development with straight.
  :straight (agent-shell
             :type git
             :host github
             :local-repo "/Users/andrea/Documents/Programming/Others/fork-agent-shell"
             :branch "display-math"
             :repo "alberti42/fork-agent-shell")
  :custom
  (agent-shell-show-context-usage-indicator 'detailed)
  ;; (agent-shell-anthropic-default-model-id "claude-opus-4-6")
  (agent-shell-opencode-default-model-id "openai/gpt-5.5")
  (agent-shell-opencode-acp-command
   ;; The --attach option relies on a custom modification
   ;; in the branch acp-attach of opencode personal fork:
   ;; https://github.com/alberti42/fork-opencode
   ;; '("opencode" "acp" "--attach" "http://localhost:4096"))
   '("opencode" "acp"))
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
              #'my/agent-shell-project-buffers)

  ;; Region/line context formatting: replace agent-shell's `path:start-end' +
  ;; "   N: line" preview with our fenced, lang-tagged, `cat -n'-style snippet
  ;; from `my/agent-snippet-format' (utils.el).  `agent-shell--get-region-context'
  ;; is the single chokepoint feeding both the `region' and `line' context
  ;; sources (`agent-shell-send-region', `agent-shell-send-dwim', ...); it runs
  ;; in the source buffer with the region active.  Paths are made relative to the
  ;; agent's cwd (its keyword arg), matching how the agent sees them.
  ;;
  ;; We keep agent-shell's nice >N-line cap + Expand button: the visible preview
  ;; shows the first `my/agent-shell-region-preview-cap' lines plus a button,
  ;; carrying the `agent-shell-region-id'/`agent-shell-region-text' properties so
  ;; both the button and `agent-shell--expand-truncated-regions' (on send) swap
  ;; in the full body.  The fence sits outside the truncated span, so expansion
  ;; yields a well-formed block.  The button machinery is reused via `fboundp'
  ;; guards, degrading to the full snippet if those internals ever change.  (We
  ;; do drop the clickable jump-to-region file link.)
  (defvar my/agent-shell-region-preview-cap 5
    "Lines shown before a region context preview is truncated with an Expand button.")
  (defun my/agent-shell--region-context (&rest args)
    "Format region/line context via `my/agent-snippet-format'.
Override for `agent-shell--get-region-context'; honors its DEACTIVATE,
NO-ERROR and AGENT-CWD keyword arguments (received in ARGS)."
    (let ((deactivate (plist-get args :deactivate))
          (no-error   (plist-get args :no-error))
          (agent-cwd  (plist-get args :agent-cwd))
          (cap        my/agent-shell-region-preview-cap))
      (if-let* ((region (agent-shell--get-region :deactivate deactivate)))
          (let* ((snip  (my/agent-snippet-format
                         (alist-get :char-start region)
                         (alist-get :char-end region)
                         (my/agent-snippet--path agent-cwd)))
                 (lines (plist-get snip :body-lines)))
            (if (or (<= (length lines) cap)
                    (not (and (fboundp 'agent-shell--make-button)
                              (fboundp 'agent-shell--add-text-properties))))
                (plist-get snip :text)
              ;; Truncated preview: first CAP lines + Expand button, with the
              ;; full body stashed on the region-id/region-text properties.
              (let* ((id        (gensym "agent-shell-region-"))
                     (full-body (plist-get snip :body))
                     (button
                      (agent-shell--make-button
                       :text "Expand..."
                       :help "RET to expand"
                       :action
                       (lambda ()
                         (interactive)
                         (save-excursion
                           (goto-char (point-min))
                           (when-let* ((m (text-property-search-forward
                                           'agent-shell-region-id id t))
                                       (inhibit-read-only t))
                             (delete-region (prop-match-beginning m)
                                            (prop-match-end m))
                             (goto-char (prop-match-beginning m))
                             (insert full-body))))))
                     (preview
                      (agent-shell--add-text-properties
                       (concat (string-join (seq-take lines cap) "\n")
                               "\n\n" button)
                       'agent-shell-region-id id
                       'agent-shell-region-text full-body)))
                (concat (plist-get snip :header) "\n"
                        preview "\n"
                        (plist-get snip :fence)))))
        (unless no-error (user-error "No region selected")))))
  (advice-add 'agent-shell--get-region-context :override
              #'my/agent-shell--region-context)

  ;; Render LaTeX display-math equations in agent responses as images
  ;; (compiled via latex + dvisvgm).  `agent-shell-markdown-render-math'
  ;; is the master switch and defaults to nil, so enable it here.  Once
  ;; on, block-level `\[...\]', `$$...$$', and ```math / ```latex fences
  ;; all render by default.  To drop `$$' (e.g. if it collides with
  ;; prose), set `agent-shell-markdown-math-delimiters' to '(bracket).
  ;; The `boundp' guard keeps this a no-op on an agent-shell build that
  ;; predates the feature, and avoids a free-variable warning.
  (when (boundp 'agent-shell-markdown-render-math)
    (setq agent-shell-markdown-render-math t))
  ;; Daemon: a chat may be rendered while a TTY (emacsclient -t) frame is
  ;; selected, but viewed later in a GUI frame.  Compile the SVGs anyway
  ;; (ignored on the terminal, shown once a graphical frame opens the
  ;; buffer) so equations aren't permanently lost to whichever frame
  ;; happened to be current at render time.
  (when (boundp 'agent-shell-markdown-math-render-on-non-graphic)
    (setq agent-shell-markdown-math-render-on-non-graphic t))
  ;; Equation size relative to the buffer font: 1.0 matches the surrounding
  ;; text, >1 enlarges, <1 shrinks.  Equations auto-track the font size, so
  ;; tune this only if they look a touch big or small (after changing it,
  ;; `M-x agent-shell-markdown-math-refresh' re-sizes existing equations).
  (when (boundp 'agent-shell-markdown-math-font-scale)
    (setq agent-shell-markdown-math-font-scale 1.0))
  ;; Configure the LaTeX preamble
  (when (boundp 'agent-shell-markdown-math-appended-preamble)
    (setq agent-shell-markdown-math-appended-preamble "\\usepackage{braket}")))

(provide 'agent-shell-setup)
;;; agent-shell-setup.el ends here
