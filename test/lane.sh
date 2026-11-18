#!/bin/sh
# test/lane.sh -- the lane a change takes, by what it touches: what CI runs for it, and what a person proves
# before a push (test/prove.sh). The one list of the areas: ci.yml's plan job and the suite read it here.
#
#   sh test/lane.sh              the change from where this branch left origin/main to HEAD
#   sh test/lane.sh --base REF   the change from REF to HEAD
#   sh test/lane.sh --at REF     ... to REF, not to HEAD: a commit that is not checked out
#   sh test/lane.sh --here       the repository of the current folder, not this file's own: the tagging rule
#                                (test/tag.sh) asks a copy it trusts about a clone it does not
#   sh test/lane.sh --full       what main and a release ask: every job
#   sh test/lane.sh --paths      the paths on stdin, one a line (a test's seam); --lines N says its size
#
# Three lines: lane=, why= (the path or the size that decided) and jobs= (ci.yml's jobs it asks for, a space
# around each name).
#
#   fast      a small fix in the user's side of the shell, in the tests or in the words. CI: lint, and the
#             suite on a dash row and a bash row, both as root in a container. The rest runs on main when
#             it lands, before any tag.
#   standard  a component, a template, a helper, a proof, the config's own module, anything this list does
#             not name, and a fix too large for the fast lane. CI: every job.
#   guarded   the supply chain (the workflows, the hooks, the signers, this gate and the tagging rule, the
#             entry every verb passes through, the update path and what else reads a signature, what
#             fetches a build) and what acts as root (on and off, a distro's package lists, a module that
#             calls a root function, before the change or after it). CI: every job. A person tags it.
#
# A path this list does not name is standard, never fast: a new kind of file is proven whole until someone
# says what it is.
set -eu

FAST_JOBS=' debian fedora '
FULL_JOBS=' linux debian ubuntu arch void fedora opensuse desktop macos dialog-build dialog wallpaper wallpaper-deny winpad winpad-deny ear ear-deny bar bar-deny '
FAST_LINES=400   # the most a fast fix changes outside test/ and the changelog

base=''; at=HEAD; here=''; full=''; paths=''; lines=''
while [ $# -gt 0 ]; do
    case $1 in
        --base) base=${2:?--base takes a commit}; shift ;;
        --at) at=${2:?--at takes a commit}; shift ;;
        --here) here=1 ;;
        --full) full=1 ;;
        --paths) paths=1 ;;
        --lines) lines=${2:?--lines takes a number}; shift ;;
        *) echo "usage: sh test/lane.sh [--base REF] [--at REF] [--here] | --full | --paths [--lines N]" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$here" ] || cd "$(dirname "$0")/.."

say() { printf 'lane=%s\nwhy=%s\njobs=%s\n' "$1" "$2" "$3"; exit 0; }
[ -z "$full" ] || say standard 'the whole matrix was asked for' "$FULL_JOBS"

if [ -n "$paths" ]; then
    changed=$(cat)
else
    [ -n "$base" ] || base=$(git merge-base origin/main "$at" 2>/dev/null) || base=''
    # no base to measure from (a clone without origin/main): every job
    [ -n "$base" ] && git rev-parse --verify --quiet "$base^{commit}" >/dev/null && git rev-parse --verify --quiet "$at^{commit}" >/dev/null || say standard 'no base to measure the change from' "$FULL_JOBS"
    # a file moved is two paths, the one it left and the one it has: a workflow moved under test/ is still a workflow gone
    # names as they are: git writes a name with a byte outside ASCII in quotes unless told not to, and a quoted name
    # would match nothing below. One it still quotes (a tab, a quote in it) is guarded: a person looks at it
    changed=$(git -c core.quotePath=false diff --no-renames --name-only "$base" "$at")
    lines=$(git diff --no-renames --numstat "$base" "$at" -- . ':(exclude)test' ':(exclude)CHANGELOG.md' | awk '{ n += $1 + $2 } END { print n + 0 }')
fi
[ -n "$changed" ] || say fast 'nothing changed' "$FAST_JOBS"

# roots -- the text on stdin calls a root function, or fetches
roots() { grep -q -e root_do -e as_root -e root_put -e root_swap -e root_try -e 'curl '; }
# module PATH -> guarded | standard | fast, for a module of src/. Read as the change leaves it and as it was before:
# a change that takes the root call out of a module changed what acts as root. A list of paths (a test's seam)
# has no before: the file in this tree. A module that is gone and never acted as root is no small fix: standard
module() {
    if [ -n "$paths" ]; then
        if [ ! -f "$1" ]; then echo standard; elif roots < "$1"; then echo guarded; else echo fast; fi
    elif git show "$at:$1" 2>/dev/null | roots || git show "$base:$1" 2>/dev/null | roots; then echo guarded
    elif git cat-file -e "$at:$1" 2>/dev/null; then echo fast
    else echo standard; fi
}
# area PATH -> guarded | standard | fast
area() {
    case $1 in
        '"'*) echo guarded ;;   # a name git had to quote
        .github/*|.githooks/*|allowed-signers|distro/*) echo guarded ;;
        test/gate.sh|test/lane.sh|test/prove.sh|test/tag.sh) echo guarded ;;
        spark-shell) echo guarded ;;                  # the entry: every verb passes through it, the update too, and the help is its head
        src/setup.sh|src/dialog.sh|src/gallery.sh) echo guarded ;;   # on and off; the update and the gallery, which read a signature and say what is trusted
        src/config.sh) echo standard ;;               # every setting goes through it
        src/*.sh) module "$1" ;;
        test/*_proof.py|test/*_proof.sh|test/*_build.sh|test/dialog_sbom.sh|test/dialog_pty.py) echo standard ;;   # run by the desktop job or a build job
        test/*) echo fast ;;
        README.md|CHANGELOG.md|CREDITS.md|LICENSE|config.example) echo fast ;;
        *) echo standard ;;
    esac
}

lane=fast; why=''
old_ifs=$IFS; IFS='
'
for p in $changed; do
    a=$(area "$p")
    case $a in
        guarded) lane=guarded; why=$p; break ;;
        standard) [ "$lane" != fast ] || { lane=standard; why=$p; } ;;
    esac
done
IFS=$old_ifs
if [ "$lane" = fast ] && [ "${lines:-0}" -gt "$FAST_LINES" ]; then lane=standard; why="$lines lines changed outside the tests and the changelog, more than $FAST_LINES"; fi
case $lane in
    fast) say fast "every path is the user's side of the shell, a test or the words, ${lines:-0} lines" "$FAST_JOBS" ;;
    *) say "$lane" "$why" "$FULL_JOBS" ;;
esac
