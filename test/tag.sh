#!/bin/sh
# test/tag.sh -- tag a patch release. main holds a patch when CHANGELOG.md's top heading has three parts,
# `## vX.Y.Z`: fixes alone. A machine that holds a patch key (the line of allowed-signers that starts
# spark-shell-patch) runs this, and this is its rule. A person tags a vX.Y, and any patch the rule refuses.
#
#   sh test/tag.sh             tag origin/main when it is a patch the rule allows
#   sh test/tag.sh --dry-run   say what it would do, touch nothing
#   sh test/tag.sh --now       a person's word: no rest on main first
#   sh test/tag.sh --cool H    the hours a fix rests on main before its tag (default 6; SPARK_SHELL_TAG_COOL too)
#
# Run it from the clone that tags, and run a copy you trust: the installed release's
# (sh ~/.spark-shell/test/tag.sh), never the one of the commit it judges. It reads that commit from git and
# runs none of its code: no hook, no test, no script of that tree.
#
# Its gates, whatever CI said:
#   - the tag it patches (vX.Y for Z = 1, else the patch before) is a release: signed by a key the installed
#     spark-shell trusts for a tag of its kind (~/.spark-shell/allowed-signers, or SPARK_SHELL_TAG_SIGNERS;
#     this clone's own file only where none is installed), named as its object says, and behind main. A tag
#     anyone with a write token could push is no base for a patch;
#   - nothing guarded differs from it, by this copy's list (test/lane.sh): the workflows, the hooks, the
#     signers, the gate and this rule, the entry and its help, the update path, what fetches a build, what
#     acts as root;
#   - it is a fix: the keys of config.example are as they were, and at most 400 lines changed outside test/
#     and the changelog;
#   - ci.yml passed for the exact commit in main's own run, the one that takes every job (GitHub's public
#     API through curl, no token);
#   - the fix has rested the cooling hours on main, counted from when that run was made, by GitHub's clock:
#     a person has time to see it. A date the committer wrote never counts. --now skips the rest.
# Then the tag is signed by the key this clone's git config names (gpg.format ssh, user.signingkey),
# checked against the same allowed-signers, and pushed as refs/tags/vX.Y.Z. A tag that does not check, or a
# push that is refused, is undone here: a tag's name cannot be taken back once it is on origin.
# Exit 0 tagged or nothing to do, 1 refused, 2 usage. SPARK_SHELL_TAG_CURL names the curl (a test's seam).
set -eu
cool=${SPARK_SHELL_TAG_COOL:-6}
CURL=${SPARK_SHELL_TAG_CURL:-curl}
MOST=400   # the most lines a fix changes outside test/ and the changelog
dry=''; now=''
usage() { echo "usage: sh test/tag.sh [--dry-run] [--now] [--cool H]" >&2; exit 2; }
say() { printf 'tag: %s\n' "$*"; }
no() { printf 'tag: refused: %s -- nothing tagged\n' "$*"; exit 1; }
while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) dry=1 ;;
        --now) now=1 ;;
        --cool) [ $# -ge 2 ] || usage; cool=$2; shift ;;
        *) usage ;;
    esac
    shift
done
case $cool in ''|*[!0-9]*) usage ;; esac
here=$(cd "$(dirname "$0")" && pwd)   # this copy: its list judges, never the one of the commit judged
top_dir=$(git rev-parse --show-toplevel 2>/dev/null) || no "this folder is no git clone"
cd "$top_dir"
quiet_git() { git -c core.hooksPath=/dev/null "$@"; }   # no hook of the tree it judges ever runs

