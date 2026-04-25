# dired-config.el

Dired with Yazi-style keybindings, OS file-manager integration, and
nerd-icons / diredfl decoration.

## External packages

- `dired-narrow` — live filter the listing as you type (`/`).
- `diredfl` — richer font-locking; distinct faces for size, date,
  permission bits, directories, symlinks, executables, compressed files,
  etc. Works in both GUI and TTY.
- `nerd-icons-dired` — icon glyphs at the start of each line. Reuses the
  font set up in `nerd-icons-config.el` (no second icon system).

Built-in (`:straight nil`): `dired`, `dired-x`.

External binary on macOS: **`gls`** (GNU coreutils). Required because
macOS BSD `ls` lacks `--dired` and `--time=birth`. Install via
`brew install coreutils`.

## Cross-module touchpoints

- **`nerd-icons-config.el`** — the icon font setup is shared. Don't
  re-install nerd-icons here.
- **`syntaxes/dired.el`** — disables line numbers in dired buffers.

## Key bindings (Yazi-inspired)

| Key      | Action                                                          |
| -------- | --------------------------------------------------------------- |
| `/`      | `dired-narrow` — live-filter the listing                        |
| `O`      | `dired-open-with` — pick "Open" (OS default app) or "Reveal in file manager" |
| `.`      | `dired-omit-mode` toggle (shadows default `dired-clean-directory`) |
| `, a`    | sort by name                                                    |
| `, A`    | sort by name reversed                                           |
| `, m`    | sort by mtime, newest first                                     |
| `, M`    | sort by mtime, oldest first                                     |
| `, b`    | sort by birth (creation) time, newest first — needs GNU ls ≥ 8.25 |
| `, B`    | sort by birth time, oldest first — same requirement             |
| `, e`    | sort by extension                                               |
| `, E`    | sort by extension reversed                                      |

## Public API beyond key bindings

- `M-x dired-reveal-file` — interactively pick any file and jump to its
  directory in dired with point on it.
- `M-x dired-open-with` — usable from any buffer where dired's
  current-file resolution works.
- `M-x dired-sort-by-{name,mtime,btime,ext}{,-r}` — directly callable.

## Settings

| Setting                                       | Value | Note |
| --------------------------------------------- | ----- | ---- |
| `dired-kill-when-opening-new-dired-buffer`    | `t`   | reuse one dired buffer when navigating |
| `dired-dwim-target`                           | `t`   | second window's path is the default target for copy/move |
| `dired-use-ls-dired`                          | `t`   | use `ls --dired` (requires GNU ls) |
| `delete-by-moving-to-trash`                   | `t`   | `D` moves to trash, doesn't unlink |
| `dired-omit-files`                            | `(rx bos "." (not (any ".")))` | hides dotfiles, **excluding** `.` and `..` |
| `dired-omit-verbose`                          | `nil` | don't echo "Omitted N lines" |
| `insert-directory-program` (macOS)            | `"gls"` | BSD ls lacks `--dired` |

## Invariants — do not change without reading

### `dired-omit-files` regex must exclude `.` and `..`

`(rx bos "." (not (any ".")))` matches a file that starts with `.`
followed by something that is **not** another `.`. So `.gitignore` and
`.config` are hidden, but `.` and `..` are kept (otherwise navigation
breaks — you can't go up a directory). A naive regex like `^\.` or
`(rx bos ".")` hides `.` and `..` and breaks `..`-traversal. Don't
"simplify" this.

### `.` key intentionally shadows `dired-clean-directory`

The default binding for `.` in `dired-mode-map` is `dired-clean-directory`,
which deletes generated/backup files. Toggling omit-mode is far more
useful in daily use; the override is deliberate.

### macOS needs `gls`, not BSD `ls`

`dired-use-ls-dired t` requires the GNU `--dired` flag. BSD `ls` on
macOS doesn't have it. Birth-time sort needs `--time=birth`, which only
GNU ls 8.25+ supports — also missing on BSD. Setting
`insert-directory-program "gls"` (only on darwin) is what makes the rest
of the module work. If `gls` is missing, dired silently falls back to
broken behavior.

### `nerd-icons-dired--add-overlay` is intentionally re-defined

The block at lines 102–107 redefines `nerd-icons-dired--add-overlay`
without the upstream `(propertize s 'display s)` wrapper.

Upstream wraps the icon string this way to fix a visual artifact when
`hl-line-mode` is active: without the wrapper, the overlay retains the
frame background rather than the highlighted line color. The wrapper
has a side-effect — Emacs defers face evaluation on first display, so
icons appear **colorless** until a redisplay is triggered (highlight,
`g`, etc.).

This config doesn't use `hl-line-mode`, so the workaround is
unnecessary and trades a real bug (cold colorless icons) for nothing.
The override drops the wrapper. **If you ever enable `hl-line-mode`,
remove this override** — otherwise icon backgrounds will mismatch
highlighted lines.

### `dired-open-with` preserves "Open" before "Reveal"

The `let` around `completing-read` sets `:display-sort-function identity`
in `completion-extra-properties` so the candidate order is preserved.
Without it, the minibuffer alphabetizes them and "Reveal in file manager"
shows up first (`R` < `O`'s "Open"). The order matters because "Open" is
the more common action and should be first.
