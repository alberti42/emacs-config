# uv-config.el

Per-buffer activation of uv-managed virtual environments. No external
package; all custom code. Replaces `pyenv-config.el` after the
2026-06-21 pyenv→uv migration.

## What changed vs. pyenv

pyenv shipped a **shim** mechanism: shims on `exec-path` (set up by
`env-config.el`) walked up from the subprocess CWD looking for
`.python-version`, so opening a file inside a project was enough for
`python` / `pip` to resolve correctly with no Emacs-side logic. That was
pyenv-config's "default layer".

uv has **no equivalent shim** for the named/global environments. A bare
`python` spawned from a buffer carries only the stdlib; packages always
come from an activated virtual environment. So under uv there is no
"default layer" — activation is always explicit, which is the whole job
of this module.

## Where the environments live

Named environments (the pyenv-virtualenv replacement) live under
`uv-virtualenvs-dir`, default:

```
$XDG_DATA_HOME/virtualenvs/<name>      # = ~/.local/share/virtualenvs/<name>
```

`uv--virtualenvs` lists the immediate subdirectories that actually
contain a `bin/python`, which is what `uv-activate-buffer` offers for
completion.

## Two layers of resolution

In order of precedence (lowest to highest), an Emacs subprocess sees:

1. **Dir-local `uv-venv`** (string, declared safe via
   `safe-local-variable`): set in `.dir-locals.el` to point a project at
   a shared named env without a per-project `.venv`. Applied from
   `hack-local-variables-hook`. Useful for long-running subprocesses
   (e.g. coding agents) that need the venv's `bin/` on their own PATH.
2. **`uv-activate-buffer`** (interactive): ad-hoc per-buffer pick.
   `completing-read` over `uv--virtualenvs`.

Both call `uv--set`, which performs the equivalent of a shell
`source <venv>/bin/activate`:

- Sets `VIRTUAL_ENV` and clears `PYTHONHOME` (in a buffer-local
  `process-environment`).
- Prepends the env's `bin/` to `PATH` (same buffer-local copy) and to a
  buffer-local `exec-path`.

A venv is considered usable when its `bin/python` exists (`uv--venv-p`,
shared with the picker's lister). Missing-env handling differs by entry
point:

- **Dir-local path** (`uv--apply-dir-local`, runs on every file open via
  `hack-local-variables-hook`): a missing env is reported with
  `display-warning` and **skipped** — a stale `.dir-locals.el` entry must
  never block opening the file. The warning surfaces via `warning-toast`.
- **`uv--set`** (the low-level activator): **errors** on a missing env.
  This is a defensive guard; the interactive picker can't trigger it
  (`completing-read` requires a match), and the dir-local path checks
  first, so it only fires on a genuine programming error.

`uv-deactivate-buffer` reverts everything in one go by killing the
buffer-local `process-environment` and `exec-path` copies.

`uv-venv` / the picker accept either a **bare name** (resolved against
`uv-virtualenvs-dir`) or an **absolute path** to a virtualenv root, so a
project-local `.venv` can be named directly when wanted.

## Cross-module touchpoints

- **`lsp-python-config.el`** reuses `uv-virtualenvs-dir` to locate the
  `py313` env that provides `basedpyright-langserver` (and `python`),
  via `lsp-python-basedpyright-venv`. Keep both pointed at the same
  XDG location.
- **`inheritenv` precedence (init.el)**: because `uv--apply-dir-local`
  sets the buffer-local env explicitly, a project's `.dir-locals.el`
  `uv-venv` wins over an interactive `uv-activate-buffer` done in a
  caller buffer that later re-applies dir-locals (e.g. agent-shell).

## Public API

| Form                         | Purpose                                              |
| ---------------------------- | ---------------------------------------------------- |
| `M-x uv-activate-buffer`     | interactive picker for the current buffer            |
| `M-x uv-deactivate-buffer`   | revert buffer-local activation                       |
| `uv-venv` (dir-local)        | set in `.dir-locals.el` to auto-activate per project |
| `uv-virtualenvs-dir`         | where named environments live (defcustom)            |
| `uv-active-venv` (read)      | inspect what's currently activated in this buffer    |
