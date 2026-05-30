# Bug report draft: invisible child frame resurrected on the NS port

Target: `bug-gnu-emacs@gnu.org` (via `M-x report-emacs-bug`).
Severity: normal. Built from Emacs 31.0.60 (NS/Cocoa, macOS).

---

## Subject

`31.0.60; [NS] invisible child frame reappears on (non-native) toggle-frame-fullscreen`

## How the bug typically manifests

On the macOS (NS) port, a dismissed completion popup can get stuck on
screen as a dead, unresponsive rectangle.

For users who rely on a completion UI that draws its popup in a child
frame (corfu, company-box, ...), here is what they see: they dismiss the
popup (pick a candidate or hit `C-g`), later they run `M-x
toggle-frame-fullscreen`, and the popup they already dismissed
**reappears** in the fullscreen frame. It just sits there — the user
cannot click it, cannot select anything in it, and `C-g` will not
clear it. The only way to get rid of it is to pop a fresh completion,
which replaces the stale one.

The attached screenshot (`real-world-demonstration-child-frame-bug.jpg`)
shows exactly this: a corfu completion popup left stuck and unresponsive
over an `init.el` buffer.

Under the hood: the leftover popup is a child frame that Emacs has made
invisible (`frame-visible-p` returns nil), but which the window server
is still displaying. Non-native `toggle-frame-fullscreen` rebuilds the
frame's parent/child window relationships, and that operation
re-attaches -- and so re-shows -- the hidden child frame. Details in
Analysis below.

## Detailed Analysis

The problem is in `-[EmacsWindow setParentChildRelationships]`
(`src/nsterm.m`). When (re)establishing the parent/child relationship it
calls:

    [parentWindow addChildWindow:self ordered:NSWindowAbove];

`-addChildWindow:ordered:` orders the child window onto the screen. This
method runs whenever the parent/child relationships are rebuilt. The
reattach loop a few lines below walks every child frame:

    FOR_EACH_FRAME (tail, frame)
      {
        if (FRAME_PARENT_FRAME (XFRAME (frame)) == ourFrame)
          [(EmacsWindow *)[FRAME_NS_VIEW (XFRAME (frame)) window]
            setParentChildRelationships];
      }

Neither the `addChildWindow:` call nor this loop checks `FRAME_VISIBLE_P`,
so a child frame Emacs had hidden is brought back onto the screen.

This buggy portion of code is only reached when a child-parent
relationship is rebuilt.  Note that `-toggleFullScreen:` reaches it only
on the *non-native* path when it allocates a fresh `EmacsWindow` whose
initializer calls `setParentChildRelationships`.  By contrast, with
native fullscreen (`ns-use-native-fullscreen` t), `-toggleFullScreen:`
hands off to AppKit (`[[self window] toggleFullScreen:sender]`) and
returns without allocating a window, so the re-attach loop never runs
and the child frame stays invisible.

To gain further insight, I investigated why Emacs does not clear the
stale frame on its own.  The reason is that on the NS port
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

The X branch already guards against exactly this situation -- a frame
the compositor still shows while Emacs believes it is invisible -- by
also consulting the server's reported visibility, not just the internal
state about what Emacs believes about the visibility of the child frame
(`FRAME_VISIBLE_P (f)`). The NS branch implements no equivalent, so when
`FRAME_VISIBLE_P` is nil, the frame is never repainted and the stale
surface persists.

Because this gate keys solely on `FRAME_VISIBLE_P`, no user action that
merely forces a redisplay clears the ghost: pressing `C-g` or otherwise
provoking a repaint leaves the child frame untouched, since redisplay
skips it while it is flagged invisible. The
frame only returns to correct behavior when its owning package (corfu,
company-box, …) next reuses the cached child frame: that goes through
`make-frame-visible`, which sets `FRAME_VISIBLE_P` and brings the frame
back into its normal show/hide cycle, so the following dismissal hides
it properly.  The bug is therefore merely annoying rather than fatal --
but the only way to get rid of the stale popup is to make the owning
package pop a fresh one, which sometimes can be frustrating for the
user. Luckily, if the maintainers approve the fix proposed below, this
bug can be fixed with the addition of a couple of lines of code.

## How to reproduce

`emacs -Q` with the attached `debug-childframe-fullscreen.el`, which uses
only built-in primitives (`make-frame` with a `parent-frame` parameter,
`make-frame-invisible`, `toggle-frame-fullscreen`):

    emacs -Q --load debug-childframe-fullscreen.el

Then, manually:

    M-x childframe-fullscreen-step-1-show   ; show a child frame (stand-in for the popup)
    M-x childframe-fullscreen-step-2-hide   ; hide it via make-frame-invisible
    M-x toggle-frame-fullscreen             ; stock command -- triggers the bug
    M-x childframe-fullscreen-bring-into-view ; (optional) if the box landed off-screen

The first two commands set up the preconditions for the bug to manifest
(a child frame that has been made invisible but is still parented to the
frame); when these preconditions are set up, the actual trigger is the
built-in `toggle-frame-fullscreen`.

The fourth command is optional. If you do NOT see the box after toggling
fullscreen, it is because it appears outside the visible area: its
position is recomputed during the rebuild and can land off-screen
(e.g. a negative top) on large displays.
`childframe-fullscreen-bring-into-view` repositions it into view.
Importantly, it does not change the visibility. Its only purpose is to
make the buggy behavior completely deterministic and reproducible
regardless of the screen size.

