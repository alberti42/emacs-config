# org-config.el

Org mode plus inline LaTeX previewing and Python babel, on **built-in Org**.

## Migration note (tecosaur fork → built-in Org)

This module used to pull Org from **tecosaur's fork**
(`https://git.tecosaur.net/tec/org-mode.git`, branch `dev`) to get karthink's
live `org-latex-preview` (auto-preview, real-time updates while editing a
fragment, dvisvgm SVG). That work never landed upstream and the fork is now
effectively unmaintained, so the config was moved back to the Org that ships
with Emacs (`:straight (org :type built-in)`).

The old fork-based configuration is preserved verbatim but **unloaded** in
`org-karthink-config.el` (renamed from the previous `org-config.el`; its
`provide`/header updated, no `init.el` entry).

The "basis for a homegrown math-rendering package" that this migration
anticipated now exists: **`org-latex-to-svg`** (front-end) over **`latex-to-svg`**
(engine), which is what actually renders math here — see the *LaTeX math
preview* section below. It restores the fork's recolour-on-theme /
rescale-on-zoom ergonomics from a content-addressed cache, without the fork.

Consequences of using built-in Org (for anything other than math preview, which
`org-latex-to-svg` handles):

- **No live preview minor mode in Org itself.** Mainline Org has no
  `org-latex-preview-mode` (the fork-only live mode); its classic
  `org-latex-preview` command remains as a dvisvgm fallback.
- The following fork-only settings were **dropped** (no mainline analogue):
  `org-latex-preview-numbered`, `org-latex-preview-mode-display-live`,
  `org-latex-preview-mode-update-delay`, `org-latex-preview-mode-ignored-commands`,
  and `org-latex-preview-appearance-options :page-width`.
- The fork-only `org-latex-preview-process-default` is replaced by the classic
  `org-preview-latex-default-process`.
