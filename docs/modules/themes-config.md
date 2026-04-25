# themes-config.el + theme-harmonize.el

Theme loading pipeline plus the post-`load-theme` face-synchronization hook.
Covered together because the two files form one system: `themes-config.el`
orchestrates loading and configures the harmonizer; `theme-harmonize.el` is
the harmonization library it drives.

## External packages

- `modus-themes` — installed via straight to track Protesilaos' upstream
  (the bundled Emacs version lags). Light variant: `modus-operandi`. Dark:
  `modus-vivendi-tinted`.

`theme-harmonize` and `zac-theme-autodetection` are local modules
(`:straight nil :load-path …`).

## The three actors and their load order

The order is intentional and load-bearing:

1. **`theme-harmonize`** (this repo, `:load-path emacs-config-dir`). Defines
   `theme-harmonize-theme` and adds it to `enable-theme-functions` and
   `after-make-frame-functions`. Must load *first* so the function exists
   before any theme change fires the hook.
2. **`modus-themes`** is installed and configured here, but **not loaded
   yet** — `themes-config.el` does not call `load-theme`. The actual
   activation happens in step 3.
3. **`zac-theme-autodetection`** (in `local/`, see CLAUDE.md "Local
   package overrides"). Reads the OS appearance state file written by
   `zsh-appearance-control` and calls `zac-load-theme-callback` with
   `:light` or `:dark`. The callback (set in `:init`) calls `load-theme`
   with the appropriate modus variant. `load-theme` runs
   `enable-theme-functions`, which in turn runs `theme-harmonize-theme`
   — synchronizing all derived faces.

If you change this order, things break silently:
- Loading `zac-theme-autodetection` before `theme-harmonize` means the
  first `load-theme` fires the hook before `theme-harmonize-theme` exists
  → no error, but no harmonization.
- Setting `zac-load-theme-callback` *after* `zac-theme-autodetection` has
  loaded means the watcher's first application uses the default callback
  (none). The `:init` block in `themes-config.el` sets the callback
  *before* the package loads precisely to avoid this.

## Configurable knobs (in `themes-config.el`)

| Variable                              | Purpose                                                      |
| ------------------------------------- | ------------------------------------------------------------ |
| `theme-harmonize-line-number-bg`      | plist `(:light "#xxx" :dark "#yyy")`. Drives the gutter color across `line-number`, `margin`, `fringe`, `header-line`, `flycheck-fringe-*`, and `git-gutter:*` backgrounds. Currently Catppuccin (Latte / Frappe). |
| `theme-harmonize-git-gutter-colors`   | plist `(:light (:added :modified :deleted) :dark (...))`. Foreground colors for git-gutter indicators per appearance. |
| `modus-operandi-palette-overrides`    | currently `((fg-heading-1 "#2e6b6a"))` (teal H1 in light theme). |
| `modus-vivendi-tinted-palette-overrides` | currently `((fg-heading-1 "#8fbcbb"))` (lighter teal H1 in dark theme). |
| `zac-load-theme-callback`             | function `(appearance) → unit`. Receives `:light` or `:dark`; switches the theme. Set in `:init` so the watcher picks it up on first application. |

Adding a new package that needs harmonizing → edit
`theme-harmonize-theme` in `theme-harmonize.el`. The existing structure is
"derive everything from `(face-background 'line-number)`" — follow that
pattern.

## What `theme-harmonize-theme` actually propagates

Pulled from `(face-background 'line-number)` after the appearance-aware
override at the top of the function:

| Face                                                        | Why                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| `line-number`                                               | the source — set first from `theme-harmonize-line-number-bg` |
| `margin` (guarded by `facep`)                               | gutter column blends across the margin (bug#80693 — face only exists on patched builds) |
| `fringe`                                                    | same column on GUI                                           |
| `header-line`                                               | lsp-mode headerline breadcrumb bar — individual `lsp-headerline-breadcrumb-*` faces carry no background of their own; the bar color comes entirely from `header-line` |
| `flycheck-fringe-error` / `-warning` / `-info`              | fringe diagnostic indicators blend with gutter               |
| `git-gutter:added` / `-modified` / `-deleted` / `-unchanged` / `-separator` (background) | gutter indicators blend with the column                       |
| `git-gutter:added` / `-modified` / `-deleted` (foreground)  | per-appearance from `theme-harmonize-git-gutter-colors`      |
| `git-gutter:unchanged` / `-separator` (foreground)          | matches background — invisible spaces, no artifact shows     |

## Invariants — do not change without reading

### `theme-harmonize-line-number-bg` is now plist-keyed by appearance

Format: `(:light "#xxx" :dark "#yyy")`. The function picks the right
value based on `(frame-parameter nil 'background-mode)`. **The earlier
single-string `theme-harmonize-tty-line-number` is gone** — both CLAUDE.md
and any reader's mental model from before need updating. Both TTY and GUI
frames are harmonized, not just TTY.

### Hook coverage: `enable-theme-functions` AND `after-make-frame-functions`

`enable-theme-functions` (Emacs 29+) handles every theme change. The
`after-make-frame-functions` hook is also wired so that a new
`emacsclient` frame (TTY *or* GUI) connecting to a daemon that started
without a graphical frame still receives the harmonized faces.
Removing the second hook silently breaks daemon-with-mixed-clients.

### `modus-themes-mixed-fonts nil`

When `t`, modus makes code/table faces inherit from `fixed-pitch` instead
of `default`. That's useful only when `default` is proportional (a
prose-writing setup). Since `default` is monospace
(`early-init.el`), enabling it would route org tables and src blocks
through whatever `fixed-pitch` resolves to (Courier on macOS, different
metrics than the rest of the editor) and they would misalign. Keep off
unless `default` ever becomes proportional.

### `zac-load-theme-callback` is set in `:init`, not `:config`

The `:init` block runs *before* `zac-theme-autodetection` loads, which
means the watcher sees the callback on its first application of the OS
appearance. Setting it in `:config` would race with the initial
application — the first theme load might use a nil/default callback.

### `zac-theme-autodetection` lives in `local/`, not the repo root

`themes-config.el` loads it via `:load-path (lambda () (list
(expand-file-name "local" emacs-config-dir)))`. The lambda form is
deliberate — the inner `expand-file-name` runs at load time when
`emacs-config-dir` is bound, not at byte-compile time.

`theme-harmonize.el` itself sits in the repo root and uses the simpler
`:load-path emacs-config-dir`.

## Cross-module touchpoints

- `git-gutter-config.el` — its faces (`git-gutter:added`, etc.) are
  recolored here.
- `lsp-core.el` — the `header-line` background is set here so the
  lsp headerline breadcrumb bar has a consistent color.
- `early-init.el` — the `default` font being monospace is what makes
  `modus-themes-mixed-fonts nil` correct here. Don't change one without
  reconsidering the other.

## Where the live appearance state comes from

- `zsh-appearance-control` (external zsh plugin) writes `:light` or
  `:dark` (encoded as `0`/`1`) to a state file.
- File location: `$ZAC_CACHE_DIR/appearance` if set, else
  `$XDG_CACHE_HOME/zac/appearance`, else `~/.cache/zac/appearance`.
- `zac-theme-autodetection` watches the file via Emacs file
  notifications and calls `zac-load-theme-callback` on change.