Expected: the window is maximized to the full screen, and the child
frame stays hidden across and after the fullscreen transition.

Actual buggy behavior: the child frame reappears in the fullscreen frame
even though `(frame-visible-p ...)` returns nil, and it cannot be
removed with `C-g`.

Note that to trigger the bug, the reproducer sets
`ns-use-native-fullscreen` to nil so that fullscreen operation is done
with the *non-native* fullscreen path. With native fullscreen, the
behavior is correct (the child frame stays invisible).

## Proposed fix

Don't attach a child frame while Emacs considers it invisible.
`addChildWindow:` orders the child onto the screen as it attaches, so
attaching a hidden child is exactly what resurrects it. A hidden child is
normally already detached anyway: Emacs hides via `-orderOut:`, which per
Apple's documentation removes a child window from its parent before
ordering it out [see
https://developer.apple.com/documentation/appkit/nswindow/orderout(_:)],
and `ns_make_frame_visible` re-attaches it when the frame is shown again.
So guarding the attach on `FRAME_VISIBLE_P` is sufficient:

    diff --git a/src/nsterm.m b/src/nsterm.m
    --- a/src/nsterm.m
    +++ b/src/nsterm.m
    @@ -9979,8 +9984,15 @@ - (void)setParentChildRelationships
     	  [ourView toggleFullScreen:self];
     #endif

    -      [parentWindow addChildWindow:self
    -                           ordered:NSWindowAbove];
    +      /* -addChildWindow: also orders the child window onto the screen, so
    +         attaching a child frame Emacs considers invisible is what
    +         resurrects a dismissed completion popup (corfu, company-box, ...)
    +         when relationships are rebuilt.  Only attach a visible child; a
    +         hidden one is re-attached by ns_make_frame_visible when it is
    +         shown again.  */
    +      if (FRAME_VISIBLE_P (ourFrame))
    +        [parentWindow addChildWindow:self
    +                             ordered:NSWindowAbove];
         }

       /* Check our child windows are configured correctly.  */

The patch also replaces the speculative comment in `ns_make_frame_visible`
(`nsterm.m`) with a grounded explanation — citing Apple's documentation —
of why the parent/child relationship must be reinstated when the child
frame is made visible.

Verified by building the same source tree both without and with the
patch, on:

    GNU Emacs 31.0.60 (build 50, aarch64-apple-darwin25.4.0,
    NS appkit-2685.50 Version 26.4.1 (Build 25E253)) of 2026-05-29

Built without the patch, the reproducer's child frame reappears on the
non-native fullscreen toggle; built with the patch (the same tree, only
the hunk above added), the initially hidden popup stays hidden, whereas
a legitimately visible popup is unaffected.

## Appendix: unrelated code-typo noticed nearby

While working in the same method I noticed a likely typo, sent as a
*separate* commit to make it clear that this is an independent change and
not part of the fix above.  The two `-respondsToSelector:` guards in
`setParentChildRelationships` test whether `@selector(toggleFullScreen)`
is available, written without the trailing colon. But because
`-toggleFullScreen:` takes a sender argument, its selector must carry the
colon; `@selector(toggleFullScreen)` names a different, nonexistent
method, so the colon-less check matches nothing and the guarded block is
always skipped.

This is harmless on modern builds: the guards are inside
`#if MAC_OS_X_VERSION_MIN_REQUIRED < 1070`, so on any deployment target of
10.7 or later they are compiled out and the fullscreen handling runs
unconditionally. It would only misbehave on a binary that targets
pre-10.7 yet runs on 10.7+, where the real `-toggleFullScreen:` exists
but the colon-less check still fails, so the block that takes a child
frame out of native fullscreen never runs. The fix is a trivial
one-character fix on each line:

    @@ -9947,7 +9947,7 @@ - (void)setParentChildRelationships
     #ifdef NS_IMPL_COCOA
     #if MAC_OS_X_VERSION_MIN_REQUIRED < 1070
    -      if ([ourView respondsToSelector:@selector (toggleFullScreen)])
    +      if ([ourView respondsToSelector:@selector (toggleFullScreen:)])
     #endif

    @@ -9972,7 +9972,7 @@ - (void)setParentChildRelationships
     #ifdef NS_IMPL_COCOA
     #if MAC_OS_X_VERSION_MIN_REQUIRED < 1070
    -      if ([ourView respondsToSelector:@selector (toggleFullScreen)])
    +      if ([ourView respondsToSelector:@selector (toggleFullScreen:)])
     #endif

---

## Notes (not for the report)

- The two evidence lines are `setParentChildRelationships` (the unguarded
  `addChildWindow:`) and `frame_redisplay_p` (NS trusts `FRAME_VISIBLE_P`
  alone). Everything else is supporting context.
- Same-tree A/B confirmed (bug present without the hunk, gone with it),
  build string pasted into the Proposed fix section.
- Attach `docs/debug-childframe-fullscreen.el` to the report.
- Attach the screenshot `real-world-demonstration-child-frame-bug.jpg`
  (referenced in "How the bug typically manifests"). It can only be an
  attachment — `report-emacs-bug` is plaintext, so no inline image.
- Branch `fix-ns-invisible-child-frame-resurrection` holds two distinct
  commits: the fix, and the separate `toggleFullScreen:` typo fix. Keep
  them as separate patches when sending (`git format-patch`).
