# themes-config.el + theme-harmonize.el

Theme loading pipeline plus the post-`load-theme` face-synchronization hook.
Covered together because the two files form one system: `themes-config.el`
orchestrates loading and configures the harmonizer; `theme-harmonize.el` is
the harmonization library it drives.

## External packages

- `doom-themes` — installed via straight with `doom-themes-enable-bold` and
  `doom-themes-enable-italic` on, and `doom-themes-org-config` for Org's
  headings, blocks and TODO keywords. Light theme: `doom-opera-light`. Dark:
  `doom-challenger-deep`.

`theme-harmonize` and `zac-theme-autodetection` are local modules
(`:straight nil :load-path …`).

## The three actors and their load order

The order is intentional and load-bearing:

1. **`theme-harmonize`** (this repo, `:load-path emacs-config-dir`). Defines
   `theme-harmonize-theme` and adds it to `enable-theme-functions` and
   `after-make-frame-functions`. Must load *first* so the function exists
   before any theme change fires the hook.
2. **`doom-themes`** is installed and configured here, but **no theme is
   loaded yet** — `themes-config.el` does not call `load-theme` itself. The
   activation happens in step 3. (In the file `use-package doom-themes`
   comes first; it only installs, so its position relative to
   `theme-harmonize` does not matter.)
3. **`zac-theme-autodetection`** (in `local/`, see CLAUDE.md "Local
   package overrides"). Reads the OS appearance state file written by
   `zsh-appearance-control` and calls `zac-load-theme-callback` with
   `:light` or `:dark`. The callback (set in `:init`) disables every other
   enabled theme, then calls `load-theme` on the matching doom theme.
   `load-theme` runs
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
| `theme-harmonize-line-number-bg`      | plist `(:light "#xxx" :dark "#yyy")`. Overrides the `line-number` background, which is then spread to `margin`, `fringe`, `header-line`, `flycheck-fringe-*`, and `git-gutter:*`. **Currently commented out**: the theme's own `line-number` background is what gets spread. |
| `theme-harmonize-git-gutter-colors`   | plist `(:light (:added :modified :deleted) :dark (...))`. Foreground colors for git-gutter indicators per appearance. **Currently commented out**: git-gutter keeps its own colors. |
| `theme-harmonize-ansi-color-palette`  | plist `(:light [16 colors] :dark [16 colors])`. Overrides the `ansi-color-*` faces. Currently Catppuccin Latte / Frappe, matching WezTerm. |
| `zac-load-theme-callback`             | function `(appearance) → unit`. Receives `:light` or `:dark`; disables every other enabled theme and loads `doom-opera-light` or `doom-challenger-deep`. Set in `:init` so the watcher picks it up on first application. |

## Face fixes on top of the theme

`themes-config.el` has five face fixes. Each fix is a function on
`enable-theme-functions`, because the callback disables every other theme
(including `user`) on each switch and so wipes any earlier
`set-face-attribute`; a `with-eval-after-load` covers the package loading
after the theme.

| Function | What it does |
| -------- | ------------ |
| `themes-config--clear-markdown-html-block-bg` | removes the background of `markdown-ts-html-block`: HTML comments in Markdown (e.g. `<!-- ltex: ... -->`) are prose, not code |
| `themes-config--harmonize-markdown-headings` | makes `markdown-ts-heading-1`…`-6` inherit `org-level-1`…`-6`, since the bundled faces all inherit one face and every level renders alike |
| `themes-config--fix-annotation-contrast` | in `doom-opera-light` only, `completions-annotations` and `marginalia-documentation` get `#8e8e8e`, readable on the `#bdbdbd` of `vertico-current` |
| `themes-config--fix-magit-header-line-contrast` | in `doom-opera-light` only, `magit-header-line` gets a `#fafafa` foreground; the theme's `#424242` on `#5272AF` is about 2.2:1 |
| `themes-config--fix-org-block-contrast` | in `doom-challenger-deep` only, `org-block`, `org-block-begin-line` and `org-block-end-line` get the `#12111E` background, and `font-lock-comment-face` and the two delimiter lines the `#858FA5` foreground; the theme's `#565575` comments on the `#292F37` block are 1.9:1, the new pair 5.75:1 |

Adding a new package that needs harmonizing → edit
`theme-harmonize-theme` in `theme-harmonize.el`. The existing structure is
"derive everything from `(face-background 'line-number)`" — follow that
pattern.

## What `theme-harmonize-theme` actually propagates

Pulled from `(face-background 'line-number)` after the appearance-aware
override at the top of the function (skipped while
`theme-harmonize-line-number-bg` is nil):

| Face                                                        | Why                                                          |
| ----------------------------------------------------------- | ------------------------------------------------------------ |
| `line-number`                                               | the source — the theme's own, or `theme-harmonize-line-number-bg` when set |
| `margin` (guarded by `facep`)                               | gutter column blends across the margin (bug#80693 — face only exists on patched builds) |
| `fringe`                                                    | same column on GUI                                           |
| `header-line`                                               | lsp-mode headerline breadcrumb bar — individual `lsp-headerline-breadcrumb-*` faces carry no background of their own; the bar color comes entirely from `header-line` |
| `flycheck-fringe-error` / `-warning` / `-info`              | fringe diagnostic indicators blend with gutter               |
| `git-gutter:added` / `-modified` / `-deleted` / `-unchanged` / `-separator` (background) | gutter indicators blend with the column                       |
| `git-gutter:added` / `-modified` / `-deleted` (foreground)  | per-appearance from `theme-harmonize-git-gutter-colors`, when set |
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

### The callback disables the other themes before loading

`load-theme` layers the new theme on top of the enabled ones: a face the
new theme does not define keeps the old theme's value. The callback
therefore runs `(mapc #'disable-theme (remq theme custom-enabled-themes))`
first. On a new frame the appearance is unchanged, the theme is already
the only one enabled, and nothing is disabled, so there is no flash. This
is also why the face fixes above live on `enable-theme-functions`.

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
- `markdown-config.el` / `org-config.el` — the Markdown heading faces are
  derived from Org's `org-level-N`, which `doom-themes-org-config` styles.

## Where the live appearance state comes from

- `zsh-appearance-control` (external zsh plugin) writes `:light` or
  `:dark` (encoded as `0`/`1`) to a state file.
- File location: `$ZAC_CACHE_DIR/appearance` if set, else
  `$XDG_CACHE_HOME/zac/appearance`, else `~/.cache/zac/appearance`.
- `zac-theme-autodetection` watches the file via Emacs file
  notifications and calls `zac-load-theme-callback` on change.
