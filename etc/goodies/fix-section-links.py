#!/usr/bin/env python3
"""Unnumber imported headings and re-point the note's own table of contents.

Obsidian notes numbered their headings in the heading text -- `3.1. Basic
Information'.  Org draws those numbers itself with `org-num-mode', so the
literal ones are both redundant and harmful: a number sits inside every
`[[*Heading]]' target, and inserting one section renumbers every heading
below it, breaking each link that named the old number.

The same notes carried a table of contents built from markdown fragment links,
`[3.1. Basic Information](#basic-information)'.  A fragment names no file, so
the importer resolved it to the note itself and every entry now points at the
top of the note.  The heading it *meant* is recoverable from the link's own
description, which is a copy of the heading text -- so the two repairs have to
happen together, in one pass, or stripping the numbers would strand the links
a second time.

    ** 3.1. Basic Information           ->  ** Basic Information
    [[id:<own>][3.1. Basic Information]] ->  [[*Basic Information]]

Matching on the words of a heading is exactly as fragile as it sounds: it
fails when a note has two headings of the same name, and when the description
was edited away from the heading it came from.  Both are reported rather than
guessed at, and nothing is rewritten unless the text matches a heading in the
same file.

Only a link pointing at the note's *own* `:ID:' is touched.  A link to another
note is a real link and is left alone, number in the description and all.

Every write restores the original mtime (and atime): mtime is a sort key in
dired and Finder, and vulpea extracts `modified-at' from it at sync time.

Dry run by default; pass --apply to write.  Save or revert any note open in
Emacs first -- a later buffer save silently undoes the rewrite.

    ./fix-section-links.py ~/org/Private            # report
    ./fix-section-links.py ~/org/Private --apply    # rewrite
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import Counter
from pathlib import Path

HEADING_RE = re.compile(r"^(?P<stars>\*+)(?P<gap>[ \t]+)(?P<text>.*?)[ \t]*$")

# A section number: dot-separated parts, each one or two digits, and a closing
# dot before the text.  `21.02.2025 Meeting' is a date, not a section: the
# four-digit year fails the part test and the missing closing dot fails the
# whole.
SECTION_RE = re.compile(r"^\d{1,2}(?:\.\d{1,2})*\.[ \t]+(?=\S)")

# An Obsidian block anchor left at the end of a heading, `…^toc' -- the space
# before it is optional, and both forms occur.  It names nothing in org.  This
# is matched against a *heading* only: in a body line the same shape is a LaTeX
# superscript, `E = mc^2'.
ANCHOR_RE = re.compile(r"[ \t\xa0]*\^[A-Za-z0-9][\w-]*$")

# A trailing no-break space, invisible and carried in from the web pages these
# notes were pasted from.  It has to go before a heading can be matched by its
# words at all.
NBSP_RE = re.compile(r"[ \t\xa0]+$")

ID_RE = re.compile(r"^[ \t]*:ID:[ \t]+(\S+)", re.MULTILINE)
ID_LINK_RE = re.compile(r"\[\[id:(?P<id>[0-9A-Fa-f-]+)\]\[(?P<desc>[^]]*)\]\]")


def write_preserving_times(path: Path, text: str) -> None:
    """Write TEXT to PATH, then restore PATH's original atime/mtime.

    Nanosecond `st_*_ns' values are used rather than the float seconds, so the
    timestamp round-trips exactly instead of being rounded.
    """
    st = path.stat()
    path.write_text(text, encoding="utf-8")
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))


def unnumber(text: str) -> tuple[str, set[str]]:
    """Return TEXT without its section number, block anchor and trailing space.

    The second value names what was removed, so the report can say which of
    the three happened rather than showing a heading that looks unchanged
    (a no-break space is invisible either way).
    """
    why: set[str] = set()
    new = text
    if SECTION_RE.match(new):
        new = SECTION_RE.sub("", new)
        why.add("number")
    if ANCHOR_RE.search(new):
        new = ANCHOR_RE.sub("", new)
        why.add("anchor")
    if NBSP_RE.search(new):
        new = NBSP_RE.sub("", new)
        why.add("trailing space")
    return new.strip(), why


def words_of(text: str) -> str:
    """The key a heading and a link description are matched on."""
    return unnumber(text)[0].replace("\xa0", " ").casefold()


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

    renamed: list[str] = []
    relinked: list[str] = []
    problems: list[str] = []
    skipped: list[str] = []
    counted: Counter[frozenset[str]] = Counter()
    touched = 0

    for path in sorted(root.rglob("*.org")):
        text = path.read_text(encoding="utf-8", errors="strict")
        rel = path.relative_to(root)

        own = ID_RE.search(text)
        own_id = own.group(1).lower() if own else None

        # Per file, not per link.  A table of contents half of whose entries
        # became `[[*Heading]]' while the rest still point at the top of the
        # note reads worse than one that is uniformly wrong, and it hides which
        # entries are the broken ones.  So a file whose links do not all
        # resolve is reported and left exactly as it was -- headings included,
        # since unnumbering them without re-pointing the links is the same
        # half-done state one level down.
        stale: list[str] = []

        # Pass 1: the headings, and the map from their words to their new text.
        lines = text.split("\n")
        by_words: dict[str, str] = {}
        duplicated: set[str] = set()
        my_renamed: list[str] = []
        my_relinked: list[str] = []
        my_counted: Counter[frozenset[str]] = Counter()
        changed = 0
        for i, line in enumerate(lines):
            m = HEADING_RE.match(line)
            if not m:
                continue
            old = m.group("text")
            new, why = unnumber(old)
            if not new:
                problems.append(f"{rel}:{i + 1}: heading is only a number: {old}")
                continue
            key = words_of(old)
            if key in by_words:
                duplicated.add(key)
            by_words[key] = new
            if new == old:
                continue
            lines[i] = f"{m.group('stars')}{m.group('gap')}{new}"
            my_renamed.append(
                f"{rel}:{i + 1}: [{', '.join(sorted(why))}] {old}\n      -> {new}"
            )
            my_counted[frozenset(why)] += 1
            changed += 1

        # Pass 2: the note's own table of contents.
        def repoint(m: re.Match[str]) -> str:
            nonlocal changed
            if own_id is None or m.group("id").lower() != own_id:
                return m.group(0)
            head = by_words.get(words_of(m.group("desc")))
            if head is None:
                stale.append(f"{rel}: no heading matches {m.group('desc')!r}")
                return m.group(0)
            if "[" in head or "]" in head:
                problems.append(
                    f"{rel}: heading {head!r} has brackets, no [[*…]] target -- left alone"
                )
                return m.group(0)
            if words_of(m.group("desc")) in duplicated:
                problems.append(
                    f"{rel}: {head!r} names more than one heading -- link goes to the first"
                )
            changed += 1
            # With a description, since a bare `[[*Heading]]' displays its own
            # target -- asterisk and all -- wherever there is nothing else to
            # show.
            my_relinked.append(
                f"{rel}: {m.group('desc')}\n      -> [[*{head}][{head}]]"
            )
            return f"[[*{head}][{head}]]"

        new_text = ID_LINK_RE.sub(repoint, "\n".join(lines))

        if stale:
            skipped.append(
                f"{rel}\n      {len(stale)} of its links name no heading here; "
                f"file left untouched"
            )
            problems.extend(stale)
            continue

        if not changed:
            continue
        renamed.extend(my_renamed)
        relinked.extend(my_relinked)
        counted.update(my_counted)
        touched += 1
        if args.apply:
            write_preserving_times(path, new_text)

    print(f"\n{len(renamed)} heading(s) to clean, "
          f"{len(relinked)} link(s) to re-point, in {touched} file(s)")
    for why, n in sorted(counted.items(), key=lambda kv: -kv[1]):
        print(f"    {n:4}  {' + '.join(sorted(why))}")
    print()
    for s in renamed[:6]:
        print(f"  {s}")
    if len(renamed) > 6:
        print(f"  ... and {len(renamed) - 6} more headings")
    print()
    for s in relinked[:6]:
        print(f"  {s}")
    if len(relinked) > 6:
        print(f"  ... and {len(relinked) - 6} more links")

    if skipped:
        print(f"\n{len(skipped)} file(s) left untouched:\n", file=sys.stderr)
        for s in skipped:
            print(f"  {s}", file=sys.stderr)
    if problems:
        print(f"\n{len(problems)} needing a look:\n", file=sys.stderr)
        for s in problems:
            print(f"  {s}", file=sys.stderr)

    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
    else:
        print("\nWritten. Now resync the indexes:")
        print("  emacsclient -e '(vulpea-db-sync)'      # or M-x vulpea-db-sync")
        print("  C-c n R                                # org-semantic reindex")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
