# scroll-config.el

Scroll parameters, pixel-precise vertical scrolling via the built-in
`pixel-scroll-precision-mode`, and a smart horizontal-scroll handler that
suppresses no-op scrolls in wrapped buffers.

## Backend

Vertical smooth scrolling is the **built-in** `pixel-scroll-precision-mode`,
running on a locally patched Emacs whose mode:

- suspends `scroll-margin` for the duration of a wheel gesture and restores it
  — repositioning point to honor it — once scrolling (including any momentum
  tail) stops, so a non-zero `scroll-margin` no longer fights smooth
  scrolling; and
- fixes the tall-inline-image scroll jumps (Emacs bug#64252).

`ultra-scroll` was previously offered as an alternative backend solely to work
around those image jumps; with the upstream fixes in place it has been removed,
and the built-in backend is the only one. TTY frames are unaffected (the wheel
steps by lines).

## Cross-module touchpoints

- **`welcome-config.el`** swallows wheel events on the splash buffer via
  `minor-mode-overriding-map-alist` keyed on `pixel-scroll-precision-mode`.
- **`pdf-tools-config.el`** redirects wheel events to `mwheel-scroll` in PDF
  buffers, also via `minor-mode-overriding-map-alist` keyed on
  `pixel-scroll-precision-mode`, so pdf-view handles them.
- **`init.el`** sets `scroll-config-suppress-hscroll` (buffer-local) in
  terminal/shell mode hooks (ghostel, term, eshell, shell). See the invariant
  on `truncate-lines` below.

## Public API

| Symbol                                     | Purpose                                                              |
| ------------------------------------------ | ------------------------------------------------------------------- |
| `scroll-config-horizontal`                 | wheel handler bound to `wheel-left`/`wheel-right` (all 3 speed tiers)|
| `scroll-config-suppress-hscroll` (defvar)  | buffer-local opt-out — set non-nil where hscroll is meaningless      |
| `scroll-config-scroll-margin` (defvar)     | lines of edge context; drives `scroll-margin` and `recenter-positions` |

## Settings

| Setting                                              | Value | Why                                                       |
| --------------------------------------------------- | ----- | --------------------------------------------------------- |
| `scroll-margin`                                      | `4` (`scroll-config-scroll-margin`) | edge context; suspended during a gesture by the patched mode |
| `scroll-conservatively`                             | `101` | scroll minimally instead of recentering                   |
| `scroll-step`                                        | `1`   |                                                           |
| `scroll-preserve-screen-position`                   | `t`   |                                                           |
| `hscroll-margin`                                     | `2`   |                                                           |
| `hscroll-step`                                       | `1`   |                                                           |
| `pixel-scroll-precision-reposition-point`           | `t`   | on settle, move point to honor the restored `scroll-margin` |
| `pixel-scroll-precision-settle-delay`               | `0.18`| idle delay after the last scroll event before settling    |
| `pixel-scroll-precision-hide-cursor-while-scrolling`| `nil` | keep the cursor visible while scrolling                   |

`recenter-positions` is set to `(middle N -N)` where `N` is
`scroll-config-scroll-margin`, so `C-l` cycles middle → N lines from top → N
from bottom.

## Vertical paging — `C-v` / `M-v` / `PgUp` / `PgDn`

Rebound globally to scroll by **10 lines** (down from the default ~half-window).
`scroll-other-window` (`M-PgDn`) and `scroll-other-window-down` (`M-PgUp`) use
the same step.

## Horizontal scrolling

`scroll-config-horizontal` is bound to `wheel-left`/`wheel-right` at all three
speed tiers (`""`, `"double-"`, `"triple-"`). Three execution paths depending
on the event payload:

1. **Pixel-precise** (trackpad / Magic Mouse on macOS): `(nth 4 event)` carries
   `(COLS . PIXELS)`. Pixel deltas accumulate in
   `scroll-config--hscroll-residual` so slow swipes contribute sub-character
   pixel amounts that aren't silently truncated.
2. **Column-delta**: when `cdr` is 0.0 the gesture was already encoded in
   column units; use `car` directly without pixel math.
3. **Fallback**: physical tilt wheel with no pixel data — fixed 3-column step.

`<C-wheel-up>` / `<C-wheel-down>` (and the X mouse-4/-5 variants) are bound to
`ignore` to disable accidental ctrl+scroll zoom. Use the keyboard for font size.

## Suppression: when does horizontal scroll do nothing?

`scroll-config--hscroll-allowed-p` gates each event per direction:

- **`scroll-config-suppress-hscroll` non-nil** → suppress unconditionally
  (terminal-style buffers whose content the child process already wraps to the
  window width, so there is nothing to reveal).
- Otherwise it consults the C primitives `window-truncated-on-left-p` /
  `window-truncated-on-right-p` (added in the local truncation-flag patch),
  which report whether the most recent redisplay actually drew a truncation
  indicator on that edge. A wheel event is allowed only when its edge is
  truncated (there is hidden content to reveal). This is preferable to
  `(> (window-hscroll) 0)` because it handles right-to-left paragraph
  direction correctly, and — because it reflects what was actually drawn — it
  has none of the old "truncation on but every line fits" false positive.
  When the primitives are unavailable (an older build), scrolling is always
  allowed.

When suppression applies, the residual accumulator is cleared so a stale carry
from a different window cannot leak through.

## Invariants — do not change without reading

### `pixel-scroll-precision-mode-map` `<next>` / `<prior>` are unbound

```elisp
(define-key pixel-scroll-precision-mode-map (kbd "<next>")  nil)
(define-key pixel-scroll-precision-mode-map (kbd "<prior>") nil)
```

The mode's minor-mode map binds `<next>` / `<prior>` to
`pixel-scroll-interpolate-*`, which shadows the 10-line PgUp/PgDn rebindings set
globally just below. Without this unbind, PgUp/PgDn revert to the interpolated
half-window steps and the 10-line setting silently fails.

### `scroll-config-suppress-hscroll` is decoupled from `truncate-lines`

Terminal emulators (ghostel, term, eshell, shell) **require `truncate-lines t`**
so the full window width is reported to the child process. Flipping
`truncate-lines nil` in those buffers would steal a column for the continuation
glyph and shell prompts would overflow by one character (memory:
`feedback_truncate_lines_in_terminals.md`). The hscroll suppression is therefore
a separate buffer-local variable; terminal mode hooks set
`scroll-config-suppress-hscroll t` without touching `truncate-lines`.

### Pixel-residual accumulator must persist across events

The trackpad emits many sub-column deltas. Without
`scroll-config--hscroll-residual` accumulating across events, slow swipes
truncate to zero columns and feel "stuck". It is cleared only when a non-pixel
column path executes (column-delta or fallback) or when suppression applies.

### All three wheel-speed tiers must be bound

Emacs reclassifies rapid successive wheel events as `double-wheel-*` and
`triple-wheel-*` (same machinery as mouse-click multipliers). A handler bound
only to `wheel-left`/`wheel-right` stops responding when you swipe fast. The
`dolist` over `'("" "double-" "triple-")` covers all three.
