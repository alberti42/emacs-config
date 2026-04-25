# lsp-python-config.el

Python LSP via `lsp-pyright` (configured for **basedpyright**, not vanilla
pyright). Activates in `python-mode` / `python-ts-mode` and inside org-babel
Python src blocks opened with `C-c '`.

## External packages

- `lsp-pyright` — lsp-mode client; the variable `lsp-pyright-langserver-command`
  is set to `"basedpyright"` so the client launches basedpyright instead of
  pyright.

External binary: `basedpyright` from the `py313` pyenv install.

## Cross-module touchpoints

- **`lsp-core.el`** provides `lsp-mode`, `lsp-deferred`, file-watcher infra.
- **`utils.el`** provides `my/unique-file-path` (collision handling for the
  org-babel phantom files).
- **`org-config.el`** sets `org-src-window-setup 'current-window`,
  `org-src-tab-acts-natively t`, `org-src-preserve-indentation t` — these
  are load-bearing for the org-babel workflow here. Don't change them
  without testing the `C-c '` flow.
- `ruff-lsp` and `ruff` lsp clients are added to `lsp-disabled-clients`
  to prevent overlap with basedpyright.

## Performance/stability tuning

The current settings are tuned to keep basedpyright responsive in large
codebases:

| Setting                                       | Value          |
| --------------------------------------------- | -------------- |
| `lsp-pyright-type-checking-mode`              | `"basic"`      |
| `lsp-pyright-use-library-code-for-types`      | `nil`          |
| `lsp-pyright-diagnostic-mode`                 | `"openFilesOnly"` |
| `lsp-pyright-auto-import-completions`         | `nil`          |
| `lsp-pyright-multi-root`                      | `nil`          |

## Invariants — do not change without reading

### Hardcoded `~/.pyenv/versions/py313/bin` on `exec-path`

`env-config.el` imports PATH from a shell env cache that does *not* include
the pyenv version's bin directory; only the pyenv shim directory. That
means `basedpyright` (which lives in the version bin, not the shim dir) is
not findable without this explicit `add-to-list 'exec-path`. If the
basedpyright version is ever migrated to a different pyenv install, this
path needs updating in `:init` *and* `lsp-pyright-python-executable-cmd`
in `:config`.

### Activation hook is a `let`-bound lambda, not a `defun`

The hook handler is held in a local `let` closure, not a global function:

```elisp
(let ((basedpyright-enable
       (lambda () (require 'lsp-pyright) (lsp-deferred))))
  (add-hook 'python-mode-hook    basedpyright-enable)
  (add-hook 'python-ts-mode-hook basedpyright-enable))
```

Reason: the lambda is a private hook handler with no standalone call site;
keeping it out of `M-x` namespace is the goal.

**Trade-off**: each re-eval of this form creates a *new* closure object.
`add-hook` dedupes by object identity, so the new closure is appended
alongside the old one — the hook accumulates duplicate entries until Emacs
restart. If this file is reloaded often, switching to a top-level `defun`
is the correct fix, accepting the M-x pollution.

### Org-babel src block: hook ordering is load-bearing

The src-block flow has two hooks that run in a specific order. **Do not
add `lsp-deferred` to `my/org-src-python-lsp-enable`.**

1. `python-mode-hook` fires first → the lambda above runs → `lsp-deferred`
   schedules LSP on `window-configuration-change-hook`.
2. `org-src-mode-hook` fires next → `my/org-src-python-lsp-enable` sets
   `buffer-file-name` and `buffer-file-truename` to the phantom path,
   pre-writes the buffer, disables file watchers.
3. The buffer becomes visible → the scheduled `lsp` runs, reads the
   already-set `buffer-file-name`, sends **one** `didOpen`.

If `my/org-src-python-lsp-enable` itself called `lsp-deferred`, two
`didOpen` events would fire and basedpyright logs "Received redundant open
text document command".

### The phantom file must be pre-written and watcher-disabled

Three things `my/org-src-python-lsp-enable` does that are not optional:

- **`buffer-file-name` AND `buffer-file-truename`**: lsp-mode uses the
  truename for workspace bookkeeping; setting only `buffer-file-name`
  silently breaks workspace mapping.
- **`(write-region ... 'no-message)`**: without this, lsp-mode logs
  "Saving file ... because it is not present on the disk" and apheleia's
  diff-based formatter fails (nothing to diff against).
- **`(setq-local lsp-enable-file-watchers nil)`**: without this, lsp-mode
  tries to watch every directory under the org file's directory (or
  `temporary-file-directory`) and prompts above `lsp-file-watch-threshold`.

### Phantom file location: `<org-dir>/._aux/org-src-<orgbase>.py`

- Placed under the org file's directory (not `temporary-file-directory`)
  so basedpyright can walk up and discover `pyproject.toml` /
  `pyrightconfig.json` in the project root.
- Tucked under `._aux/` (leading dot hides from `ls`).
- Filename derived from the org file's basename (already filesystem-safe,
  no sanitisation needed). Falls back to `scratch` if the org buffer
  isn't file-backed.
- `my/unique-file-path` (from `utils.el`) appends `_1`, `_2`, … on
  collisions — covers simultaneous edits of multiple blocks from the
  same org file *and* leftover files from a crashed prior session.

### Resolving the original org buffer

`my/org-src-python-lsp-enable` walks three fallbacks, most reliable first:

1. `org-src--beg-marker` — buffer-local marker set by `org-src.el`; its
   `marker-buffer` is the org buffer. Authoritative for modern Org (plain
   edit buffers, not indirect).
2. `(buffer-base-buffer)` — covers the case where Org ever switches back
   to indirect buffers, or where the user opened the edit buffer via
   `clone-indirect-buffer`.
3. `(current-buffer)` — last resort; yields no useful filename but keeps
   the activation from crashing.

The forward declaration `(defvar org-src--beg-marker)` is there only to
silence the byte-compiler when `org-src.el` hasn't been loaded yet at
byte-compile time. The real value is set by `org-src.el` itself.

### Phantom file cleanup on kill

`(add-hook 'kill-buffer-hook ... nil t)` deletes the phantom file when
the edit buffer is killed (typically on `C-c '` exit). The path is
captured in a closure variable, *not* read from `buffer-file-name`, so the
deletion still works if lsp-mode's teardown clears `buffer-file-name`
first.
