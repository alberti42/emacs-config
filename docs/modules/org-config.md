# org-config.el

Org mode plus inline LaTeX previewing and Python babel.

## External packages

- **`org`** — installed from **tecosaur's fork** (`https://git.tecosaur.net/tec/org-mode.git`,
  branch `dev`), not mainline. The fork carries karthink's `org-latex-preview`
  with auto-preview, live updates, and dvisvgm SVG rendering. These features
  are not yet upstream. The custom straight recipe must appear before any
  package that depends on Org.
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

## LaTeX preview pipeline

| Setting                                       | Value          | Note |
| --------------------------------------------- | -------------- | ---- |
| `org-startup-with-latex-preview`              | `t`            | render all previews on file open |
| `org-startup-with-link-previews`              | `t`            | display inline images on file open |
| `org-latex-preview-numbered`                  | `t`            | consistent equation numbering |
| `org-latex-preview-mode-display-live`         | `t`            | live update while editing fragments |
| `org-latex-preview-process-default`           | `'dvisvgm`     | SVG output |
| `org-latex-preview-mode-update-delay`         | `0.25`         | down from default 1s |
| `org-latex-preview-appearance-options :page-width` | `0.8`     | avoids chopped formulas |
| `org-latex-preview-mode-ignored-commands`     | next/prev-line, mwheel-scroll, scroll-up/down | keep navigation responsive |

`org-latex-preview-mode` is enabled via `org-mode-hook`.

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
- `org-hide-emphasis-markers t` — markers hidden by default; `org-appear`
  reveals them on cursor proximity.

## Invariants — do not change without reading

### Tecosaur fork is required for live LaTeX preview

The recipe forks from `https://git.tecosaur.net/tec/org-mode.git` (branch
`dev`) specifically for karthink's preview features
(`org-startup-with-latex-preview`, `org-latex-preview-mode-display-live`,
dvisvgm rendering). Mainline Org doesn't have these. Reverting to mainline
means losing the preview pipeline.

### Pre-build hook synthesizes `org-version.el`

The fork doesn't ship `org-version.el`. Straight runs the `:pre-build`
form, which extracts the version string from `lisp/org.el`'s
`Version:` Lisp header (via `lisp-mnt`'s `lm-header`) and the short git
hash, then writes a stub providing `org-release` and `org-git-version`.
Without this, byte-compilation fails because `org-version` is `require`d
elsewhere.

### Stale `.fmt` purge runs in `:config`, before previews start

After a TeX Live upgrade, pdfTeX refuses precompiled preamble `.fmt`
files cached under `$XDG_CACHE_HOME/org-persist/` because their binary
fingerprint no longer matches. Org's cache key is the **preamble hash**,
not the engine, so the cache looks valid and the first preview fails
with exit 252 ("format file ... made by different executable version").

The `:config` block does a cheap mtime check: if `pdftex` is newer than
a `.fmt`, it was built against an older engine — delete it. Also deletes
the sibling metadata file (same stem minus the `-<preamble-hash>.fmt`
suffix). The next preview rebuilds via `pdftex -ini`.

This **must** run in `:config` (before `org-mode-hook` fires
`org-latex-preview-mode`); moving it to `:config` after `org-mode-hook`
or to `org-mode-hook` itself races with the first startup preview.

(Memory entry `project_org_latex_preview_stale_fmt` documents the
underlying bug; this code is the automatic cleanup.)

### `org-tempo` needs explicit `(require ...)`

Not auto-loaded since Org 9.2. Without it, `<s TAB`, `<q TAB`, etc. for
structure-block expansion stop working silently.

### `org-image-actual-width` must be `(800)`, not `800`

The list form `(N)` enables the per-image `#+ATTR_*: :width Npx`
override fallback. Bare integer or `t` disables it.

### Python babel header args are deliberately minimal

`:results output :exports both` and nothing else. Matplotlib (Agg backend,
SVG savefig, imports, rcParams) lives in per-file setup blocks or
yasnippets. Resist adding global header args here — different files have
different plotting/data needs and a global default makes per-file blocks
fight the config.

### `:results output` not `:results value`

Captures the entire stdout from a Python REPL, including print() calls.
`value` would only return the last expression's value. The `output` choice
is what makes typical research-notebook flows (print intermediate state,
show plots after) work without per-block overrides.

## Commented-out: `org-babel-eval-error-notify` advice

Lines 91–100 contain a commented-out `:around` advice that would suppress
the `*Org-Babel Error Output*` popup when the subprocess exited cleanly
(exit 0). `ob-eval.el` always pops that buffer whenever stderr is
non-empty, which is noisy for tools like matplotlib that print benign
warnings to stderr.

The advice writes to the buffer but doesn't pop it on success; non-zero
exits still pop. Inspectable via `M-x switch-to-buffer
*Org-Babel Error Output*`.

Currently disabled — uncomment if matplotlib/sklearn warnings start
spamming the popup.
