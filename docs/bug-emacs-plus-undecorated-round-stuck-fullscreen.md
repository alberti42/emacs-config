# Handoff note: emacs-plus `round-undecorated-frame` — stuck fullscreen (TO BE FIXED)

Status: **open / not yet fixed.** This is an **emacs-plus downstream-patch bug**, distinct
from the upstream NS child-frame resurrection bug (see *Related* below). Written as a
handoff for a future session.

## One-line summary

On emacs-plus, an `undecorated-round` frame that is **maximized** gets **stuck in
fullscreen**: after `M-x toggle-frame-fullscreen` it enters fullscreen but can no longer
return to a normal window.

## Confirmed by testing

- **Trigger (all required):**
  1. emacs-plus build (i.e. the `round-undecorated-frame` patch is present), and a frame
     with `(undecorated-round . t)`;
  2. the frame is **maximized** — via either `(add-to-list 'default-frame-alist
     '(fullscreen . maximized))` or `(set-frame-parameter frame 'fullscreen 'maximized)`;
  3. `ns-use-native-fullscreen` is nil (non-native fullscreen);
  4. `M-x toggle-frame-fullscreen`.
- **Without the `maximized` state, fullscreen toggles in and out fine** even with
  `undecorated-round`. So it is the `maximized` ⇄ `fullboth` ⇄ restore cycle that breaks.
- **Does NOT need corfu or any child frame** — it is the *main* frame that gets stuck.
  (corfu only ever mattered for the *other*, upstream bug; see *Related*.)
- **Independent of our skip-attach fix** — reproduces with skip-attach installed.
- **Vanilla Emacs is not affected**, because `undecorated-round` is an emacs-plus-only
  parameter; a self-built vanilla `emacs-31` (which ignores it) does not reproduce.

## Minimal reproduction

emacs-plus@31, on macOS, `emacs -Q` plus:

```elisp
(setq ns-use-native-fullscreen nil)
(add-to-list 'default-frame-alist '(undecorated-round . t))
(add-to-list 'default-frame-alist '(fullscreen . maximized))
;; then, in the GUI frame:
;;   M-x toggle-frame-fullscreen   -> enters fullscreen
;;   M-x toggle-frame-fullscreen   -> does NOT return to a normal (maximized) window; stuck
```

## Root cause (hypothesis — verify before fixing)

The `round-undecorated-frame` patch adds, in `-[EmacsWindow initWithEmacsFrame:]`:

```objc
if (FRAME_UNDECORATED_ROUND (f))
  {
    styleMask |= NSFullSizeContentViewWindowMask;   /* == NSWindowStyleMaskFullSizeContentView */
  }
```

`NSWindowStyleMaskFullSizeContentView` interacting with the **non-native** fullscreen
round-trip (`-toggleFullScreen:` allocates a fresh `EmacsWindow`, see `ns_make_frame_*`
and `toggleFullScreen:` in `nsterm.m`) is the leading suspect: after the maximized →
fullboth → restore cycle the window's style mask / frame is not restored to a normal
window. The patch also adds `ns_set_undecorated_round` (recreates the window when the
param changes), which may be involved.

This is a hypothesis from reading the patch, not yet confirmed with a runtime trace.
Confirm with `NSLog` in the non-native branch of `-toggleFullScreen:` and in
`initWithEmacsFrame:` (style mask before/after) before committing to a fix.

## Where it lives

- **Local Emacs source fork (for building/testing):**
  `/Users/andrea/Documents/Programming/Others/fork-emacs`
  - `emacs-31` = the vanilla base branch (build this to confirm vanilla is unaffected).
  - `fix-ns-invisible-child-frame-resurrection` = the branch carrying our skip-attach fix
    (the *other*, upstream bug — see *Related*).
  - To reproduce bug 2 in isolation: branch from `emacs-31`, apply the
    `round-undecorated-frame.patch` below (`git apply --3way`), build, and use the minimal
    reproduction above.
- Patch: `round-undecorated-frame.patch` in the emacs-plus tap, e.g.
  `/opt/homebrew/Library/Taps/d12frosted/homebrew-emacs-plus/patches/emacs-31/round-undecorated-frame.patch`
  (also on GitHub: `d12frosted/homebrew-emacs-plus`, `patches/emacs-31/`).
- emacs-plus@31 applies exactly three patches unconditionally: `fix-ns-x-colors`,
  `system-appearance`, `round-undecorated-frame` (formula
  `Formula/emacs-plus@31.rb`). Only `round-undecorated-frame` is implicated here.

## Suggested next steps

1. Confirm the `NSFullSizeContentViewWindowMask` mechanism with a runtime trace (above).
2. This is a **downstream emacs-plus patch bug**, so the right home is an issue/PR to
   **d12frosted/homebrew-emacs-plus** — not the upstream `bug-gnu-emacs` tracker (vanilla
   Emacs has no `undecorated-round`).
3. Daily-use workaround until fixed: you can keep **`undecorated-round`** *or*
   **`(fullscreen . maximized)`**, but not both. Drop one.

## Related (do not conflate)

- **Upstream NS child-frame resurrection bug** (ours, fixed by skip-attach) — a *different*
  bug: a hidden child frame (e.g. a corfu popup) reappears when `toggle-frame-fullscreen`
  rebuilds parent/child relationships. See `docs/bug-report-ns-childframe-fullscreen.md`
  and `docs/debug-childframe-fullscreen.el`. That one is vanilla-reproducible and
  submittable upstream; this `round-undecorated-frame` bug is emacs-plus-only and separate.
</content>