# repo_of URL -> OWNER/REPO of a github.com remote (https, ssh, scp-like)
repo_of() {
    r=$1
    case $r in
        https://github.com/*) r=${r#https://github.com/} ;;
        ssh://*@github.com/*) r=${r#ssh://*@github.com/} ;;
        *@github.com:*) r=${r#*@github.com:} ;;
        *) return 1 ;;
    esac
    r=${r%/}; r=${r%.git}
    case $r in */*/*|*[!A-Za-z0-9._/-]*|/*|*/|'') return 1 ;; */*) printf '%s\n' "$r" ;; *) return 1 ;; esac
}
repo=$(repo_of "$(git config --get remote.origin.url || :)") || no "origin is not on github.com"

quiet_git fetch -q origin '+refs/heads/main:refs/remotes/origin/main' 'refs/tags/*:refs/tags/*' 2>/dev/null || no "main and the tags could not be fetched from origin"
sha=$(git rev-parse refs/remotes/origin/main)
short=$(printf '%s' "$sha" | cut -c1-7)
top=$(git show "$sha:CHANGELOG.md" 2>/dev/null | grep -m1 '^## v' || :)
ver=${top#"## v"}
# three_numbers X.Y.Z -- a patch's version
three_numbers() { case $1 in *[!0-9.]*|*..*|.*|*.|*.*.*.*) return 1 ;; *.*.*) return 0 ;; *) return 1 ;; esac; }
[ -n "$ver" ] || no "CHANGELOG.md on main has no '## vX.Y' heading"
three_numbers "$ver" || { say "main is at $short, under $top: no patch, a person tags it"; exit 0; }
tag=v$ver
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then say "$tag exists: nothing to do"; exit 0; fi

# the tag it patches: the release for Z = 1, else the patch before
patch=${ver##*.}; line=${ver%.*}
[ "$patch" -ge 1 ] || no "$top is no patch of a release"
if [ "$patch" -eq 1 ]; then base=v$line; else base=v$line.$((patch - 1)); fi
git rev-parse -q --verify "refs/tags/$base" >/dev/null 2>&1 || no "$tag patches $base, and no such tag exists"
git merge-base --is-ancestor "$base^{commit}" "$sha" 2>/dev/null || no "$base is not behind main"
# ... and it is a release: signed by a key the installed spark-shell trusts for a tag of its kind. A vX.Y is
# a release key's alone; a patch may be a patch key's. The fence below measures from it, so a tag that is no
# release would make any commit a patch
signers=${SPARK_SHELL_TAG_SIGNERS:-$HOME/.spark-shell/allowed-signers}
[ -f "$signers" ] || signers=$top_dir/allowed-signers
[ -f "$signers" ] || no "no allowed-signers to check $base against"
keys=$(mktemp); trap 'rm -f "$keys"' EXIT
verify() { git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="$keys" -c gpg.program=false -c gpg.openpgp.program=false -c gpg.x509.program=false verify-tag "$1" >/dev/null 2>&1; }
if three_numbers "${base#v}"; then cat "$signers" > "$keys"; else grep -v '^spark-shell-patch ' "$signers" > "$keys" || :; fi
verify "$base" || no "$base is not signed by a key the installed allowed-signers trust for it: not a release"
named=$(git cat-file tag "$base" 2>/dev/null | sed -n '/^$/q; s/^tag //p')
[ "$named" = "$base" ] || no "the tag object $base points to is named '$named'"

git show "$sha:CHANGELOG.md" | awk -v h="$top" '$0 == h { on = 1; next } on && /^## / { exit } on && /^- / { n++ } END { exit n ? 0 : 1 }' \
    || no "the $top section has no bullet"

# the fence: nothing guarded differs from the tag it patches, by this copy's list
answer=$(sh "$here/lane.sh" --here --base "$base" --at "$sha") || no "the lane list could not be asked"
lane=$(printf '%s\n' "$answer" | sed -n 's/^lane=//p'); why=$(printf '%s\n' "$answer" | sed -n 's/^why=//p')
case $lane in
    fast|standard) ;;
    guarded) no "$tag changes $why since $base, and that is guarded: a person tags it" ;;
    *) no "the lane list gave no lane for $base to $short" ;;
esac
# a fix alone: no new setting (config.example's keys), not a large change. A new verb or option would change the
# help, which is the head of the entry, and the entry is guarded
keys_of() { git show "$1:config.example" 2>/dev/null | sed -n 's/^\([A-Z][A-Z0-9_]*\)=.*/\1/p' | sort -u; }
[ "$(keys_of "$base")" = "$(keys_of "$sha")" ] || no "the keys of config.example differ from $base: more than a fix, a person tags it"
lines=$(git diff --no-renames --numstat "$base" "$sha" -- . ':(exclude)test' ':(exclude)CHANGELOG.md' | awk '{ n += $1 + $2 } END { print n + 0 }')
[ "$lines" -le "$MOST" ] || no "$lines lines differ from $base outside test/ and the changelog, more than $MOST: a person tags it"

# ci.yml passed for the exact commit, in main's own run; and when that run was made, by GitHub's clock
runs=$("$CURL" -fsS -m 30 -H 'Accept: application/vnd.github+json' "https://api.github.com/repos/$repo/actions/workflows/ci.yml/runs?head_sha=$sha&branch=main&event=push&status=success&per_page=20" 2>/dev/null) \
    || no "GitHub could not be asked whether ci.yml passed for main at $short"
made=$(printf '%s' "$runs" | jq -r --arg sha "$sha" '[.workflow_runs[]? | select(.head_sha == $sha and .head_branch == "main" and .event == "push" and .conclusion == "success") | .created_at | fromdateiso8601] | min // empty' 2>/dev/null) \
    || no "GitHub's answer about ci.yml could not be read"
case $made in ''|*[!0-9]*) no "ci.yml has not passed for main at $short in main's own run" ;; esac
if [ -z "$now" ]; then
    age=$(( $(date +%s) - made ))
    if [ "$age" -lt $((cool * 3600)) ]; then
        say "$tag waits: main at $short is $((age / 60)) minutes old, and a fix rests $cool hours before its tag (--now skips the rest)"
        exit 0
    fi
fi

if [ -n "$dry" ]; then
    say "would tag $tag at $short, a $lane change of $lines lines since $base:"
    say "  git tag -s $tag -m 'spark-shell $tag' $short"
    say "  git push origin refs/tags/$tag"
    exit 0
fi
quiet_git tag -s "$tag" -m "spark-shell $tag" "$sha" 2>/dev/null || no "$tag could not be signed (git config gpg.format ssh, user.signingkey)"
# the tag just made checks against the installed allowed-signers, or it never leaves: on origin its name is taken for good
cat "$signers" > "$keys"
if ! verify "$tag"; then
    git tag -d "$tag" >/dev/null 2>&1 || :
    no "the key this clone signs with is not one the installed allowed-signers trust; the tag is undone"
fi
if ! quiet_git push -q origin "refs/tags/$tag" 2>/dev/null; then
    git tag -d "$tag" >/dev/null 2>&1 || :
    no "the push of $tag was refused; the tag is undone"
fi
say "$tag at $short, a $lane change of $lines lines since $base"
