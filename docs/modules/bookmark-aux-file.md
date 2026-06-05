# bookmark-aux-file.el

Per-context **auxiliary bookmark files** layered on top of stock `bookmark.el`
with advice only — no fork. A buffer-local variable, `bookmark-aux-file`, names
an extra bookmark file. While it is set in the current buffer:

- that file's bookmarks merge into the view (computed on demand; entries are
  kept verbatim — duplicate names are never silently removed);
- newly set bookmarks are **routed** to the auxiliary file;
- saves **partition** the in-memory list and write each group back to its own
  file, in plain stock format;
- a *different* context's auxiliary file is never visible.

The motivating use case is per-project bookmarks (a coding project, a novel, a
LaTeX book) that stay isolated and persist across sessions — without losing your
cross-cutting global bookmarks.

Two files:

- **`local/bookmark-aux-file.el`** — the library (this document). Project-agnostic
  mechanism; an upstream candidate.
- **`bookmark-aux-config.el`** — the thin consumer/wiring layer (loads the
  library, enables the mode, supplies a project.el-based path resolver).

## Design principles

These are the load-bearing decisions. Changing one usually breaks another.

1. **No fork.** Everything is advice on stock functions. The on-disk format is
   plain stock `bookmark.el` (the in-memory routing tag is stripped before
   writing), so files round-trip cleanly and a future upstream feature could
   replace this library transparently.
2. **Mechanism, not policy.** The library decides *nothing* about where the file
   lives or when `bookmark-aux-file` is set. It exposes a variable and a resolver
   hook; the consumer owns lifecycle and location. (See the repo memory
   "Don't decide consumer policy".) All project.el coupling lives in
   `bookmark-aux-config.el`, never here.
3. **One in-memory list; route on save.** `bookmark-alist` stays the single
   merged list stock already mutates everywhere (push, setcdr, delq). Each record
   carries a private prop `(baf-file . ABS-PATH)` marking the file it belongs to.
   Reads work unchanged because everything still reads one list; only *load* and
   *save* are file-aware. This is why the implementation is small.
4. **Merge computed on demand, not eagerly cached.** At ~10–100 bookmarks the
   merge is free, so there is no merge cache to go stale. The only thing cached
   is the *parsed auxiliary file*, keyed by mtime — mirroring stock's own
   `bookmark-bookmarks-timestamp`.
