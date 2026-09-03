# markdown-obsidian.el

Obsidian's two non-CommonMark link forms, rendered and followed in
`markdown-ts-mode`:

| Syntax | Meaning |
| ------ | ------- |
| `[[name]]`, `[[name\|alias]]` | wiki link |
| `![[file]]`, `![[file\|alias]]` | embed, shown as an inline image |

Loaded from the bottom of `markdown-config.el` when
`markdown-config-enable-obsidian` is non-nil. Off by default: nothing
here is CommonMark, and nothing here is needed for a Markdown file that
is not part of an Obsidian vault.

The load is one-way. This module borrows two names from
`markdown-config.el` — `markdown-config--link-keymap` (the shared,
parser-agnostic click keymap) and `markdown-config-follow-link-functions`
(the extension point) — and `markdown-config.el` names nothing from here.
That is what lets the option be off with no trace: the core file has no
wiki-link branch to skip.

The option is read at load time only. Set it in `custom.el` or before
`markdown-config` loads; toggling it in a running Emacs does nothing,
since the module installs its `markdown-ts-mode-hook` and its follow-link
handler when it loads.

## Path resolution

Obsidian's rules, not Emacs'. `markdown-obsidian--base-directory` picks
the directory a name resolves against, by the name's shape:

- A name containing a `/` is **vault-relative**: it resolves from the
  vault root, which is the nearest ancestor of the visited file holding a
  `.obsidian` directory (`markdown-obsidian--vault-root`). Outside any
  vault there is no root, so it falls back to the visited file's own
  directory and following still does something sensible.
- A **bare** name (no `/`) always resolves from the visited file's own
  directory.

Two callers layer on top:

- `markdown-obsidian--follow-wiki-link` appends `.md` when the name has
  no extension, then opens: `.md`/`.markdown` via `find-file`, anything
  else via `dired` with point on the target, a missing path as
  `user-error`. **Never creates empty files.**
- `markdown-obsidian--resolve-wiki-path` appends nothing — an embed names
  its target as written, image extension included.

## Rendering — one font-lock keyword

The grammar has no `wiki_link` node (see the invariant below), so
`markdown-obsidian--wiki-link-fontify` is a `re-search-forward` keyword
layered on top of the tree-sitter rules by
`markdown-obsidian--setup`, which is appended to `markdown-ts-mode-hook`
so it runs after `markdown-config--markdown-ts-mode-setup`. Per match:

1. Splits the inner content on `|` to find the visible label (alias when
   present, name otherwise).
2. Restricts match data to the label range, so
   `markdown-obsidian-wiki-link-face` (inherits `link`) covers the label
   only.
3. Adds `mouse-face`, `keymap` and `help-echo` over the **whole** link
   span — `[[`, `]]` and an embed's leading `!` included, not just the
   label — so a click lands regardless of `markdown-ts-hide-markup`: with
   markup shown the brackets are visible and must be clickable, and with
   markup hidden they carry harmless, undisplayed properties. The keymap
   is `markdown-config--link-keymap`, so RET, `mouse-1` and `mouse-2`
   behave exactly as they do on the buttons the mode makes itself.
4. When `markdown-ts-hide-markup` is non-nil, marks the surrounding
   markup `invisible` against the `markdown-ts--markup` spec — the same
   spec as the bundled mode's other hidden markup, so
   `markdown-ts-toggle-hide-markup`'s `font-lock-flush` re-runs the
   matcher and the hiding follows the toggle. `invisible` is added to
   `font-lock-extra-managed-props` here, by this module alone.
5. For an embed, calls `markdown-obsidian--render-embed-image`.

## Embeds — two overlays, not one

`markdown-obsidian-inline-embed-images` (default `t`) controls whether
`![[file]]` renders as an image; `markdown-ts-inline-images` (the bundled
toggle) must also be on. With the option nil the embed keeps its literal
`![[file|alias]]` markup — still faced, clickable, target on hover — so
the un-rendered form can be inspected.

The rendered form is **two** overlays: a `display` of the image on the
embed's first character, and an `invisible` overlay over the rest of the
markup. Both are tagged `markdown-ts-image` so the bundled
`markdown-ts--remove-image-overlays` clears embed images along with the
grammar-node ones, and both are tagged `markdown-obsidian-embed-image` so
a refontify replaces rather than stacks them.

> **Why not one wide `display` overlay, and why not an `after-string`.**
> Both break smooth scrolling. An `after-string` has no buffer position,
> and prefixing it with a newline — the "image on its own line" idiom
> `markdown-ts--fontify-image` uses — puts the image on a phantom display
> line that `pixel-scroll-precision-mode` cannot anchor `window-start`
> to, so scrolling jumps by a whole image height (Emacs bug#64252). A
> `display` overlay over the whole markup is nearly as bad: these embed
> paths run ~180 characters, and a wide display span lets `window-start`
> park deep inside the image region, reviving the same one-image jump on
> scroll-up. Confining the image to a single buffer position leaves
> `window-start` nowhere to park.

This is also why an embed's alias is **not** rendered as a caption line —
that would need a phantom line too. A non-blank alias becomes the image's
`help-echo` instead, shown on hover. A bare `![[file]]` has no alias and
gets no hover label.

## Following

`markdown-obsidian--follow-link-at-point` is registered on
`markdown-config-follow-link-functions`, the abnormal hook
`markdown-config-follow-link-at-point` runs (with
`run-hook-with-args-until-success`) before its own CommonMark handling.
It matches `markdown-obsidian--wiki-link-regexp` around point, follows
group 1, and returns non-nil; on no match it returns nil and the
dispatcher carries on to the CommonMark branches.

## Invariants — do not change without reading

### Wiki links are detected by regex, not tree-sitter

`tree-sitter-markdown` does **not** expose `[[name]]` as a node type.
Both places that recognise a wiki link match text: the follow-link
handler via `markdown-obsidian--wiki-link-regexp`, and the font-lock
matcher via its own laxer regex inside `re-search-forward`. Don't rewrite
either as a treesit query — the query will silently return no nodes.

Forking `tree-sitter-markdown` to add a `wiki_link` node would mean
owning merge conflicts forever, building the parser `.so` on every
machine, and isolating this config from the rest of the tree-sitter
ecosystem (Helix, nvim-treesitter, GitHub), which would not see the node.
The regex cost is one bounded single-line pattern per visible window via
`jit-lock` — not measurable. The grammar cost is structural and ongoing.

### The hook must be appended

`markdown-obsidian--setup` is added to `markdown-ts-mode-hook` with
`add-hook`'s APPEND argument, so it runs after
`markdown-config--markdown-ts-mode-setup`, which `use-package`'s `:hook`
adds with a plain (prepending) `add-hook`. Both extend
`font-lock-extra-managed-props` and add keywords with `'append`; running
this one first would reverse the keyword order.

## Cross-module touchpoints

- `markdown-config.el` — owns the loading decision
  (`markdown-config-enable-obsidian`), the click keymap, and the
  follow-link dispatcher this module hooks.
- `treesitter-config.el` provides the `markdown` + `markdown-inline`
  grammar pair. The embed renderer reads `markdown-ts-inline-images` and
  `markdown-ts-image-max-width` from the bundled mode.
