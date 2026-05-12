# agent-shell-config.el

Configures `agent-shell` (interactive chat with AI coding agents — Claude
Code, Gemini CLI, OpenCode, etc. — over the Agent Client Protocol). Sets
the default OpenCode model, scopes the agent's working directory when
launched from a dired buffer, and points OpenCode at a forked binary
that supports `opencode acp --attach <url>`.

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
- Around-advice on `agent-shell-cwd` — see [Dired cwd advice](#dired-cwd-advice).

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

## Dired cwd advice

`agent-shell-cwd` (defined in `agent-shell-project.el:67`) resolves the
shell's working directory via projectile → `project.el` → fallback to
`default-directory`. In a monorepo, this walks all the way up to the
git root, which is rarely what you want.

The advice short-circuits two cases and lets everything else fall
through:

```elisp
(defun my/agent-shell-cwd-dired-advice (orig-fn &rest args)
  (if (derived-mode-p 'dired-mode 'agent-shell-mode)
      (expand-file-name default-directory)
    (apply orig-fn args)))
```

- **Launched from a dired buffer** → returns dired's listed dir, so the
  agent gets scoped to that subdir of the monorepo.
- **Called from inside a running agent-shell session** → returns the
  shell buffer's own `default-directory`, which was set correctly at
  session start.
- **Everywhere else** (file buffers, `*scratch*`) → delegates to the
  original, preserving the package's smart project-root resolution.

### Why both checks are needed

`agent-shell-cwd` is called **repeatedly** during the session — not
just at start, but on every outgoing ACP message (`prompt`,
`update_session_mode`, file-context queries, …). Each in-session call
happens with the agent-shell buffer current.

Without the `agent-shell-mode` clause, only the first call (from the
dired buffer) returns the scoped dir; every later call has
`derived-mode-p 'dired-mode'` → false → falls through to original →
`project.el` walks back up to the git root. The agent then drifts mid-
session, with `pwd` and file-tool roots silently snapping to the
monorepo top.

The agent-shell buffer's `default-directory` is set once at session
start to whatever `agent-shell-cwd` returned then; trusting it for
in-session calls is what makes the dired anchor persist.

## Invariants — do not change without reading

### Don't replace the advice with a hook on `agent-shell-cwd-function`

`agent-shell-cwd-function` is the package's documented extension point.
A function set there fires on every call to `agent-shell-cwd` and is a
valid alternative — but in practice it ends up looking like the same
advice rewritten as a defcustom-hook function, with no real upside.
Sticking with `advice-add` keeps the override visible at the
`agent-shell-cwd` call site (e.g. when stepping through `agent-shell`
with edebug) and makes removal explicit: `(advice-remove
'agent-shell-cwd #'my/agent-shell-cwd-dired-advice)`.

### Don't drop the `agent-shell-mode` short-circuit

It looks like defensive scaffolding but it isn't — without it the
dired-anchored session drifts back to the monorepo root after the
first ACP message. See [Why both checks are needed](#why-both-checks-are-needed)
above.

### The OpenCode binary on `$PATH` must be the forked build

Setting `agent-shell-opencode-acp-command` to use `--attach` only
works if the resolved `opencode` carries the `acp-attach` patch. Both
upstream's release binary and a clean upstream `dev` build will
silently swallow the unknown flag. `(executable-find "opencode")` plus
`opencode acp --help | grep -E "attach|cwd"` is the fastest sanity
check.
