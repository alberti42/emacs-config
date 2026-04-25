# welcome-config.el

GUI-only startup splash: centered logo plus a "Welcome to Emacs!" title,
shown when Emacs is launched without file arguments. Sets
`inhibit-startup-screen t` to suppress the default GNU startup screen.

External packages: none — built on `create-image` and `space :align-to`.

## Activation

Two hooks fire `welcome-config--maybe-show`:

- `emacs-startup-hook` — direct `emacs` launches.
- `server-after-make-frame-hook` — `emacsclient` frames against a running
  daemon.

The handler shows the buffer only when **all** of the following hold:

- `(display-graphic-p)` — TTY frames are skipped (terminal handles its own
  blank canvas).
- The image file is readable and `(image-type-available-p 'svg)`.
- The current buffer is `*scratch*` or `*Welcome*` — i.e. nothing else
  has been opened by the user. This is the "did Emacs start clean?" guard.

`M-x show-welcome-buffer` resurfaces the buffer at any time and re-lays
it out for the current window size.

## Public API

| Form                              | Purpose                                                  |
| --------------------------------- | -------------------------------------------------------- |
| `M-x show-welcome-buffer`         | re-show the welcome buffer                               |
| `welcome-config-image-file`       | path to the logo (defaults to `goodies/Emacs-logo-alt.svg`) |
| `welcome-config-image-width`      | displayed width in pixels (default 200)                  |
| `q` (in `*Welcome*`)              | `bury-buffer` (kept for the session, not killed)         |

## Invariants — do not change without reading

### Horizontal centering uses `space :align-to`, not char-unit math

```elisp
(propertize " " 'display
            `(space :align-to (- center (0.5 . ,image))))
```

This makes Emacs do the pixel math internally. The naïve approach —
deriving a column offset from `image-size` in characters — mis-centres on
Retina/HiDPI: the image's reported char width is fractional, and rounding
shifts the logo half a column off true centre. Don't replace this with
`(make-string N ?\s)` even if it looks simpler.

Vertical centering still needs a line count, since you can't `:align-to`
in the y axis. It's derived from the pixel height:

```elisp
(img-lines (ceiling (/ (float img-height-px) (frame-char-height))))
```

### Wheel events: `minor-mode-overriding-map-alist`, not `local-set-key`

`local-set-key` does **not** suppress `<wheel-up>` / `<wheel-down>` in
this buffer. `pixel-scroll-precision-mode-map` (which carries
`ultra-scroll`) is a *minor-mode* map and its bindings win over the
buffer-local map at lookup time.

The fix is to install an override map keyed on `pixel-scroll-precision-mode`
in `minor-mode-overriding-map-alist`, which is consulted *before*
`minor-mode-map-alist` and shadows per-buffer:

```elisp
(setq-local minor-mode-overriding-map-alist
            (list (cons 'pixel-scroll-precision-mode override)))
```

The override map binds every wheel/mouse-scroll event to `#'ignore`. If
new wheel event symbols are added (e.g. higher-order multipliers), they
need adding to the `dolist` in `show-welcome-buffer`.

### Frame-size cache skips internal reflows

`welcome-config--last-frame-size` caches the last frame outer pixel size
the buffer was rendered for. `welcome-config--on-size-change` only re-renders
when the cached size differs. Without this guard, internal window reflows
(minibuffer growth, echo-area resize) would trigger redundant re-renders
even though the frame itself didn't resize.

### `q` buries, does not kill

The buffer is kept for the session so `M-x show-welcome-buffer` can
re-show it without re-creating from scratch. Don't switch this to
`kill-this-buffer`.
