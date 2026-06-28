Subject: [PATCH] window-text-pixel-size: exclude an overlay string anchored at TO

To: 64252@debbugs.gnu.org

I have been looking for a while for a solution to this bug that in 
pixel-scroll-precision-mode, it causes jumps when scrolling over large images.

I started from the Lisp side, added some instrumentation to
pixel-scroll-precision-mode, and traced the symptom to the C layer, precisely to
`window_text_pixel_size' (src/xdisp.c).  I believe I now understand the origin
of the problem and I may have a solution to it, which is contained in the attached
patch.

== Where the bug is ==

The bug is in how `window_text_pixel_size' handles the boundary at TO.
After moving the iterator to TO it has an existing back-off for a `display'
property at TO (which makes the move overshoot); an overlay before/after-
string anchored at TO slips past that back-off because it does not
overshoot, so its height is wrongly folded into the result.

It surfaces through the cons-FROM "pixels around a position" form with
IGNORE-LINE-AT-END, which was added in 2021 when developing
pixel-scroll-precision (commits 43c4cc2ea29 and d54d8a88e9a).
`pixel-scroll-precision-scroll-up-page' is still the only caller in stock
Emacs of that form.

== Reproducing it, and seeing the patch work ==

The attached patch adds a regression test,
`xdisp-tests--window-text-pixel-size-backward-boundary-string', which is
itself a minimal reproducer: on an unpatched build it fails, naming the
wrong value outright, and it passes once the patch is applied.

For the visible behavior I also attach a small interactive reproducer
(debug-pixel-scroll-tall-line.el).  Its `pixel-scroll-tall-line-test-002'
puts a tall image on a line partway down a buffer (the markdown-ts
"\n " + image idiom) and turns on pixel-scroll-precision-mode; on a stock
"emacs -Q" the image lurches at the top, and with this patch installed it
scrolls nearly perfectly smoothly.

== Known limitations ==

One small glitch remains: scrolling across the same tall line (this time
regardless of the direction), the image can jump by about one text line
(~14px) for a single frame before redisplay corrects it.  I believe this is a
separate, Lisp-side vscroll issue in pixel-scroll-precision rather than in
this C function, and I plan to investigate it separately.  It does not affect
what this patch fixes.

The second limitation is scrolling through images that are larger than
the window. For this, I believe I have an Elisp fix that goes into
pixel-scroll.el; I prefer to post that other fix separately from the patch
to xdisp.c, since they are two different bugs. 

== Explanation of the bug and the fix ==

What follows is **nearly a verbatim copy of the commit message** of the
attached patch, so there is no need to read two separate texts.

----------------------------------------------------------------------
window-text-pixel-size: exclude an overlay string anchored at TO

With IGNORE-LINE-AT-END non-nil, `window-text-pixel-size' is documented
to "not add the height of the screen line that includes TO to the
returned height": the measurement stops at the top of TO's display line
and counts only the lines above it.

That was not honored when TO's line carried an overlay string.  Anything
drawn above TO's buffer text but still on TO's display line was not
excluded -- a before-string whose overlay starts at TO, or an
after-string whose overlay ends at TO.  The two are symmetric: a
before-string is drawn at its overlay's start and an after-string at its
overlay's end, so when either anchor is TO the string is drawn at TO,
just before TO's own character; the range the overlay spans is irrelevant
to where its string lands.  Such an overlay string belongs to TO's display 
line, which this option drops whole, so its height must not leak into the
result.  The error grows with the string's height and matters once the
string is taller than an ordinary line -- whether it carries an image, is
enlarged by a face :height, or simply spans several rows.  An image is
the dramatic case, inflating the height by a whole image.

Why only overlay strings?  To measure up to TO the code moves the
iterator there with move_it_to.  A `display' property at TO makes
move_it_to stop past TO -- an overshoot the code already detects and
undoes.  An overlay string at TO causes no overshoot: move_it_to stops
exactly at TO.  But on its way there it has already passed over the
string, so the string's height is already in the total; and since nothing
overshot, the existing check never fires to take it back out.

Detect an overlay string anchored at TO and back off the same way:
re-measure stopping before TO and account for the last position's width
by hand.  The overlay is found by scanning those touching TO for a
before-string whose overlay starts at TO or an after-string whose overlay
ends at TO.

----------------------------------------------------------------------

== A side note: an approach that did not work ==

Before settling on the overlay scan, I tried to avoid scanning over all
overlays around END.  Instead of measuring to TO and backing off, I walked
down from FROM one screen line at a time and stopped at the top of TO's
display line: content on TO's line is then excluded by construction, with no
overlay lookup and a single pass over the span.

It is clean for content drawn *above* the anchor's text (a before-string
opens a fresh line, left below the stop).  But it fails for an after-string
with a leading newline -- the markdown "\n " + image idiom -- where the
image hangs *below* the anchor's text, in rows that still carry the
anchor's own buffer position.  The walk decides where to stop by comparing
buffer position to TO, and those rows are indistinguishable by position
from TO itself, so it stops one row too low and folds the image back in.
Recovering the correct height there needs precisely the overlay-boundary
information the scan provides. So, I eventually kept the scan, although
it is not a particularly elegant solution.

I am looking forward to hearing your feedback.

Thanks,
Andrea
