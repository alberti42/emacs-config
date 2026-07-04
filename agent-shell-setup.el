;;; agent-shell-setup.el --- agent-shell AI agent integration -*- lexical-binding: t; -*-

;; agent-shell: interact with AI agents (Claude Code, Gemini CLI, etc.)
;; via the Agent Client Protocol (ACP) inside an Emacs shell buffer.
;; Requires shell-maker and acp as dependencies.

(use-package agent-shell  
  :straight (agent-shell
             :type git
             ;;:host github
             :local-repo "~/Documents/Programming/Others/fork-agent-shell"
             :branch "fork/angle-bracket-link-destinations"
             :repo "xenodium/agent-shell")
  :custom  
  (agent-shell-show-context-usage-indicator 'detailed)
  ;; Agent advertises `loadSession', so a resume can replay the whole
  ;; conversation back into the buffer from the ACP server (equations
  ;; and all).  `full' replays every turn on every resume; switch to
  ;; `first-last' or `last' if reopening a long session feels slow.
  (agent-shell-session-restore-verbosity 'full)
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
              ("C-c a" . agent-shell-prompt-compose)
              ("C-c w" . my/agent-shell-copy-code-block-at-point))
  :config
  ;; Copy should yield the LLM's raw markdown with NO Emacs cruft.  agent-shell
  ;; tags rendered lines with `line-prefix'/`wrap-prefix' "  " for visual indent;
  ;; those aren't in `yank-excluded-properties', so the stock filter leaks them
  ;; as a phantom, non-editable 2-space left margin on paste.  Return characters
  ;; only (no properties): drops the phantom margin, faces, keymaps.  Paired with
  ;; the overlay renderer above, region + M-w yields verbatim markdown.
  (add-hook 'agent-shell-mode-hook
            (lambda ()
              (setq-local filter-buffer-substring-function
                          (lambda (beg end &optional delete)
                            (prog1 (buffer-substring-no-properties beg end)
                              (when delete (delete-region beg end)))))))

  ;; The overlay renderer's `📋' snippet button copies a wrong/truncated range
  ;; (it bakes raw integer positions into its closure, which misalign under
  ;; agent-shell's incremental rendering) AND only the body, no fences.  This
  ;; command copies the whole fenced block at point verbatim (fences included)
  ;; by locating the fences via text search -- reliable, and it pastes straight
  ;; into a .md file.  Bound to `C-c w' above.
  (defun my/agent-shell-copy-code-block-at-point ()
    "Copy the fenced code block surrounding point (fences included) as plain text."
    (interactive)
    (save-excursion
      (beginning-of-line)
      (let ((open (if (looking-at "[ \t]*```")
                      (point)
                    (when (re-search-backward "^[ \t]*```" nil t) (point)))))
        (unless open (user-error "Not inside a fenced code block"))
        (goto-char open)
        (end-of-line)
        (let ((close (when (re-search-forward "^[ \t]*```" nil t)
                       (line-end-position))))
          (unless close (user-error "No closing fence found"))
          (kill-new (buffer-substring-no-properties open close))
          (message "Copied fenced block (%d chars)" (- close open))))))

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

  ;; Region/line context formatting (fenced, lang-tagged, `cat -n'-style
  ;; snippet) is now upstream: `agent-shell-region-context-style' defaults to
  ;; `code-block' and `agent-shell--get-numbered-region' emits the `cat -n'
  ;; shape.  The former `agent-shell--get-region-context' override lived here.

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
  )

(use-package agent-shell-math-renderer
  :straight (agent-shell-math-renderer
             :type git
             :local-repo "/Users/andrea/Documents/Programming/Emacs/agent-shell-math-renderer")
  :after agent-shell
  :config
  ;; Use the overlay renderer (buffer text stays raw markdown -> verbatim
  ;; copy) *with* math.  The drop-in wraps shell-maker's `markdown-overlays-put'
  ;; directly (not agent-shell's deprecated `agent-shell--markdown-overlays-put'),
  ;; then renders LaTeX on its output -- the overlay path runs no
  ;; `agent-shell-markdown-render-functions' hook, so this is how math gets in.
  (setq agent-shell-markdown-render-function
        #'agent-shell-math-renderer-markdown-overlays-put)
  (setq agent-shell-math-renderer-enabled t)
  (setq agent-shell-math-renderer-render-on-non-graphic t)
  (setq agent-shell-math-renderer-font-scale 1.0)
  (setq agent-shell-math-renderer-appended-preamble
        "\\usepackage{physics}
\\usepackage[only,llbracket,rrbracket]{stmaryrd}"))

(provide 'agent-shell-setup)
;;; agent-shell-setup.el ends here
