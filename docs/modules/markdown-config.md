# markdown-config.el

Markdown reading and authoring. Configures `markdown-ts-mode`
(tree-sitter backed, bundled with Emacs 31) and adds the handful of
things the bundled mode still does not do, all of them CommonMark:

- **Local-file link policy.** `markdown-ts--make-link-button` opens every
  schemeless destination with `find-file`, so clicking an image link
  lands a JPEG in `image-mode`. Rerouted so Markdown opens in a buffer
  and anything else lands in `dired` with point on the file.
- **Bracketed and percent-encoded image paths.**
  `markdown-ts--fontify-image` resolves the raw node text with a bare
  `expand-file-name`, so `![a](<path with spaces>)` and `%20`-encoded
  paths silently never render.
- **Collapsing code-fence lines while editing** — upstream hides whole
  fence lines in `markdown-ts-view-mode` only.
- **SVG math preview**, via the shared `latex-to-svg` front-end.

Anything upstream has since grown its own version of is **not** here:
inline-link markup hiding and click-to-follow are the mode's own job now
(`markdown-ts--fontify-link-node` makes real text buttons,
`markdown-ts--fontify-link-destination` hides the URL).

Obsidian's `[[wiki links]]` and `![[embeds]]` are not CommonMark and are
not here either — they live in `markdown-obsidian.el`, loaded from the
bottom of this file when `markdown-config-enable-obsidian` is non-nil.
See `docs/modules/markdown-obsidian.md`.

External packages: none. `markdown-ts-mode` is built-in and used as-is
(no vendored copy). No `markdown-mode` configuration block exists in this
file.

> **Preview — none in Emacs.** A succession of preview packages
> (`grip-mode`, then `markdown-live-preview-mode` + `markdown-preview-mode`)
> all dragged in classic `markdown-mode` — `markdown-preview-mode` in
> particular needed `markdown-mode` for HTML conversion, a `web-server`
> recipe workaround for a `:local-repo` basename collision with
> `simple-httpd`, and an `:around` advice to stop its minor-mode body from
> yanking the buffer out of `markdown-ts-mode`. That is a lot of machinery
> to do what one shell command does, so it was all removed. Render from a
> terminal with pandoc instead:
>
>     pandoc --from=gfm --to=html5 file.md -o file.html
>
> and pair it with a watcher (`entr`, `watchexec`, …) plus the browser's
> auto-reload for a live loop. Consult git history for the previous
> `markdown-preview-mode` configuration block if you want it back.

> **`markdown-mode` is not used here at all.** It is not configured, no
> hooks fire, no custom variables are tuned, and no preview package depends
> on it. It is installed only if some other package pulls it in as a
> dependency (e.g. `rustic`). (`lsp-mode` no longer requires it either —
> hover docs render via `markdown-ts-view-mode`; see
> `lsp-markdown-render-engine`.)

## File routing

`.md` and `.markdown` are routed directly to `markdown-ts-mode` via
`:mode` in this file's `use-package` block. There is no
`markdown-mode → markdown-ts-mode` entry in `major-mode-remap-alist`.
Should `markdown-mode` ever load (transitively, e.g. via `rustic`) it
prepends a broad-regex `auto-mode-alist` entry that would shadow the
built-in association; a `with-eval-after-load 'markdown-mode` guard
rewrites that entry's target back to `markdown-ts-mode`. No `gfm-mode`
mapping (README.md is handled the same as any other `.md`).

## Link helpers

- `markdown-config--follow-local-link` — resolves a `[label](path)`
  destination as a local path and opens it by type: `.md`/`.markdown` via
  `find-file`, other files via `dired` with point on the target, missing
  paths as `user-error`. Returns `t` when handled (local) and `nil` for
  full URLs so the caller can fall back to `browse-url`. **Never creates
  empty files.** Used both by the dispatcher and by the rerouted link
  buttons, so a click and a keystroke land in the same place.
- `markdown-config--normalize-link-path` — strips a `<…>` wrapper and
  percent-decodes, but only when the path actually contains a `%XX`
  escape, so a plain path is returned unchanged and a literal `%` in a
  filename is left alone.
- `markdown-config--inline-link-destination-at-point` — walks up to the
  `inline_link` ancestor of the node at point, reads the
  `link_destination` child's text, and strips a matched `<…>` pair.
  Returns nil when not on a link.
- `markdown-config-follow-link-at-point` — the dispatcher on
  `markdown-config--link-keymap`. Cond order:
  1. `markdown-config-follow-link-functions` via
     `run-hook-with-args-until-success` — the extension point where an
     optional module registers a non-CommonMark syntax of its own.
  2. `[label](path)` via the treesit helper above.
  3. Bare URL at point via `thing-at-point 'url`.
  4. Otherwise `user-error "No link at point"`.

## Keybindings

