# windows-config.el

Window management modeled on tmux pane operations. Defines `tmux-map` on
`C-b` (shadowing `backward-char`) as the pane prefix.

External packages: none — all built on `windmove`, `winner-mode`, and
`repeat-mode`.

## Cross-module touchpoints

- **`terminal-config.el`** exposes `C-b` inside `vterm-mode-map` and
  `ghostel-mode-map` so the prefix and `C-b <arrow>` navigation work inside
  terminal buffers. Adding new `C-b` bindings here is automatically picked
  up there.
- `tmux-map` is added to `which-key-inhibit-regexps` so the popup does not
  flash on the prefix.
- Rebinds `C-x 2` / `C-x 3` (split + switch to other buffer) and `C-x m`
  (jump to active minibuffer, overriding `compose-mail`).

## Key bindings

All under the `C-b` prefix unless noted. Resize / join / reflow / swap /
send-buffer all carry `:repeat t` keymaps — once entered, the modifier
chord can be repeated without `C-b` until `repeat-exit-timeout`.

| Key                | Action                                                    |
| ------------------ | --------------------------------------------------------- |
| `C-b <arrow>`      | move focus; falls through to `tmux select-pane` at edge   |
| `C-b C-<arrow>`    | resize (arrow = direction the shared border moves)        |
| `C-b S-<arrow>`    | join window into split adjacent to neighbour              |
| `C-b M-S-<arrow>`  | reflow: join if neighbour exists, else full-edge split    |
| `C-b M-<arrow>`    | swap buffers with adjacent window                         |
| `C-b C-M-<arrow>`  | send current buffer to adjacent window; focus follows     |
| `C-b %`            | split right and switch to other buffer                    |
| `C-b "`            | split below and switch to other buffer                    |
| `C-b x`            | `delete-window`                                           |
| `C-b z`            | toggle single-window zoom (winner-aware)                  |
| `C-b b`            | forward prefix to tmux (so `C-b b c/n/p/d/b` reach tmux)  |
| `C-x 1`            | same as `C-b z` — winner-undo if already single, else `delete-other-windows` |
| `C-x 2` / `C-x 3`  | split + switch to other buffer (overrides default mirror) |
| `C-x m`            | jump to active minibuffer                                 |

## Invariants — do not change without reading

### Resize semantics swap at frame edges

When a window exists on the side the arrow points to, the corresponding
border is moved. At the frame edge (no neighbour), the *opposite* border is
moved and the enlarge/shrink actions are swapped, so arrow direction always
matches the visible border movement. See the comments in
`windows-config-resize-{right,left,up,down}` for the truth table. Don't
"simplify" this into unconditional `enlarge-window` calls.

### Tmux dispatch table uses explicit per-key bindings, not `[t]` catch-all

`windows-config-tmux-key-commands` lists `c/n/p/d/b` and the `dolist` binds
each key explicitly in `tmux-map`. A `[t]` catch-all would interfere with
arrow-key escape-sequence assembly in terminals — the prefix would intercept
the `\e[` continuation and the arrow keys would never decode.

### Reflow vs join

`windows-config-reflow-*` (M-S-arrow) is "always move": it calls
`windows-config-join-*` when a neighbour exists, but at the frame edge it
deletes the window and re-splits the frame root window on that side. This
is what keeps reshaping unstuck — without it, S-arrow would silently
no-op at the edge.

### tmux detection is daemon-aware

`windows-config--in-tmux-p` reads the *frame's* `environment` parameter
first (which reflects the connecting client when running as a daemon) and
only falls back to `getenv "TMUX"`. A plain `getenv` here would
mis-detect when an `emacsclient` from inside tmux connects to a daemon
launched outside.

### `C-x 1` toggle test

`windows-config-toggle-delete-other-windows` uses `(equal (selected-window)
(next-window))` to detect "already single window" and call `winner-undo`
instead. `one-window-p` would also work but `(equal ... (next-window))` is
the existing form — don't churn it.
