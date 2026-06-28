Subject: window-text-pixel-size: IGNORE-LINE-AT-END over-counts when TO's line carries an overlay string

To: bug-gnu-emacs@gnu.org

I would like to report a bug in the C function `window_text_pixel_size'
(src/xdisp.c). I also attach a proposed patch and a regression test.

This is a bug that affects users of `pixel-scroll-precision-mode'.  Many users
have discussed it on Reddit and emacs-devel (e.g., bug#64252; more on this
later).  Community packages such as ultra-scroll ship workarounds for these
scrolling problems alongside their other features, but a workaround at the
package level cannot fix a defect that lives in a C primitive -- only a change
in stock Emacs can.
  
== How I found it ==

I was investigating bug#64252 -- the pixel-scroll-precision "lurch": when
you scroll up and a tall line (typically one carrying an image) rises
toward the top of the window, the view jumps onto it and snaps back
instead of gliding past.

The author and maintainer of precision-scroll, Po Lu, commented in bug#64252:

     If an image is larger than the window, pixel-scroll-precision-mode is
     unable to determine a position of point that will not cause redisplay to
     recenter the window after scrolling takes place.

     There is definitely a solution to this problem, but I haven't found it
     yet.  Patches welcome.

So, the bug remained open until today. I decided to look closer at it and
started from the Lisp side. I added some instrumentation to
pixel-scroll-precision-mode, and traced one of the
symptoms below the Lisp layer into `window_text_pixel_size'.

While doing this I also found a couple of separate problems that really
are on the Lisp side of pixel-scroll-precision; I will report those under
bug#64252 in due course.  This report is only the C-level bug.  It is
independent of the Lisp issues and affects the stock function for any
caller, so I think it is best tracked on its own.

== Where it lives ==

The bug is in the IGNORE-LINE-AT-END branch of `window_text_pixel_size'.
This branch, and the cons-FROM "pixels around a position" form it supports,
were added by Po Lu in 2021 while he was developing
pixel-scroll-precision (commits 43c4cc2ea29 and d54d8a88e9a).

`pixel-scroll-precision-scroll-up-page' is still the only caller in stock
Emacs of that branch. It is likely that other community-contributed packages
like ultra-scroll also make use of the same function `window_text_pixel_size'.

== Reproducing it ==

The attached patch adds a regression test,
`xdisp-tests--window-text-pixel-size-backward-boundary-string', which is
itself a minimal reproducer: on an unpatched build it fails, naming the
wrong value outright (e.g. `:form (equal 4 1)'), and it passes once the
patch is applied.  I also have a small self-contained reproducer and am
happy to share it if useful.

One caveat on the user-visible symptom.  This C fix corrects the
*measurement*; on its own it does not remove the scrolling "lurch".  That
also needs a companion Lisp-side patch for pixel-scroll-precision (much
more scoped and self-contained), which I will submit under bug#64252.
Until both are in place the smooth result is not yet visible, so I have
deliberately limited this report to the C-level measurement bug, which
stands on its own. This is also the reason why I did not yet submit a full
visual reproducer to demonstrate complete smooth scrolling.

== Explanation of the bug and the fix ==

What follows is **nearly a verbatim copy of the commit message** of the
attached patch, so there is no need to read two separate texts.

----------------------------------------------------------------------
window-text-pixel-size: stop IGNORE-LINE-AT-END at the top of TO's line

