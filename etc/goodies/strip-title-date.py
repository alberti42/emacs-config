#!/usr/bin/env python3
"""Strip the redundant leading ISO date from #+title: in an org note tree.

The date is kept in the file name (which is what sorts the notes in dired and
Finder) and is therefore duplicated in the title.  This removes it from the
title only, and only when it provably matches the file name date, so nothing
is lost.

Deliberately NOT keyed on the :CREATED: property: in the Obsidian import that
property drifted from the note date in a number of files, while the file name
date matched the title date everywhere.  The file name is authoritative.

Also rewrites `[[id:...][<dated title>]]` link descriptions so labels do not
keep a date the target no longer shows.

Every write restores the original mtime (and atime).  mtime is a sort key in
dired and Finder, and vulpea extracts `modified-at' from it at sync time, so a
cosmetic title edit must not disturb it.  `:MODIFIED:' is likewise left alone:
stripping a duplicated date from a title is not a semantic edit of the note.
(The `before-save-hook' stamp in vulpea-vault/modified-stamp.el does not fire
here, since this edits outside Emacs.)

Dry run by default; pass --apply to write.

    ./strip-title-date.py ~/org/Work            # report
    ./strip-title-date.py ~/org/Work --apply    # rewrite
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# Leading ISO date in a #+title:, with the separator that follows it.
TITLE_RE = re.compile(
    r"^(?P<kw>[ \t]*#\+title:[ \t]*)"
    r"(?P<date>\d{4}-\d{2}-\d{2})"
    r"(?P<sep>[ \t]+|[ \t]*[-–—][ \t]*)"
    r"(?P<rest>\S.*)$",
    re.IGNORECASE | re.MULTILINE,
)

FILENAME_DATE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})")

ID_LINK_RE = re.compile(r"\[\[id:(?P<id>[0-9A-Fa-f-]+)\]\[(?P<desc>[^]]*)\]\]")


def write_preserving_times(path: Path, text: str) -> None:
    """Write TEXT to PATH, then restore PATH's original atime/mtime.

    Nanosecond `st_*_ns' values are used rather than the float seconds, so the
    timestamp round-trips exactly instead of being rounded.
    """
    st = path.stat()
    path.write_text(text, encoding="utf-8")
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))


def scan(root: Path) -> tuple[dict[str, tuple[str, str]], list[tuple[Path, str, str, str]]]:
    """Return (id -> (old dated title, new title)) and planned title rewrites."""
    id_to_title: dict[str, tuple[str, str]] = {}
    plans: list[tuple[Path, str, str, str]] = []

    for path in sorted(root.rglob("*.org")):
        text = path.read_text(encoding="utf-8", errors="strict")
        m = TITLE_RE.search(text)
        if not m:
            continue

        fn = FILENAME_DATE_RE.match(path.name)
        if not fn:
            print(f"SKIP (no date in file name): {path.name}", file=sys.stderr)
            continue
        if fn.group(1) != m.group("date"):
            print(
                f"SKIP (title {m.group('date')} != file name {fn.group(1)}): {path.name}",
                file=sys.stderr,
            )
            continue

        new_title = m.group("rest").rstrip()
        if not new_title:
            print(f"SKIP (title is only a date): {path.name}", file=sys.stderr)
            continue

        plans.append((path, m.group("date"), new_title, text))

        nid = re.search(r"^:ID:[ \t]+(\S+)", text, re.MULTILINE)
        if nid:
            old_title = f"{m.group('date')}{m.group('sep')}{new_title}"
            id_to_title[nid.group(1).lower()] = (old_title, new_title)

    return id_to_title, plans


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("root", type=Path)
    ap.add_argument("--apply", action="store_true", help="write changes")
    ap.add_argument("--no-links", action="store_true",
                    help="do not rewrite id: link descriptions")
    args = ap.parse_args()

    root = args.root.expanduser()
    if not root.is_dir():
        ap.error(f"not a directory: {root}")

    id_to_title, plans = scan(root)
    print(f"\n{len(plans)} title(s) to strip\n")
    for path, date, new_title, _ in plans[:10]:
        print(f"  {date} {new_title}\n    -> {new_title}")
    if len(plans) > 10:
        print(f"  ... and {len(plans) - 10} more")

    # Apply title rewrites, preserving mtime.
    if args.apply:
        for path, _, _, text in plans:
            new = TITLE_RE.sub(
                lambda m: f"{m.group('kw')}{m.group('rest').rstrip()}", text, count=1
            )
            write_preserving_times(path, new)

    # Refresh id: link descriptions that carried the dated title.
    if not args.no_links:
        touched = 0
        relabels: list[tuple[str, str]] = []

        def repl(m: re.Match[str]) -> str:
            entry = id_to_title.get(m.group("id").lower())
            if entry is None:
                return m.group(0)
            old_title, want = entry
            # Only refresh a label that IS the stale dated title.  A hand-written
            # description ("a previous note") is prose and must be left alone.
            if m.group("desc").strip() != old_title.strip():
                return m.group(0)
            relabels.append((m.group("desc"), want))
            return f"[[id:{m.group('id')}][{want}]]"

        for path in sorted(root.rglob("*.org")):
            text = path.read_text(encoding="utf-8", errors="strict")
            before = len(relabels)
            new = ID_LINK_RE.sub(repl, text)
            if len(relabels) > before:
                touched += 1
                if args.apply:
                    write_preserving_times(path, new)

        print(f"\n{len(relabels)} link label(s) in {touched} file(s) to update\n")
        for old, want in relabels[:10]:
            print(f"  {old}\n    -> {want}")
        if len(relabels) > 10:
            print(f"  ... and {len(relabels) - 10} more")

    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
    else:
        print("\nWritten. Now resync the indexes:")
        print("  emacsclient -e '(vulpea-db-sync)'      # or M-x vulpea-db-sync")
        print("  M-x org-id-update-id-locations")
        print("  C-c n R                                # org-semantic reindex")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
