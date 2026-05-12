# terminal-config.el

Terminal emulator setup: `term`, `eshell`, `vterm`, `ghostel`, plus the `ev`
"open in Emacs" `$EDITOR` integration.

## External packages

- `vterm` — libvterm-backed terminal emulator.
- `ghostel` — libghostty-vt-backed terminal emulator (~2× vterm throughput;
  adds Kitty keyboard protocol, OSC 8 hyperlinks, 5 underline styles, mouse
  passthrough, auto shell integration). The native module is downloaded on
  first use. The straight recipe pins a custom `:files` spec to keep the
  bundled `terminfo/` tree (both macOS hashed layout `78/xterm-ghostty` and
  Linux layout `x/xterm-ghostty`); without it, ghostel falls back to
  `xterm-256color` with a warning.

## Dependencies on other modules

- **`windows-config.el`** owns `tmux-map` on `C-b`. This module deliberately
  exposes `C-b` to Emacs in `vterm-mode-map`, `ghostel-mode-map`, and
  `ghostel-semi-char-mode-map` (the minor-mode map for ghostel's default
  input mode) so the prefix and `C-b <arrow>` window navigation work inside
  terminal buffers. Removing the C-b exposure breaks pane navigation.

## Invariants — do not change without reading

### vterm: use `setq` for `vterm-keymap-exceptions`, never `customize-set-variable` / `setopt` / `:custom`

Their `:set` handler calls `vterm--exclude-keys`, which unbinds `C-c` in
`vterm-mode-map` and wipes every `C-c X` binding (`C-c C-t` copy-mode, `C-c
C-l`, `C-c C-r`, `C-c C-n`, `C-c C-p`) that the `vterm-mode-map` defvar added
*after* the exclude pass. The handler only re-runs `vterm--exclude-keys`; it
does not replay the defvar, and vterm exposes no rebuild helper.

The current code uses `setq` to bypass the handler, then performs the
single excise manually for C-b. **Unbinding alone is not enough**:
`vterm-mode-map` has a `[t]` catch-all bound to `vterm--self-insert` that
forwards every otherwise-unbound key to the terminal, so a plain
`(define-key vterm-mode-map (kbd "C-b") nil)` would still leak C-b to the
shell. We must copy the global binding into `vterm-mode-map`, mirroring
the second step of `vterm--exclude-keys`:

```elisp
(define-key vterm-mode-map (kbd "C-b") (lookup-key global-map (kbd "C-b")))
```

This makes C-b a prefix in vterm-mode-map that resolves to the global
`tmux-map`.

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

### Forward keys with `*-send-string`, not `*-send-key`

`vterm-send-key` / `ghostel-send-key` go through the C module's
`vterm--update`, which re-encodes through the active escape mode. When an
app like Claude Code has enabled CSI-u mode, `C-@` becomes `^[[64;5u` instead
of `\C-@`. Always send raw bytes via `*-send-string`.

### Bind `C-@`, not `C-SPC`

Emacs resolves `C-SPC` to `set-mark-command` from `global-map` *before* the
mode map is consulted. `C-@` is the canonical terminal encoding for C-SPC
(NUL byte) and is the only form that reaches the mode map.

### vterm: `C-c C-c` → `vterm-send-C-c`

`C-c` is an Emacs prefix, so the literal SIGINT byte must be sent via the
`C-c C-c` chord explicitly bound to `vterm-send-C-c`.

## Key bindings (both emulators)

| Key       | Action                                                          |
| --------- | --------------------------------------------------------------- |
| `C-c C-c` | (vterm only) send SIGINT via `vterm-send-C-c`                   |
| `C-M-m`   | send `\e\r` (Shift/Alt+Enter; matches WezTerm remap)            |
| `C-g`     | send BEL (`\C-g`) so terminal apps receive it                   |
| `C-b`     | falls through to global `tmux-map` (windows-config.el)          |

`C-@` (C-SPC) bindings are present-but-commented in the source — uncomment
when needed.

## `ev` editor integration

Blocking "open in Emacs" for use as `$EDITOR` from a vterm/ghostel shell.
Flow:

1. Shell `ev` function runs `vterm_cmd ev-open-file FILE SEMAPHORE` (or the
   ghostel equivalent), then polls until `SEMAPHORE` exists.
2. `ev-open-file` opens `FILE` and binds `C-c C-q` to `ev-done`.
3. `ev-done` writes the semaphore file and buries the buffer, unblocking
   the shell process **without involving the Emacs server** (no
   `emacsclient`, no daemon required).

`ev-open-file` is registered in both `vterm-eval-cmds` and `ghostel-eval-cmds`.
