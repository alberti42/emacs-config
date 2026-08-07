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
# Run from a launchd agent, which is where the path of the notes belongs —
# a repository this script never has to know the name of.
#
# Usage:  notes-git-rollup.sh REPO

set -eu

repo=${1:?usage: notes-git-rollup.sh REPO}

if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    echo "notes-git-rollup: $repo is not a git repository" >&2
    exit 1
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
