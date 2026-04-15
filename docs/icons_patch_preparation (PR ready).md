# Emoji icons in TTY Emacs — patch preparation notes

## Background

Emacs's `icons.el` (introduced in Emacs 29) provides a unified icon system
via `define-icon` and `icons--create`. Each icon can be represented as an
image, an emoji, a Unicode symbol, or plain text, in order of preference
controlled by `icon-preference`.

The `icons--create` method for the `emoji` type had the following original
implementation:

```elisp
(cl-defmethod icons--create ((_type (eql 'emoji)) icon _keywords)
  (when-let* ((font (and (display-multi-font-p)
                         ;; FIXME: This is not enough for ensuring
                         ;; display of color Emoji.
                         (car (internal-char-font nil ?🟠)))))
    (and (font-has-char-p font (aref icon 0))
         icon)))
```

## The problem

The original method conflates two fundamentally different display contexts
under a single code path:

**GUI frames** — Emacs manages font rendering directly. The check for
`display-multi-font-p` and `internal-char-font` is appropriate here: it
verifies that some font in the active fontset covers the emoji codepoint.
The original FIXME acknowledges that even this check is incomplete: a font
may have the codepoint but render it as a monochrome glyph rather than a
color emoji.

**TTY frames** — Emacs does not manage font rendering at all. It outputs
raw Unicode codepoints to the terminal, and the *terminal emulator* is
responsible for rendering them using its configured fonts. As a result,
`display-multi-font-p` always returns `nil` in TTY, so the emoji branch is
never taken — Emacs always falls back to the `symbol` type (e.g. `■`) even
when the terminal is perfectly capable of rendering emoji.

This is observable: typing `⛔` directly into a TTY Emacs buffer renders
correctly (the terminal handles it), but the icon system still shows `■`
for warnings.

## Why auto-detection is not straightforward

There is no standard terminal capability for querying emoji support (unlike
colors, which are advertised via terminfo). Heuristics exist:

- `TERM_PROGRAM` (set by WezTerm, iTerm.app, Ghostty, etc.)
- `KITTY_WINDOW_ID` (Kitty terminal)
- `VTE_VERSION` (VTE-based terminals)
- Terminal coding system (`utf-8` is necessary but not sufficient)
- `DA2` (secondary device attributes) query — correct but requires async I/O

None of these is universally reliable, and implementing a `DA2`-based probe
would require significant infrastructure to integrate with Emacs's
synchronous startup path. The conservative option — defaulting to `nil` and
requiring an explicit user opt-in — is honest about this limitation and easy
to review upstream.

## The fix

The `icons--create` emoji method is patched to separate the two display
contexts and introduce two new `defcustom` variables:

```elisp
(defcustom icons-gui-emoji t
  "Whether to use emoji icons in GUI frames when a suitable font is available.
Set to nil to prefer symbol icons even in graphical displays."
  :type 'boolean
  :group 'icons
  :version "31.1")

(defcustom icons-tty-emoji nil
  "Whether to use emoji icons in TTY frames.
Emacs cannot reliably auto-detect terminal emoji support, so this
must be set manually if your terminal renders emoji correctly."
  :type 'boolean
  :group 'icons
  :version "31.1")

(cl-defmethod icons--create ((_type (eql 'emoji)) icon _keywords)
  (if (display-graphic-p)
      ;; GUI: honour icons-gui-emoji and check that a font covering the
      ;; glyph is available.  Note: this confirms the codepoint is present
      ;; in some font but does not guarantee color emoji rendering (the font
      ;; may render it as a monochrome glyph).
      (when (and icons-gui-emoji
                 (display-multi-font-p)
                 (when-let* ((font (car (internal-char-font nil ?🟠))))
                   (font-has-char-p font (aref icon 0))))
        icon)
    ;; TTY: Emacs has no font renderer; the terminal emulator renders
    ;; emoji directly from the Unicode codepoint.  Honour the user's
    ;; explicit opt-in via `icons-tty-emoji'.
    (when icons-tty-emoji
      icon)))
```

`icons-gui-emoji` defaults to `t`, preserving existing GUI behaviour.
`icons-tty-emoji` defaults to `nil`, requiring explicit opt-in.

## How it is applied in this config

`local/icons.el` is a patched copy of the built-in `icons.el` containing
the changes above. It shadows the built-in via `load-path` prepending, done
early in `early-init.el`:

```elisp
(let ((dir (file-name-directory (file-truename (or load-file-name buffer-file-name)))))
  (add-to-list 'load-path (expand-file-name "local" dir)))
```

The opt-in is set in `ui-config.el`:

```elisp
(setq icons-tty-emoji t)
```

## Future work

- A proper `DA2`-based terminal probe would allow auto-detection without
  user opt-in. The result should be cached as a `terminal-parameter` so it
  is computed once per terminal, not on every icon render.
- The GUI-side limitation (monochrome vs. color emoji) requires checking
  for color font tables (SBIX, CBDT/CBLC, COLR/CPAL) in addition to mere
  codepoint presence. `font-has-char-p` does not distinguish these.
- This patch is intended as preparation for an upstream bug report /
  patch submission to emacs-devel.
