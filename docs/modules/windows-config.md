# windows-config.el

Window management modeled on tmux pane operations. Defines `tmux-map` on
`C-b` (shadowing `backward-char`) as the pane prefix.

External packages: none — all built on `windmove`, `winner-mode`, and
`repeat-mode`.

## Cross-module touchpoints

- **`terminal-config.el`** exposes `C-b` inside `ghostel-mode-map` and
  `ghostel-semi-char-mode-map` so the prefix and `C-b <arrow>` navigation work inside
  terminal buffers. Adding new `C-b` bindings here is automatically picked
  up there.
- `tmux-map` is added to `which-key-inhibit-regexps` so the popup does not
  flash on the prefix.
- Rebinds `C-x 2` / `C-x 3` (split + switch to other buffer) and `C-x m`
  (jump to active minibuffer, overriding `compose-mail`).

## Key bindings

All under the `C-b` prefix unless noted. Resize / join / unjoin / swap /
send-buffer all carry `:repeat t` keymaps — once entered, the modifier
chord can be repeated without `C-b` until `repeat-exit-timeout`.

| Key                | Action                                                    |
| ------------------ | --------------------------------------------------------- |
| `C-b <arrow>`      | move focus; falls through to `tmux select-pane` at edge   |
| `C-b C-<arrow>`    | resize (arrow = direction the shared border moves)        |
| `C-b S-<arrow>`    | join window into split adjacent to neighbour              |
| `C-b M-S-<arrow>`  | unjoin: move window out of its stack, beside the stack    |
| `C-b M-<arrow>`    | swap buffers with adjacent window                         |
| `C-b C-M-<arrow>`  | send current buffer to adjacent window; focus follows     |
| `C-b w <n>`        | select window `n`                                         |
| `C-b M-w <n>`      | swap buffers with window `n`                              |
| `C-b C-M-w <n>`    | send current buffer to window `n`; focus follows          |
| `C-b W <n>`        | join window `n`                                           |
| `C-b M-W <dir>`    | unjoin toward `l`/`r`/`u`/`d` or an arrow                 |
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

### Numbered windows

`C-b w`, `C-b M-w`, `C-b C-M-w` and `C-b W` draw a number in every window
and act on the window whose number is typed, as the arrow forms act on the
neighbour. Numbers follow `window-list` from `frame-first-window`, so they
do not depend on which window is selected; only 1–9 exist. The number
replaces the first character shown in the window through a `display`
overlay, so no text moves. Any non-digit key quits. `C-b M-W` draws no
numbers: unjoin has no target window, so it reads a direction
(`l`/`r`/`u`/`d` or an arrow) instead.

`C-b W <n>` has no arrow to say how to split the target, so
`windows-config--join-side` derives it: a target left or right of the
selected window is split `below`, one above or below is split `right` (what
the matching `S-<arrow>` does), and a diagonal target is split along its
longer side.

### Unjoin splits the parent before deleting

`windows-config--unjoin` splits the window's parent (the stack) on the
chosen side, then deletes the window. The other order breaks a stack of two:
deleting one window dissolves the parent, and there is no stack left to
split. `<left>`/`<right>` require a vertical stack, `<up>`/`<down>` a
side-by-side row. When the whole frame is one stack, the parent is the root
window and the window lands at the frame edge.

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