None are added to `markdown-ts-mode-map`. Following a link is the
bundled mode's own gesture: `markdown-ts--fontify-link-node` makes every
inline link, reference link, autolink and bare URL a real text button,
and `button-map` binds `RET` and `mouse-2` to `push-button` with
`mouse-1` following via `mouse-1-click-follows-link`.

`markdown-config--link-keymap` gives the *same three gestures* to the
links that never become buttons — whatever an optional link-syntax
module attaches it to:

| Key | Command |
| --- | ------- |
| `RET`, `mouse-1`, `mouse-2` on such a link | `markdown-config-follow-link-at-point` |

Reaching for a separate chord (`C-c C-o` and the like) would be a second
way to do what `RET` already does, so there isn't one.

## Bundled link and image fixes

Two `:around` advices, sharing `markdown-config--normalize-link-path`:

- **`markdown-ts--fontify-image`** resolves an image's
  `link_destination` with a bare `expand-file-name` on the raw node text,
  so `![a](<path with spaces>)` keeps its literal `<>` and a `%20`-encoded
  path keeps its escapes — both then fail the `file-exists-p` guard and
  the image silently never renders. The advice normalizes the
  destination by rebinding the one `treesit-node-text` call the fontifier
  makes, guarded to `link_destination` nodes, for the dynamic extent of
  the original.

  > **Why hook `treesit-node-text` and not `expand-file-name`.**
  > `expand-file-name` is a C primitive, and redefining it forces
  > native-comp trampoline rebuilds on every fontify pass.
  > `treesit-node-text` is a native-compiled Lisp function
  > (`subr-native-elisp-p`), so rebinding it needs no trampoline.

- **`markdown-ts--make-link-button`** gives every schemeless destination
  a stock `find-file` action, so clicking an image or link button opens
  the target in a buffer (a JPEG in `image-mode`) whatever its type. The
  advice builds the stock button, then reroutes schemeless (local-file)
  buttons through `markdown-config--follow-local-link` so they obey the
  same policy as the dispatcher. URLs, `mailto:` and `#fragment` targets
  keep the stock action.

## Rendering (markdown-ts-mode only)

`markdown-ts-mode-hook` runs
`markdown-config--markdown-ts-mode-setup`, which turns on the code-fence
collapse machinery. Inline links in
prose need nothing from it — the bundled rules hide the brackets, parens
and URL under `markdown-ts-hide-markup` and make the label a button.

### Inline links inside tables

The bundled inline-link rules only fire where a **local**
`markdown-inline` parser runs, and the range rule embeds one on host
`(inline)` nodes only — `((inline) @markdown-inline)`. A
`pipe_table_cell` is not an `inline` node: `treesitter-explore` shows
`(pipe_table_cell [ . _ . ] ( . _ . ))` where a paragraph shows
`(inline … (inline_link …))`. So by itself the mode runs no local
parser on a cell and renders nothing inside a table.

Note the qualifier. The *global* `markdown-inline` parser does parse the
whole buffer text and a whole-buffer query against it will happily
return an `inline_link` inside a table row. That is a different parser
instance from the ones font-lock uses, so it proves nothing about
rendering — don't let it mislead you into thinking the gap is closed.

`markdown-table-view-mode` (the `markdown-table-view` package, enabled
from `markdown-ts-mode-hook` in this file) adds a rule to the buffer-local
`treesit-range-settings` that runs `markdown-inline` on `pipe_table_cell`
nodes too. The bundled rules then fontify, hide and follow links in a
cell as they do in a paragraph, and nothing in this file handles tables.
With that mode off, a link in a table is plain text.

### Code-fence collapse + reveal-on-edit

With `markdown-ts-hide-markup` on, the bundled fontifier marks only the
fence delimiter *text* invisible and leaves the line's newline live, so
every hidden fence leaves a stray blank row. (Upstream collapses whole
fence lines in `markdown-ts-view-mode` only.)
`markdown-config--collapse-fence-line`, `:after` advice on
`markdown-ts--fontify-delimiter`, hides the whole physical line —
newline included — with an overlay `display` of `""`, which renders the
range as nothing and pulls the next line up. It also drops the host's
`invisible` text property on the node, so a revealed fence shows its
real text including the language tag.

> **Why an overlay `display` and not the `invisible` property.**
> `reveal-mode` reveals *overlays* only (it scans `overlays-at`), and
> only those hidden via ellipsis-`invisible` or a `display` property
> carrying a `reveal-toggle-invisible` function. A plain `invisible`
> overlay or property is invisible to it, and ellipsis would render a
> literal `…` on the row. `display` `""` plus a toggle function is the
> only form that both fully removes the line and is revealable.