- The `:pre-build` `org-version.el` synthesis and the stale `.fmt` purge (both
  specific to the fork's straight recipe / `org-persist` `.fmt` caching) are
  gone. Classic preview caches rendered images under `ltximg/`, not precompiled
  `.fmt` preambles, so the purge is unnecessary.

## External packages

- **`org`** — the Emacs-bundled Org, registered with
  `:straight (org :type built-in)`. No custom recipe, no fork, no pre-build
  step. **Not** a bare `:straight nil`: `org-appear` declares `(org "9.3")` in
  its `Package-Requires`, so straight resolves `org` as a dependency and would
  otherwise rebuild the leftover tecosaur checkout in `straight/repos/org` and
  put it on `load-path`, shadowing the bundled Org. `:type built-in` makes the
  org-appear dependency resolve to built-in too. (The stale fork checkout under
  `straight/repos/org` / `straight/build/org` is harmless once org isn't
  activated by straight; it's left in place so re-enabling
  `org-karthink-config.el` doesn't require a re-clone.)
- **`org-appear`** — auto-toggles visibility of emphasis markers, links,
  sub/superscripts based on cursor position.

## Cross-module touchpoints

- **`lsp-python-config.el`** depends on the `org-src-*` settings configured
  here (`org-src-window-setup`, `org-src-tab-acts-natively`,
  `org-src-preserve-indentation`). The `C-c '` Python-LSP-in-babel workflow
  breaks if these change.
- **`jupyter-config.el`** registers `jupyter-python` as a babel language;
  the babel infrastructure here is the substrate.
- **`code-cells-config.el`** redirects jupyter line/region eval; orthogonal
  to babel but operates on the same buffers.
- **`yasnippets/org-mode/`** holds matplotlib setup blocks — the Python
  babel defaults here are deliberately minimal so per-file/snippet setup
  isn't fighting global config.
- **`pdf-tools-config.el`** sets a literal `pdf-annot-latex-header` to bypass
  an initializer that read `org-format-latex-header`. With built-in Org that
  variable exists again, so the workaround is now belt-and-suspenders rather
  than load-bearing; harmless to keep.

## LaTeX math preview — `org-latex-to-svg`

In-buffer math is **not** rendered by built-in Org's classic
`org-latex-preview`. It is rendered by the homegrown **`org-latex-to-svg`**
package, a front-end over the standalone **`latex-to-svg`** engine. Both live
in `~/Documents/Programming/Emacs/` and are wired in at the end of
`org-config.el` via local-checkout straight recipes; `org-mode-hook` turns on
`org-latex-to-svg-mode`, which renders every `latex-fragment` /
`latex-environment` on open.

Why, and what it buys us:

- The engine compiles each unique equation **once** (content-addressed on
  disk), **color-independent** (`dvisvgm --currentcolor`, tinted at display)
  and **size-independent** (scaled at display to the buffer font).
- So previews **recolour on an OS light/dark theme switch** and **rescale on
  buffer text zoom** straight from cache, with **no LaTeX recompile** — the
  tecosaur/karthink ergonomics, without the fork. `org-latex-to-svg` owns the
  refresh hooks (`enable-theme-functions`, `text-scale-mode-hook`,
  `window-buffer-change-functions`); nothing here in `org-config.el`.
- `C-c C-x C-l` is rebound (while the mode is on) to `org-latex-to-svg`:
  toggle the fragment at point / render the region / render the buffer;
  `C-u` clears. Editing under a preview reveals its source.

What `org-config.el` keeps for math is minimal: `org-preview-latex-default-process
'dvisvgm`, so built-in Org's classic `org-latex-preview` still works as a
fallback when `org-latex-to-svg-mode` is off. `org-startup-with-latex-preview`
is **not** set (the mode renders on the hook instead), and the old classic
stopgap (the `org-format-latex-options` `:scale`/`:foreground`/`:background`
settings plus the `enable-theme-functions` / `text-scale-mode-hook` recolour and
rescale hooks, and the `org-config-latex-preview-base-scale` defvar) was
removed — `org-latex-to-svg` supersedes all of it, doing the recolour/rescale
from cache instead of re-running LaTeX.

**Known v0 limitation:** each fragment compiles standalone, so cross-fragment
`\eqref` / equation numbering do not resolve in-buffer (numbered environments
show `(1)`); export is unaffected. Numbering + `\eqref` (via a `label → number`
map and a `\setcounter` injected into the per-fragment LaTeX, which folds into
the engine's content hash) is a planned `org-latex-to-svg` milestone. See that
package's repo for details.

## Babel (Python)

- Languages loaded: `(python . t)` only.
- `org-confirm-babel-evaluate nil` — no confirmation prompt on `C-c C-c`
  in trusted files. Switch to a predicate function if selective confirmation
  is ever needed.
- Default Python header args: `:results output :exports both`. Deliberately
  minimal — matplotlib-specific setup (Agg backend, SVG savefig format,
  imports, rcParams) lives in per-file setup blocks or `yasnippets/org-mode/`,
  not here. Don't accumulate global babel defaults.
- `org-display-inline-images` hooked on `org-babel-after-execute-hook` so
  plot output appears immediately after the block runs.

## Org-edit-special (`C-c '`) tuning

Three settings, all load-bearing for the Python-LSP-in-babel workflow in
`lsp-python-config.el`:

| Setting                          | Value             | Why                                                                                                |
| -------------------------------- | ----------------- | -------------------------------------------------------------------------------------------------- |
| `org-src-window-setup`           | `'current-window` | reuse the current window instead of rearranging the frame                                          |
| `org-src-tab-acts-natively`      | `t`               | language's own indentation behavior applies inside the edit buffer (Python indent works naturally) |
| `org-src-preserve-indentation`   | `t`               | source block's leading whitespace round-trips on `C-c '` exit                                      |

## Image display

`(setq org-image-actual-width '(800))` — note the **list form `(800)`**,
not bare `800` and not `t`. The list form enables the per-image fallback
mechanism: `#+ATTR_ORG: :width Npx` / `#+ATTR_HTML: :width Npx` overrides
for individual images. Bare `800` or `t` would disable that fallback.

## `org-appear` settings

- `org-appear-autoemphasis t` — show `*foo*` markers when cursor is inside.
- `org-appear-autolinks t` — same for links.
- `org-appear-autosubmarkers t` — same for sub/superscripts.
- `org-hide-emphasis-markers nil` — markers shown by default; toggle with
  `C-c t e` (`my/org-toggle-emphasis-markers`).

## Invariants — do not change without reading

### `org-tempo` needs explicit `(require ...)`

Not auto-loaded since Org 9.2. Without it, `<s TAB`, `<q TAB`, etc. for
structure-block expansion stop working silently.

### `org-image-actual-width` must be `(800)`, not `800`

The list form `(N)` enables the per-image `#+ATTR_*: :width Npx`
override fallback. Bare integer or `t` disables it.

### Python babel header args are deliberately minimal

`:results output :exports both` and nothing else. Matplotlib (Agg backend,
SVG savefig, imports, rcParams) lives in per-file setup blocks or
yasnippets. Resist adding global header args here.

### `:results output` not `:results value`

Captures the entire stdout from a Python REPL, including print() calls.
`value` would only return the last expression's value.

### Math preview lives in `org-latex-to-svg`, not the fork

Math rendering is owned by the homegrown `org-latex-to-svg` (over `latex-to-svg`),
wired in at the bottom of the file. Do NOT resurrect the tecosaur fork
dependency for math. Enhancements (per-keystroke live update, reveal-on-cursor,
equation numbering, `\eqref`) belong in those packages'
(`~/Documents/Programming/Emacs/{latex-to-svg,org-latex-to-svg}`) repos, not
here. `org-config.el` only wires the mode on and keeps classic `org-latex-preview`
(dvisvgm) as an off-mode fallback. `org-karthink-config.el` remains unloaded,
kept only for reference.
</content>
</invoke>
