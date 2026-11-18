#!/bin/sh
# test/lane.sh -- the lane a change takes, by what it touches: what CI runs for it, and what a person proves
# before a push (test/prove.sh). The one list of the areas: ci.yml's plan job and the suite read it here.
#
#   sh test/lane.sh              the change from where this branch left origin/main to HEAD
#   sh test/lane.sh --base REF   the change from REF to HEAD
#   sh test/lane.sh --full       what main and a release ask: every job
#   sh test/lane.sh --paths      the paths on stdin, one a line (a test's seam); --lines N says its size
#
# Three lines: lane=, why= (the path or the size that decided) and jobs= (ci.yml's jobs it asks for, a space
# around each name).
#
#   fast      a small fix in the user's side of the shell, in the tests or in the words. CI: lint, and the
#             suite on a dash row and a bash row, both as root in a container. The rest runs on main when
#             it lands, before any tag.
#   standard  a component, a template, the entry, a helper, a proof, the config's own module, anything this
#             list does not name, and a fix too large for the fast lane. CI: every job.
#   guarded   the supply chain (the workflows, the hooks, the signers, this gate, the update path, what
#             fetches a build) and what acts as root (on and off, a distro's package lists, a module that
#             calls a root function). CI: every job. A person tags it.
#
# A path this list does not name is standard, never fast: a new kind of file is proven whole until someone
# says what it is.
set -eu
cd "$(dirname "$0")/.."

FAST_JOBS=' debian fedora '
FULL_JOBS=' linux debian ubuntu arch void fedora opensuse desktop macos dialog-build dialog wallpaper wallpaper-deny winpad winpad-deny ear ear-deny bar bar-deny '
FAST_LINES=400   # the most a fast fix changes outside test/ and the changelog

base=''; full=''; paths=''; lines=''
while [ $# -gt 0 ]; do
    case $1 in
        --base) base=${2:?--base takes a commit}; shift ;;
        --full) full=1 ;;
        --paths) paths=1 ;;
        --lines) lines=${2:?--lines takes a number}; shift ;;
        *) echo "usage: sh test/lane.sh [--base REF | --full | --paths [--lines N]]" >&2; exit 2 ;;
    esac
    shift
done

say() { printf 'lane=%s\nwhy=%s\njobs=%s\n' "$1" "$2" "$3"; exit 0; }
[ -z "$full" ] || say standard 'the whole matrix was asked for' "$FULL_JOBS"

if [ -n "$paths" ]; then
    changed=$(cat)
else
    [ -n "$base" ] || base=$(git merge-base origin/main HEAD 2>/dev/null) || base=''
    # no base to measure from (a clone without origin/main): every job
    [ -n "$base" ] && git rev-parse --verify --quiet "$base^{commit}" >/dev/null || say standard 'no base to measure the change from' "$FULL_JOBS"
    # a file moved is two paths, the one it left and the one it has: a workflow moved under test/ is still a workflow gone
    changed=$(git diff --no-renames --name-only "$base" HEAD)
    lines=$(git diff --no-renames --numstat "$base" HEAD -- . ':(exclude)test' ':(exclude)CHANGELOG.md' | awk '{ n += $1 + $2 } END { print n + 0 }')
fi
[ -n "$changed" ] || say fast 'nothing changed' "$FAST_JOBS"

# area PATH -> guarded | standard | fast
area() {
    case $1 in
        .github/*|.githooks/*|allowed-signers|distro/*) echo guarded ;;
        test/gate.sh|test/lane.sh|test/prove.sh) echo guarded ;;
        src/setup.sh|src/dialog.sh) echo guarded ;;   # on and off; the update, and what it trusts
        src/config.sh) echo standard ;;               # every setting goes through it
        src/*.sh)
            # a module that calls a root function, or fetches, read from the tree as it is now. One that is gone
            # cannot be read: a module taken out is no small fix
            if [ ! -f "$1" ]; then echo standard
            elif grep -q -e root_do -e as_root -e root_put -e root_swap -e root_try -e 'curl ' "$1"; then echo guarded
            else echo fast; fi ;;
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
