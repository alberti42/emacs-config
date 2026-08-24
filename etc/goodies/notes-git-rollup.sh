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
# Usage:  notes-git-rollup.sh REPO [MIN-INTERVAL-SECONDS] [STALE-DAYS]
#
# STALE-DAYS is how long commits may sit unpushed before that is worth
# complaining about -- three by default.  Being off the network for an
# afternoon is normal; being off it, or broken, for days is the failure that
# would otherwise pass unnoticed for weeks.
#
# Exit status:  0  nothing to do, or rolled up (and pushed, if reachable)
#               1  not a git repository, the push failed, or the backlog is
#                  older than STALE-DAYS

set -eu

# No agent, in either of the two roles one could play here.  A rollup fires on
# a timer with nobody at the keyboard, and an SSH agent that wants unlocking
# turns both of its roles into a dialog: it is asked to *sign* the commit, and
# asked to *authenticate* the push.  Taking it out of the environment makes
# that dialog impossible rather than merely unlikely -- the commit signs from a
# key file below, and the push carries credentials of its own.  A credential
# that is missing then fails loudly, which is the right failure: waiting on a
# prompt nobody will answer costs the backup.
unset SSH_AUTH_SOCK

repo=${1:?usage: notes-git-rollup.sh REPO [MIN-INTERVAL-SECONDS] [STALE-DAYS]}
min_interval=${2:-0}
stale_days=${3:-3}

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
# behind to say so.  The push below still runs: a commit made while the
# network was away is waiting whether or not there is anything new today.
# Signed by a key this script can read, or not signed at all.
#
# `ssh-keygen -Y sign' signs locally from a private key file, and otherwise
# asks an agent to sign for the matching public key.  There being no agent
# here, that second path leads nowhere: a key this script cannot read costs the
# commit rather than raising a prompt.  Hence the readability test, and
# unsigned in preference to sorry when it fails.
#
# Which key is not this script's business, nor this repository's: it is read at
# each run from an environment file outside the repository -- the same plain
# `KEY=VALUE' form the shell sources, so `~' expands as it would there.  The
# repository's own configuration is neither consulted for this nor altered.
signing_key_file=${NOTES_GIT_SIGNING_KEY_FILE:-\
${XDG_CONFIG_HOME:-$HOME/.config}/envs/git-signing-key.sh}
key=${GIT_ROLLUP_SIGNING_KEY:-}
if [ -z "$key" ] && [ -r "$signing_key_file" ]; then
    # shellcheck disable=SC1090
    . "$signing_key_file"
    key=${GIT_ROLLUP_SIGNING_KEY:-}
fi

if [ -n "$key" ] && [ -r "$key" ]; then
    sign="-c commit.gpgsign=true -c gpg.format=ssh -c user.signingkey=$key"
else
    sign="-c commit.gpgsign=false"
    [ -n "$key" ] && echo "notes-git-rollup: cannot read the configured" \
                          "signing key; committing unsigned" >&2
fi

if ! git -C "$repo" diff --cached --quiet; then
    # Unquoted on purpose: $sign is a word list of git options, not one word.
    # shellcheck disable=SC2086
    git -C "$repo" $sign commit -q -m "notes $(date '+%Y-%m-%d %H:%M')"

    # The saves are now contained in the commit above.  Deleting the refs is
    # what keeps the repository from carrying every keystroke of every day
    # forever; Magit starts a fresh chain from the new commit by itself.
    git -C "$repo" for-each-ref --format='%(refname)' refs/wip/ |
        while IFS= read -r ref; do
            git -C "$repo" update-ref -d "$ref"
        done
fi

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

# Is anything actually waiting to go out?  Once the remote is level there is
# nothing to say to it, and saying it every twenty minutes would be chatter.
upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
if [ -n "$upstream" ] && [ "$(git -C "$repo" rev-list --count "$upstream..HEAD")" -eq 0 ]; then
    exit 0
fi

# Being off the network is the ordinary state of a laptop, not a fault, so it
# is established before pushing rather than diagnosed from the wreckage
# afterwards: no network, no attempt, nothing to report.  `scutil -r' asks the
# system whether it has a path to the destination and answers instantly
# without sending anything.
#
# Only an explicit "Not Reachable" skips.  Anything else -- no scutil, a URL
# this cannot pick a host out of, an answer in a form not foreseen -- pushes
# and lets git speak, so a test that stops working cannot quietly stop the
# pushes with it.
if command -v scutil >/dev/null 2>&1; then
    host=$(git -C "$repo" remote get-url "$remote" |
               sed -E 's#^[a-z+]+://##; s#^[^@/]*@##; s#[:/].*$##')
    if [ -n "$host" ] && scutil -r "$host" 2>/dev/null | grep -q '^Not Reachable'; then
        # Silence is right for a day off the network and wrong for a fortnight
        # of one.  The failure that matters is not any single skipped push but
        # a backlog nobody is looking at -- so the age of the oldest commit
        # still waiting is what decides whether to speak.  Nothing to persist
        # here either: the commits carry their own dates.
        if [ -n "$upstream" ]; then
            oldest=$(git -C "$repo" log --format=%ct "$upstream..HEAD" | tail -1)
            if [ -n "$oldest" ]; then
                days=$(( ($(date +%s) - oldest) / 86400 ))
                if [ "$days" -ge "$stale_days" ]; then
                    echo "notes-git-rollup: nothing pushed to $remote for $days days" >&2
                    exit 1
                fi
            fi
        fi
        exit 0
    fi
fi

# Reachable, so a failure here is a real one: bad credentials, a rejected
# force push, a branch gone from the remote.  `set -e' carries git's status
# out of the script, and the caller warns.
git -C "$repo" push --quiet --set-upstream "$remote" "$branch"
