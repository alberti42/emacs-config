# Bug report draft: invisible child frame resurrected on the NS port

Target: `bug-gnu-emacs@gnu.org` (via `M-x report-emacs-bug`).
Severity: normal. Built from Emacs 31.0.60 (NS/Cocoa, macOS).

---

## Subject

`31.0.60; [NS] invisible child frame reappears on toggle-frame-fullscreen / monitor change`

## Body

On the macOS (NS) port, a child frame that Emacs has made *invisible*
reappears on screen whenever the parent frame rebuilds its parent/child
window relationships — for example on `toggle-frame-fullscreen`, when a
monitor is connected or disconnected, or when the undecorated status is
toggled.

The child frame's `frame-visible-p` stays nil throughout, so Emacs never
repaints to clear it: it remains on screen as a dead, non-interactive
surface that `C-g` cannot dismiss. In practice this is what users of
child-frame completion popups (corfu, company-box, …) see as a "stuck
completion popup" after, for example, waking a laptop on a different
monitor.

## How to reproduce

`emacs -Q` with the attached `debug-childframe-fullscreen.el`, which uses
only built-in primitives (`make-frame` with a `parent-frame` parameter,
`make-frame-invisible`, `toggle-frame-fullscreen`):

    emacs -Q --load debug-childframe-fullscreen.el

Then, manually:

    M-x childframe-fullscreen-step-1-show   ; show a child frame (stand-in for the popup)
    M-x childframe-fullscreen-step-2-hide   ; hide it via make-frame-invisible
    M-x toggle-frame-fullscreen             ; stock command -- triggers the bug

The first two commands only reconstruct the precondition (a child frame
that has been made invisible but is still parented to the frame); the
trigger is the unmodified built-in `toggle-frame-fullscreen`.

Expected: the child frame stays hidden across the fullscreen transition.

Actual: the child frame reappears in the fullscreen frame even though
`(frame-visible-p ...)` returns nil, and it cannot be removed with `C-g`.
Run `M-x childframe-fullscreen-status` to confirm the discrepancy: it
reports `frame-visible-p` = nil while the frame is plainly on screen.

(The reproducer sets `ns-use-native-fullscreen` to nil for determinism;
the bug also occurs with native fullscreen and on monitor hot-plug, which
is fullscreen-independent.)

## Analysis

The problem is in `-[EmacsWindow setParentChildRelationships]`
(`src/nsterm.m`). When (re)establishing the parent/child relationship it
calls:

    [parentWindow addChildWindow:self ordered:NSWindowAbove];

`-addChildWindow:ordered:` orders the child window onto the screen. This
method runs on every relationship rebuild — including the one triggered by
entering fullscreen (for non-native fullscreen, through the fresh
`EmacsWindow` created in `-toggleFullScreen:`) and by a display
reconfiguration. The reattach loop a few lines below walks every child
frame:

    FOR_EACH_FRAME (tail, frame)
      {
        if (FRAME_PARENT_FRAME (XFRAME (frame)) == ourFrame)
          [(EmacsWindow *)[FRAME_NS_VIEW (XFRAME (frame)) window]
            setParentChildRelationships];
      }

Neither the `addChildWindow:` call nor this loop checks `FRAME_VISIBLE_P`,
so a child frame Emacs had hidden is brought back onto the screen.

Emacs then never corrects this, because on the NS port
`frame_redisplay_p` (`src/frame.c`) decides whether to redisplay a frame
from `FRAME_VISIBLE_P` alone:

    #ifndef HAVE_X_WINDOWS
        return FRAME_VISIBLE_P (f);
    #else
      /* Under X, frames can continue to be displayed to the user by the
         compositing manager even if they are invisible, so this also
         checks whether or not the frame is reported visible by the X
         server.  */
      return (FRAME_VISIBLE_P (f)
              || (FRAME_X_P (f) && FRAME_X_VISIBLE (f)));
    #endif

The X branch already guards against exactly this situation — a frame the
compositor still shows while Emacs believes it is invisible — by also
consulting the server's reported visibility. The NS branch has no
equivalent, so once `FRAME_VISIBLE_P` is nil the frame is never repainted
and the stale surface persists.

(For context, the NS port already treats visibility transitions and
parent/child links as fragile: `ns_make_frame_visible` at
`src/nsterm.m:1654` has a block to repair the parent/child link and frame
offset that an `orderOut:` left broken.)

## Proposed fix

Honor the frame's own visibility state after reattaching: if Emacs
considers the frame invisible, order it back out so `addChildWindow:`
cannot resurrect it.

    diff --git a/src/nsterm.m b/src/nsterm.m
    --- a/src/nsterm.m
    +++ b/src/nsterm.m
    @@ -9981,6 +9981,14 @@ - (void)setParentChildRelationships

           [parentWindow addChildWindow:self
                                ordered:NSWindowAbove];
    +
    +      /* -addChildWindow: orders the child window onto the screen, so
    +         rebuilding the parent/child relationships (e.g. when entering
    +         fullscreen or after a display reconfiguration) resurrects child
    +         frames that Emacs considers invisible.  Honor the frame's own
    +         visibility state and order it back out if it should be hidden.  */
    +      if (!FRAME_VISIBLE_P (ourFrame))
    +        [self orderOut:nil];
         }

       /* Check our child windows are configured correctly.  */

Verified on macOS with a same-tree A/B at 31.0.60: built without the
patch, the reproducer's child frame reappears on the fullscreen toggle;
built with the patch (the same tree, only the hunk above added), it stays
hidden, and a legitimately-visible popup is unaffected.

---

## Notes (not for the report)

- The two evidence lines are `setParentChildRelationships` (the unguarded
  `addChildWindow:`) and `frame_redisplay_p` (NS trusts `FRAME_VISIBLE_P`
  alone). Everything else is supporting context.
- Same-tree A/B confirmed (bug present without the hunk, gone with it).
  Optionally paste the exact build string from `M-x emacs-version` for
  precision.
- Attach `docs/debug-childframe-fullscreen.el` to the report.
