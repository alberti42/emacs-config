# Idea: native Apple Event / AppleScript support for Emacs (NS)

Status: **idea / scoping note.** Not started. Written so the reasoning is ready
if picked up later. The pitch strategy matters as much as the code (see
*Approach* below).

## One-line summary

Emacs on macOS (NS) registers no custom Apple Event handlers, so it can't be
driven from the native macOS scripting layer (AppleScript, JXA, Shortcuts.app,
Automator, Alfred/Raycast, Keyboard Maestro). A small `NSAppleEventManager`
handler — plus eventually an `sdef` dictionary — would plug Emacs into that
ecosystem. "Open file at line:column" is the natural first verb.

## What exists today (verified in source)

- `EmacsApp` implements only the standard Cocoa delegate open methods:
  `application:openFile:` / `openFiles:` / `openTempFile:` /
  `openFileWithoutUI:` (`src/nsterm.m` 6649–6688). The system synthesizes
  these from the **`odoc`** ("open document") Apple Event — which carries only a
  file URL, no line, no selection.
- The open path queues into `ns_pending_files`, then `-[EmacsApp openFile:]`
  (`src/nsterm.m` 6400) fires a non-key Lisp event `KEY_NS_OPEN_FILE_LINE`
  and sets `ns_input_file` (path) and `ns_input_line` (**hard-coded `Qnil`** on
  this path).
- **The line-display Lisp already exists and works**: `ns-open-file-select-line`
  reads `ns-input-line` — an integer → `goto-line`, or a cons `(start . end)` →
  highlight overlay (`lisp/term/ns-win.el` 399–435). Bound via
  `[ns-open-file-line] -> ns-open-file-select-line`. Nothing on modern macOS
  feeds it, so it's effectively **dormant**.
- There is **no** `NSAppleEventManager`/`setEventHandler` registration, no
  `sdef`, no AppleScript dictionary. `osascript -e 'tell application "Emacs"…'`
  has nothing to talk to.

Implication: an "Apple Event shim" (in practice `open -a Emacs file`) opens the
file but **cannot carry a line/column** — there is no field and no handler. The
only external interface that carries line/column today is `emacsclient
+LINE:COLUMN` (and `emacsclient --eval`).

## What a patch would involve

Mechanically low difficulty; structurally a mirror of `-[EmacsApp openFile:]`.

1. **Register a real handler** (the genuinely new part), in
   `applicationDidFinishLaunching` or near delegate setup:
   ```objc
   [[NSAppleEventManager sharedAppleEventManager]
       setEventHandler:self
          andSelector:@selector(handleOpenWithLine:withReplyEvent:)
        forEventClass:kClass andEventID:kID];
   ```
   Handler pulls path + line/column out of the `NSAppleEventDescriptor`, stuffs
   `ns_input_file` / `ns_input_line` / a new `ns_input_column`, fires the
   existing `KEY_NS_OPEN_FILE_LINE` event. 30–50 lines of ObjC.
2. **Column support** (small): a `ns-input-column` defvar + `move-to-column` in
   the Lisp handler.
3. **`sdef` dictionary** (optional, later): the discoverable AppleScript/JXA/
   Shortcuts surface. This is the part that makes it ecosystem-visible.

## The harder 20% (judgment, not effort)

- **Interface design**: event class/ID + `sdef`, or extend the existing
  `odoc`/open path with a line/column parameter. Clean + upstreamable is the
  real cost.
- **Daemon delivery**: Apple Events go to the process registered with
  LaunchServices as the GUI app — naturally a **non-daemon Emacs.app**. A
  terminal-started `--fg-daemon` is the fiddly case. v1 should target the GUI
  app process and say so. (This also means daemon users are already on the
  `emacsclient` path, where line/col works today.)
- **Upstream taste / API commitment**: an `sdef` is a long-term public API —
  once shipped people script against it and it's hard to change. NS maintainers
  are conservative about macOS surface area and will likely be *more* cautious
  about a dictionary than about a single internal open-at-line extension.

## Honest scope of the value

- **Overlaps `emacsclient --eval`**: anything an AE verb does, `emacsclient`
  can already do. The value is **discoverability + native integration** (an
  `sdef` that Shortcuts.app can see), not new capability. Pre-empt this
  objection, don't dodge it.
- **Audience without the AppleScript angle** is narrow: GUI Emacs.app run
  *deliberately without a server* that wants native "Open with… at line." Even
  a non-daemon Emacs can `(server-start)` and use `emacsclient`; and external
  tools (e.g. Sublime Merge's "external editor") need a shim anyway, where
  calling `emacsclient -n +LINE:COL file` is one line.
- **The AppleScript/`sdef` framing widens it** from that niche to "anyone
  automating Emacs from the macOS scripting layer" — the stronger pitch.

## Approach (how to propose it)

Send a **demonstrator, framed as a question**, not a manifesto. "Hey, here's a
possible way to do this — what do you think, what would you change?" beats "this
is how it should be," because:

- NS is maintained by a small, pragmatic group; a compiling thing they can run
  is more legible than prose about an interface that doesn't exist.
- It has a credibility anchor: the `ns-input-line` path **already exists but is
  dormant** — ask whether it was left dormant on purpose. The answer tells you
  if the idea is viable before polishing.
- "What would you change?" converts a gatekeeping conversation ("we don't want
  more macOS surface") into a design conversation ("do it this other way" = yes
  in disguise).

Refinements (consistent with [[feedback_plain_english_in_writing]] and the
lead-with-user-experience habit from the round-undecorated bug report):

- **Lead with the user-visible win**, not the mechanism: "Emacs could be
  scriptable from Shortcuts/AppleScript like other Mac apps" / "external tools
  could open Emacs at a line."
- **Mark it explicitly as a demonstrator** (daemon delivery untested, no `sdef`
  yet) to keep the thread on the idea, not the scaffolding.
- **Say you'll do the finishing** — ask for direction, not labor — so a
  half-finished demo doesn't read as a chore handed to the maintainers.
- **One verb only** for the demo (open-at-line, or a single eval/`do-script`):
  enough to show the shape, not a populated dictionary that reads as a finished
  framework. Present the `sdef` as "smallest possible seed, your call on growth."
- First step is a short design note to `emacs-devel` / `bug-gnu-emacs` *with*
  the demonstrator, not abstract first.

## Related

- `emacsclient +LINE:COLUMN` and `emacsclient --eval` are the existing,
  column-capable external interfaces — the baseline any patch is measured
  against.
- [[project_finder_open_ns_pop_up_frames]] — Finder "Open with Emacs" uses the
  same NS `odoc` path (`ns-pop-up-frames`), distinct from `emacsclient`
  (`server-window`).
