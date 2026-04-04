# Emacs Patch Status: 'margin' Face (Bug#80693)

## Overview
This patch introduces a new basic face, `margin`, to control the background and default styling of the window margins (left and right). Its primary goal is to fix the "stripe bug" where the margin area beyond the end-of-buffer (EOB) reverts to the frame's default background, even when themes or packages have colored the margin area on text lines.

## Current Status (as of 2026-04-02)
The patch is currently in the **Strategy/Execution** phase. There is a consensus on the technical approach, but a design disagreement exists regarding the naming and scope of the face.

### Agreed Requirements
- **Dedicated Face:** Instead of reusing the `line-number` face, a new basic face (provisionally `margin`) will be introduced.
- **Basic Face Integration:** The face must be added to `realize_basic_faces` in `xfaces.c` to ensure support for face-remapping.
- **Base Face Logic:** The face serves as the "base" for the margin area. If an overlay or display property provides a face that specifies only a foreground color (e.g., a red `!` for an error), the `margin` face background will "show through." This ensures that annotations do not create visual "holes" or stripes of the default background color within the gutter. (Verified by **`face-margin-test-003`**).
- **Graceful Degradation:** The face inherits from `default`. If left uncustomized, it produces a no-op, preserving existing Emacs behavior.

### Open Design Issues
- **Single vs. Separate Faces:**
    - **Eli Zaretskii (Maintainer):** Insists on a single `margin` face covering both left and right margins for symmetry and simplicity, analogous to how `fringe` works.
    - **Andrea Alberti (Contributor):** Argues for separate `left-margin` and `right-margin` faces. The rationale is that the left margin is typically used for **content/annotations** (git-gutter, LSP), while the right margin is frequently used as **empty layout padding** for focus/centering modes (e.g., `olivetti`). In these layout scenarios, the margin is meant to be invisible; automatically coloring the right padding to match a left-hand annotation gutter creates a new visual asymmetry. (Demonstrated by **`face-margin-test-004`**).
- **Status:** Andrea is currently refactoring the patch to use a single `margin` face as requested, while documenting the potential issues with soft-wrapping asymmetry.

## The "Stripe Bug" Explained
When a theme (like the built-in `modus-operandi`) gives the `line-number` face a distinct background color:
1. **On text lines:** Packages like `git-gutter` fill the margin area with annotation glyphs (e.g., a red `!` for changes) or space fillers. To make the gutter look uniform, they typically set the background of these glyphs to match the `line-number` background.
2. **Below EOB:** No glyphs or overlays exist in the margin area beyond the last line of text. Consequently, the display engine clears this area using the frame's default background.
3. **Result:** A visible vertical "white stripe" appears in the margin area below the end of the buffer, while the adjacent `line-number` column correctly continues with its themed background. (Demonstrated by **`face-margin-test-001`**).

**The Solution:** The patch modifies `extend_face_to_end_of_line` in `xdisp.c` to produce space glyphs with the `margin` face for any empty margin areas if the `margin` face's background differs from the frame default. This ensures the gutter background is consistent regardless of buffer content. (Verified by **`face-margin-test-002`**).

### The Choice of Reference Color
In these tests, the `line-number` background is used as the target color for the margin. This choice is illustrative:
- **Visual Consistency:** Users typically want the left margin (annotations) and the line-number column to appear as a single, unified "gutter."
- **Standard Reference:** The `line-number` face is not functionally linked to the margin, but it provides a convenient, built-in example of how a theme intends the gutter to look. By matching the `margin` face to the `line-number` background, we can demonstrate a "visually consistent result" using only components that ship with Emacs.

## Discovered Preexisting Bugs
The investigation into this patch surfaced four preexisting bugs in the Emacs display engine. These issues are independent of the `margin` face implementation but are made more visible by it. They are documented here for future resolution:

1.  **TTY Annotation Disappearance (Hscroll Skip):** On TTY frames, `LEFT_MARGIN_AREA` annotations (e.g., git-gutter indicators) disappear on lines that are horizontally scrolled (`hscroll > 0`). 
    - **Root Cause:** The issue lies in `xdisp.c:move_it_in_display_line_to`. When the display engine seeks the first visible character for an hscrolled line, it processes display properties at the start of the line (including margin overlays) but sets `it->glyph_row = NULL`. Consequently, the metrics are calculated but no glyphs are produced for the fixed marginal areas. By the time the seek phase reaches the visible text, the iterator has already bypassed the margin content.
    - **Independence:** This disappearance is functionally independent of the `$` truncation indicator. While both occur on hscrolled lines, the `$` is inserted into the text area after the row is built, whereas the margin annotations are discarded during the initial seek phase.

2.  **Hardcoded Truncation Face:** The left `$` truncation indicator incorrectly uses the frame's default background instead of blending with the adjacent gutter.
    - **Root Cause:** In `xdisp.c:insert_left_trunc_glyphs`, the face for the truncation indicator is hardcoded to `DEFAULT_FACE_ID`. A proper fix would require the function to detect the presence of line numbers or margins and inherit the background of the visual element it abuts.

3.  **Display Table Mirroring Face Loss:** Remapping the truncation glyph via a display table (e.g., to use a different character or face) fails for the left-edge indicator when bidi mirroring is active.
    - **Root Cause:** In `xdisp.c:produce_special_glyphs`, the code path for mirrored truncation glyphs (used for L2R left-edge and R2L right-edge indicators) initializes a local `face_id` from the basic default face. This local variable is then used to produce the glyph, effectively discarding any face information specified in the display table entry.

4.  **RTL Margin Rendering (TTY):** On Right-to-Left (R2L) rows (e.g., Hebrew or Arabic text), the left margin area incorrectly reverts to the default face (black foreground, white background).
    - **Root Cause:** While `extend_face_to_end_of_line` correctly produces margin glyphs with the `margin` face for reversed rows, the TTY renderer appears to neglect these faces during the final output phase. This likely occurs in `dispnew.c:build_frame_matrix_from_leaf_window` or `term.c`, where the interaction between the row's `reversed_p` flag and the flattened frame matrix causes the margin area to be treated as unassigned or reset to the default face. (Demonstrated by **`face-margin-test-008`**).

## Required Validation (Eli's Checklist)
The following items from the maintainer's review are verified using the interactive test suite in `debug-margin-face.el`:
- [x] **Basic Faces:** Confirm `face-remapping-alist` works for `margin`. (Verified by `face-margin-test-006`)
- [x] **Asymmetric Margins:** Verify behavior when only one margin is enabled. (Verified by `face-margin-test-004` and others)
- [x] **Font Variations:** Test the `margin` face with larger fonts or different weights. (Verified by `face-margin-test-005`)
- [x] **Horizontal Scrolling:** Ensure no redraw glitches or color bleed during `C-e` / `C-a`. (Verified by `face-margin-test-007` and `007b`)
- [x] **R2L Text:** Verify behavior in Hebrew/Arabic buffers. (Verified by `face-margin-test-008`)
- [x] **Built-in LSP (Flymake):** Verify behavior with `eglot` style margin indicators. (Verified by `face-margin-test-009`)
- [x] **Third-party Integration:** Smoke tests with `olivetti` (right margin) and `git-gutter` (left margin). (Simulated by `face-margin-test-004` and `face-margin-test--annotate`)
