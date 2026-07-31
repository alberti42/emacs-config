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
`provide`/header updated, no `init.el` entry). Keep it as a reference or as a
basis for a homegrown math-rendering package.

Consequences of using built-in Org:

- **No live preview minor mode.** Mainline Org has no `org-latex-preview-mode`
  (the fork-only live mode). Math rendering is the classic on-demand
  `org-latex-preview` command (`C-c C-x C-l`), still using the dvisvgm backend.
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

## LaTeX preview pipeline (classic)

| Setting                             | Value        | Note |
| ----------------------------------- | ------------ | ---- |
| `org-startup-with-latex-preview`    | `t`          | render all previews on file open |
| `org-startup-with-link-previews`    | `t`          | display inline images on file open |
| `org-preview-latex-default-process` | `'dvisvgm`   | SVG output |
| `org-format-latex-options :scale`   | `1.5`        | on-screen size of fragment previews |

Preview is on-demand via `org-latex-preview` (`C-c C-x C-l`) — there is no
per-keystroke live mode in mainline Org. `org-startup-with-latex-preview t`
still renders everything on file open.

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

### Live math preview is a future homegrown-package concern

If per-keystroke live LaTeX preview is wanted again, do NOT resurrect the
tecosaur fork dependency. Either revive `org-karthink-config.el` deliberately
(understanding it is unmaintained) or build a small dedicated package. Built-in
Org intentionally stays fork-free here.
</content>
</invoke>
