# ui-config.el

Visual presentation layer: UI chrome, frame chrome, window dividers,
display-table glyphs, per-frame centering, TTY mode-line tweaks, macOS
modifier handling, and TTY emoji opt-in.

External packages: none — all built on built-in Emacs functionality.

## Cross-module touchpoints

- **`early-init.el`** sets the default font face and the `fixed-pitch`
  inheritance.
- **`welcome-config.el`** also sets `inhibit-startup-screen t`. This
  module sets it too; the duplicate is harmless but redundant — either
  could be considered authoritative.
- **`terminal-config.el`** complements the macOS modifier handling here:
  the `ns-*-modifier` settings only affect the GUI; terminal emulators
  manage their own modifier interpretation.
- **`themes-config.el`** + **`theme-harmonize.el`** handle the
  *colors*; this module handles the *structure* (chrome, dividers,
  glyphs).

## What it disables

| Setting                  | Value      | Why                                           |
| ------------------------ | ---------- | --------------------------------------------- |
| `inhibit-startup-screen` | `t`        | suppress GNU splash; welcome buffer takes over (welcome-config.el) |
| `ring-bell-function`     | `'ignore`  | no audible/visible bells                      |
| `menu-bar-mode`          | off        | per-frame `menu-bar-lines 0` reinforces this  |
| `tool-bar-mode`          | off        |                                               |
| `scroll-bar-mode`        | off        |                                               |
| `tooltip-mode`           | off        | use minibuffer prompts instead                |
| `use-dialog-box`         | `nil`      | minibuffer prompts, never GUI dialogs         |
| `use-file-dialog`        | `nil`      | likewise for file pickers                     |

## Window dividers (GUI)

`window-divider-mode 1` with `bottom-only` placement and
`bottom-width 2`. Treemacs and the right-side vertical border are drawn
by Emacs's built-in window-divider machinery; this module adds a matching
2px bar between the mode-line and minibuffer.

## Display-table glyphs

`special-glyphs` face inherits from `(shadow default)` so truncation/
wrap glyphs use the `shadow` style on the editor's default background.

| Slot              | Glyph | Codepoint | Why                                                     |
| ----------------- | ----- | --------- | ------------------------------------------------------- |
| `vertical-border` | `█`   | U+2588 (FULL BLOCK) | default `|` leaves visible gaps with most monospace fonts; FULL BLOCK draws a continuous bar |
| `truncation`      | `…`   | U+2026    | truncation indicator on long lines (TTY)                |
| `wrap`            | `↲`   | U+21B2    | continuation marker on wrapped lines (TTY)              |

GUI uses fringe bitmaps for these slots; setting them is harmless there.

## TTY mode-line trailing fill

```elisp
(setq-default mode-line-end-spaces
              '(:eval (unless (display-graphic-p) "")))
```

The default `mode-line-end-spaces` is `"%-"` (fill remaining mode-line
width with dashes). The override makes it empty in TTY frames, while GUI
frames stay on the default behavior (the `:eval` returns nil there, so
the spec falls back to whatever the theme uses).

The hook fires on `after-init-hook` so it runs after themes load and
won't be clobbered.

## Frame chrome (GUI)

Platform-specific:

| Platform | `default-frame-alist` adds                                     | Result                                                  |
| -------- | --------------------------------------------------------------- | ------------------------------------------------------- |
| macOS    | `(undecorated-round . t)`                                       | frameless with native rounded corners (emacs-plus only) |
| other    | `(undecorated . t)` and `(internal-border-width . 10)`          | frameless with manual padding                           |
| all GUI  | `(fullscreen . maximized)`                                      | open maximized                                          |

`(undecorated-round . t)` is **emacs-plus specific** — vanilla Emacs
doesn't support this frame parameter. Other GUI builds fall back to the
generic `undecorated` + internal border path.

## macOS modifier keys (GUI)

```elisp
(setq ns-alternate-modifier 'meta
      ns-right-alternate-modifier 'none)
```

Hands the **right** Option key to macOS for character composition
(e.g. `⌥u u → ü`, `⌥s → ß`), while **left** Option remains Meta for
Emacs. `'none` means "don't intercept; pass through to the system".

TTY composition is the terminal emulator's responsibility — these
settings only affect the Nextstep GUI build.

## Per-frame setup

Two functions wired to multiple hooks so direct launches, daemon
startup, and `emacsclient` frames all get the same treatment:

| Function                              | Hook(s)                                  | Purpose                                              |
| ------------------------------------- | ---------------------------------------- | ---------------------------------------------------- |
| `emacs-config-setup-frame`            | `emacs-startup-hook`, `after-make-frame-functions` | enforce no menu bar; in GUI: blink cursor, box shape, schedule centering |
| `emacs-config-center-frame`           | called from setup-frame via `run-at-time`| center frame on its current monitor                  |
| `emacs-config--activate-gui-frame`    | `server-after-make-frame-hook`           | best-effort focus/raise via `select-frame-set-input-focus` + `raise-frame` |

## TTY emoji opt-in

```elisp
(setq icons-tty-emoji t)
```

Tells Emacs's built-in `icons` library to use emoji glyphs in TTY frames.
The terminal emulator renders the codepoint directly.

`icons-tty-emoji` is provided by an emacs-plus patch
(`ttys-emoji-icons-fix`, cherry-pick of upstream commit
`4d789ea0d145a3c752a7930fa8fd3bcddd624c50`). On a vanilla Emacs build
without that patch, this `setq` creates an unused dynamic binding and the
TTY emoji feature is silently absent. If/when this lands in upstream
Emacs, the patch can be retired without any change here.

## Invariants — do not change without reading

### Per-frame `menu-bar-lines 0` is needed even with global `menu-bar-mode -1`

`emacsclient` GUI frames re-enable the menu bar by default, ignoring
the global mode setting. `emacs-config-setup-frame` hard-sets
`menu-bar-lines 0` per-frame so the menu bar stays off across all
clients. Removing this re-introduces the menu bar on emacsclient frames.

### Frame setup runs on TWO hooks

- `emacs-startup-hook` — direct `emacs` launch path.
- `after-make-frame-functions` — daemon and `emacsclient -c` path.

Removing either silently breaks one of the two launch modes. Keep both.

### `vertical-border` glyph: FULL BLOCK avoids font gaps

`█` (U+2588) renders as a solid continuous bar in every monospace font.
The default `|` shows visible gaps between line cells with most fonts —
the divider looks dotted instead of continuous. Don't restore `|`.

### `special-glyphs` face inherits from `(shadow default)`

Order matters: `default` is the base; `shadow` adds the dimming. A bare
`shadow` inheritance picks up its own background and clashes with the
editor's. Don't simplify to `:inherit shadow`.

### `(undecorated-round . t)` is emacs-plus only

The `undecorated-round` frame parameter exists in the emacs-plus
distribution; vanilla Emacs and most Linux builds will ignore it (no
error, no rounded corners). The branch on `(eq system-type 'darwin)` is
correct. Don't unify the two branches.

## Notes for future tidying

- `inhibit-startup-screen t` is set both here and in `welcome-config.el`.
  Either could own it; the duplicate is harmless but worth knowing about
  if the welcome module is ever removed (this one would still suppress
  the GNU splash).
- The TTY mode-line separator block has a comment describing an
  alternative form `(make-string 500 ?─)` that fills the trailing space
  with U+2500 horizontal-line glyphs. The active code uses `""`. The
  comment is documenting a not-currently-used alternative — keep or
  delete based on whether you might switch back.
