# terminal-config.el

Terminal emulator setup: `term`, `eshell`, `ghostel`, plus the `ev`
"open in Emacs" `$EDITOR` integration.

## External packages

- `ghostel` — libghostty-vt-backed terminal emulator (Kitty keyboard
  protocol, OSC 8 hyperlinks, 5 underline styles, mouse passthrough, auto
  shell integration). The native module is downloaded on first use. The
  straight recipe pins a custom `:files` spec to keep the bundled
  `terminfo/` tree (both macOS hashed layout `78/xterm-ghostty` and Linux
  layout `x/xterm-ghostty`); without it, ghostel falls back to
  `xterm-256color` with a warning.

## Dependencies on other modules

- **`windows-config.el`** owns `tmux-map` on `C-b`. This module deliberately
  exposes `C-b` to Emacs in `ghostel-mode-map` and
  `ghostel-semi-char-mode-map` (the minor-mode map for ghostel's default
  input mode) so the prefix and `C-b <arrow>` window navigation work inside
  terminal buffers. Removing the C-b exposure breaks pane navigation.

## Invariants — do not change without reading

### ghostel: the real interceptor is `ghostel-semi-char-mode-map`, not `ghostel-mode-map`

ghostel's default input mode is the minor mode `ghostel-semi-char-mode`,
and *its* keymap shadows the major-mode map. The minor-mode map is built
at load time by `ghostel--define-terminal-keys`, which binds every
`C-<letter>` not listed in `ghostel-keymap-exceptions` to a lambda that
forwards the ASCII control code to the terminal. So C-b gets a "send ^B"
lambda unless excluded — and `add-to-list 'ghostel-keymap-exceptions
"C-b"` in `:config` runs *after* the map is built, with no retroactive
effect.

The fix is to rebind C-b explicitly in both `ghostel-mode-map` *and*
`ghostel-semi-char-mode-map`, pointing at the global `tmux-map` prefix:

```elisp
(define-key ghostel-mode-map           (kbd "C-b") (lookup-key global-map (kbd "C-b")))
(define-key ghostel-semi-char-mode-map (kbd "C-b") (lookup-key global-map (kbd "C-b")))
```

The `add-to-list` call is kept so any future rebuild of the map picks up
the exception via the normal mechanism.

Note: `ghostel-char-mode-map` is intentionally *not* patched. char mode is
designed to forward every key — including C-b — to the terminal.

### Forward keys with `ghostel-send-string`, not `ghostel-send-key`

`ghostel-send-key` goes through the C module's update path, which
re-encodes through the active escape mode. When an app like Claude Code has
enabled CSI-u mode, `C-@` becomes `^[[64;5u` instead of `\C-@`. Always send
raw bytes via `ghostel-send-string`.

### Bind `C-@`, not `C-SPC`

Emacs resolves `C-SPC` to `set-mark-command` from `global-map` *before* the
mode map is consulted. `C-@` is the canonical terminal encoding for C-SPC
(NUL byte) and is the only form that reaches the mode map.

## Key bindings

| Key       | Action                                                          |
| --------- | --------------------------------------------------------------- |
| `C-M-m`   | send `\e\r` (Shift/Alt+Enter; matches WezTerm remap)            |
| `C-g`     | send BEL (`\C-g`) so terminal apps receive it                   |
| `C-b`     | falls through to global `tmux-map` (windows-config.el)          |

`C-@` (C-SPC) bindings are present-but-commented in the source — uncomment
when needed.

## `ev` editor integration

Blocking "open in Emacs" for use as `$EDITOR` from a ghostel shell. Flow:

1. Shell `ev` function runs `ghostel_cmd ev-open-file FILE SEMAPHORE`, then
   polls until `SEMAPHORE` exists.
2. `ev-open-file` opens `FILE` and binds `C-c C-q` to `ev-done`.
3. `ev-done` writes the semaphore file and buries the buffer, unblocking
   the shell process **without involving the Emacs server** (no
   `emacsclient`, no daemon required).

`ev-open-file` is registered in `ghostel-eval-cmds`.
