# Emacs Patch Status: 'margin' Face (Bug#80693)

## Overview
This patch introduces a new basic face, `margin`, to control the background and default styling of the window margins (left and right). Its primary goal is to fix the "stripe bug" where the margin area beyond the end-of-buffer (EOB) reverts to the frame's default background, even when themes or packages have colored the margin area on text lines.

## Current Status (as of 2026-04-02)
The patch is currently in the **Strategy/Execution** phase. There is a consensus on the technical approach, but a design disagreement exists regarding the naming and scope of the face.

### Agreed Requirements
- **Dedicated Face:** Instead of reusing the `line-number` face, a new basic face (provisionally `margin`) will be introduced.
- **Basic Face Integration:** The face must be added to `realize_basic_faces` in `xfaces.c` to ensure support for face-remapping.
- **Base Face Logic:** The face will serve as the "base" for the margin area. If an overlay or display property provides a face, the two will be merged (allowing the margin background to show through if the overlay specifies only a foreground).
- **Graceful Degradation:** The face inherits from `default`. If left uncustomized, it produces a no-op, preserving existing Emacs behavior.

### Open Design Issues
- **Single vs. Separate Faces:**
    - **Eli Zaretskii (Maintainer):** Insists on a single `margin` face covering both left and right margins for symmetry and simplicity, analogous to how `fringe` works.
    - **Andrea Alberti (Contributor):** Argues for separate `left-margin` and `right-margin` faces. The rationale is that the left margin is typically used for **content/annotations** (git-gutter, LSP), while the right margin is often used for **layout** (soft-wrapping padding). Coloring the right margin automatically when only the left gutter is desired creates a new visual inconsistency.
- **Status:** Andrea is currently refactoring the patch to use a single `margin` face as requested, while documenting the potential issues with soft-wrapping asymmetry.

## The "Stripe Bug" Explained
When a theme (like the built-in `modus-operandi`) gives the `line-number` face or margin annotations a distinct background color:
1. **On text lines:** Packages like `git-gutter` fill the margin with space glyphs carrying a specific background face.
2. **Below EOB:** No glyphs exist, so the display engine clears the area using the frame's default background.
3. **Result:** A visible vertical "stripe" appears where the gutter color abruptly stops at the end of the text.

The fix involves modifying `extend_face_to_end_of_line` in `xdisp.c` to produce space glyphs with the `margin` face for any empty margin areas if the `margin` face's background differs from the frame default.

## Discovered Preexisting Bugs
Horizontal scrolling (`face-margin-test-007`) surfaces three preexisting bugs in the Emacs display engine. These are considered out-of-scope for the current patch but are documented for tracking:

1.  **TTY Annotation Disappearance:** On TTY frames, `LEFT_MARGIN_AREA` annotations (e.g., git-gutter indicators) disappear on lines that are horizontally scrolled. While the `$` truncation glyph is placed in the text area and the annotation is in the margin, the TTY renderer fails to display the margin area for these specific rows.
2.  **Hardcoded Truncation Face:** The left `$` truncation indicator always uses `DEFAULT_FACE_ID` (via `insert_left_trunc_glyphs` in `xdisp.c`). This causes a visual clash when line numbers or margins have a custom background, as the `$` glyph shows the buffer's default background instead of blending with the gutter.
3.  **Display Table Mirroring Failure:** Display table remapping does not work for the left-edge `$` truncation glyph. In `produce_special_glyphs`, the mirroring code path for L2R left-edge glyphs discards both the character and the face from the display table when no bidi mirror is found. Furthermore, the display table uses a single "truncation" slot for both edges, making independent styling of left vs. right indicators impossible.

## Required Validation (Eli's Checklist)
The following items from the maintainer's review are verified using the interactive test suite in `debug-margin-face.el`:
- [x] **Basic Faces:** Confirm `face-remapping-alist` works for `margin`. (Verified by `face-margin-test-006`)
- [x] **Asymmetric Margins:** Verify behavior when only one margin is enabled. (Verified by `face-margin-test-004` and others)
- [x] **Font Variations:** Test the `margin` face with larger fonts or different weights. (Verified by `face-margin-test-005`)
- [x] **Horizontal Scrolling:** Ensure no redraw glitches or color bleed during `C-e` / `C-a`. (Verified by `face-margin-test-007` and `007b`)
- [x] **R2L Text:** Verify behavior in Hebrew/Arabic buffers. (Verified by `face-margin-test-008`)
- [x] **Third-party Integration:** Smoke tests with `olivetti` (right margin) and `git-gutter` (left margin). (Simulated by `face-margin-test-004` and `face-margin-test--annotate`)
