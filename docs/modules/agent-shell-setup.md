# agent-shell-setup.el

Configures `agent-shell` (interactive chat with AI coding agents — Claude
Code, Gemini CLI, OpenCode, etc. — over the Agent Client Protocol). Sets
the default OpenCode model, feeds the agent the launching buffer's
`default-directory` as its working directory, matches session reuse on the
project root, and points OpenCode at a forked binary that supports
`opencode acp --attach <url>`.

External packages: `agent-shell` (which pulls in `shell-maker` and `acp`).

## What's configured

- `agent-shell-show-context-usage-indicator 'detailed` — verbose token
  meter in the mode line.
- `agent-shell-opencode-default-model-id "openai/gpt-5.4"` — default
  model for `M-x agent-shell-opencode-start-agent`.
- `agent-shell-opencode-acp-command '("opencode" "acp" "--attach"
  "http://localhost:4096")` — see [OpenCode fork dependency](#opencode-fork-dependency).
- Keys in `agent-shell-mode-map`:
  - `M-RET` → `newline`
  - `C-c a` → `agent-shell-prompt-compose`
- `agent-shell-cwd-function` + an override on `agent-shell-project-buffers`
  — see [Working directory and session reuse](#working-directory-and-session-reuse).

## OpenCode fork dependency

The `agent-shell-opencode-acp-command` value passes `--attach <url>` to
`opencode acp`. Upstream OpenCode does **not** support this flag — the
binary on `$PATH` must come from a personal fork that carries the patch:

- Fork repo: <https://github.com/alberti42/fork-opencode>
- Local working copy: `~/Documents/Programming/Others/fork-opencode.nosync`
- Feature branch: `acp-attach` (clean feature commit on top of upstream `dev`).
- Working branch: `integrated` (carries the same patch alongside other
  local changes; this is what's typically built and installed).
- PR draft: `ACP_ATTACH_PR.md` at the fork repo root, on `acp-attach`.
  Captures the rationale, CLI surface, the two pitfalls (below), and
  verification steps. Not yet submitted upstream. Supersedes the closed,
  unmerged upstream PR #18272.

A long-running server is also required:

```bash
$DOTFILES_DIR/.local/bin/opencode_backend_launcher
# → exec opencode serve --port 4096 --print-logs --log-level DEBUG
```

The launcher must `cd` into the project root **before** `exec`ing
`opencode serve`, because the server bootstraps its workspace from
`process.cwd()` at startup. Earlier the launcher did `cd /`, which made
every attach session fail with `"No context found for instance"` — the
server had no usable workspace and couldn't satisfy SDK requests.

If you ever rebuild OpenCode from upstream `dev` without merging
`acp-attach`, the `--attach` flag will be silently rejected by yargs
(its error path returns 0 with usage), and the binary will sit there
running its own in-process server instead of bridging to port 4096. You
won't see an obvious error — just that nothing reaches `opencode session
list`. Confirm with `opencode acp --help | grep -E "attach|cwd"`; both
flags must be present.

### Two pitfalls baked into the fork patch

Documented here as well as in the PR draft, because future-you will
otherwise rederive them painfully when tweaking
`packages/opencode/src/cli/cmd/acp.ts`:

1. **`--cwd` must not default to `process.cwd()`.** The original PR
   (#18272) had `default: process.cwd()`, which makes the SDK send the
   acp client's cwd as `x-opencode-directory` on every request. The
   server then tries to load an instance for a directory it may not own
   and fails with `"No context found for instance"`. Leave `--cwd`
   optional so the SDK passes `directory: undefined` and the server
   falls back to its own workspace. Matches `opencode attach --dir`.

2. **The local `InstanceContext` must still load in attach mode.** It
   is tempting to set `instance: (args) => !args.attach` on the
   `effectCmd`, mirroring `run.ts`'s pattern. But `acp/agent.ts`'s
   `resolveModeState` calls `AgentModule.Service.defaultAgent()`, which
   reads `Instance.current` via AsyncLocalStorage. Without a loaded
   local instance, that read throws `NotFound("instance")` on the very
   first `session/new`. Keep `effectCmd`'s `instance: true` default;
   the SDK still proxies workspace-scoped calls to the remote server.

## Working directory and session reuse

`agent-shell-cwd` (defined in `agent-shell-project.el:67`) serves **two**
jobs through one value: the `:cwd` sent to the agent (its working
directory), and project identity for session reuse
(`agent-shell-project-buffers` matches shells by `equal` on
`agent-shell-cwd`). Stock resolution walks projectile → `project.el` →
`default-directory`, so in a project it returns the git root.

Two pieces of config override this:

### `agent-shell-cwd-function` → `default-directory`

```elisp
(defun my/agent-shell-cwd-function ()
  (expand-file-name default-directory))
(setq agent-shell-cwd-function #'my/agent-shell-cwd-function)
```

The agent's working directory becomes the launching buffer's
`default-directory` — not the project root. There is **no dired
special-casing**: a dired buffer behaves like any other buffer, so
agent-shell's stock file-picking workflow (mark files, send to the
agent) works there normally. Because the function returns
`default-directory` unconditionally, in-session calls (which run with the
agent-shell buffer current, on every outgoing ACP message) return that
buffer's own `default-directory`, so the session does not drift.

### Override on `agent-shell-project-buffers` → match on project root

Feeding `agent-shell-cwd` the buffer's `default-directory` breaks stock
reuse: a buffer in `/proj/sub/` no longer `equal`s a shell started at
`/proj/`, so DWIM would fall through to "Start new agent:". The override
matches on the real **project root** (`project.el`), decoupled from cwd,
so any buffer inside a project reuses that project's shell regardless of
subdirectory:

```elisp
(defun my/agent-shell--project-root ()
  (expand-file-name
   (if-let* ((proj (project-current)))
       (project-root proj)
     default-directory)))
(defun my/agent-shell-project-buffers (&rest _)
  (let ((root (my/agent-shell--project-root)))
    (seq-filter (lambda (buffer)
                  (equal root (with-current-buffer buffer
                                (my/agent-shell--project-root))))
                (agent-shell-buffers))))
(advice-add 'agent-shell-project-buffers :override
            #'my/agent-shell-project-buffers)
```

## Invariants — do not change without reading

### The two overrides go together

Overriding the cwd (so the agent gets `default-directory`) **requires**
the `agent-shell-project-buffers` override. Without it, launching from any
subdirectory other than the one the shell was started in fails to match
the existing shell and spawns a duplicate session. Conversely the
project-root match exists *because* cwd no longer doubles as project
identity. Remove one and the pair is broken.

### Match reuse on the project root, not on cwd

An earlier version matched on whether a shell's cwd lived *within* the
current buffer's cwd (`file-in-directory-p`). That is directional and
wrong: a shell at `/proj/` is a **parent** of a dired buffer at
`/proj/sub/`, not a child, so it never matched and a new session spawned.
Comparing `project.el` roots is symmetric and subdirectory-agnostic.

### The OpenCode binary on `$PATH` must be the forked build

Setting `agent-shell-opencode-acp-command` to use `--attach` only
works if the resolved `opencode` carries the `acp-attach` patch. Both
upstream's release binary and a clean upstream `dev` build will
silently swallow the unknown flag. `(executable-find "opencode")` plus
`opencode acp --help | grep -E "attach|cwd"` is the fastest sanity
check.
