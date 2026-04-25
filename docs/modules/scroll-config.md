# scroll-config.el

Scroll parameters, pixel-precise vertical scrolling via `ultra-scroll`,
and a smart horizontal-scroll handler that suppresses no-op scrolls in
wrapped buffers.

## External packages

- `ultra-scroll` — pixel-precise GUI scrolling. Replaces (and internally
  activates) `pixel-scroll-precision-mode`. TTY frames are unaffected.

## Cross-module touchpoints

- **`welcome-config.el`** suppresses wheel events on the splash buffer
  via `minor-mode-overriding-map-alist` keyed on
  `pixel-scroll-precision-mode` — that minor-mode is the one ultra-scroll
  activates here.
- **`init.el`** sets `scroll-config-suppress-hscroll` (buffer-local) in
  terminal/shell mode hooks (vterm, ghostel, term, eshell, shell). See
  the invariant on truncate-lines below.

## Public API

| Symbol                                     | Purpose                                                       |
| ------------------------------------------ | ------------------------------------------------------------- |
| `scroll-config-horizontal`                 | wheel handler bound to `wheel-left`/`wheel-right` (all 3 speed tiers) |
| `scroll-config-suppress-hscroll` (defvar)  | buffer-local opt-out — set non-nil where hscroll is meaningless |

## Settings

| Setting                          | Value | Why                                                |
| -------------------------------- | ----- | -------------------------------------------------- |
| `scroll-margin`                  | `0`   | required by `ultra-scroll`; non-zero glitches it   |
| `scroll-conservatively`          | `101` | recommended by `ultra-scroll`                      |
| `scroll-step`                    | `1`   |                                                    |
| `scroll-preserve-screen-position`| `t`   |                                                    |
| `hscroll-margin`                 | `2`   |                                                    |
| `hscroll-step`                   | `1`   |                                                    |
| `ultra-scroll-hide-cursor`       | `t`   | hide cursor while scrolling, restore after         |
| `ultra-scroll-preserve-column`   | `nil` |                                                    |

## Vertical paging — `C-v` / `M-v` / `PgUp` / `PgDn`

Rebound globally to scroll by **10 lines** (down from the default ~half-window).
`scroll-other-window` (`M-PgDn`) and `scroll-other-window-down`
(`M-PgUp`) are also rebound to the same step.

## Horizontal scrolling

`scroll-config-horizontal` is bound to `wheel-left`/`wheel-right` at all
three speed tiers (`""`, `"double-"`, `"triple-"`). Three execution paths
depending on the event payload:

1. **Pixel-precise** (trackpad / Magic Mouse on macOS): `(nth 4 event)`
   carries `(COLS . PIXELS)`. Pixel deltas are accumulated in
   `scroll-config--hscroll-residual` so slow swipes contribute
   sub-character pixel amounts that aren't silently truncated.
2. **Column-delta**: when `cdr` is 0.0 the gesture was already encoded
   in column units; use `car` directly without pixel math.
3. **Fallback**: physical tilt wheel with no pixel data — fixed 3-column
   step.

`<C-wheel-up>` / `<C-wheel-down>` (and the X mouse-4/-5 variants) are
bound to `ignore` to disable accidental ctrl+scroll zoom — too fast to
control. Use the keyboard for font size.

## Suppression: when does horizontal scroll do nothing?

`scroll-config--hscroll-applicable-p` returns nil when the window is
wrapping lines (any horizontal scroll would have no visible effect). The
predicate mirrors the C-level logic in `xdisp.c:init_iterator`:

- **`scroll-config-suppress-hscroll` non-nil** → suppress unconditionally
  (terminal-style buffers).
- **`truncate-lines` non-nil** → truncation explicitly on; hscroll is
  meaningful.
- **Partial-width window with `truncate-partial-width-windows` enabled**
  → Emacs implicitly truncates side-by-side splits. Three sub-conditions
  apply (window narrower than frame; the variable enabled; width
  threshold check if it's an integer).

When suppression applies and the wheel fires, the residual accumulator
is cleared so a stale carry from a different window can't leak through.

**Escape hatch**: if `(window-hscroll) > 0`, scroll proceeds even when the
predicate would suppress. This guarantees the user can always scroll
back to column 0 — no trap state.

## Invariants — do not change without reading

### `scroll-margin` must be `0` for ultra-scroll

Ultra-scroll documents this explicitly. Non-zero margins make the cursor
jump in an ugly way as it approaches the window edge. Don't restore the
typical `scroll-margin` of 2–4.

### `pixel-scroll-precision-mode-map` `<next>` / `<prior>` are unbound

```elisp
(define-key pixel-scroll-precision-mode-map (kbd "<next>")  nil)
(define-key pixel-scroll-precision-mode-map (kbd "<prior>") nil)
```

Ultra-scroll activates `pixel-scroll-precision-mode`, whose minor-mode
map binds `<next>` / `<prior>` to `pixel-scroll-interpolate-*`. That
shadows the 10-line PgUp/PgDn rebindings set globally just below.
Without this unbind, PgUp/PgDn revert to ultra-scroll's interpolated
half-window steps and the 10-line setting silently fails.

### `scroll-config-suppress-hscroll` is decoupled from `truncate-lines`

Terminal emulators (vterm, ghostel, term, eshell, shell) **require
`truncate-lines t`** so the full window width is reported to the child
process. Flipping `truncate-lines nil` in those buffers would steal a
column for the continuation glyph and shell prompts would overflow by one
character (memory: `feedback_truncate_lines_in_terminals.md`).

The hscroll suppression is therefore a separate buffer-local variable.
Terminal mode hooks set `scroll-config-suppress-hscroll t` without
touching `truncate-lines`. Don't conflate the two.

### Pixel-residual accumulator must persist across events

The trackpad emits many sub-column deltas. Without
`scroll-config--hscroll-residual` accumulating across events, slow
swipes truncate to zero columns and feel "stuck". The residual is
cleared only when:
- A non-pixel column path executes (column-delta or fallback).
- Suppression applies (so a stale carry from another window can't leak).

Don't rewrite this with a per-call truncation that discards the
remainder.

### All three wheel-speed tiers must be bound

Emacs reclassifies rapid successive wheel events as `double-wheel-*` and
`triple-wheel-*` (same machinery as mouse-click multipliers). A handler
bound only to `wheel-left`/`wheel-right` stops responding when you swipe
fast. The `dolist` over `'("" "double-" "triple-")` covers all three.

### Suppression has a known false-positive

When truncation mode is on but every visible line happens to fit in the
window, hscroll still moves the column offset and the cursor appears to
drift sideways even though no content is hidden. A pixel-perfect fix
would need a C-level flag set when the display engine renders a
truncation glyph — out of scope. Lived with as a minor annoyance.
