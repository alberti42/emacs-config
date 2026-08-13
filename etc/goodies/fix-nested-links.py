#!/usr/bin/env python3
"""Repair org links whose description is a nested link, in an org note tree.

The Obsidian import handed `http(s):'/`mailto:' links back to pandoc as
markdown, and pandoc's GFM reader (autolink_bare_uris) linkified the bare URI
sitting in the link *label* as well.  A link inside a link has no org syntax,
so the writer emitted it literally:

    [https://x](https://x)          ->  [[https://x][[[https://x]]]]
    [x@y](mailto:x@y)               ->  [[mailto:x@y][[[mailto:x@y][x@y]]]]

which org renders as the brackets themselves.  obsidian-to-org.py no longer
produces this (the extension is switched off), but the import has already run
and the notes have been edited since, so the tree is repaired in place instead
of being regenerated.

The repair unwraps the nested link to its text and then drops a description
that has become identical to the target -- exactly the two forms above turn
into `[[https://x]]' and `[[mailto:x@y][x@y]]', which is what the fixed
importer writes today.

Only a nested link pointing at the *same* target as the one enclosing it is
unwrapped, since that is the signature of an autolinked label.  A nested link
pointing somewhere else is a real construct org cannot express -- an image
used as a link description, `[![](thumb.jpg)](doc.pdf)' -- which the importer
still produces and which needs a human decision.  Those are reported, not
touched.

Every write restores the original mtime (and atime): mtime is a sort key in
dired and Finder, and vulpea extracts `modified-at' from it at sync time.

Dry run by default; pass --apply to write.  Save or revert any note open in
Emacs first -- a later buffer save silently puts the broken link back.

    ./fix-nested-links.py ~/org/Work            # report
    ./fix-nested-links.py ~/org/Work --apply    # rewrite
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# A parsed org bracket link: target, and the description as a list of plain
# strings and nested Link objects (None when the link carries no description).
class Link:
    __slots__ = ("start", "end", "target", "desc")

    def __init__(self, start: int, end: int, target: str, desc):
        self.start, self.end, self.target, self.desc = start, end, target, desc

    def text(self) -> str:
        """The link as the reader sees it: its description, else its target."""
        if self.desc is None:
            return self.target
        return "".join(p if isinstance(p, str) else p.text() for p in self.desc)


def write_preserving_times(path: Path, text: str) -> None:
    """Write TEXT to PATH, then restore PATH's original atime/mtime.

    Nanosecond `st_*_ns' values are used rather than the float seconds, so the
    timestamp round-trips exactly instead of being rounded.
    """
    st = path.stat()
    path.write_text(text, encoding="utf-8")
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))


def normalize(target: str) -> str:
    """Compare two targets ignoring a trailing slash.

    A GFM autolink stops before a trailing slash the destination kept, so the
    label and the destination of one and the same URL can differ by that one
    character.
    """
    return target.rstrip("/")


def parse_link(text: str, i: int) -> Link | None:
    """Parse the org bracket link starting at text[i] == '[', or return None.

    Nesting is handled by recursion: the description ends at the first `]]'
    that does not belong to a link inside it.  A regexp cannot draw that line,
    which is why the broken links are scanned rather than matched.
    """
    if not text.startswith("[[", i):
        return None
    close = text.find("]", i + 2)
    if close == -1:
        return None
    target = text[i + 2 : close]
    if text.startswith("]]", close):
        return Link(i, close + 2, target, None)
    if not text.startswith("][", close):
        return None

    desc: list = []
    buf = ""
    k = close + 2
    while k < len(text):
        if text.startswith("]]", k):
            if buf:
                desc.append(buf)
            return Link(i, k + 2, target, desc)
        nested = parse_link(text, k) if text.startswith("[[", k) else None
        if nested is not None:
            if buf:
                desc.append(buf)
                buf = ""
            desc.append(nested)
            k = nested.end
            continue
        buf += text[k]
        k += 1
    return None  # unterminated


def scan_links(text: str):
    """Yield every top-level org bracket link in TEXT, in order."""
    i = 0
    while (i := text.find("[[", i)) != -1:
        link = parse_link(text, i)
        if link is None:
            i += 2
            continue
        yield link
        i = link.end


def repair(link: Link) -> str | None:
    """Return the repaired form of LINK, or None if there is nothing to fix."""
    if link.desc is None:
        return None
    nested = [p for p in link.desc if isinstance(p, Link)]
    if not nested:
        return None
    if any(normalize(n.target) != normalize(link.target) for n in nested):
        return None  # not an autolinked label -- leave it to a human
    desc = link.text()  # nested links flatten to their own text
    if desc == link.target:
        return f"[[{link.target}]]"
    return f"[[{link.target}][{desc}]]"


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("root", type=Path)
    ap.add_argument("--apply", action="store_true", help="write changes")
    args = ap.parse_args()

    root = args.root.expanduser()
    if not root.is_dir():
        ap.error(f"not a directory: {root}")

    fixes: list[tuple[str, str]] = []
    skipped: list[tuple[str, int, str]] = []
    touched = 0

    for path in sorted(root.rglob("*.org")):
        text = path.read_text(encoding="utf-8", errors="strict")
        if "[[" not in text:
            continue

        out: list[str] = []
        pos = 0
        changed = 0
        for link in scan_links(text):
            if link.desc is None or not any(isinstance(p, Link) for p in link.desc):
                continue
            new = repair(link)
            if new is None:
                line = text.count("\n", 0, link.start) + 1
                raw = text[link.start : link.end]
                skipped.append((str(path.relative_to(root)), line, raw))
                continue
            out.append(text[pos : link.start])
            out.append(new)
            pos = link.end
            changed += 1
            fixes.append((text[link.start : link.end], new))
        if not changed:
            continue
        out.append(text[pos:])
        touched += 1
        if args.apply:
            write_preserving_times(path, "".join(out))

    print(f"\n{len(fixes)} nested link(s) in {touched} file(s) to repair\n")
    for old, new in fixes[:10]:
        print(f"  {old}\n    -> {new}")
    if len(fixes) > 10:
        print(f"  ... and {len(fixes) - 10} more")

    if skipped:
        print(
            f"\n{len(skipped)} nested link(s) left alone "
            "(description points elsewhere -- decide by hand):\n",
            file=sys.stderr,
        )
        for relpath, line, raw in skipped:
            print(f"  {relpath}:{line}\n    {raw}", file=sys.stderr)

    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
    else:
        print("\nWritten. Now resync the indexes:")
        print("  emacsclient -e '(vulpea-db-sync)'      # or M-x vulpea-db-sync")
        print("  C-c n R                                # org-semantic reindex")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
