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
#   sh test/lane.sh --names      each name a module of this tree takes from another, or from a command, "MODULE NAME"
#                                a line (test/modules_check.py)
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
#             fetches a build, what a build is made by and takes from outside) and what acts as root (on and
#             off, a distro's package lists, what becomes root's file, a module that says a root word or
#             takes a name that is another's, before the change or after it). CI: every job. A person tags it.
#
# A path this list does not name is standard, never fast: a new kind of file is proven whole until someone
# says what it is.
set -eu

FAST_JOBS=' debian fedora '
FULL_JOBS=' linux debian ubuntu arch void fedora opensuse desktop macos dialog-build dialog wallpaper wallpaper-deny winpad winpad-deny ear ear-deny bar bar-deny '
FAST_LINES=400   # the most a fast fix changes outside test/ and the changelog

base=''; at=HEAD; here=''; full=''; paths=''; taken_names=''; lines=''
while [ $# -gt 0 ]; do
    case $1 in
        --base) base=${2:?--base takes a commit}; shift ;;
        --at) at=${2:?--at takes a commit}; shift ;;
        --here) here=1 ;;
        --full) full=1 ;;
        --paths) paths=1 ;;
        --names) taken_names=1 ;;
        --lines) lines=${2:?--lines takes a number}; shift ;;
        *) echo "usage: sh test/lane.sh [--base REF] [--at REF] [--here] | --full | --paths [--lines N] | --names" >&2; exit 2 ;;
    esac
    shift
done
[ -n "$here" ] || cd "$(dirname "$0")/.."

say() { printf 'lane=%s\nwhy=%s\njobs=%s\n' "$1" "$2" "$3"; exit 0; }
[ -z "$full" ] || say standard 'the whole matrix was asked for' "$FULL_JOBS"

if [ -n "$taken_names" ]; then changed=names
elif [ -n "$paths" ]; then
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
    # a path is judged by its name and its text, and a link's text is not what it stands for
    link=$(git -c core.quotePath=false diff --no-renames --raw "$base" "$at" | awk -F '\t' '$1 ~ /^:[0-7]+ 1[26]0000 / { print $2; exit }')
    [ -z "$link" ] || say guarded "$link" "$FULL_JOBS"
fi
[ -n "$changed" ] || say fast 'nothing changed' "$FAST_JOBS"

# the commands the update, a signature and root's steps run: a function by one of these names takes its place
COMMANDS='awk basename cat cd chmod cksum cmp command cp curl cut date dirname echo env find git grep head id install jq kill ln ls mkdir mktemp mv paste printf python3 read readlink rm rmdir sed sh sha256sum shasum sort sudo systemctl tail tar test touch tr true type uname visudo wc'
# the globals more than one module sets: the flags of a run, the palette's file and a subshell's own temp folder
SHARED='LAYOUT_ON MODE PROVIDE_CLIENT PULSE REFUSE_AS THEME_ENV TMP US VERBOSE YES'

