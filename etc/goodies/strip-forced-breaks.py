#!/usr/bin/env python3
"""Strip the trailing `\\\\' forced line break from prose in an org note tree.

Obsidian notes ended a line with two spaces -- markdown's hard line break --
wherever the writer wanted a break rather than a wrapped paragraph.  The
spaces were invisible in Obsidian, which breaks a line on a bare newline
anyway, so they accumulated unnoticed.  Pandoc translated each one into org's
own forced break, `\\\\' at end of line, which is correct and, unlike its
markdown counterpart, plainly visible while reading the note.

Removing it costs nothing on screen (org does not reflow text in a buffer) and
merges those lines into a running paragraph on export.  `org-export-preserve-
breaks' restores the Obsidian model globally if the breaks are wanted back.

`\\\\' is also the row separator of a LaTeX environment, so a line inside
multi-line math is never touched -- nor is one inside a block that is quoting
something verbatim.  Only `quote' among the blocks holds prose, and it is
treated as such.  Inline math on the line is irrelevant: `\\(x\\)=1.\\\\' is a
sentence with a break after it, not a matrix row.

Every write restores the original mtime (and atime): mtime is a sort key in
dired and Finder, and vulpea extracts `modified-at' from it at sync time.

Dry run by default; pass --apply to write.  Save or revert any note open in
Emacs first -- a later buffer save silently puts the markers back.

    ./strip-forced-breaks.py ~/org/Work            # report
    ./strip-forced-breaks.py ~/org/Work --apply    # rewrite
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# Trailing forced break: two backslashes ending the line, whitespace allowed
# after them (org accepts it, and the importer sometimes left one).
BREAK_RE = re.compile(r"\\\\[ \t]*$")

# Blocks whose contents are reproduced verbatim.  `quote' is prose and is the
# one block deliberately absent from this set.
VERBATIM_BLOCKS = {
    "src",
    "example",
    "export",
    "verse",
    "latex",
    "ascii",
    "html",
    "comment",
}

BEGIN_RE = re.compile(r"^[ \t]*#\+begin_(?P<kind>\S+)", re.IGNORECASE)
END_RE = re.compile(r"^[ \t]*#\+end_(?P<kind>\S+)", re.IGNORECASE)

ENV_BEGIN_RE = re.compile(r"\\begin\{(?P<env>[^}]+)\}")
ENV_END_RE = re.compile(r"\\end\{(?P<env>[^}]+)\}")


def write_preserving_times(path: Path, text: str) -> None:
    """Write TEXT to PATH, then restore PATH's original atime/mtime.

    Nanosecond `st_*_ns' values are used rather than the float seconds, so the
    timestamp round-trips exactly instead of being rounded.
    """
    st = path.stat()
    path.write_text(text, encoding="utf-8")
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))


def protected_lines(lines: list[str]) -> list[bool]:
    """Mark every line whose `\\\\' means something other than a line break.

    A region counts as protected while it spans more than one line: a `$$…$$',
    `\\[…\\]' or `\\begin{env}…\\end{env}' that opens and closes on the same
    line cannot hold a row separator at the *end* of that line, so it is left
    unmarked and the break after it survives the test.
    """
    protected = [False] * len(lines)
    block: str | None = None
    math: str | None = None  # "$$" | "\\]" | an environment name

    for i, line in enumerate(lines):
        if block is not None:
            protected[i] = True
            m = END_RE.match(line)
            if m and m.group("kind").lower() == block:
                block = None
            continue

        m = BEGIN_RE.match(line)
        if m:
            kind = m.group("kind").lower()
            if kind in VERBATIM_BLOCKS:
                block = kind
                protected[i] = True
            continue

        if math is not None:
            protected[i] = True
            if math == "$$" and "$$" in line:
                math = None
            elif math == "\\]" and "\\]" in line:
                math = None
            elif any(e.group("env") == math for e in ENV_END_RE.finditer(line)):
                math = None
            continue

        # A table row: a `\\' inside a cell is LaTeX, not a break.
        if line.lstrip().startswith("|"):
            protected[i] = True
            continue

        if line.count("$$") % 2 == 1:
            math = "$$"
            protected[i] = True
            continue

        opened = [e.group("env") for e in ENV_BEGIN_RE.finditer(line)]
        closed = [e.group("env") for e in ENV_END_RE.finditer(line)]
        for env in opened:
            if env not in closed:
                math = env
                protected[i] = True
                break
        if protected[i]:
            continue

        if line.count("\\[") > line.count("\\]"):
            math = "\\]"
            protected[i] = True

    return protected


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

    stripped: list[str] = []
    kept: list[str] = []
    touched = 0

    for path in sorted(root.rglob("*.org")):
        text = path.read_text(encoding="utf-8", errors="strict")
        if "\\\\" not in text:
            continue

        lines = text.split("\n")
        protected = protected_lines(lines)
        changed = 0
        for i, line in enumerate(lines):
            if not BREAK_RE.search(line):
                continue
            where = f"{path.relative_to(root)}:{i + 1}"
            if protected[i]:
                kept.append(f"{where}: {line.strip()[:96]}")
                continue
            lines[i] = BREAK_RE.sub("", line).rstrip()
            stripped.append(f"{where}: {lines[i].strip()[:96]}")
            changed += 1
        if not changed:
            continue
        touched += 1
        if args.apply:
            write_preserving_times(path, "\n".join(lines))

    print(f"\n{len(stripped)} forced break(s) in {touched} file(s) to strip\n")
    for s in stripped[:10]:
        print(f"  {s}")
    if len(stripped) > 10:
        print(f"  ... and {len(stripped) - 10} more")

    print(f"\n{len(kept)} kept (inside math, a table, or a verbatim block)\n",
          file=sys.stderr)
    for s in kept[:10]:
        print(f"  {s}", file=sys.stderr)
    if len(kept) > 10:
        print(f"  ... and {len(kept) - 10} more", file=sys.stderr)

    if not args.apply:
        print("\nDry run. Re-run with --apply to write.")
    else:
        print("\nWritten. Now resync the indexes:")
        print("  emacsclient -e '(vulpea-db-sync)'      # or M-x vulpea-db-sync")
        print("  C-c n R                                # org-semantic reindex")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