5. **Prepend, don't de-duplicate.** Auxiliary records are merged at the *front*
   of the list, exactly as stock `bookmark-load` inserts a loaded file ("to the
   front"). The only observable effect of that order is stock's own first-match
   rule: a bare-name `bookmark-get-bookmark` resolves to the auxiliary entry.
   **Both entries always remain visible** in listings and completion — the
   library never silently collapses same-named bookmarks (they may point at
   different places; deduping is the user's call, by renaming). This matches
   stock `bookmark.el`, which itself keeps duplicate names (the `push` path).

## External packages

None. Built-in `bookmark` and `seq` only. `Package-Requires: ((emacs "28.1"))`.

## Public surface

| Symbol | Kind | Purpose |
| ------ | ---- | ------- |
| `bookmark-aux-file` | `defvar-local`, `safe-local-variable` | The knob. Raw path (absolute, relative, or nil). Set by the consumer. |
| `bookmark-aux-file-resolver` | variable (fn or nil) | Maps the raw value to an absolute path. Default: expand a relative value against `default-directory`. |
| `bookmark-aux-file-include-global` | defcustom (default `t`) | `t` = merge view; `nil` = buffers with an active aux file show only its bookmarks. Presentation only. |
| `bookmark-aux-file-mode` | global minor mode | Installs/removes all advice. |

## Consumer layer (`bookmark-aux-config.el`)

Loads the library, enables the mode, and sets `bookmark-aux-file-resolver` to
resolve **relative** paths against the **project.el root** (falling back to
`default-directory` outside a project). This matters because dir-locals applies
the variable in every file buffer with `default-directory` = that file's
directory; resolving against the project root gives **one** aux file for the
whole project regardless of which subdirectory file is open.

Per-project setup is otherwise automatic — the library marks `bookmark-aux-file`
safe, so a project's `.dir-locals.el` sets it with no further wiring:

```elisp
((nil . ((bookmark-aux-file . "._aux/bookmarks.eld"))))   ; one file per project root
```

## How it works — the advice set

Record tag: `(baf-file . ABS-PATH)` in the record's PARAM-ALIST, in memory only.

1. **`:after bookmark-maybe-load-default-file` → `--sync`.** This is the
   universal choke point (called at the top of store/set-internal/
   completing-read/all-names/delete/save). Reconciles `bookmark-alist` with the
   current buffer's resolved aux file: if unchanged (same path + same mtime) it
   is a no-op; otherwise it removes all `baf-file`-tagged records and, if an aux
   file is set and readable, re-reads it (low-level, via
   `bookmark-alist-from-buffer` in a temp buffer — **never** `bookmark-load`),
   tags each record, and prepends.
2. **`:filter-args bookmark-store` → `--tag-args`.** When an aux file is active,
   (a) injects the tag into the record's alist *before* `store` runs (so the
   `bookmark-save-flag`-triggered save routes correctly), and (b) confines
   `store`'s overwrite-by-name to *auxiliary* records: if no aux record of that
   name exists it forces `NO-OVERWRITE t` so the set creates a fresh aux
   bookmark instead of clobbering a same-named global one. A set from an aux
   buffer thus always targets the aux file and never touches global bookmarks.
3. **`:around bookmark-write-file` → `--partition-write`.** The sole save choke
   point. Groups the list by `baf-file`, then writes each group to its file by
   rebinding `bookmark-alist` and calling the original per group (reusing all of
   stock's encoding logic), with the tag stripped.
4. **`:around bookmark-completing-read` / `bookmark-all-names` → `--present`.**
   Syncs the real list first, then binds the view. In the default merge view the
   binding is the real list unchanged (no dedup); it differs only when
   `bookmark-aux-file-include-global` is nil, where it filters to tagged entries.
5. **`:around bookmark-bmenu-list` → `--bmenu-inherit`.** Stamps the
   `*Bookmark List*` buffer with the originating buffer's resolved aux path.
6. **`:after bookmark-load` → `--invalidate`.** Resets the mtime cache so the
   next sync rebuilds (the watch-reload path can wholesale-replace the list).

## Invariants — do not change without reading

### `:filter-args` on `bookmark-store`, NOT `:after`
`bookmark-store` runs its own `bookmark-save` (the `bookmark-save-flag 1` path)
**before** returning. An `:after` advice that tagged the stored record would run
*after* that internal save, so the new bookmark would be written to the **global**
file. Tagging via `:filter-args` puts the tag on the record's alist before
`store` saves it. Also: look up the record by name (`bookmark-get-bookmark`), not
"the front" — overwrite does `setcdr` in place, leaving the record wherever it
already was.

### A set from an aux buffer must never overwrite a global bookmark
`bookmark-store` overwrites the first record matching the name. In the merged
list that first match could be a *global* record (e.g. setting a name that
exists globally but not yet in the aux file), so a naive tag-on-store would
*move* the global bookmark into the aux file and drop it from the global file —
silent data movement. `--tag-args` prevents this: it scans for an
auxiliary-tagged record of that name and, when none exists, forces the push
path (`NO-OVERWRITE t`) so `store` creates a new aux record and leaves the
global one untouched. Because aux records are prepended, when an aux record
*does* exist it is the first match and is overwritten as intended (no
duplicate). Consequence: from an aux buffer a set never edits a global bookmark
in place. (This is not a regression — before this guard the collision case
*silently relocated* the global entry into the aux file; the change only makes
it non-destructive.) To deliberately write to the global file from within a
project, toggle `bookmark-aux-file-mode' off, set the bookmark, and toggle it
back on: teardown drops the in-memory aux records (already persisted to disk),
so stock `bookmark-set' writes to `bookmark-default-file'. This is rare enough
that no per-command escape hatch is provided. An explicit `C-u` (push) still
creates duplicates as in stock.

### `--present` must sync the real list *before* binding the view
The readers internally call `bookmark-maybe-load-default-file`, whose `:after`
sync mutates `bookmark-alist`. If `--present` binds its view first, that inner
sync corrupts the temporary binding (and the cache). So `--present` calls
`--sync` on the real list first (refreshing the cache); the inner sync then
no-ops against the view binding.

### `--sync` must use only low-level reads + a reentrancy guard
It must never call `bookmark-load` (recursion + timestamp clobber); it reads with
`bookmark-alist-from-buffer` in a temp buffer. `baf--syncing` guards against
re-entry through any of the advised functions.

### The mtime no-op guard treats "absent == absent" as in-sync
`--mtime=` returns non-nil when both mtimes are nil (file not yet created). This
is essential: when an aux file does not exist yet, a freshly set-but-unsaved
bookmark lives only in memory; without this, the next sync (e.g. `store`'s
internal save) would rebuild from the empty/absent file and **drop the unsaved
bookmark**.

### `--partition-write` always writes the global target and the active aux file
Even when their groups are empty. Stock `bookmark-write-file FILE` always writes
`FILE`; honoring that means a global-only `bookmark-delete-all` empties the
global file (instead of leaving it stale), and the active aux file is emptied
rather than orphaned. After writing the active aux path, refresh the mtime cache
so the next sync does not treat our own write as an external change.

### The on-disk format must stay plain stock — strip the tag on write
`--strip-tags` copies records with `baf-file` removed. Never persist the tag: a
shared/committed aux file must contain no foreign keys, and round-tripping must
match stock.

### `*Bookmark List*` is not in the project — it must inherit the aux path
The list is *built* in the originating (project) buffer, so it shows the aux
bookmarks; but acting on an entry (RET/delete/rename) runs in the list buffer,
which has `bookmark-aux-file = nil`. Without `--bmenu-inherit` stamping the list
buffer with the originating buffer's *absolute* resolved path, the next sync
drops the aux records and `bookmark-get-bookmark` errors with "Invalid bookmark".

### Disabling the mode strips tags first
`bookmark-aux-file-mode -1` runs `--teardown` (drop tagged records, reset cache)
**before** removing the advice, so a later stock save cannot leak auxiliary
entries into the global file.

## Gotchas

- **Nearest `.dir-locals.el` wins — Emacs does not merge across directories.** A
  deeper `.dir-locals.el` shadows a project-root one entirely. If a subdirectory
  has its own dir-locals (e.g. setting `pyenv-version`) and you want
  `bookmark-aux-file` there too, you must repeat it in that file. This is stock
  Emacs behavior, not a quirk of this library.
- **`bookmark-delete-all` + a nil `bookmark-bookmarks-timestamp`.** If the
  timestamp is nil and the default file is readable, the internal save reloads
  the default file (repopulating the list), which then re-merges the aux file —
  so `delete-all` appears not to clear. In a normal session the timestamp is set
  when the default file loads at startup, so this does not occur; it shows up
  only in synthetic setups where the global file exists but was never loaded.
- **Same-named bookmarks both appear (by design).** A name present in both a
  project's aux file and the global file shows up twice — in stock completion,
  in `bookmark-bmenu-list`, and in `consult-bookmark` alike. This is intentional
  and consistent with stock `bookmark.el` (which keeps duplicate names). A bare
  `bookmark-jump` typing the exact name resolves to the auxiliary one
  (first-match); to disambiguate, rename one. The library never hides either.
- **Parent directories are created on save.** `--partition-write` `make-directory`s
  the target's parent, so an aux path into a not-yet-existing subdir (e.g.
  `._aux/`) just works instead of failing in `write-file`.

## Upstream notes

This is a candidate for a stock `bookmark.el` proposal. Two existing hooks point
the same way: the `RW:` comment inside `bookmark-load` already sketches tagging
records with their source file; and `bookmark-after-load-file-hook` (Emacs 31.1)
exists to "reconcile `bookmark-alist` against bookmark state that a package
maintains." The strongest upstream framing is the *seam*, not the feature: small,
policy-free extension points (a save-target/write hook and a record-creation
hook) so a package like this no longer has to advise internals.

## Testing

Verified with two `emacs --batch` harnesses: a library suite (routing, isolation,
shadowing, overwrite-in-place, rename, delete, delete-all, mtime/external-edit,
self-write-no-reload, disable-safety) and a project-integration suite (project.el
+ `.dir-locals.el` → project-root resolution, plus the `*Bookmark List*` flow).
When changing the advice set, re-run both. Note the case-sensitivity trap when
asserting on raw file contents: the format stamp contains the word "Bookmark"
(capital B) and "Emacs"/"Stamp" (lowercase a) — assert on parsed
`bookmark-alist-from-buffer` names, not substrings.
