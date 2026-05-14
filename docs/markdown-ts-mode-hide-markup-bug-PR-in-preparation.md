# markdown-ts-mode: ATX heading marker whitespace not hidden — fixed upstream

**Status (2026-05-14)**: fixed upstream in commit `286833e401d` ("Add
read-only `markdown-ts-view-mode` (bug#81023)", 2026-05-12). The
local patched copy at `local/markdown-ts-mode.el` and the `:load-path`
entry in the `markdown-ts-mode` `use-package` block in
`markdown-config.el` have been removed. No further action on the
markdown-ts-mode side; this note is kept as a historical record.

## What the bug was

When `markdown-ts-hide-markup` was on, `markdown-ts--fontify-delimiter`
set the `invisible` text property only on the `atx_h[1-6]_marker`
node range — i.e., the `#` characters themselves. The single space
that separates the marker from the heading text was left visible, so
the heading title sat one column off the left edge instead of flush
at column 0 where the user expects when "hide markup" is in effect.

## Upstream fix

`286833e401d` introduces a dedicated `markdown-ts--fontify-atx-delimiter`
that extends the `invisible` region forward through any trailing
whitespace between the marker and the heading text, and routes the six
`atx_h[1-6]_marker` captures through it instead of the generic
delimiter fontifier. The fix is in
`lisp/textmodes/markdown-ts-mode.el` on Emacs `master`.

Verified on master (2026-05-14): the prefix `### ` is fully invisible
when `markdown-ts-hide-markup` is on, and the heading title renders
flush at column 0.

## Related — still open

`visual-wrap-prefix-mode` has a separate latent bug: when it computes
the wrap-prefix's `min-width`, it does not consult
`buffer-invisibility-spec`, so column space is reserved for invisible
characters. This was partially closed by branch-local commit
`c2de8aa08fa` ("Don't reserve column-width for invisible prefixes in
visual-wrap") — the fully-invisible-prefix case. The
partially-invisible case (some chars hidden, others visible) is still
unhandled. The c2de8aa0 patch has not yet been filed upstream; see
the visual-wrap report when it goes out.

The two bugs composed in the wild: without the upstream
markdown-ts-mode fix, the trailing space stayed visible, which
defeated c2de8aa0's "fully-invisible prefix" predicate and let the
visual-wrap min-width hole show as a multi-column gap proportional to
heading level. With the upstream markdown-ts-mode fix in place the
gap collapses, but the visual-wrap assumption (`string-width` ignores
invisibility) is still wrong and worth filing on its own merits.
