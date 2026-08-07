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

`vulpea-config--initial-vault` resumes the most recent entry of
`vulpea-vault-history`, walking down past any vault whose directory is
missing right now — an unmounted volume is a reason to open something
else, not a reason to fail. The vault actually resumed is then pushed to
the front of the history at the foot of the file, so skipping an
unreachable one is recorded as what it is.

Reading the history that early works because of a load-order fact worth
knowing:

- `savehist-mode` starts at **init.el:299** and restores the list by
  plain `setq`;
- `vulpea-config.el` is loaded at **init.el:636**, well after;
- `vulpea-vault/switch.el`, which owns the variable, is loaded at the
  *foot* of `vulpea-config.el` — so its `defvar` runs last of all, and
  leaves an already-bound value alone.

Hence `bound-and-true-p` at the call site: the variable may legitimately
not exist yet.

### No vault open is a supported state

`vulpea-config-notes-directory` nil is ordinary — a first run with an
empty history. Autosync stays off with a message, and the first note
opened from a vault activates it through the `find-file-hook` guard.

Consumers split two ways:

- **Answer nil and carry on** — `vulpea-vault--candidates` (no "current"
  entry, just the escape), `vulpea-vault-switch` (nothing to close),
  `vulpea-vault-special-directory`, `vulpea-vault--context-directory`.
- **Refuse cleanly** — `vulpea-vault-orphans`,
  `vulpea-config-update-id-locations` and note creation with no daily
  folder go through `vulpea-config-vault-or-error`, so nil fails as one
  `user-error` instead of a wrong-type-argument deep inside.

## `vulpea-config-apply-vault`

Derives five settings from a root and assigns them. Called at load and
by `vulpea-vault-switch`:

| Setting                        | Value                        |
| ------------------------------ | ---------------------------- |
| `vulpea-config-state-directory` | `<root>/.vulpea/`           |
| `vulpea-config-attach-directory` | `<root>/data/`             |
| `org-attach-id-dir`            | = attach directory           |
| `vulpea-db-sync-directories`   | `(<root>)`                   |
| `vulpea-db-location`           | `<root>/.vulpea/vulpea.db`   |

Three of those belong to other packages, which is why a vault cannot be
re-pointed by hand.

`org-id` locations live under `$XDG_CACHE_HOME/emacs/` instead — they
span every org file Emacs knows, not one vault. The database lives in
the vault's own `.vulpea/`, so the index travels with the notes.

## Switching vaults live

`M-x vulpea-vault-switch` (`vulpea-vault/switch.el`) closes the leaving
vault's buffers, stops the watcher, closes the database, re-points, and
restarts — no Emacs restart.

The prompt offers `vulpea-vault-history` (persisted via
`savehist-additional-variables`, appended under a
`with-eval-after-load 'savehist` so load order does not matter), the
active vault last, and project.el's `... (choose a directory)` escape
for a vault reached by path. A remembered vault whose directory is
missing is left out of the prompt but kept in the history; the history
entry is added only after the switch succeeds.

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

## What makes a directory a vault

Only this, in its `.dir-locals.el`:

```elisp
(vulpea-vault-version . 1)
```

The mere presence of a `.dir-locals.el` means nothing — most projects
have one, this repository included.

`vulpea-vault-schema-version` (in `scheme.el`) is what these modules
implement. A vault declaring anything else, or nothing, is still opened,
but `vulpea-vault-version-check` warns — once per vault per session,
since the check runs for every note opened there. The version governs
the whole vault↔config contract (folder roles, tag vocabulary,
templates), which is why it lives on its own rather than inside any one
of them. Raise it when a change would make an older vault behave
*wrongly* rather than merely differently.

## What the vault declares

All in the vault's own `.dir-locals.el`, all behind `safe-local-variable`
predicates that admit inert data only — no function symbols — so a vault
cannot introduce code: `natnump` for the version itself, then
`vulpea-vault-special-directories-p`, `vulpea-vault-tag-alist-p` and
`vulpea-vault-template-p`.

### Folder roles — `vulpea-vault-special-directories`

