#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = ["pyyaml"]
# ///
"""Convert an Obsidian vault to org-mode notes for vulpea.

Reads a vault of markdown notes carrying a `uuid` in YAML front matter and
writes a mirrored tree of .org files whose file-level :ID: property is that
same uuid, so links survive renames and external UUID references keep working.

    uv run obsidian-to-org.py --dry-run
    uv run obsidian-to-org.py --only '06 MPQ' --limit 5
    uv run obsidian-to-org.py

Nothing is ever written inside the vault.

Design notes, in decreasing order of "will silently break if changed":

1. The :PROPERTIES: drawer holding :ID: MUST be the first byte of the file.
   A leading blank line, or placing it after #+title:, makes org return nil
   for the file-level ID with no error.  Verified against org 9.8.7.

2. Links are resolved to their targets *before* pandoc runs and replaced with
   opaque alphanumeric tokens, which pandoc passes through untouched.  The
   final org link text is substituted back afterwards.  This avoids every
   escaping question that arises from feeding paths with spaces, brackets or
   non-ASCII through markdown and then through pandoc.

3. Tokenizing must skip fenced blocks and inline code spans, or a `[[foo]]`
   written inside a shell snippet becomes a real link.

4. Org tag syntax is [[:alnum:]_@#%]+ — no `/`, no `-`.  Obsidian's nested
   `#Teaching/QCMPSIM` becomes the bare child tag `QCMPSIM`, with the
   hierarchy re-expressed as an org tag group (see --write-tag-alist).  A
   slash tag left in #+filetags: is stored and inherited but matches nothing
   in a tags search, which is why this is a rename and not a passthrough.

5. Attachments default to the org-attach layout: one central store, each
   note's files under <attach-dir>/<first 2 chars of ID>/<rest of ID>/, which
   is what org-attach-id-uuid-folder-format computes.  --attach-dir MUST match
   `org-attach-id-dir' in Emacs; a mismatch yields an empty attachment
   directory rather than an error.  Links to another note's attachment take
   the form attachment:<uuid>/<file>, which stock org does not understand —
   `org-attach-crossref.el' in this config teaches it that form.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import glob
import os
import re
import shutil
import subprocess
import sys
import unicodedata
import urllib.parse
from collections import defaultdict
from pathlib import Path

import yaml

# --------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------

DEFAULT_VAULT = Path("~/Obsidian/Work").expanduser()
DEFAULT_OUT = Path("~/org/Work").expanduser()

# The tag-group declaration is derived from the vault and belongs with it, so it
# goes under the tree's own "00 Meta", mirroring the vault's convention.  None of
# the vault's 00 Meta files are notes, so nothing collides.
META_DIR = "00 Meta"

# The reports are the audit trail for this import, kept in a directory named
# after it so a later import — or a different kind of report — sits beside them
# rather than mixing in.
REPORT_SUBDIR = f"{META_DIR}/reports/import-from-obsidian"

# Directories never walked.
SKIP_DIRS = {".git", ".obsidian", ".smart-env", ".trash", "00 Meta/Templates"}


# Files that are vault machinery rather than notes.  Absence of a `uuid` in
# front matter already excludes them; these are listed so the report can say
# "deliberately skipped" instead of "missing uuid".
KNOWN_NON_NOTES = {
    "AGENTS.md",
    "CLAUDE.md",
    "00 Meta/Misc/Home.md",
    "00 Meta/Misc/Plugins annotations.md",
    "00 Meta/Misc/Sorting configurations.md",
    "00 Meta/Orphaned/List of broken links.md",
    "00 Meta/Orphaned/List of empty files.md",
    "00 Meta/Orphaned/List of orphaned files.md",
}

ORG_TAG_RE = re.compile(r"\A[0-9A-Za-z_@#%]+\Z")

# URI schemes handed straight to org, which passes them to the OS or to a
# link type defined in the Emacs config (x-bdsk: BibDesk, message: Apple
# Mail, pdffile: an Obsidian plugin scheme needing an org-link-set-parameters
# reimplementation).
PASSTHROUGH_SCHEMES = {
    "http",
    "https",
    "mailto",
    "message",
    "x-bdsk",
    "pdffile",
    "obsidian",
    "file",
    "filefinder",
    "ftp",
    "doi",
    "tel",
    "zotero",
}

TOKEN_PREFIX = "ZZORGLINKZZ"
TOKEN_RE = re.compile(TOKEN_PREFIX + r"(\d+)ZZ")

# Regions whose contents must not be treated as markdown: code, and math.
# Math matters as much as code here — in a physics vault `$[[8,3,2]]$` is
# stabilizer-code notation, not a wiki link.  Inline math is deliberately
# restricted to a single line with no inner `$` so that a stray dollar sign in
# prose cannot swallow a large region along with the real links inside it.
PROTECTED_RE = re.compile(
    r"(?P<fence>^[ \t]*(?P<ticks>```+|~~~+)[^\n]*\n.*?^[ \t]*(?P=ticks)[ \t]*$)"
    r"|(?P<code>`+[^`\n]*`+)"
    r"|(?P<dmath>\$\$.*?\$\$)"
    r"|(?P<pmath>\\\(.*?\\\)|\\\[.*?\\\])"
    r"|(?P<imath>\$(?!\s)[^$\n]*[^\s$]\$(?!\d))",
    re.DOTALL | re.MULTILINE,
)


def nfc(text: str) -> str:
    """Normalise to NFC.

    macOS stores these filenames in NFD ("Rahmenvertra" + U+0308) while the
    link text inside the notes is NFC ("…verträge").  Dict lookups are exact,
    so without this every link to a note with an umlaut silently fails to
    resolve.
    """
    return unicodedata.normalize("NFC", text)


def is_debris(path: Path, root: Path) -> bool:
    """True if any component of PATH below ROOT starts with a dot.

    Catches both shapes of filesystem debris found inside attachment folders:
    dotted files (.DS_Store, written by Finder) and dotted directories
    (.ipynb_checkpoints, Jupyter's autosaves beside a notebook attachment).
    Neither is ever an attachment.  Same convention vulpea uses when scanning.
    """
    return any(part.startswith(".") for part in path.relative_to(root).parts)


# Non-greedy up to the first "]]", so that a target may itself contain "]" —
# attachment filenames here include mailing-list subjects like
# "[All-mpq] Important Changes ….eml".
EMBED_RE = re.compile(r"!\[\[(?P<target>[^\n]*?)\]\]")
WIKI_RE = re.compile(r"(?<!!)\[\[(?P<target>[^\n]*?)\]\]")

# Characters pandoc's org writer rewrites into ASCII digraphs (en dash -> "--",
# em dash -> "---", ellipsis -> "...", typographic apostrophe -> "'").  The
# `smart` extension is not supported for the org writer, so the only way to
# keep the originals is to hide them from pandoc behind tokens.
PRESERVE_CHARS_RE = re.compile("[–—…’]")
# Markdown links are NOT matched by regexp: this vault stores attachments in
# "<note name> (attachments)/" folders, so destinations routinely contain
# balanced parentheses that any [^)]* pattern truncates.  See scan_md_links.
LINK_OPEN_RE = re.compile(r"!?\[")

FRONTMATTER_RE = re.compile(r"\A---\n(?P<yaml>.*?)\n---[ \t]*\n?", re.DOTALL)
RAW_SCALAR_RE = "^{key}:[ \t]*(?P<value>.*?)[ \t]*$"


# --------------------------------------------------------------------------
# model
# --------------------------------------------------------------------------


@dataclasses.dataclass(slots=True)
class Note:
    relpath: str  # "06 MPQ/foo.md", vault-relative, POSIX
    path: Path
    uuid: str
    title: str
    org_tags: list[str]
    created: str | None
    modified: str | None
    extras: dict[str, object]
    body: str

    @property
    def out_relpath(self) -> str:
        return self.relpath[: -len(".md")] + ".org"

    @property
    def attach_dir(self) -> Path:
        """The Obsidian convention: a sibling "<note name> (attachments)"."""
        return self.path.parent / f"{self.path.stem} (attachments)"

    def org_attach_relpath(self, attach_dir_name: str) -> str:
        """Where org-attach expects this note's attachments, from the tree root.

        Mirrors org-attach-id-uuid-folder-format: the first two characters of
        the ID become a bucket directory, the rest names the note's own folder.
        """
        return f"{attach_dir_name}/{self.uuid[:2]}/{self.uuid[2:]}"


@dataclasses.dataclass(slots=True)
class LinkEvent:
    """One rewritten (or not) link, for the report."""

    source: str
    kind: str  # wiki | embed | mdlink
    raw: str
    outcome: str  # id | file | passthrough | heading-degraded | blockref-degraded | unresolved
    target: str = ""


@dataclasses.dataclass(slots=True)
class Skipped:
    relpath: str
    reason: str


# --------------------------------------------------------------------------
# front matter
# --------------------------------------------------------------------------


def split_frontmatter(text: str) -> tuple[dict[str, object], str, str]:
    """Return (parsed yaml, raw yaml block, body)."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, "", text
    raw = m.group("yaml")
    try:
        data = yaml.safe_load(raw) or {}
    except yaml.YAMLError as exc:
        raise ValueError(f"unparseable front matter: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("front matter is not a mapping")
    return data, raw, text[m.end() :]


def raw_scalar(raw_yaml: str, key: str) -> str | None:
    """Read a scalar straight from the YAML text.

    Used for `created`/`modified` so the exact timestamp string is preserved:
    yaml.safe_load turns them into datetime objects, and formatting those back
    would silently normalise the offset spelling.
    """
    m = re.search(RAW_SCALAR_RE.format(key=re.escape(key)), raw_yaml, re.MULTILINE)
    if not m:
        return None
    value = m.group("value").strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    return value or None


def map_tag(raw: str) -> tuple[str, str | None]:
    """Map an Obsidian tag to (org tag, group parent or None).

    "#Teaching/QCMPSIM" -> ("QCMPSIM", "Teaching")
    "#Self-learning"    -> ("Self_learning", None)
    """
    tag = raw.strip().lstrip("#").strip("/")
    parent = None
    if "/" in tag:
        head, _, tail = tag.rpartition("/")
        parent = sanitize_tag(head.split("/")[0])
        tag = tail
    return sanitize_tag(tag), parent


def sanitize_tag(tag: str) -> str:
    return re.sub(r"[^0-9A-Za-z_@#%]", "_", tag)


def extract_tags(data: dict[str, object]) -> tuple[list[str], list[tuple[str, str]]]:
    """Return (org tags, [(parent, child), ...] group pairs)."""
    value = data.get("tags")
    if value is None:
        return [], []
    raw_tags = value if isinstance(value, list) else [value]
    tags: list[str] = []
    groups: list[tuple[str, str]] = []
    for raw in raw_tags:
        if not isinstance(raw, str) or not raw.strip():
            continue
        tag, parent = map_tag(raw)
        if not tag:
            continue
        if tag not in tags:
            tags.append(tag)
        if parent:
            groups.append((parent, tag))
    return tags, groups


# --------------------------------------------------------------------------
# indexing
# --------------------------------------------------------------------------


def walk_markdown(vault: Path) -> list[Path]:
    out: list[Path] = []
    for root, dirs, files in os.walk(vault):
        rel_root = Path(root).relative_to(vault).as_posix()
        keep = []
        for d in dirs:
            rel = d if rel_root == "." else f"{rel_root}/{d}"
            if d.startswith(".") or d in SKIP_DIRS or rel in SKIP_DIRS:
                continue
            keep.append(d)
        dirs[:] = keep
        for name in files:
            if name.endswith(".md"):
                out.append(Path(root) / name)
    return sorted(out)


class Index:
    """Everything needed to resolve an Obsidian link target."""

    def __init__(self) -> None:
        self.notes: list[Note] = []
        self.by_relpath: dict[str, Note] = {}  # with and without .md
        self.by_stem: dict[str, list[Note]] = defaultdict(list)
        self.by_title: dict[str, list[Note]] = defaultdict(list)
        # "<note> (attachments)" directory -> the note that owns it
        self.by_attach_dir: dict[str, Note] = {}

    def add(self, note: Note) -> None:
        self.notes.append(note)
        rel = nfc(note.relpath)
        self.by_relpath[rel] = note
        self.by_relpath[rel[: -len(".md")]] = note
        self.by_stem[nfc(Path(rel).stem)].append(note)
        self.by_title[nfc(note.title)].append(note)
        self.by_attach_dir[nfc(str(note.attach_dir))] = note

    def attachment_owner(self, target: Path) -> tuple[Note, str] | None:
        """Which note owns TARGET, and its path within that note's attachments.

        Walks up the parents so that a file in a subdirectory of an attachments
        folder is still attributed to the owning note.
        """
        for parent in target.parents:
            owner = self.by_attach_dir.get(nfc(str(parent)))
            if owner is not None:
                return owner, nfc(target.relative_to(parent).as_posix())
        return None

    def lookup(self, target: str) -> Note | None:
        """Resolve an Obsidian target the way Obsidian would.

        Obsidian accepts a full vault-relative path, a path without the .md
        extension, or a bare filename ("shortest path when possible").  An
        ambiguous bare name is left unresolved rather than guessed at.
        """
        target = nfc(target)
        for key in (target, f"{target}.md"):
            if key in self.by_relpath:
                return self.by_relpath[key]
        stem = nfc(Path(target).stem)
        for bucket in (self.by_stem.get(stem, []), self.by_title.get(target, [])):
            if len(bucket) == 1:
                return bucket[0]
        return None


def build_index(vault: Path, verbose: bool) -> tuple[Index, list[Skipped], list[str]]:
    index = Index()
    skipped: list[Skipped] = []
    problems: list[str] = []
    seen_uuids: dict[str, str] = {}

    for path in walk_markdown(vault):
        rel = path.relative_to(vault).as_posix()
        text = path.read_text(encoding="utf-8")
        try:
            data, raw_yaml, body = split_frontmatter(text)
        except ValueError as exc:
            skipped.append(Skipped(rel, f"bad front matter: {exc}"))
            continue

        uuid = data.get("uuid")
        if not isinstance(uuid, str) or not uuid.strip():
            reason = (
                "deliberate non-note"
                if rel in KNOWN_NON_NOTES
                else "no uuid in front matter"
            )
            skipped.append(Skipped(rel, reason))
            continue
        uuid = uuid.strip()

        if uuid in seen_uuids:
            problems.append(f"duplicate uuid {uuid}: {seen_uuids[uuid]} and {rel}")
            skipped.append(Skipped(rel, f"duplicate uuid (also in {seen_uuids[uuid]})"))
            continue
        seen_uuids[uuid] = rel

        title = data.get("title")
        if not isinstance(title, str) or not title.strip():
            title = Path(rel).stem
        title = unicodedata.normalize("NFC", title.strip())

        org_tags, _ = extract_tags(data)
        for tag in org_tags:
            if not ORG_TAG_RE.match(tag):
                problems.append(f"{rel}: tag {tag!r} is still not legal org syntax")

        extras = {
            k: v
            for k, v in data.items()
            if k not in {"uuid", "tags", "created", "modified", "title"}
            and v not in (None, "", [], {})
        }

        index.add(
            Note(
                relpath=rel,
                path=path,
                uuid=uuid,
                title=title,
                org_tags=org_tags,
                created=raw_scalar(raw_yaml, "created"),
                modified=raw_scalar(raw_yaml, "modified"),
                extras=extras,
                body=body,
            )
        )
        if verbose:
            print(f"  indexed {rel}", file=sys.stderr)

    for stem, bucket in index.by_stem.items():
        if len(bucket) > 1:
            problems.append(
                f"ambiguous bare name {stem!r} ({len(bucket)} notes): "
                "bare wiki links to it cannot be resolved"
            )
    return index, skipped, problems


# --------------------------------------------------------------------------
# link rewriting
# --------------------------------------------------------------------------


def org_escape_description(text: str) -> str:
    """Make text safe as an org link description."""
    return text.replace("[", "(").replace("]", ")").strip() or "link"


BDSK_STUB_RE = re.compile(r"\Ax-bdsk://\S+\Z")


def read_bdsk_stub(path: Path) -> str | None:
    """Return the `x-bdsk:' URL in a PDF++ stub file, or None.

    Detected by content rather than by location, so it holds wherever the
    stubs live.  The size guard means a real PDF is never read.
    """
    try:
        if path.stat().st_size > 512:
            return None
        text = path.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        return None
    return text if BDSK_STUB_RE.match(text) else None


def org_link_escape(path: str) -> str:
    """Port of org-link-escape (ol.el).

    Backslash-escape square brackets, doubling any run of backslashes that
    immediately precedes a bracket or the end of the string.  Percent-encoding
    is NOT an alternative: %5B parses as a link but org then looks for a file
    whose name literally contains "%5B".

    61 files in this vault need it — mailing-list attachments are saved as
    "[All-mpq] Subject….eml", and an unescaped "]" makes org parse the whole
    link as ordinary text.
    """

    def repl(m: re.Match[str]) -> str:
        backslashes, bracket = m.group(1), m.group(2)
        return backslashes * 2 + (f"\\{bracket}" if bracket else "")

    return re.sub(r"(\\*)([\[\]]|\Z)", repl, path, count=0)


def scan_destination(text: str, i: int) -> tuple[str, int] | None:
    """Read a markdown link destination. text[i] must be '('.

    Handles both the <angle-bracketed> form (which may contain spaces) and the
    bare form with balanced parentheses, as in

        [label](2026-07-02 Some note (attachments)/plot.png)

    Returns (destination, index just past the closing paren), or None if this
    is not a well-formed destination.
    """
    assert text[i] == "("
    i += 1
    if i < len(text) and text[i] == "<":
        end = text.find(">", i + 1)
        if end == -1 or "\n" in text[i:end]:
            return None
        close = text.find(")", end + 1)
        return (text[i + 1 : end], close + 1) if close != -1 else None

    depth = 1
    buf: list[str] = []
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            buf.append(text[i + 1])
            i += 2
            continue
        if ch == "\n":
            return None
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                dest = "".join(buf).strip()
                # An optional title follows the destination: (path "title")
                if match := re.match(
                    r"""\A(?P<dest>\S+)\s+["'(].*\Z""", dest, re.DOTALL
                ):
                    dest = match.group("dest")
                return dest, i + 1
        buf.append(ch)
        i += 1
    return None


def scan_md_links(text: str):
    """Yield (start, end, bang, label, destination) for each markdown link."""
    i = 0
    while (m := LINK_OPEN_RE.search(text, i)) is not None:
        start = m.start()
        bang = m.group(0).startswith("!")
        depth = 0
        j = m.end() - 1  # at the '['
        label_end = -1
        while j < len(text):
            if text[j] == "\\":
                j += 2
                continue
            if text[j] == "[":
                depth += 1
            elif text[j] == "]":
                depth -= 1
                if depth == 0:
                    label_end = j
                    break
            j += 1
        if label_end == -1 or label_end + 1 >= len(text) or text[label_end + 1] != "(":
            i = start + 1
            continue
        scanned = scan_destination(text, label_end + 1)
        if scanned is None:
            i = start + 1
            continue
        dest, end = scanned
        yield start, end, "!" if bang else "", text[m.end() : label_end], dest
        i = end


def split_target(target: str) -> tuple[str, str | None, str | None]:
    """Split "Note#Heading" / "Note#^blockid" into (path, heading, blockref)."""
    if "#^" in target:
        head, _, block = target.partition("#^")
        return head.strip(), None, block.strip()
    if "#" in target:
        head, _, heading = target.partition("#")
        return head.strip(), heading.strip() or None, None
    return target.strip(), None, None


class Rewriter:
    """Replaces links with tokens, remembering the org text for each."""

    def __init__(
        self,
        note: Note,
        index: Index,
        vault: Path,
        out_root: Path,
        out_dir: Path,
        link_style: str,
        attachments: str,
        attach_dir_name: str,
    ) -> None:
        self.note = note
        self.index = index
        self.vault = vault
        self.out_root = out_root  # root of the generated .org tree
        self.out_dir = out_dir  # directory the .org file is written to
        self.link_style = link_style  # "absolute" | "relative"
        self.attachments = attachments  # "mirror" | "org-attach"
        self.attach_dir_name = attach_dir_name
        self.replacements: list[str] = []
        self.events: list[LinkEvent] = []

    def attachment_link(self, target: Path, desc: str | None) -> str | None:
        """Render TARGET as an `attachment:' link, or None if it is not one.

        Only meaningful in org-attach mode.  A file in this note's own
        attachment directory is addressed by bare filename; one belonging to
        another note is prefixed with that note's UUID, which the
        org-attach-crossref advice resolves through org-attach-dir-from-id.
        Either way the link never mentions where the owning note lives.
        """
        if self.attachments != "org-attach":
            return None
        owned = self.index.attachment_owner(target)
        if owned is None:
            return None
        owner, inner = owned
        if owner is self.note:
            path, outcome = inner, "attachment"
        else:
            path, outcome = f"{owner.uuid}/{inner}", "attachment-crossref"
        self.events.append(
            LinkEvent(self.note.relpath, "attachment", str(target), outcome, path)
        )
        escaped = org_link_escape(path)
        if desc is None:
            return self.token(f"[[attachment:{escaped}]]")
        return self.token(f"[[attachment:{escaped}][{org_escape_description(desc)}]]")

    def link_path(self, target: Path) -> str:
        """Render a file target for an org link.

        Org resolves a relative file: path against the buffer's
        default-directory — the note's own directory — so a relative path into
        a sibling "<note> (attachments)/" subdirectory is the natural form and
        keeps the tree portable.

        A relative link points at the *copied* location inside the org tree,
        not at the vault, which is what makes the result self-contained.
        Targets outside the vault (Nextcloud, iCloud, mpcdf …) are never made
        relative: they are not copied, and "../../../.." chains to elsewhere on
        the disk would be both unreadable and fragile.
        """
        if self.link_style == "relative":
            try:
                inside = target.relative_to(self.vault)
            except ValueError:
                return str(target)
            # NFC, matching the names the copy phase writes.  The two sources
            # disagree otherwise: os.walk returns the NFD names macOS stores,
            # while a path resolved from link text is NFC.  APFS is
            # normalisation-insensitive so a mismatch resolves locally and
            # hides, but it breaks as soon as the tree is copied to a
            # normalisation-sensitive filesystem.
            return nfc(os.path.relpath(self.out_root / inside, self.out_dir))
        return str(target)

    def token(self, org_text: str) -> str:
        self.replacements.append(org_text)
        return f"{TOKEN_PREFIX}{len(self.replacements) - 1}ZZ"

    def bdsk_link(self, stub: Path, fragment: str | None, desc: str,
                  raw: str) -> str | None:
        """Turn a link to a PDF++ stub into a direct `x-bdsk:' link.

        The vault does not store these PDFs.  Each "*.pdf" under 00 Meta/PDF++
        is a one-line text file holding `x-bdsk://CITEKEY?doc=N', which a PDF++
        monkey patch read in order to open the real file from the BibDesk
        library.  Org needs no such indirection: `x-bdsk:' is a scheme BibDesk
        itself registers, so the note can address the publication directly.

        The whole Obsidian fragment (page, rect, color, selection, annotation)
        is appended to the query verbatim.  BibDesk ignores parameters it does
        not know, so following the link behaves as the bare form does today,
        while every locator the note carried stays in the link where a future
        `:follow' handler can read it.  Nothing is judged worth dropping —
        `page' is the note's own reference point, and the printed page in the
        description is the citation's start page, a different thing.
        """
        url = read_bdsk_stub(stub)
        if url is None:
            return None
        if fragment:
            url += ("&" if "?" in url else "?") + fragment
        # RAW, not the stub path: the report is an audit trail, and the original
        # link is what a reader needs to see.
        self.events.append(LinkEvent(self.note.relpath, "bdsk", raw, "bdsk", url))
        return self.token(
            f"[[{org_link_escape(url)}][{org_escape_description(desc)}]]")

    # -- target resolution ------------------------------------------------

    def resolve_file(self, target: str) -> Path | None:
        """Resolve a non-note target to a file on disk.

        A wiki link to a markdown file carries no extension — Obsidian drops
        ".md" — so each candidate is also tried with it appended.  Without that,
        a markdown file kept as an *attachment* resolves nowhere: it is not in
        the note index either, since it has no `uuid` in its front matter and so
        was never treated as a note.

        The vault-wide search escapes the name: `rglob' reads it as a glob
        pattern, so a filename containing "[…]" (the PDF++ stubs abbreviate
        author lists that way) becomes a character class matching a bare "…"
        and finds nothing.
        """
        candidate = urllib.parse.unquote(target).strip().strip("<>")
        if candidate.startswith("/"):
            # An absolute path outside the vault (Nextcloud, iCloud, mpcdf …).
            absolute = Path(candidate)
            return absolute if absolute.exists() else None
        names = [candidate] if candidate.endswith(".md") else [candidate, candidate + ".md"]
        for base in (self.vault, self.note.path.parent):
            for name in names:
                probe = (base / name).resolve()
                if probe.is_file():
                    return probe
        for name in names:
            matches = sorted(self.vault.rglob(glob.escape(Path(name).name)))
            if len(matches) == 1:
                return matches[0]
        return None

    def wiki_link(self, raw: str, kind: str) -> str:
        # "target|alias|width": Obsidian's third field is an embed width, which
        # must not end up in the description.  Split on an optionally escaped
        # pipe: inside a markdown TABLE the separator is written "\|", and
        # splitting on a bare "|" leaves the backslash stuck to the path, so the
        # target never resolves.
        fields = re.split(r"\\?\|", raw)
        target = fields[0]
        alias = fields[1].strip() if len(fields) > 1 and fields[1].strip() else None
        # An embed has no alias — its one field is a display width.  Only a
        # *link* alias is a label, so "![[stub.pdf#page=4…|600]]" must not end
        # up described as "600".
        if kind == "embed" and alias is not None and alias.isdigit():
            alias = None
        # "[[target|]]" with an explicitly empty alias renders as nothing in
        # Obsidian.  It was used to make PDF++ highlight a second rectangle —
        # a selection running across two columns needs one link per rectangle —
        # without showing a second link in the rendered note.  Nothing outside
        # PDF++ can draw that highlight, so such a link is dropped rather than
        # given a label it never had; the visible citation beside it remains.
        anchor_only = len(fields) > 1 and not fields[1].strip()

        # A URL inside wiki brackets.  Without this it is read as a filename all
        # the way down: `split_target' tears the "#fragment" off as a heading and
        # what is left is looked up as a note, then as a file.  `md_link' has had
        # this scheme test all along; here it must run *before* the target is
        # taken apart, because the whole URL is the target.
        url = target.strip()
        scheme = url.split(":", 1)[0].lower() if ":" in url else ""
        if scheme in PASSTHROUGH_SCHEMES:
            self.events.append(
                LinkEvent(self.note.relpath, kind, raw, "passthrough", url)
            )
            return self.token(
                f"[[{org_link_escape(url)}][{org_escape_description(alias or url)}]]"
            )

        path_part, heading, blockref = split_target(target)

        note = self.index.lookup(path_part) if path_part else None
        if note is None and not path_part and (heading or blockref):
            note = self.note  # same-file heading link

        if note is not None:
            desc = alias or (f"{note.title} › {heading}" if heading else note.title)
            outcome = "id"
            if blockref:
                outcome = "blockref-degraded"
            elif heading:
                outcome = "heading-degraded"
            self.events.append(
                LinkEvent(self.note.relpath, kind, raw, outcome, note.uuid)
            )
            return self.token(f"[[id:{note.uuid}][{org_escape_description(desc)}]]")

        resolved = self.resolve_file(path_part)
        if resolved is not None:
            desc = alias or Path(path_part).name
            if anchor_only and read_bdsk_stub(resolved) is not None:
                self.events.append(
                    LinkEvent(self.note.relpath, kind, raw, "bdsk-anchor-dropped",
                              str(resolved))
                )
                return ""
            # A PDF++ stub is not a document: it names a BibDesk publication.
            # The fragment (page/rect/color/selection) rides along in the query.
            bdsk = self.bdsk_link(resolved, heading or blockref, desc, raw)
            if bdsk is not None:
                return bdsk
            is_image = resolved.suffix.lower() in {
                ".png",
                ".jpg",
                ".jpeg",
                ".gif",
                ".svg",
                ".webp",
            }
            attachment = self.attachment_link(
                resolved, None if (kind == "embed" and is_image) else desc
            )
            if attachment is not None:
                return attachment
            self.events.append(
                LinkEvent(self.note.relpath, kind, raw, "file", str(resolved))
            )
            if kind == "embed" and is_image:
                return self.token(
                    f"[[file:{org_link_escape(self.link_path(resolved))}]]"
                )
            return self.token(
                f"[[file:{org_link_escape(self.link_path(resolved))}][{org_escape_description(desc)}]]"
            )

        self.events.append(LinkEvent(self.note.relpath, kind, raw, "unresolved"))
        # An unregistered link type: visible, greppable, and it errors clearly
        # when followed instead of pretending to work.
        return self.token(
            f"[[obsidian-unresolved:{raw}][{org_escape_description(alias or raw)}]]"
        )

    def md_link(self, bang: str, label: str, target: str) -> str:
        clean = target.strip()
        scheme = clean.split(":", 1)[0].lower() if ":" in clean else ""

        if clean.startswith("#"):
            # Fragment-only: a heading or block inside this same note.
            heading = clean.lstrip("#^").strip()
            outcome = (
                "blockref-degraded" if clean.startswith("#^") else "heading-degraded"
            )
            self.events.append(
                LinkEvent(self.note.relpath, "mdlink", target, outcome, self.note.uuid)
            )
            desc = label or f"{self.note.title} › {heading}"
            return self.token(
                f"[[id:{self.note.uuid}][{org_escape_description(desc)}]]"
            )

        if scheme == "file":
            # file:// URL: decode to a path and treat it as a local target.
            clean = urllib.parse.unquote(urllib.parse.urlsplit(clean).path)
        elif scheme in PASSTHROUGH_SCHEMES:
            self.events.append(
                LinkEvent(self.note.relpath, "mdlink", target, "passthrough", clean)
            )
            return f"{bang}[{label}]({clean})"  # let pandoc handle it

        note = self.index.lookup(urllib.parse.unquote(clean).strip("<>"))
        if note is not None:
            desc = label or note.title
            self.events.append(
                LinkEvent(self.note.relpath, "mdlink", target, "id", note.uuid)
            )
            return self.token(f"[[id:{note.uuid}][{org_escape_description(desc)}]]")

        resolved = self.resolve_file(clean)
        if resolved is not None:
            is_image = resolved.suffix.lower() in {
                ".png",
                ".jpg",
                ".jpeg",
                ".gif",
                ".svg",
                ".webp",
            }
            attachment = self.attachment_link(
                resolved, None if (bang and is_image) else (label or resolved.name)
            )
            if attachment is not None:
                return attachment
            self.events.append(
                LinkEvent(self.note.relpath, "mdlink", target, "file", str(resolved))
            )
            if bang and is_image:
                return self.token(
                    f"[[file:{org_link_escape(self.link_path(resolved))}]]"
                )
            return self.token(
                f"[[file:{org_link_escape(self.link_path(resolved))}][{org_escape_description(label or resolved.name)}]]"
            )

        decoded = urllib.parse.unquote(clean).strip("<>")
        if decoded.startswith("/"):
            # Absolute path that is currently missing — an external reference
            # to a file that moved or lives on an unmounted volume.  Keep the
            # link rather than discard the intent, and flag it in the report.
            self.events.append(
                LinkEvent(self.note.relpath, "mdlink", target, "file-missing", decoded)
            )
            return self.token(
                f"[[file:{org_link_escape(self.link_path(Path(decoded)))}][{org_escape_description(label or Path(decoded).name)}]]"
            )

        self.events.append(LinkEvent(self.note.relpath, "mdlink", target, "unresolved"))
        return f"{bang}[{label}]({clean})"

    # -- driver -----------------------------------------------------------

    def rewrite(self) -> str:
        def rewrite_prose(chunk: str) -> str:
            chunk = EMBED_RE.sub(
                lambda m: self.wiki_link(m.group("target"), "embed"), chunk
            )
            chunk = WIKI_RE.sub(
                lambda m: self.wiki_link(m.group("target"), "wiki"), chunk
            )
            # Markdown links are scanned, not regexped, so that "(attachments)"
            # in a destination does not truncate it.
            out: list[str] = []
            pos = 0
            for start, end, bang, label, dest in scan_md_links(chunk):
                out.append(chunk[pos:start])
                out.append(self.md_link(bang, label, dest))
                pos = end
            out.append(chunk[pos:])
            return "".join(out)

        # TODO: a link that *contains* code or math is never converted.
        #
        # Protected spans are skipped by slicing around them, so `rewrite_prose'
        # only ever sees the gaps between them.  A wiki link whose target holds
        # inline code or math straddles a span and arrives as two fragments —
        # "[[#7.1. Understanding " and " Commands|7.1. Understanding " and
        # " Commands]]" — so neither EMBED_RE nor WIKI_RE nor `scan_md_links'
        # matches anything, and the link reaches pandoc as plain text.  It comes
        # out looking converted (pandoc turns the backticks into "=code=") while
        # keeping Obsidian's "[[#Heading|alias]]" shape, which org then reads as
        # a `custom-id' link and fails to follow: 36 such links in this vault.
        #
        # The fix is to protect by substitution rather than by slicing: replace
        # each span with an inert placeholder, run `rewrite_prose' over the whole
        # body, then put the spans back.  It needs a *second* placeholder table,
        # separate from `self.token': these must be restored to their original
        # markdown before pandoc runs (so pandoc still renders the code and math),
        # whereas link tokens are restored as org text afterwards.
        #
        # Not done because this tree is no longer re-imported; the 36 links were
        # repaired in place.  Worth doing before any future vault is converted.
        out: list[str] = []
        pos = 0
        for m in PROTECTED_RE.finditer(self.note.body):
            out.append(rewrite_prose(self.note.body[pos : m.start()]))
            out.append(m.group(0))  # code or math, verbatim
            pos = m.end()
        out.append(rewrite_prose(self.note.body[pos:]))
        # Applied last, and to code/math regions too, so a dash inside a
        # fenced block survives as well.  Restoration is the same token pass.
        return PRESERVE_CHARS_RE.sub(lambda m: self.token(m.group(0)), "".join(out))


# --------------------------------------------------------------------------
# conversion
# --------------------------------------------------------------------------


HEADING_FILTER = Path(__file__).resolve().parent / "normalize-headings.lua"


def run_pandoc(markdown: str) -> str:
    proc = subprocess.run(
        # gfm_auto_identifiers off: otherwise every heading gains a
        # :PROPERTIES: :CUSTOM_ID: drawer derived from its text, which is pure
        # noise here.  wrap=preserve keeps the original line breaks so the
        # output stays diffable against the markdown.  The lua filter shifts
        # headings so the shallowest is level 1; it works on pandoc's AST
        # because a "# comment" inside a shell fence is not a heading and no
        # regexp over the markdown can reliably tell the difference.
        [
            "pandoc",
            "--from=gfm-gfm_auto_identifiers",
            "--to=org",
            "--wrap=preserve",
            f"--lua-filter={HEADING_FILTER}",
        ],
        input=markdown,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"pandoc failed: {proc.stderr.strip()}")
    return proc.stdout


def keyword_name(key: str) -> str:
    return re.sub(r"[^0-9A-Za-z_]", "_", key.strip()).lower()


def scalar(value: object) -> str:
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value)


def build_org(note: Note, body: str) -> str:
    lines: list[str] = []
    # The drawer is first by requirement, not by preference: org reads a
    # file-level ID only from byte 0.  Do not insert anything above it.
    lines.append(":PROPERTIES:")
    lines.append(f":ID:       {note.uuid}")
    lines.append(":END:")
    lines.append(f"#+title: {note.title}")
    if note.org_tags:
        lines.append("#+filetags: :" + ":".join(note.org_tags) + ":")
    if note.created:
        lines.append(f"#+created: {note.created}")
    if note.modified:
        lines.append(f"#+modified: {note.modified}")
    for key, value in note.extras.items():
        lines.append(f"#+{keyword_name(key)}: {scalar(value)}")
    lines.append("")
    return "\n".join(lines) + body.lstrip("\n")


def convert(
    note: Note,
    index: Index,
    vault: Path,
    out_root: Path,
    out_dir: Path,
    link_style: str,
    attachments: str,
    attach_dir_name: str,
) -> tuple[str, list[LinkEvent]]:
    if TOKEN_PREFIX in note.body:
        raise RuntimeError(f"{note.relpath}: body already contains {TOKEN_PREFIX}")
    rewriter = Rewriter(
        note, index, vault, out_root, out_dir, link_style, attachments, attach_dir_name
    )
    org_body = run_pandoc(rewriter.rewrite())

    def restore(m: re.Match[str]) -> str:
        return rewriter.replacements[int(m.group(1))]

    org_body = TOKEN_RE.sub(restore, org_body)
    if TOKEN_PREFIX in org_body:
        raise RuntimeError(f"{note.relpath}: unsubstituted link token survived")
    return build_org(note, org_body), rewriter.events


# --------------------------------------------------------------------------
# reporting
# --------------------------------------------------------------------------


def write_tag_alist(index: Index, dest: Path) -> list[tuple[str, list[str]]]:
    """Emit the org-tag-alist group declaration implied by the vault's tags."""
    # Re-derive parents from the source front matter, since Note keeps only
    # the mapped child names.
    groups: dict[str, set[str]] = defaultdict(set)
    for note in index.notes:
        data, _, _ = split_frontmatter(note.path.read_text(encoding="utf-8"))
        _, pairs = extract_tags(data)
        for parent, child in pairs:
            groups[parent].add(child)

    ordered = sorted((parent, sorted(children)) for parent, children in groups.items())
    lines = [
        ";;; Generated by obsidian-to-org.py — org tag groups replacing",
        ";;; Obsidian's nested tags.  Searching a parent matches its children",
        ";;; (org-group-tags is t by default).",
        "(setq org-tag-alist",
        "      '(",
    ]
    for parent, children in ordered:
        lines.append(f'        (:startgrouptag) ("{parent}")')
        lines.append("        (:grouptags)")
        lines.append("        " + " ".join(f'("{child}")' for child in children))
        lines.append("        (:endgrouptag)")
    lines.append("        ))")
    dest.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return ordered


@dataclasses.dataclass(slots=True)
class CopyStats:
    linked: int = 0
    copied: int = 0
    skipped: int = 0
    failed: int = 0
    bytes_new: int = 0


def place_file(src: Path, dest: Path, mode: str, stats: CopyStats) -> None:
    """Put src at dest by hardlink or copy, idempotently."""
    if dest.exists():
        s, d = src.stat(), dest.stat()
        if s.st_size == d.st_size and int(s.st_mtime) == int(d.st_mtime):
            stats.skipped += 1
            return
        dest.unlink()
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        if mode == "hardlink":
            os.link(src, dest)
            stats.linked += 1
            return
    except OSError:
        pass  # different filesystem, or link limit
    try:
        shutil.copy2(src, dest)
        stats.copied += 1
        stats.bytes_new += src.stat().st_size
    except OSError:
        stats.failed += 1


def copy_attachments(
    notes: list[Note],
    events: list[LinkEvent],
    index: Index,
    vault: Path,
    out: Path,
    mode: str,
    attachments: str,
    attach_dir_name: str,
) -> CopyStats:
    """Mirror attachments into the org tree so relative links resolve.

    Two sources, deliberately overlapping:

    - the whole "<note> (attachments)/" directory beside each converted note,
      so files that exist but are not linked come along too;
    - every in-vault file that a link actually points at, which catches the
      targets living outside that convention (Lectures/, Clippings/, and links
      into another note's attachment folder).

    The union is what guarantees no relative link can dangle.
    """
    stats = CopyStats()
    wanted: set[Path] = set()

    for note in notes:
        if note.attach_dir.is_dir():
            for f in note.attach_dir.rglob("*"):
                if f.is_file() and not is_debris(f, note.attach_dir):
                    wanted.add(f)

    for event in events:
        if event.outcome not in {"file", "attachment", "attachment-crossref"}:
            continue
        if not event.target:
            continue
        target = Path(event.target)
        if target.is_file() and target.is_relative_to(vault):
            wanted.add(target)

    # One entry per file regardless of how its name is normalised: rglob yields
    # the NFD names macOS stores, resolved link targets are NFC, and both can
    # name the same file.  Destinations are written NFC so the org tree is
    # self-consistent and survives a copy to a normalisation-sensitive
    # filesystem, matching what link_path emits.
    unique: dict[str, Path] = {}
    for src in wanted:
        unique.setdefault(nfc(str(src.relative_to(vault))), src)

    for rel, src in sorted(unique.items()):
        dest_rel = rel
        if attachments == "org-attach":
            # A file belonging to a note goes to that note's ID-derived
            # directory; anything else (Lectures/, Clippings/ …) keeps its
            # place in the tree and stays a plain file: link.
            owned = index.attachment_owner(src)
            if owned is not None:
                owner, inner = owned
                dest_rel = f"{owner.org_attach_relpath(attach_dir_name)}/{inner}"
        place_file(src, out / dest_rel, mode, stats)
    return stats


def write_reports(
    report_dir: Path,
    events: list[LinkEvent],
    skipped: list[Skipped],
    problems: list[str],
) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    with (report_dir / "links.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["source", "kind", "raw", "outcome", "target"])
        for e in events:
            w.writerow([e.source, e.kind, e.raw, e.outcome, e.target])
    with (report_dir / "skipped.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["relpath", "reason"])
        for s in skipped:
            w.writerow([s.relpath, s.reason])
    (report_dir / "problems.txt").write_text(
        "\n".join(problems) + ("\n" if problems else ""), encoding="utf-8"
    )


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--vault", type=Path, default=DEFAULT_VAULT)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument(
        "--report-dir",
        type=Path,
        default=None,
        help=f"default: <out>/{REPORT_SUBDIR}",
    )
    ap.add_argument(
        "--only",
        default=None,
        help="regexp; convert only notes whose vault-relative path matches",
    )
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="index, convert and report, but write no .org files",
    )
    ap.add_argument(
        "--link-style",
        choices=("absolute", "relative"),
        default="relative",
        help="how to render file: links to attachments and other "
        "local files. relative keeps the tree portable when "
        "notes and attachments move together; absolute always "
        "resolves but pins notes to the current location",
    )
    ap.add_argument(
        "--attachments",
        choices=("org-attach", "mirror"),
        default="org-attach",
        help="org-attach (default) puts every note's attachments in "
        "one central store under --attach-dir, keyed by the "
        "note's :ID:, addressed by attachment: links that "
        "survive renaming and moving the note. mirror keeps "
        "the Obsidian convention instead: attachments stay in "
        "a '<note> (attachments)' folder beside the note, "
        "addressed by relative file: links",
    )
    ap.add_argument(
        "--attach-dir",
        default="data",
        metavar="NAME",
        help="org-attach mode only: name of the central attachment "
        "directory at the tree root; must match "
        "org-attach-id-dir in Emacs (default: data)",
    )
    ap.add_argument(
        "--copy-mode",
        choices=("copy", "hardlink"),
        default="copy",
        help="how attachments are mirrored into the org tree. "
        "copy (default) makes the org tree an independent "
        "source of truth, at the cost of ~1.75 GB. hardlink "
        "costs no extra disk but gives the file one identity "
        "shared with the vault, so editing it in one place "
        "changes both",
    )
    ap.add_argument("--write-tag-alist", action="store_true", default=True)
    ap.add_argument("--force", action="store_true",
                    help="overwrite a tree that already holds notes. Refused by "
                         "default: the converter rewrites every note from the "
                         "vault, so a second import discards whatever was edited "
                         "in the tree since the first")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    vault: Path = args.vault.expanduser().resolve()
    out: Path = args.out.expanduser().resolve()
    if not vault.is_dir():
        print(f"vault not found: {vault}", file=sys.stderr)
        return 2
    if out == vault or vault in out.parents:
        print(f"refusing to write inside the vault: {out}", file=sys.stderr)
        return 2

    # A second import is destructive: every note is rewritten from the vault,
    # so any editing done in the tree since the first import is discarded.
    # Once the tree is in use it — not the vault — is the source of truth.
    if not args.dry_run and not args.force and out.is_dir():
        existing = next(out.rglob("*.org"), None)
        if existing is not None:
            print(f"refusing to overwrite the notes at {out}", file=sys.stderr)
            print(f"  it already holds .org files, e.g. {existing.relative_to(out)}",
                  file=sys.stderr)
            print("  a second import rewrites every note and discards edits made",
                  file=sys.stderr)
            print("  there since the first.  Use --dry-run to inspect, --out to",
                  file=sys.stderr)
            print("  write elsewhere, or --force if overwriting is intended.",
                  file=sys.stderr)
            return 2

    report_dir = (args.report_dir or out / REPORT_SUBDIR).expanduser()

    print(f"indexing {vault} …")
    index, skipped, problems = build_index(vault, args.verbose)
    print(f"  {len(index.notes)} notes, {len(skipped)} skipped")

    selected = index.notes
    if args.only:
        pattern = re.compile(args.only)
        selected = [n for n in selected if pattern.search(n.relpath)]
    if args.limit is not None:
        selected = selected[: args.limit]

    events: list[LinkEvent] = []
    written = failed = 0
    for note in selected:
        try:
            # NFC so note filenames, directory names and the relative
            # link paths computed from them all agree.
            dest = out / nfc(note.out_relpath)
            org, note_events = convert(
                note,
                index,
                vault,
                out,
                dest.parent,
                args.link_style,
                args.attachments,
                args.attach_dir,
            )
        except Exception as exc:  # noqa: BLE001 - reported, not raised
            problems.append(f"{note.relpath}: conversion failed: {exc}")
            failed += 1
            continue
        events.extend(note_events)
        if not args.dry_run:
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(org, encoding="utf-8")
        written += 1
        if args.verbose:
            print(
                f"  {'would write' if args.dry_run else 'wrote'} {note.out_relpath}",
                file=sys.stderr,
            )

    copy_stats: CopyStats | None = None
    if args.link_style == "relative" and not args.dry_run:
        print("mirroring attachments …")
        copy_stats = copy_attachments(
            selected,
            events,
            index,
            vault,
            out,
            args.copy_mode,
            args.attachments,
            args.attach_dir,
        )

    groups: list[tuple[str, list[str]]] = []
    if args.write_tag_alist and not args.dry_run:
        out.mkdir(parents=True, exist_ok=True)
        tag_alist = out / META_DIR / "org-tag-alist.el"
        tag_alist.parent.mkdir(parents=True, exist_ok=True)
        groups = write_tag_alist(index, tag_alist)

    write_reports(report_dir, events, skipped, problems)

    by_outcome: dict[str, int] = defaultdict(int)
    for e in events:
        by_outcome[e.outcome] += 1

    print()
    print(
        f"{'would convert' if args.dry_run else 'converted'}: {written} notes"
        + (f", {failed} failed" if failed else "")
    )
    print("links:")
    for outcome in (
        "id",
        "attachment",
        "attachment-crossref",
        "bdsk",
        "bdsk-anchor-dropped",
        "file",
        "file-missing",
        "passthrough",
        "heading-degraded",
        "blockref-degraded",
        "unresolved",
    ):
        if by_outcome.get(outcome):
            note = {
                "heading-degraded": "  (points at the note, not the heading — deferred)",
                "blockref-degraded": "  (points at the note, not the block — deferred)",
                "attachment-crossref": "  (another note's attachment, via its :ID:)",
                "bdsk": "  (BibDesk publication, replacing a PDF++ stub)",
                "bdsk-anchor-dropped": "  (invisible PDF++ highlight anchor, removed)",
                "file-missing": "  (target absent on disk — see links.csv)",
                "unresolved": "  (emitted as obsidian-unresolved: links)",
            }.get(outcome, "")
            print(f"  {by_outcome[outcome]:6d}  {outcome}{note}")
    if copy_stats is not None:
        print(f"attachments ({args.copy_mode}):")
        print(f"  {copy_stats.linked:6d}  hardlinked")
        print(
            f"  {copy_stats.copied:6d}  copied ({copy_stats.bytes_new / 2**30:.2f} GB)"
        )
        print(f"  {copy_stats.skipped:6d}  already present")
        if copy_stats.failed:
            print(f"  {copy_stats.failed:6d}  FAILED")
    if args.attachments == "org-attach":
        print("\norg-attach expects, in your Emacs config:")
        print(f'  (setq org-attach-id-dir "{out / args.attach_dir}/")')
        print("  vulpea-config.el must supply the attachment:<uuid>/file advice")
        print("  and vulpea-vault/bibdesk.el the x-bdsk: link type")
    if groups:
        print(f"tag groups written to {out / META_DIR / 'org-tag-alist.el'}:")
        for parent, children in groups:
            print(f"  {parent}: {' '.join(children)}")
    if problems:
        print(f"\n{len(problems)} problems (see {report_dir / 'problems.txt'}):")
        for p in problems[:10]:
            print(f"  {p}")
        if len(problems) > 10:
            print(f"  … and {len(problems) - 10} more")
    print(f"\nreports: {report_dir}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
