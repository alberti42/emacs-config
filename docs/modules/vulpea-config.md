# vulpea-config.el

Note database over the org notes migrated from an Obsidian vault —
**vulpea v2**, which is standalone (v2 dropped org-roam and owns its own
SQLite db).

Also the single owner of the settings that key off `:ID:`, because
*three* systems share that one property:

| System       | Uses `:ID:` for               |
| ------------ | ----------------------------- |
| `org-id`     | `id:` links                   |
| `org-attach` | the attachment directory      |
| vulpea       | its database primary key      |

Each note's `:ID:` is the `uuid` its Obsidian front matter carried, so
links, external UUID references and attachment directories survive
renames.

The tree itself is produced by `etc/goodies/obsidian-to-org.py` — see
its header for the conversion invariants.

## The package / config seam

`vulpea-vault/` is written as **a package that happens not to be
published**: generic mechanism, nothing in it naming a machine or a
directory, usable for anyone's vault. `vulpea-config.el` is *this user
on this machine* configuring it — straight recipes, key bindings, the
module list, and one host fact (the GitLab token that lets the rollup
push over HTTPS).

One test for anything added later: **would this be wrong on another
machine or for another vault?** Then it belongs in `vulpea-config.el`;
otherwise in `vulpea-vault/`, under the `vulpea-vault-` prefix.

The seam is already built into the code in the one place it is crossed:
`git.el` *declares* `vulpea-vault-git-rollup-environment` (a socket),
and `vulpea-config.el` *plugs into it* with the MPCDF function. Add new
host-specific behaviour the same way rather than putting a hostname
inside a module.

Two consequences that look like inconsistencies but are not:

- `org-attach-preferred-new-method 'id` and `org-attach-use-inheritance
  t` live in `attachments.el`, not here — they are not taste, they follow
  from the ID-keyed store layout the scheme and the converter agreed on.
- `org-id` is not configured here **at all**. The mechanism that keeps it
  in step with vulpea's db is `ids.el`; where `org-id-locations-file`
  lives is an org-wide, per-machine choice and sits with the rest of org,
  in `org-config.el` — via `emacs-config-cache-file`, the one helper every
  module uses to keep state out of this git worktree.

## The vault ↔ config boundary

Everything a vault can state about itself, it states in its own
`.dir-locals.el`: that it *is* a vault, which scheme it follows, what
its folders are for, its tag vocabulary, its note templates. The
configuration keeps only what a vault cannot say — where it is — and
even that is not written down anywhere.

**No vault directory is named in this repository.** There is no vault
list and no startup setting. A vault becomes known by being opened, and
`vulpea-vault-history` is the whole of what Emacs knows about which
vaults exist.

### Startup

`vulpea-vault-resume` (`core.el`) opens the most recent entry of
`vulpea-vault-history`, walking down past any vault whose directory is
missing right now — an unmounted volume is a reason to open something
else, not a reason to fail. The vault actually resumed is then pushed to
the front of the history, so skipping an unreachable one is recorded as
what it is.

Reading the history that early works because of a load-order fact worth
knowing:

- `savehist-mode` starts at **init.el:299** and restores the list by
  plain `setq`;
- `vulpea-config.el` is loaded at **init.el:636**, well after;
- `vulpea-vault/switch.el`, which owns the variable, is loaded at the
  *foot* of `vulpea-config.el`, while `core.el` (which reads it) is
  loaded at the head — so the `defvar` runs last of all, and leaves an
  already-bound value alone.

Hence `bound-and-true-p` at the call site: the variable may legitimately
not exist yet.

### No vault open is a supported state

`vulpea-vault-directory` nil is ordinary — a first run with an
empty history. Autosync stays off with a message, and the first note
opened from a vault activates it through the `find-file-hook` guard.

Consumers split two ways:

- **Answer nil and carry on** — `vulpea-vault--candidates` (no "current"
  entry, just the escape), `vulpea-vault-switch` (nothing to close),
  `vulpea-vault-special-directory`, `vulpea-vault--context-directory`.
- **Refuse cleanly** — `vulpea-vault-orphans`,
  `vulpea-vault-update-id-locations` and note creation with no daily
  folder go through `vulpea-vault-or-error`, so nil fails as one
  `user-error` instead of a wrong-type-argument deep inside.

## `vulpea-vault-apply`

Derives five settings from a root and assigns them. Called at load and
by `vulpea-vault-switch`:

| Setting                        | Value                        |
| ------------------------------ | ---------------------------- |
| `vulpea-db-location`           | `expand-file-name(<db>, <root>)` |
| `vulpea-vault-state-directory` | directory of `vulpea-db-location` |
| `vulpea-vault-attach-directory` | `<root>/<data>/`           |
| `org-attach-id-dir`            | = attach directory           |
| `vulpea-db-sync-directories`   | `(<root>)`                   |

Three of those belong to other packages, which is why a vault cannot be
re-pointed by hand.

