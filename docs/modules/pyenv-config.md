# pyenv-config.el

Per-buffer pyenv version selection. No external package; all custom code.

## Cross-module touchpoints

- **`env-config.el`** puts pyenv shims on `exec-path` at startup. That, plus
  Emacs subprocesses inheriting `default-directory` as their CWD, is what
  makes the *default* path work — pyenv shims walk up from CWD looking for
  `.python-version`, so opening a file inside a project is enough for
  `python` / `pip` / etc. to resolve to the project's interpreter without
  any Emacs-side logic.
- This module only adds **override paths** on top of that default.

## Three layers of resolution

In order of precedence (lowest to highest), an Emacs subprocess sees:

1. **Default**: pyenv shim walks up from CWD, finds `.python-version`,
   resolves to the matching install. *Nothing here in Emacs is involved* —
   the work is in `env-config.el` putting shims on PATH and Emacs setting
   subprocess CWD from `default-directory`.
2. **Dir-local `pyenv-version`** (string, declared safe via
   `safe-local-variable`): set in `.dir-locals.el` for project overrides
   you don't want to commit as a `.python-version` file. Applied from
   `hack-local-variables-hook`. Useful for long-running subprocesses (e.g.
   coding agents) that need the venv's `bin/` on their own PATH.
3. **`pyenv-activate-buffer`** (interactive): ad-hoc per-buffer pick.
   `completing-read` over `pyenv virtualenvs --bare` — same list
   `pyenv activate <TAB>` offers (canonical names and aliases).

Layers 2 and 3 both call `pyenv--set`, which performs the full equivalent
of a shell `pyenv activate`:

- Sets `PYENV_VERSION` and `VIRTUAL_ENV` (in a buffer-local
  `process-environment`).
- Prepends the env's `bin/` to `PATH` (in the same buffer-local copy) and
  to a buffer-local `exec-path`.
- Resolves the filesystem prefix once at activation via `pyenv prefix
  <version>` — not on every subprocess spawn.

`pyenv-deactivate-buffer` reverts all four changes in one go by killing
the buffer-local `process-environment` and `exec-path` copies.

## Why not the `pyenv-mode` package?

Two reasons:

1. **Duplication**: `pyenv-mode` adds shims to `exec-path` itself. We
   already do that in `env-config.el` for the whole Emacs session, so the
   default shim path works without it.
2. **Wrong scope**: `pyenv-mode` switches *globally* — every buffer sees
   the same `PYENV_VERSION`. We want per-buffer scope so two projects
   open at the same time pick up their own `.python-version` files
   independently.

Don't replace this module with `pyenv-mode`.

## Naming convention

Public names use the `pyenv-` prefix to match the underlying tool
(`pyenv-activate-buffer`, `pyenv-deactivate-buffer`, `pyenv-version`,
`pyenv-active-version`). The filename keeps the repo-wide `-config.el`
convention.

## Public API

| Form                              | Purpose                                                  |
| --------------------------------- | -------------------------------------------------------- |
| `M-x pyenv-activate-buffer`       | interactive picker for the current buffer                |
| `M-x pyenv-deactivate-buffer`     | revert buffer-local activation                           |
| `pyenv-version` (dir-local)       | set in `.dir-locals.el` to auto-activate per project     |
| `pyenv-active-version` (read)     | inspect what's currently activated in this buffer        |