# text END PATH -- the file at END, a commit; this tree's when END is empty
text() { if [ -n "$1" ]; then git show "$1:$2" 2>/dev/null; else cat "$2" 2>/dev/null; fi; }
# roots -- the text on stdin calls a root function or a way to root, fetches, runs git, or takes a name by alias or
# unset. A word only shown to the person counts too: it is kept in a module that is guarded anyway
roots() { grep -q -e root_do -e as_root -e root_put -e root_swap -e root_try -e sudo -e doas -e pkexec -e run0 -e 'curl ' -e wget -e 'git ' -e GIT_ -e 'alias ' -e 'unset -f'; }
# names MODULE [all] -- of the module on stdin, "MODULE<tab>NAME" a line: the functions it defines and the globals it
# sets at source time; with all, each global it sets anywhere too
names() {
    tr -d '\000' | LC_ALL=C awk -v m="$1" -v all="${2:-}" '
        { while (sub(/\\$/, "")) { if ((getline next_line) <= 0) break; $0 = $0 next_line } }
        {
            for (s = $0; match(s, /[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*\)/); s = substr(s, RSTART + RLENGTH)) {
                n = substr(s, RSTART, RLENGTH); sub(/[ \t(].*/, "", n)
                if (RSTART == 1 || substr(s, RSTART - 1, 1) !~ /[0-9.$-]/) print m "\t" n
            }
            if (match($0, /^[A-Za-z_][A-Za-z0-9_]*=/)) print m "\t" substr($0, 1, RLENGTH - 1)
            if (all) for (s = " " $0; match(s, /[^A-Za-z0-9_][A-Z_][A-Z0-9_]*=/); s = substr(s, RSTART + RLENGTH)) print m "\t" substr(s, RSTART + 1, RLENGTH - 2)
        }'
}
# owned END -- the names of the entry and of every module at END
owned() {
    if [ -n "$1" ]; then git ls-tree --full-tree --name-only "$1" spark-shell src/ 2>/dev/null; else ls spark-shell src/*.sh 2>/dev/null; fi \
        | while IFS= read -r m; do text "$1" "$m" | names "$m"; done
}
# says END OWNED PATH -- the file says a root word
says() { text "$1" "$3" | roots; }
# taken END OWNED PATH -> the names of the module that are another's, or a command's: the modules share one namespace,
# and the last to take a name is the one that answers to it
taken() {
    mine=$(text "$1" "$3" | names '' all | cut -f2)
    [ -z "$mine" ] || { printf '%s\n' "$COMMANDS" | tr ' ' '\n'; printf '%s\n' "$2" | awk -F '\t' -v m="$3" '$1 != m { print $2 }'; } \
        | grep -vxF "$(printf '%s\n' "$SHARED" | tr ' ' '\n')" | grep -xF "$mine" | sort -u
}
takes() { [ -n "$(taken "$@")" ]; }
if [ -n "$taken_names" ]; then
    own_at=$(owned '')
    for p in src/*.sh; do taken '' "$own_at" "$p" | sed "s|^|$p |"; done
    exit 0
fi
# either TEST PATH -- it holds as the change leaves the file or as it was before: a change that takes the root call out
# of a module changed what acts as root. A list of paths (a test's seam) has no before: the file in this tree
either() { if [ -n "$paths" ]; then "$1" '' "$own_at" "$2"; else "$1" "$at" "$own_at" "$2" || "$1" "$base" "$own_base" "$2"; fi; }
here_still() { if [ -n "$paths" ]; then [ -f "$1" ]; else git cat-file -e "$at:$1" 2>/dev/null; fi; }
# module PATH LANE -> guarded, else LANE, for a module of src/. One that is gone and never acted as root is no small fix: standard
module() { if either says "$1" || either takes "$1"; then echo guarded; elif here_still "$1"; then echo "$2"; else echo standard; fi; }
# crates PATH -- the Cargo.lock or the Cargo.toml on stdin without the version of a package of this tree: the one thing a
# fix moves there. Everything else is kept as it is written, so a package from outside is not missed by how it is written
crates() {
    case $1 in
        *Cargo.lock) awk '
            function out(   i) { for (i = 1; i <= n; i++) if (outside || line[i] !~ /^version = "[0-9.]*"$/) print line[i]; n = 0; outside = 0 }
            /^\[/ { out() }
            { line[++n] = $0 } /source/ { outside = 1 }
            END { out() }' ;;
        *) awk '/^\[/ { part = $0 } part == "[package]" && /^version = "[0-9.]*"$/ { next } { print }' ;;
    esac
}
# cargo PATH -> guarded when a build would take another package, or be made another way; our own version that moves is standard
cargo() { if [ -z "$paths" ] && [ "$(text "$at" "$1" | crates "$1")" != "$(text "$base" "$1" | crates "$1")" ]; then echo guarded; else echo standard; fi; }
# area PATH -> guarded | standard | fast
area() {
    case $1 in
        '"'*) echo guarded ;;   # a name git had to quote
        .github/*|.githooks/*|allowed-signers|distro/*) echo guarded ;;
        .gitattributes|*/.gitattributes|.gitmodules) echo guarded ;;   # what a checkout writes
        test/gate.sh|test/lane.sh|test/prove.sh|test/tag.sh|test/reds.sh) echo guarded ;;
        test/*_build.sh|test/dialog_sbom.sh) echo guarded ;;   # a release runs them
        *deny.toml|*build.rs|.cargo/*|*/.cargo/*|*rust-toolchain*) echo guarded ;;   # how a build is made, and what it may take
        *Cargo.lock|*Cargo.toml) cargo "$1" ;;
        spark-shell) echo guarded ;;                  # the entry: every verb passes through it, the update too, and the help is its head
        src/setup.sh|src/dialog.sh|src/gallery.sh) echo guarded ;;   # on and off; the update and the gallery, which read a signature and say what is trusted
        src/render.sh|template/etc/*|template/login/*) echo guarded ;;   # root's own files, and what renders them
        lib/dhcp.py|lib/network.py) echo guarded ;;   # run as root
        src/config.sh) module "$1" standard ;;        # every setting goes through it
        src/*.sh) module "$1" fast ;;
        lib/*) if either says "$1"; then echo guarded; else echo standard; fi ;;
        test/*_proof.py|test/*_proof.sh|test/desk.py|test/journeys.py|test/replay.py|test/dialog_pty.py) echo standard ;;   # run by the desktop job or a build job
        test/*) echo fast ;;
        README.md|CHANGELOG.md|CREDITS.md|LICENSE|config.example) echo fast ;;
        *) echo standard ;;
    esac
}

own_at=''; own_base=''
case $changed in *src/*) if [ -n "$paths" ]; then own_at=$(owned ''); else own_at=$(owned "$at"); own_base=$(owned "$base"); fi ;; esac
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