With IGNORE-LINE-AT-END non-nil, `window-text-pixel-size' is documented
to "not add the height of the screen line that includes TO to the
returned height": the measurement is meant to stop at the top of TO's
display line and count only the lines above it.

This patch fixes a bug where the IGNORE-LINE-AT-END contract was not
honored when TO's line contained overlay strings.  It did not stop at
the top of TO's display line; it stopped at TO itself, i.e., at the top
of TO's buffer text, and took that y as the top of TO's line.  So
anything drawn above that text but still on TO's display line was not
excluded -- a before-string whose overlay starts at TO, or an
after-string whose overlay ends at TO.  The two are symmetric: a
before-string is drawn at its overlay's start and an after-string at its
overlay's end, so when either anchor is TO the string is drawn at TO,
just before TO's own character.  The range the overlay spans is
irrelevant to where its string lands.  Such an overlay string belongs to
TO's display line, which this option is supposed to drop whole; by not
accounting for it, the code let its height leak into the y it took for
the top of TO's line, inflating the returned height by the vertical
space the string occupies on TO's line.  The error grows with the
string's height and matters once the string is taller than an ordinary
line -- whether because it carries an image, is enlarged by a face
:height, or simply spans several rows (the regression test uses a plain
three-line string).  An image is just the dramatic case, inflating the
height by a whole image.

The cause is how the height was obtained.  The old code moved the
iterator forward to TO with move_it_to and read it.current_y.  On a
plain line TO is at the top of its screen line, so current_y is that
top -- correct.  A `display' property at TO makes move_it_to overshoot
(it stops past TO), and an existing block detects that and backs off so
the property is excluded.  But a before/after-string at TO does not
overshoot: move_it_to stops exactly at TO, below the string, with the
string's rows already folded into current_y, so it slipped past that
guard and was included in the height.

Stop at the top of TO's screen line directly, reading the running y the
iterator keeps as it walks there, instead of measuring to TO and
correcting afterwards.  Correcting afterwards would mean detecting what
sits at TO -- a before-string, an after-string, possibly a zero-length
overlay, or a display property, each its own case -- and subtracting a
height the iterator had already passed; that is the brittle overlay
scan an earlier version of this fix used and this one drops.  Instead,
step down toward TO one screen line at a time and take the y at the top
of TO's own line.  TO's line is the first line that starts at TO -- a
string anchored there opens a fresh line, which is left below the stop
-- or, when no line starts exactly at TO (TO is interior to a line,
e.g. a bare newline), the line that contains TO, so the height matches
an ordinary measurement.  Whatever is drawn on TO's line is left out by
construction, and the result with no such content is byte-identical to
before.

IGNORE-LINE-AT-END was added in commit 43c4cc2ea29 (2021-12-18), and
the cons-FROM "pixels around a position" form in d54d8a88e9a
(2021-12-23), both to serve pixel-scroll-precision-scroll-up-page, which
remains the only in-tree caller of that form.  The option was
implemented by withholding the last line's ascent and descent from the
returned height -- correct only when the measurement already stops at
the top of TO's line, which a plain line satisfies but a line with a
string drawn above TO does not.

The change is confined to the IGNORE-LINE-AT-END branch; every other
caller takes the unchanged path.  In pixel-scroll-precision-mode this
over-count is one cause of the visible scrolling glitches tracked in
bug#64252.  Correcting the measurement is necessary for scrolling
smoothly onto a tall line, but not sufficient by itself: more contained
Lisp-side fixes (to be submitted under bug#64252) are also required.

----------------------------------------------------------------------

== A note on an alternative I considered ==

I left this out of the commit message to keep it focused.  An alternative
route is to keep the old "measure all the way down to TO's line"
and then correct: look at the overlay strings that land on TO's line,
work out how much vertical space they add, and subtract that line's
height back out.  I tried that first and dropped it.  It forces the code
to find and classify whatever sits at TO -- a before-string, an
after-string, a zero-length overlay (which the ordinary char-property
lookups cannot even see), or a display property, each its own case -- and
then subtract a height the iterator had already folded in.  The walk-down
sidesteps all of that: it stops at the top of TO's line, so the string is
never reached and there is nothing to detect or subtract, and it measures
the span only once.

== The patch ==

The patch applies to current master.  It changes only the
IGNORE-LINE-AT-END branch, so every other caller follows the unchanged
path: the three existing `window-text-pixel-size' tests introduced with
bug#45748 still pass, and the patch adds one new regression test
(the comparison shown in the reproducer above).

I am looking forward to hearing your feedback.

Thanks,
Andrea
