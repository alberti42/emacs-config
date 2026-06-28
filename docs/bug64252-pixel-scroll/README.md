# bug#64252 — pixel-scroll-precision jumps over tall lines

claude --resume ef1058ee-f01b-49ba-931c-7a6505a9859b

A three-commit series that fixes
[bug#64252](https://debbugs.gnu.org/cgi/bugreport.cgi?bug=64252):
`pixel-scroll-precision-mode` lurches, snaps back, and cannot reach the
top/bottom when a buffer contains a **display line taller than the scroll
step** — an inline image, or an overlay before/after-string carrying an
image (the markdown-ts `"\n " + image` idiom is the worst case).

The commits live in the local Emacs fork
(`~/Documents/Programming/Others/fork-emacs`) on branch
`fix/pixel-scroll-precision-margin-settle`.

## The series (apply in this order)

|#|Commit (title)                                                  |File(s)                |Scope                  |
|-|----------------------------------------------------------------|-----------------------|-----------------------|
|1|[Respect scroll-margin in                                       |`lisp/pixel-scroll.el` |mode-only (feature)    |
| |pixel-scroll-precision-mode](01-respect-scroll-margin.md)       |                       |                       |
|2|[Force the window start in pixel-scroll-precision page          |`lisp/pixel-scroll.el` |mode-only (fix)        |
| |scrolling](02-force-window-start.md)                            |                       |                       |
|3|[Exclude a display string anchored at window-start from backward|`src/xdisp.c` + `test/`|general primitive (fix)|
| |span](03-exclude-boundary-display-string.md)                    |                       |                       |

Commits are identified by their title (first line) above, not by SHA — the
branch is rebased and amended often, so any SHA goes stale almost immediately.

## What the symptoms looked like

Three distinct misbehaviours, all triggered by a tall line:

1. **Lurch to the buffer edge / can't reach the top.** Scrolling up through
   (or onto) a tall line, `window-start` was thrown to the buffer edge and
   the view could not settle. → fixed by commit **2** (force the start).
2. **Re-snap / double-traversal.** Scrolling up, `window-start` would land on
   the tall line, the view would crawl through it via `vscroll`, then *snap
   back* and traverse the same image again. → fixed by commit **3** (the
   backward measurement was over-counting a boundary string).
3. **Margin fighting smooth scroll.** A non-zero `scroll-margin` made
   redisplay re-impose the margin mid-gesture, reading as the text snapping
   back near edges. → fixed by commit **1** (suspend `scroll-margin` during a
   gesture, restore on idle).

## Two independent root causes

- **A redisplay/measurement bug in the C primitive `window_text_pixel_size`**
  (commit 3): its *backward* form (`FROM` = a cons with a negative offset)
  wrongly counted a before/after-string anchored at the `TO` boundary as part
  of the span *above* `TO`. This is a general bug in shared API, not specific
  to pixel-scroll — though pixel-scroll is effectively its only in-tree caller
  of the backward form. **This is the commit worth upstreaming on its own
  merits**, and it ships with an ERT regression test.

- **`pixel-scroll-precision`'s own page-scroll logic** (commits 1 & 2): it used
  `set-window-start` with `NOFORCE` non-nil, which lets redisplay *disregard*
  the requested start when point would be invisible — across a tall line that
  produced the lurch. Forcing the start fixes it; the manual point
  repositioning that rides point at the window **edge** had to be kept (a
  forced start otherwise recenters an off-screen point to mid-window).

## Hard-won gotchas (read before touching this code again)

- **Batch `redisplay t` does not reproduce interactive point-visibility
  recentering.** Several wrong conclusions came from batch drives that looked
  smooth while interactive scrolling lurched. Verify scroll/point fixes with a
  live frame (or the user's live trace), not batch.
- **Measure point's *row*, not just `window-start`/`vscroll`.** The mid-window
  teleport regression (see commit 2's history) was invisible to traces that
  only watched the window start and collapsed point-unchanged rows.
- **`make-cursor-line-fully-visible` is a red herring here.** It governs a
  *partially* visible cursor line; the recenter that bit us is the plain
  *point-must-be-visible* recompute, which it does not control.
- **A daemon started with `--daemon` (not `--fg-daemon`) `chdir`s to `/`**, so
  launch the test binary with an **absolute** `argv[0]` or it fails to find
  its Lisp (`Cannot open load file: server`).
- **`emacsclient -c` blocks** until its frame is deleted; for a non-blocking
  GUI frame on macOS use
  `-e '(make-frame (quote ((window-system . ns))))'`.

## Verifying

```sh
cd ~/Documents/Programming/Others/fork-emacs
make -j8                       # ~10s incremental for one TU

# regression test for commit 3 (runs in batch):
./src/emacs -Q --batch -l ert -l test/src/xdisp-tests.el \
  --eval '(ert-run-tests-batch-and-exit "backward-boundary-string")'
```

### Self-standing reproducer

[`../debug-pixel-scroll-tall-line.el`](../debug-pixel-scroll-tall-line.el) is a
load-and-run reproducer in the same style as the other `docs/debug-*.el`. Each
test opens a buffer that documents itself.

```sh
EMACS=~/Documents/Programming/Others/fork-emacs/src/emacs   # or any build
$EMACS -Q --load docs/debug-pixel-scroll-tall-line.el \
       --eval '(pixel-scroll-tall-line-test-001)'
```

- `pixel-scroll-tall-line-test-001` — measures the defect live and prints a
  **PATCHED / UNPATCHED** verdict with the numbers (works even in `-nw`). On an
  unpatched build it reports the tall boundary string leaking in
  (`plain=1, before=5, after=5`); on a patched build all three are equal.
- `pixel-scroll-tall-line-test-002` — the visible scrolling symptom (tall
  after-string image; GUI).
- `pixel-scroll-tall-line-test-003` — the control (same image as a `display`
  property; smooth on both builds, isolating what the patch changes).

(The throwaway development harness `psd.el` lived in the session scratchpad and
is not committed; the reproducer above supersedes it for sharing.)