Both of a block's fence overlays are created together from parse-tree
positions and cross-linked via `markdown-config-fence-sibling`, so
opener and closer reveal and re-collapse as a pair — and so the closer's
overlay exists even before that line has been fontified or scrolled into
view. The sibling link is stored at fontify time, where the parse tree
is solid, rather than looked up inside the toggle: a toggle-time treesit
lookup fails when the closing fence has not been fontified yet, and
`reveal-mode`'s `with-demoted-errors` swallows the error, so the opener
toggles and the closer silently does not.

`markdown-config--prune-fence-overlays`, a `treesit-parser` notifier,
drops overlays in a reparsed region whose `fenced_code_block` is gone.

Skipped entirely in `markdown-ts-view-mode`: that read-only mode already
hides whole fence lines via the host's `invisible` property, and
swapping it for an overlay `display` would break off-screen consumers
that extract the buffer with `buffer-substring` — notably `lsp-mode`'s
hover and signature rendering, which does not capture overlays.

## SVG math preview

`latex-to-svg-for-markdown` is the Markdown adaptor of the shared
`latex-to-svg-frontend` core, enabled in every Markdown buffer via
`markdown-config--latex-to-svg-setup`. The core detects `$…$`, `$$…$$`,
`\(…\)`, `\[…\]` and `\begin{env}…\end{env}` with a
blank-line-bounded scanner and overlays each with an SVG compiled once
(content-addressed), re-tinting on theme switch and re-scaling on text
zoom straight from cache — no LaTeX recompile. The adaptor supplies
Markdown's code and verbatim exclusions.

Per-mode sizing is buffer-local and set here before the adaptor turns
the core on: `latex-to-svg-frontend-rescale-inline` 1.20 and
`latex-to-svg-frontend-rescale-display` 1.25, on top of the engine's
global `latex-to-svg-backend-font-scale`.

`latex-to-svg-config.el` registers the engine and core recipes and
`init.el` loads it first, so straight resolves this adaptor's
dependencies from the local `latex-to-svg` checkout.

## Performance

- Inline links (paragraphs): entirely the bundled tree-sitter rules,
  reusing nodes the parser already built. Nothing added here.
- Inline links (tables): the same bundled rules, on the local parsers
  `markdown-table-view-mode` runs on each cell.

The reasons `markdown-mode` is slow on large files do not apply here:

- No `markdown-fontify-code-blocks-natively` (a whole secondary major
  mode booted per fenced block).
- No `markdown-syntax-propertize` pass.
- No multiline regex keywords scanning the buffer.

## Invariants — do not change without reading

### Inline links are detected via treesit, not regex

For `[label](path)` **in paragraphs** we walk up to the `inline_link`
ancestor and read the `link_destination` child. This handles nested
brackets and escaped parens correctly; a regex-based detector would
mis-match. The grammar node names are stable — don't paraphrase them.

The pointy-bracket form `[label](<url with spaces>)` returns
`<url with spaces>` from `treesit-node-text` — angle brackets included.
`markdown-config--inline-link-destination-at-point` strips one matched
`<…>` pair before returning, so the follower sees a plain path.

### Advices name internal (double-underscore) upstream functions

`markdown-ts--fontify-image`, `markdown-ts--make-link-button` and
`markdown-ts--fontify-delimiter` are all internal symbols. Advising them
is deliberate — the alternative is inlining copies that drift from
upstream — but it means a rename upstream breaks this file loudly rather
than silently. The advices are the first thing to check after an Emacs
upgrade.

### Inline-link handling relies on the `markdown-inline` grammar

The bundled `link` face, the markup hiding, the buttons, and this file's
`markdown-config--inline-link-destination-at-point` all depend on
`markdown-inline` seeing complete `inline_link` constructs. If
inline-link fontification, hiding or following breaks, suspect the
`markdown-inline` range setup rather than this module.

### Adding a link syntax means using the extension point

A new non-CommonMark syntax registers on
`markdown-config-follow-link-functions` and adds its own font-lock
keyword from its own `markdown-ts-mode-hook` entry, the way
`markdown-obsidian.el` does. Don't add a branch to
`markdown-config-follow-link-at-point` — the point of the hook is that
this file stays CommonMark-only and an unused syntax leaves no trace.

## Cross-module touchpoints

- `markdown-obsidian.el` — optional, loaded from the bottom of this file
  under `markdown-config-enable-obsidian`. It borrows the click keymap
  and the follow-link hook; nothing here names it back. See
  `docs/modules/markdown-obsidian.md`.
- `treesitter-config.el` provides the `split_parser` grammar pair
  (`markdown` + `markdown-inline`). Removing either entry breaks this
  module. There is no `markdown-mode → markdown-ts-mode` remap — file
  routing is via `:mode` in this file.
- `syntaxes/markdown.el` sets `fill-column 100` for `markdown-ts-mode`;
  `text-mode-hook` triggers `soft-wrap-mode` (because
  `markdown-ts-mode` derives from `text-mode`).
- `lsp-ltex-plus-config.el` may attach to `markdown-ts-mode` for
  grammar checking — orthogonal to this module.
