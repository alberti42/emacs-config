#!/bin/sh
# Fold a window of autosaved notes into one commit.
#
# Emacs records every save of a note on a work-in-progress ref (see
# vulpea-vault/git.el).  That is the right granularity for stepping back
# through an afternoon and the wrong one for reading a history, so this runs
# on a timer: commit whatever the working tree now holds, then drop the
# per-save detail it just folded in.
#
# What survives is one commit per run, and the saves made since the last one.
#
# The working tree is committed, not the work-in-progress ref, because that
# ref is a partial record: `magit-wip' commits tracked files saved from
# Emacs, so a note created today is absent from it, and so is every change
# made by a script.  `git add -A' is what sees all of it.
#
# When is the last run?  The repository already knows -- rollups are the only
# thing that commits here, so the timestamp of HEAD is the answer.  Nothing is
# persisted anywhere, the answer is per-repository by construction, and it is
# still right after Emacs has been closed for a week.
#
# The caller passes the repository, so this script never has to know the name
# of any particular one.
#
# Usage:  notes-git-rollup.sh REPO [MIN-INTERVAL-SECONDS]
#
# Exit status:  0  nothing to do, or rolled up (and pushed, if a remote)
#               1  the argument is not a git repository
#               3  rolled up, but the push did not go through

set -eu

repo=${1:?usage: notes-git-rollup.sh REPO [MIN-INTERVAL-SECONDS]}
min_interval=${2:-0}

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "notes-git-rollup: $repo is not a git repository" >&2
    exit 1
fi

# Ask the cheap question first.  On a timer that ticks far more often than the
# interval, most runs end here without the working tree being touched at all.
if [ "$min_interval" -gt 0 ] && last=$(git -C "$repo" log -1 --format=%ct 2>/dev/null); then
    age=$(( $(date +%s) - last ))
    [ "$age" -lt "$min_interval" ] && exit 0
fi

git -C "$repo" add -A

# Nothing staged means nothing changed since the last run; leave no commit
# behind to say so.
if git -C "$repo" diff --cached --quiet; then
    exit 0
fi

git -C "$repo" commit -q -m "notes $(date '+%Y-%m-%d %H:%M')"

# The saves are now contained in the commit above.  Deleting the refs is what
# keeps the repository from carrying every keystroke of every day forever;
# Magit starts a fresh chain from the new commit by itself.
git -C "$repo" for-each-ref --format='%(refname)' refs/wip/ |
    while IFS= read -r ref; do
        git -C "$repo" update-ref -d "$ref"
    done

# Off-machine, if the repository says where to.  No remote is named here: the
# branch's own upstream first, and failing that the only remote there is.  Two
# remotes and no upstream is a question this script has no business answering,
# so it stays home.
branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD) || exit 0
remote=$(git -C "$repo" config --get "branch.$branch.remote" || true)
if [ -z "$remote" ] && [ "$(git -C "$repo" remote | wc -l)" -eq 1 ]; then
    remote=$(git -C "$repo" remote)
fi
[ -n "$remote" ] || exit 0

# A failed push is not a failed rollup: the commit is made, and the next run
# carries it.  Exit 3 says exactly that — rolled up, not pushed — so the
# caller can mention it without treating it as a fault.  A laptop off the
# network is not a fault.
git -C "$repo" push --quiet --set-upstream "$remote" "$branch" || exit 3