An alist of role → folder, currently just `daily`, read back by
`vulpea-vault-special-directory`, which resolves against the vault root
because the caller is usually outside the vault. Keeps folder names like
`01 Daily notes/` out of this repository.

### Tag vocabulary — `org-tag-alist` / `org-tag-persistent-alist`

`vulpea-vault/tags.el` marks both safe as file-locals behind a predicate
admitting only tag names, selection characters and grouping keywords,
then re-runs `(org-set-regexps-and-options 'tags-only)` from
`hack-local-variables-hook`.

**That recompute is not optional.** Dir-locals are applied *after* the
major mode has run, and `org-mode` has already derived the buffer-local
`org-current-tag-alist` — the value every consumer reads — from the
globals. A dir-local `org-tag-alist` alone changes nothing.

Obsidian's nested tags appear as org tag *groups*, the converter having
kept the last segment of `#Teaching/E4`. The converter still emits
`00 Meta/org-tag-alist.el` for a fresh vault; the work vault's copy was
folded into its `.dir-locals.el` and the file deleted.

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
  that variable — which is why `tags.el` must be loaded for the
  *templates* to apply at all.

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
  `M-x vulpea-config-update-id-locations` after a conversion.
  (`vulpea-config-register-ids` on `vulpea-db-worker-done-functions`
  keeps the two in step for files indexed later.)
- **`org-attach-id-dir` must match the converter's `--attach-dir`.** A
  mismatch yields an *empty* attachment directory rather than an error.
  Likewise `vulpea-config-notes-directory` versus its `DEFAULT_OUT`.
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

## Other behaviour owned here

- **IDs are minted by an `:override` on `org-id-new`** returning
  `(uuid-to-string (uuid-v4))`. Org 9.8.7 still forks
  `org-id-uuid-program`, which is uppercase on macOS, and ID lookup is
  case-sensitive.
- **Cross-note attachment links.** Stock `attachment:` carries only a
  filename, resolved against the *current* node, so there is no
  cross-reference syntax. An `attachment:<uuid>/file` form is added via
  advice on `org-attach-expand` — the one choke point shared by
  following, inline preview and export. The converter emits 51 of them.
- **Autosync is guarded on the tree existing**, so a not-yet-run
  conversion degrades to "installed but idle" rather than erroring at
  startup.

## History of the notes

Duplicacy backs the tree up hourly, which answers "get it back" but not
"what did I change" — reading that from snapshots means diffing two of
them in a shell. So the vault is also a git repository, and every save
is recorded without anyone writing a commit.

**Per save** — `vulpea-vault/git.el` adds Magit's two work-in-progress
hooks buffer-locally to any file under the open vault:
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
`vulpea-vault-switch` had moved on. The timer reads
`vulpea-config-notes-directory` at each tick, so it follows the switch.

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
| `modified-stamp.el`   | refreshes `:MODIFIED:` on save, only in notes that have it      |
| `scheme.el`           | what makes a directory a vault; the schema version and its check |
| `directories.el`      | `vulpea-vault-special-directories` — role → folder              |
| `tags.el`             | the vault's tag vocabulary as safe file-locals, plus the recompute |
| `create.el`           | where a new note lands and what it starts as                    |
| `attachments.el`      | `M-x vulpea-vault-orphans` — dangling links, unreferenced attachments, undeclared tags |
| `bibdesk.el`          | the `x-bdsk:` link type                                         |
| `pdffile.el`          | the `pdffile:` link type                                        |
| `message.el`          | the `message:` link type                                        |
| `switch.el`           | live vault switching, the history, the wrong-vault guard        |
| `git.el`              | records every save on a git work-in-progress ref; `C-c n l` to read it |

## Keys and commands

| Binding / command                     | Purpose                              |
| ------------------------------------- | ------------------------------------ |
| `C-c n f`                             | `vulpea-find`                        |
| `C-c n i`                             | `vulpea-insert`                      |
| `C-c n b`                             | `vulpea-find-backlink`               |
| `M-x vulpea-vault-switch`             | open another vault, live             |
| `M-x vulpea-vault-orphans`            | the vault health report              |
| `M-x vulpea-config-update-id-locations` | repair `org-id-locations` from the db |