Two of the values are vault-configurable, read from the root with
`hack-dir-local-variables` before assigning (the idiom every declared
variable uses). This is the *deriving* half of the contract —
`scheme.el` states what a vault may say, `apply-vault` turns a stated
value into the global another package reads:

- `<data>` defaults to `data` — see
  [Attachment store](#attachment-store--vulpea-vault-data-directory).
- `<db>` defaults to `./.vulpea/vulpea.db` and is `expand-file-name`-d
  against the root — see
  [Cache location](#cache-location--vulpea-vault-db-location). So a
  relative value lands inside the vault and an absolute one is taken
  as-is, and `vulpea-vault-state-directory` follows its directory part.

`org-id` locations are not among them: they live under
`emacs-config-cache-dir` (`$XDG_CACHE_HOME/emacs/`, set in
`org-config.el`) because they span every org file Emacs knows, not one
vault. The vulpea database, by contrast, defaults to the vault's own
`.vulpea/`, so the index travels with the notes unless the vault points
it elsewhere.

## Switching vaults live

`M-x vulpea-vault-switch` (`vulpea-vault/switch.el`) closes the leaving
vault's buffers, stops the watcher, closes the database, re-points, and
restarts — no Emacs restart.

The prompt offers `vulpea-vault-history` (persisted via
`savehist-additional-variables`, appended under a
`with-eval-after-load 'savehist` so load order does not matter), the
active vault last, and project.el's `... (choose a directory)` escape
for a vault reached by path. A remembered entry that is not a vault
right now is left out of the prompt but kept in the history (`vulpea-vault-p`
filters `vulpea-vault--candidates`); the history entry is added only
after the switch succeeds.

**A directory chosen by hand must be a vault.** `vulpea-vault-switch`
refuses a directory whose `.dir-locals.el` declares no
`vulpea-vault-version`, with a `user-error` — an explicit switch is the
one path with no other signal that a directory is a vault (the
`find-file-hook` guard keys off the per-buffer `vulpea-vault-version` a
note's own directory-locals set), so without this check the
`... (choose a directory)` escape would happily open an ordinary
directory like `~/org` as a vault. A directory that declares a
*non-nil but unrecognised* version is still a vault and is opened with a
warning, as everywhere else — only the *absence* of the declaration is
refused. The same `vulpea-vault-p` test guards the startup resume
(`vulpea-vault-resume`), so a stale non-vault entry left in the
history is skipped rather than resumed.

Modified notes are offered for saving before the kill, `save-some-buffers`
doing the asking; declining leaves `kill-buffer` to ask again, which is
the bargain any other kill makes.

**Closing the buffers is required, not tidy.** `org-attach-id-dir` is a
single global with no per-buffer form, so a note left open from the old
vault would resolve `attachment:` links against the *new* vault's store
and find nothing. Dir-locals, being per-buffer, stay correct — it is
only this one global that cannot. Buffers are closed *before* anything
is re-pointed, so declining to kill a modified note leaves the vault
unchanged rather than half-switched.

The same module guards the other direction from `find-file-hook`:
opening an org file whose vault is not the active one offers **switch /
open anyway / cancel**, since that is exactly the case where
`attachment:` links fail silently. With no vault active there is nothing
to weigh, so the note's own vault is simply opened. A loose org file
outside any vault never prompts.

## Multiple vaults: why single-vault, and what a redesign would take

The current design keeps **one vault active at a time** and closes the
leaving vault's buffers on `vulpea-vault-switch`. This is a deliberate
choice forced by vulpea's architecture, not a preference. What follows
records a design investigation (2026) into a project.el-style model —
where every open buffer belongs to *its own* vault and switching closes
nothing — so the reasoning need not be re-derived. **Nothing here is
implemented; the decision was to defer and pursue the fix upstream.**

### What a project.el-style model would want

Three cleanly separated roles, mirroring how `project.el` derives the
current project from the buffer rather than from a global:

- **Contextual vault** — `(vulpea-vault-current)`, derived per buffer
  from `default-directory` (walk up to the `.dir-locals.el` carrying
  `vulpea-vault-version`; use `default-directory` for dired buffers with
  no `buffer-file-name`). Drives everything *about where you are*:
  new-note placement, `vulpea-vault-orphans`, the git target, and the
  attachment store. A command run from a buffer in no vault would
  `message` and abort (via a `vulpea-vault-current-or-message` helper).
- **Live vault** — the single vault the database pointer and file watcher
  are bound to. Would *follow* the contextual vault **lazily**: when a
  db-backed command runs in a buffer whose vault differs, re-point the db
  first (the existing `apply-vault` + close/reopen/re-watch), **without
  killing buffers**.
- **Registered vaults** — `vulpea-vault-history`, the set worth backing
  up and offering in the picker.

### The one soft blocker: attachments (solvable)

The stated reason for closing buffers — `org-attach-id-dir` is a single
global — is **soft**. It is a defcustom, but nothing stops making it
**buffer-local**: `org-attach-dir-from-id` reads it dynamically in the
current buffer when following / previewing / exporting a link. Setting
`(setq-local org-attach-id-dir <this-buffer's-vault-store>)` from
`find-file-hook` makes every open note resolve its *own* vault's
attachments regardless of which vault is live — removing the entire
reason to close buffers. (Cross-*vault* attachment cross-refs would then
miss, but those never worked and are never used here; the 51
within-vault crossrefs the converter emits are fine.)

### The hard blocker: vulpea's db + sync are singletons

Everything else rides one root cause — vulpea's database and its whole
background pipeline are **module-global singletons**, not a per-vault
"workspace" object:

- `vulpea-db--connection` — **one** emacsql connection; every query
  calls `(vulpea-db)`, which lazily opens *that one* from the global
  `vulpea-db-location` (`vulpea-db.el`).
- The sync/watch pipeline is a singleton too: `vulpea-db-sync--watchers`,
  `--queue`, `--queue-tail`, `--queue-set`, `--force-set`, `--timer`,
  `--idle-timer`, `--fswatch-process`, `--file-attributes`,
  `--queue-total`, plus the global `vulpea-db-sync-directories` and the
  worker (`vulpea-db-worker.el`). There is exactly **one** autosync
  context in the process.

This is the opposite of `lsp-mode` (a `lsp--workspace` struct per
project, backed by an independent server subprocess) and `eglot` (one
server process per project root, tracked in `eglot--servers-by-project`)
— both designed for concurrent workspaces from the start. vulpea has no
workspace abstraction to hang a second db on; "the current db" *is* a
global.

### Consequences that ride the same singleton

Because the pipeline is one object, "only the watcher is single" quietly
implies more:

1. **Note creation in a non-live vault would not be indexed.**
   `vulpea-create` writes the file; the db learns of it only through the
   live watcher/worker. So `org-id` auto-registration
   (`vulpea-vault-register-ids`, fired from
   `vulpea-db-worker-done-functions`) also misses it. → A redesign must
   make **creation promote its target vault to live**.
2. **Schema/version skew kills the "read-only connection pool" shortcut.**
   `vulpea-db--init` rebuilds the schema (a full re-scan, needing the
   sync pipeline) when a db's stored settings-fingerprint or parser
   epoch differs. A vault last indexed by another vulpea version, opened
   as a pooled read-only connection, could error or under-report. So a
   pool is not actually read-only — some opens demand a scan. This is the
   decisive argument for **single live vault, lazily re-pointed** over a
   connection pool. (`vulpea-db-close`/`-clear`/full-scan and the rebuild
   flags are global too, safe only when one vault drives the pipeline.)
3. **Git backup must span *registered* vaults, in two halves.** The
   rollup timer iterating a vault list is the obvious half; the easy one
   to forget is that the **per-save `magit-wip-*` hook** in
   `vulpea-vault/git.el` is *also* single-vault (it gates on
   `vulpea-vault-directory`). Editing a note in a non-live vault
   would record no per-save history unless that buffer-local hook keys
   off "under **any** registered vault." Git backup is genuinely
   independent of the db/watcher question and could be improved on its
   own, anytime.
4. **Opening must register a vault.** Today `vulpea-vault-history` grows
   only on explicit `vulpea-vault-switch`. For backup + the picker to
   know a vault, opening a note in a not-yet-known vault would have to
   register it.

### Decision (2026)

Deferred — build nothing. Vault switching is rare in this workflow, and
the genuinely hard part (schema-skew, creation-promotes-to-live,
watcher/worker singleton) can only be done cleanly by **forking**
`vulpea-db.el` + `vulpea-db-sync.el` + `vulpea-db-worker.el`, a
forever-maintenance cost out of proportion to the benefit here. Since
home/work vault separation is a canonical multi-vault need and the
lsp/eglot per-workspace pattern is well established, the right venue is
**upstream**: open a vulpea issue proposing concurrent vaults
(lsp-workspace style), citing the singleton inventory above, and gauge
the author's interest in a PR before anyone writes one. The only piece
we would still own regardless is **git rollup across registered vaults**,
which needs none of the db multiplicity and stays on the "later, and
unblocked" pile.

## What makes a directory a vault

Only this, in its `.dir-locals.el`:

```elisp
(vulpea-vault-version . 1)
```

The mere presence of a `.dir-locals.el` means nothing — most projects
have one, this repository included. `vulpea-vault-p` (in `scheme.el`)
is the single predicate for "is this directory a vault": a directory
plus a declared `vulpea-vault-version`.

**Absence of the declaration and an unrecognised value are different
cases.** `vulpea-vault-schema-version` (in `scheme.el`) is the version
these modules implement. A vault declaring a *different non-nil* version
is still a vault and is still opened — `vulpea-vault-version-check` warns
(once per vault per session, since the check runs for every note opened
there) but does not refuse, because being unable to read a vault
perfectly is no reason to refuse it at all. Declaring *nothing*,
however, means the directory is not a vault: the `find-file-hook` guard
never treats such a buffer as belonging to one, and `vulpea-vault-switch`
refuses to open it (see "Switching vaults live"). The version governs
the whole vault↔config contract (folder roles, tag vocabulary,
templates), which is why it lives beside the declarations themselves
rather than inside any one of their consumers. Raise it when a change
would make an older vault behave *wrongly* rather than merely
differently.

## What the vault declares

All in the vault's own `.dir-locals.el`, all behind `safe-local-variable`
predicates that admit inert data only — no function symbols — so a vault
cannot introduce code: `natnump` for the version itself, then
`vulpea-vault-data-directory-p`, `vulpea-vault-db-location-p`,
`vulpea-vault-special-directories-p`, `vulpea-vault-tag-alist-p` and
`vulpea-vault-template-p`.

**Every one of them is declared in `vulpea-vault/scheme.el`** — the
`defvar`, the default, the docstring and the predicate — and nowhere
else. Three reasons, in order of weight:

1. `vulpea-vault-schema-version` is a version *of this list*. Adding or
   changing a declaration is the moment to weigh a bump, so the two
   edits are adjacent lines in one file. Split across files, the edit
   that must not be forgotten is the easy one to forget — and forgetting
   it is silent: an old vault keeps declaring version 1 and is read
   wrongly instead of reported.
2. A `safe-local-variable` predicate must be attached to its symbol
   *before* anything reads a `.dir-locals.el` naming it. The vault
   resumed at startup is read before the other modules load, so the
   declarations cannot live with the code that consumes them — while
   `scheme.el` is loaded first anyway, to answer `vulpea-vault-p`.
3. "What may a vault declare?" gets one answer from one file, in the
   same order as the header of the vault's own `.dir-locals.el`, instead
   of a grep for `safe-local-variable` across five modules.

The consuming modules (`directories.el`, `tags.el`, `create.el`, and
`apply-vault` for the two global ones) only *read* the values. Two kinds:
`defvar-local` for what is read per buffer or folder (version, folder
roles, templates) and plain `defvar` for what `apply-vault` reads once
from the root (store name, cache location) — there being one store and
one index per vault, a per-folder value would be meaningless.

Not in `scheme.el`, deliberately: `org-semantic-vault-root`, which
org-semantic marks safe itself.

### Folder roles — `vulpea-vault-special-directories`

An alist of role → folder, currently just `daily`, read back by
`vulpea-vault-special-directory`, which resolves against the vault root
because the caller is usually outside the vault. Keeps folder names like
`01 Daily notes/` out of this repository.

### Tag vocabulary — `org-tag-alist` / `org-tag-persistent-alist`

`scheme.el` marks both safe as file-locals behind
`vulpea-vault-tag-alist-p`, admitting only tag names, selection
characters and grouping keywords — org's own variables rather than
proxies of ours, so what a vault writes is what the org manual
describes. `vulpea-vault/tags.el` is then left with the one thing that
makes the declaration *take effect*: re-running
`(org-set-regexps-and-options 'tags-only)` from
`hack-local-variables-hook`.

**That recompute is not optional.** Dir-locals are applied *after* the
major mode has run, and `org-mode` has already derived the buffer-local
`org-current-tag-alist` — the value every consumer reads — from the
globals. A dir-local `org-tag-alist` alone changes nothing.

Obsidian's nested tags appear as org tag *groups*, the converter having
kept the last segment of `#Teaching/E4`. The converter still emits
`00 Meta/org-tag-alist.el` for a fresh vault; the work vault's copy was
folded into its `.dir-locals.el` and the file deleted.

### Attachment store — `vulpea-vault-data-directory`

A relative directory name (default `"data"`) placing the central
org-attach store under the root. Behind `vulpea-vault-data-directory-p`
(non-empty string). Lets a vault hide its data: `".data"` tucks it away
*and* keeps vulpea's scanner out (it skips any `/.` path);
`"00 Meta/data"` files it under a folder.

An **absolute** value (or a `~`-path) is honoured as declared, but
`vulpea-vault--store-name` warns — a store holds content and travels
with the notes, so outside the vault is nearly always a mistake, yet it
remains the vault's statement to make. See [Shape vs
policy](#shape-vs-policy-where-a-rule-about-a-value-belongs) for why the
rule is a warning here and not a rejection in the predicate.

Declared in `scheme.el` like everything else a vault may state; the
reading and expanding into `org-attach-id-dir` is `apply-vault`, and the
store wiring that resolves an `attachment:` link through it is
`vulpea-vault/attachments.el`.

**It is one contract with the converter.** The name MUST match
`obsidian-to-org.py --attach-dir` (also default `data`); a mismatch
yields an *empty* attachment directory, not an error. Moving an existing
store is link-safe — `attachment:` and the UUID crossref form resolve
through `org-attach-dir-from-id`, never a literal path — but the files
themselves need a one-time `git mv`, and the store must hold nothing but
attachments (a stray `.org` under it would be indexed as a note).

### Cache location — `vulpea-vault-db-location`

Where the vault's SQLite index lives (default `"./.vulpea/vulpea.db"`).
`apply-vault` `expand-file-name`s it against the root, so a **relative**
value lands inside the vault and an **absolute** value (or a `~`-path) is
taken as-is; `vulpea-vault-state-directory` becomes its directory and is
created if absent. Behind `vulpea-vault-db-location-p` (non-empty
string), and — like `vulpea-vault-data-directory` — declared in
`scheme.el` and read from the root by `apply-vault`.

**The index is a cache, not content.** It embeds absolute paths and is
machine-local, so it is never synced and never part of the vault's
tracked content (`.vulpea/` is git-ignored). Keeping it inside the vault
by default is what gives the storage-domain property: on an encrypted
disk the cache is encrypted-at-rest and unmounts with the vault. The
variable exists for the cases where in-vault is *wrong*:

- A **shared/synced** vault (Samba, Dropbox, Syncthing) must not host one
  SQLite file that several machines write over a mount, nor sync a DB of
  stale absolute paths. Point it at a per-machine local path instead. But
  note the vault's `.dir-locals.el` travels with it, so a hardwired
  absolute path would be identical on every machine, *not* per-machine —
  for a shared vault, leave the value relative and sync-exclude the
  directory, or resolve the per-machine path from user configuration
  keyed on the vault rather than naming it here.

An **absolute** path is admitted by the safe predicate — the whole point
is placement outside a shared vault — and, unlike
`vulpea-vault-data-directory`, is not even warned about: a cache is
machine-local by nature, so out-of-vault is a normal choice for it rather
than a suspicious one. The value is inert data, never code. If untrusted
vaults were ever a concern, both are a user-config resolver away, *not* a
tightened predicate — see below.

### One spelling for a root — `vulpea-vault-root`

Absolute, trailing slash, symlinks left alone. Used by `apply-vault`, the
switch prompt, the `find-file-hook` guard and the backup's vault list.

**Equality depends on it**, which is why it is a named function and not an
inline idiom: a candidate is hidden from the switch prompt by `equal`
against `vulpea-vault-directory`, the active root and the
remembered ones are folded with `delete-dups` before backup, and
`file-in-directory-p` decides which buffers belong to a vault. Two
spellings of one directory would list it twice, back it up twice, or fail
to recognise it — and none of those announces itself as a spelling
problem.

It is *normalisation*, not relative-to-absolute resolution: every caller
already holds an absolute path (a `default-directory`, a
`locate-dominating-file` result, a `vulpea-vault-history` entry — only
ever written from `vulpea-vault-directory`), so it expands `~` and
`..` and settles the trailing slash.

**The one exception is deliberate.** `vulpea-vault-semantic-root` uses
`file-truename` and *no* trailing slash, because that is how the
org-semantic server keys a vault; it is the boundary between the two
spellings and the only place the truename form appears. Folding it into
`vulpea-vault-root` would make every `close` a no-op that reports success.
Equally, `vulpea-vault-root` must *not* start resolving symlinks: vulpea,
`org-attach` and the buffer list all speak the path as the user opened it,
and truenaming here would stop `file-in-directory-p` from recognising a
vault reached through a symlink.

### Shape vs policy: where a rule about a value belongs

All three declared paths (`data-directory`, `db-location`,
`special-directories`) now admit the same shapes, and pattern-1 resolution
— `expand-file-name VALUE ROOT`, relative under the root, absolute or
`~` as-is — is used for every one of them. That uniformity was worth a
fix: `vulpea-vault-data-directory-p` used to *require* relative.

**A `safe-local-variable` predicate answers "is this value safe to
read?" — inert data, no code — and nothing else.** It is the wrong place
for "is this value wise?", because it cannot say so: returning nil makes
Emacs discard the vault's **entire `.dir-locals.el`** (silently, when
non-interactive). The old predicate therefore meant that a vault naming an
absolute store lost its tags, its templates, its folder roles, its cache
location *and its `vulpea-vault-version`* — so it was no longer
recognised as a vault at all, over one setting nothing else depends on.
Verified before the fix: a test vault with an absolute store read back
`version=nil special=nil vault-p=nil`; after it, everything reads and one
warning is emitted.

So: **shape in the predicate (`scheme.el`), policy on the deriving side
(`apply-vault`)**, where it can warn, fall back, or both. This is the same
declare/derive split the module layout follows, applied to a single value.
Honouring the declared value rather than substituting the default is
deliberate too: a live vault silently re-pointed at an empty store reads
as "every attachment link is broken" and says nothing about why.

### Note templates — `vulpea-vault-template`

Declared **per folder**, under the directory keys dir-locals already
supports, so Emacs resolves the folder and nothing here matches paths.
This is the Obsidian Templater `folder_templates` configuration carried
over, reconciled with what the converted notes actually carry. Keys:
`:tags`, `:head`, `:body`, `:dated`.

### Dir-locals gotchas that bite here

- A **deeper directory key replaces** a shallower one's value rather
  than merging it, so each entry must be self-contained; absent keys
  fall back to code.
- A **nested `.dir-locals.el`** anywhere under the vault shadows the
  root file *wholesale*. One file per vault.
- **One unsafe variable makes Emacs discard the entire file**, not just
  that variable — and non-interactively (batch, or a `--batch` smoke
  test) it is discarded *silently*, with no prompt. Which is why every
  declaration has to be in place before any of them can apply: with
  `scheme.el` unloaded, nothing in the file takes effect, not merely the
  variables it declares. The same trap catches `org-semantic-vault-root`
  in a batch Emacs where org-semantic is not loaded.

## Where a per-note fact goes: keyword, drawer, or meta list

Org offers three places, and they are not interchangeable — vulpea reads
two of them:

| Where | Syntax | Indexed | Queryable by |
| ----- | ------ | ------- | ------------ |
| Keyword | `#+created: 2024-11-04` | **no** | grep |
| Property drawer | `:CREATED:  2024-11-04` | yes → `properties` | `vulpea-db-query-by-property` |
| Meta list | `- status :: open` | yes → `meta` | `vulpea-db-query-by-meta` |

Only a handful of keywords are special-cased at extraction — `#+title`,
`#+filetags`, `#+CATEGORY`, aliases. Everything else in the preamble is
text the index never sees. That is why this vault's timestamps are
`:CREATED:` / `:MODIFIED:` properties: `:CREATED:` becomes
`vulpea-note-created-at` (read by `vulpea-db--extract-created-date`,
which scans the value for the first `YYYY-MM-DD`, so a full ISO stamp
with zone offset is fine) and answers `vulpea-db-query-by-created-date`.

`:MODIFIED:` earns less — properties support exact-match lookup only —
because **filesystem mtime is already indexed**, as `vulpea-note-modified-at`
and the `files` table behind `vulpea-db-query-stale-notes`. It is there
for symmetry and because the stamp describes the file-level node.

### Where a file-level drawer may sit

It must be the **first element in the buffer**: before the first heading
*and* before every keyword, with only comments allowed above. Verified:

| File starts with | `org-entry-get` | `org-element` |
| ---------------- | --------------- | ------------- |
| drawer, then `#+title:` | ✅ | ✅ |
| `#+title:`, then drawer | ❌ | ❌ not parsed as a property drawer |
| `# comment`, then drawer | ✅ | ✅ |
| blank line, then drawer | ❌ | ✅ parsed |

The last row is the trap: a leading blank line splits the two parsers, so
vulpea would index properties that `org-entry-get` — and therefore
inheritance, `org-entry-put`, and `modified-stamp.el` — cannot see. The
converter emits the drawer at byte 0 for this reason.

## Where a new note lands

`vulpea-create-default-function` → `vulpea-vault-create-defaults`
(`vulpea-vault/create.el`).

A new note goes in the current buffer's `default-directory` when that is
inside the vault — dired's listed directory, the directory of the note
being read, a shell's cwd. Otherwise it becomes a note under
`<daily>/<year>/`, where `<daily>` is the folder the vault gives the
`daily` role (vault root if it declares none).

The daily tree is the one exception to following `default-directory`:
its subdirectory is the note's *year* rather than a topic, so creating
from a 2024 daily note still files under the new note's own year.

The note is named after its title, opens with today's date, and is
seeded with `:CREATED:` / `:MODIFIED:` plus the folder's
`vulpea-vault-template`.

## Two gotchas that cost real time

- **vulpea does not hook `org-id`.** Its own commands resolve through
  the db, but a plain `[[id:…]]` link goes through `org-id-locations`,
  which nothing populates automatically. Run
  `M-x vulpea-vault-update-id-locations` after a conversion.
  (`vulpea-vault-register-ids` on `vulpea-db-worker-done-functions`
  keeps the two in step for files indexed later.)
- **`org-attach-id-dir` must match the converter's `--attach-dir`.** A
  mismatch yields an *empty* attachment directory rather than an error.
  Likewise `vulpea-vault-directory` versus its `DEFAULT_OUT`. The
  store name is now the vault's to choose — see [Attachment store](#attachment-store--vulpea-vault-data-directory)
  — which makes keeping the two ends in step the vault's responsibility.
- **The watcher does not survive a bulk external edit.** Rewriting all
  949 notes at once (the `:CREATED:`/`:MODIFIED:` migration) left the
  index holding 697 of them, and it never caught up — no error, just a
  database quietly describing the previous state. `M-x
  vulpea-db-sync-full-scan` reconciled it in one pass. Run it after any
  change made from outside Emacs: a script, a `git pull`, a restore.
- **A plain full scan will not notice a metadata-only change.** It
  compares content, so restoring 948 mtimes moved nothing: the index
  went on reporting one single day until `(vulpea-db-sync-full-scan
  'force)` — `C-u M-x vulpea-db-sync-full-scan` — re-indexed everything.
  Reach for the prefix argument whenever what changed is *about* the
  files rather than *in* them.

## Other behaviour

- **IDs are minted by an `:override` on `org-id-new`** (`ids.el`)
  returning `(uuid-to-string (uuid-v4))`. Org 9.8.7 still forks
  `org-id-uuid-program`, which is uppercase on macOS, and ID lookup is
  case-sensitive.
- **Cross-note attachment links** (`attachments.el`). Stock
  `attachment:` carries only a filename, resolved against the *current*
  node, so there is no cross-reference syntax. An `attachment:<uuid>/file`
  form is added via advice on `org-attach-expand` — the one choke point
  shared by following, inline preview and export. The converter emits 51
  of them.
- **Autosync is guarded on the tree existing** (`vulpea-config.el`), so a
  not-yet-run conversion degrades to "installed but idle" rather than
  erroring at startup.

## History of the notes

Duplicacy backs the tree up hourly, which answers "get it back" but not
"what did I change" — reading that from snapshots means diffing two of
them in a shell. So the vault is also a git repository, and every save
is recorded without anyone writing a commit.

**Per save** — `vulpea-vault/git.el` adds Magit's two work-in-progress
hooks buffer-locally to any file under a known vault (see "Backup is not
scoped to the active vault" below):
`magit-wip-commit-initial-backup` (the state before your first change of
the session) and `magit-wip-commit-buffer-file` (after every save). The
commits go to `refs/wip/wtree/refs/heads/<branch>` — an ordinary git ref
that simply is not a branch, so `git log` and Magit's log show nothing
unusual. Not the global `magit-wip-mode`, which would record saves in
every repository on the machine, this one included.

**Every six hours** — `etc/goodies/notes-git-rollup.sh` commits the
working tree to the branch and deletes the WIP refs. Magit re-anchors a
fresh chain on the new commit by itself (`magit-wip-get-parent` follows
the WIP ref only while the branch is still an ancestor of it).

It commits the **working tree**, not the WIP ref, because that ref is a
partial record: `magit-wip` only commits tracked files saved from Emacs,
so a note created today is absent from it, and so is every change made
by a script. `git add -A` sees all of it.

An Emacs timer drives this, not a launchd agent. An agent has to name a
repository, and this configuration names no vault — it would go on
rolling up the vault it was written for long after
`vulpea-vault-switch` had moved on. The timer reads the set of vaults
opened in this Emacs at each tick (`vulpea-vault-git--known-vaults`:
`vulpea-vault-history` plus the active vault), so it follows whatever
has been opened.

**Backup is not scoped to the active vault; per-save recording isn't
either.** The single-active-vault limit is vulpea's *database*, not git —
each vault is its own git repository, and git has no such limit. So every
vault opened in this Emacs is rolled up in turn, each on its own repo,
and a note edited in a vault other than the active one is backed up all
the same. The per-save `magit-wip-*` hooks work identically: they are
added buffer-locally to any file under a *known* vault (not only the
active one — `vulpea-vault-git--vault-file-p` tests membership in
`vulpea-vault-git--known-vaults`), and `magit-wip` records to whichever
repository the file lives in, so no per-vault wiring is needed. The
rollup subprocess environment (`vulpea-vault-git-rollup-environment`,
e.g. the MPCDF HTTPS-token rewrite) is applied to every vault's rollup;
it only rewrites the one remote it names, so it is inert on a vault
whose remote it does not match.

**How a vault enters the backup set (note for a future agent).** The set
is `vulpea-vault-git--known-vaults` = `vulpea-vault-history` + the active
vault. Under today's single-active-vault design, `vulpea-vault-history`
grows *only* when a vault is **switched into** — `vulpea-vault-switch`,
the `find-file-hook` guard's **switch** choice, or the active vault at
startup. It does **not** grow on the guard's **open anyway** choice, nor
by merely visiting a note. So a vault backed up is exactly a vault
switched into at least once (persisted across sessions by savehist); a
vault only ever "opened anyway" is neither rolled up nor given per-save
WIP hooks. This is self-consistent now — *using* another vault means
switching to it, which is the act that registers it — but it is
precisely consequence #4 ("opening must register a vault") of the
deferred multi-vault work above: if that model is ever built, the
registration point must broaden so a vault used without being made
active is still backed up.

**The timer does not measure the six hours.** It ticks every
`vulpea-vault-git-rollup-check-interval` (20 min) and the *script*
decides whether a rollup is due, from the age of `HEAD`. Rollups are the
only thing that commits here, so HEAD's timestamp is the record of the
last one: nothing persisted, correct per repository, and still correct
after a week with Emacs closed — where a repeating timer would have
restarted its clock at every Emacs restart and possibly never fired.
A check with nothing to do costs one `git log -1` and stops before
reading the working tree.

`M-x vulpea-vault-git-rollup` runs it on demand; `C-u` waives the
interval.

**Pushing.** After the commit the script pushes, if the repository says
where to: the branch's own upstream first, else the only remote there is,
and nothing at all when there are two remotes and no upstream — a
question the script has no business answering. No remote name appears in
it. **Being offline is established before pushing, not diagnosed after.**
`scutil -r <host>` asks macOS whether it has a network path to the
remote and answers instantly without sending anything; on "Not
Reachable" the push is skipped and nothing is reported, because a laptop
off the network is not a fault. Everything else — no `scutil`, a URL no
host can be picked out of, an unfamiliar answer — pushes anyway and lets
git speak, so a check that stops working cannot quietly stop the pushes
with it.

That leaves one rule for the caller: **any non-zero exit is a real
failure and is warned about** (bad credentials, a rejected force push, a
branch gone from the remote). No classifying of git's error text, and no
warning for a missing wifi — which matters here because
`warning-toast.el` renders warnings as popups. The warning repeats the
script's own words rather than wrapping them in a sentence that guesses
which failure it was.

**The push runs whether or not anything was committed**, so a commit
made offline goes out at the next tick once the network is back — not
only when there is fresh work to commit. It is skipped when the branch
is level with its upstream, so a quiet vault causes no network chatter.

**Silence has a time limit.** Skipping the push is right for an
afternoon away from the network and wrong for a fortnight of it: the
failure that actually costs something is not one skipped push but a
backlog nobody is watching. So when the push is skipped, the age of the
*earliest* commit still waiting is checked against
`vulpea-vault-git-push-stale-days` (3), passed to the script as its
third argument, and anything older is reported — through the same non-zero exit, so the same warning. Nothing
persisted for this either: the commits carry their own dates.

The commit is made either way.

Only branches travel. `refs/wip/*` stays local, which matches what it is
— detail that exists to be discarded.

The result: four readable commits a day, plus save-by-save detail for
the last few hours. Older detail is discarded deliberately.

`C-c n l` (`vulpea-vault-log-saves`) shows both at once — rolled-up
commits with the individual saves woven in.

Two things to know:

- **A note must be tracked before its saves are recorded** —
  `magit-wip` checks `magit-file-tracked-p`. A new note has no per-save
  history until the next rollup, whose `git add -A` picks it up.
- **`data/` (1.5 GB), `*.pdf` (227 MB of lecture slides among the notes)
  and `.vulpea/` are git-ignored.** Binaries git cannot diff, and an
  index rebuilt in one scan. Duplicacy still covers all of them.

The script takes the repository as an argument and a minimum interval
in seconds, so it names no vault either and is testable from a shell:
`notes-git-rollup.sh ~/org/Work 21600`.

## Modules — `vulpea-vault/`

One concern per file, loaded from `vulpea-config.el` the way
`completion.el` loads `completions/`.

| File                  | Concern                                                        |
| --------------------- | -------------------------------------------------------------- |
| `scheme.el`           | the contract: every variable a vault may declare (defaults + safe predicates), the schema version and its check, `vulpea-vault-p`, `vulpea-vault-root` |
| `core.el`             | which vault is in use (`vulpea-vault-directory`), the five settings derived from it (`vulpea-vault-apply`), `vulpea-vault-or-error`, `vulpea-vault-resume` |
| `modified-stamp.el`   | refreshes `:MODIFIED:` on save, only in notes that have it      |
| `select.el`           | dates and sorting in the note-selection UI                      |
| `directories.el`      | `vulpea-vault-special-directories` — role → folder              |
| `tags.el`             | the vault's tag vocabulary as safe file-locals, plus the recompute |
| `create.el`           | where a new note lands and what it starts as                    |
| `ids.el`              | keeps `org-id` in step with vulpea's db: the index hook, `M-x vulpea-vault-update-id-locations`, the lowercase-UUID `org-id-new` override |
| `attachments.el`      | the ID-keyed store: `org-attach-preferred-new-method` / `-use-inheritance`, and the cross-note `attachment:<uuid>/file` syntax |
| `orphans.el`          | `M-x vulpea-vault-orphans` — dangling links, unreferenced attachments, undeclared tags |
| `bibdesk.el`          | the `x-bdsk:` link type                                         |
| `pdffile.el`          | the `pdffile:` link type                                        |
| `message.el`          | the `message:` link type                                        |
| `switch.el`           | live vault switching, the history, the wrong-vault guard        |
| `semantic.el`         | ties the vault's org-semantic index to the switch               |
| `git.el`              | records every save on a git work-in-progress ref; `C-c n l` to read it |

Load order matters only where a module `require`s a sibling:
`scheme` → `core` (both loaded before the `use-package` forms, since a
`safe-local-variable` predicate must exist before the resume reads a
vault's `.dir-locals.el`), then `attachments` before `orphans`, `ids`
before `switch`, `switch` before `semantic`.

## Keys and commands

| Binding / command                     | Purpose                              |
| ------------------------------------- | ------------------------------------ |
| `C-c n f`                             | `vulpea-find`                        |
| `C-c n i`                             | `vulpea-insert`                      |
| `C-c n b`                             | `vulpea-find-backlink`               |
| `M-x vulpea-vault-switch`             | open another vault, live             |
| `M-x vulpea-vault-orphans`            | the vault health report              |
| `M-x vulpea-vault-update-id-locations` | repair `org-id-locations` from the db |
