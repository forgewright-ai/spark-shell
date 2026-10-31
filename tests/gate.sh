#!/bin/sh
# tests/gate.sh -- every check CI runs, on this machine, before a push (#155):
# the lint job's (privacy over the tree, ASCII docs, no hex color in a
# template, shellcheck), the dialog's (cargo fmt, clippy, test, the pty test
# against a release build), every python3 test ci.yml runs, read from ci.yml
# itself so a step added there runs here too, then the suite's two halves
# (this machine's, and Linux's through a uname stub on a Mac). One line a
# check; the first failure is named, with its log, and the gate stops.
#   sh tests/gate.sh           everything
#   sh tests/gate.sh --quick   all but the two suites (the pre-push hook)
#   sh tests/gate.sh --list    the checks, one a line; nothing runs
set -eu
cd "$(dirname "$0")/.."
ci=.github/workflows/ci.yml
quick=''; list=''
case ${1:-} in
    '') ;;
    --quick) quick=1 ;;
    --list) list=1 ;;
    *) echo "usage: sh tests/gate.sh [--quick | --list]" >&2; exit 2 ;;
esac
logs=$(mktemp -d "${TMPDIR:-/tmp}/gate.XXXXXX")
trap 'rm -rf "$logs"' EXIT INT TERM
export SPARK_SHELL_NO_APPLY=1   # a test never touches this machine's terminal profile

# the python3 tests ci.yml runs, each as written there (-I kept); dialog_pty
# takes the release build as its argument
py_tests() { grep -oE 'python3( -I)? tests/[A-Za-z0-9_]+\.py' "$ci" | awk '!seen[$0]++'; }

checks() {
    printf '%s\n' privacy ascii templates shellcheck 'cargo fmt --check' 'cargo clippy' 'cargo test' 'cargo build --release'
    py_tests
    [ -n "$quick" ] || printf '%s\n' 'suite: this machine' 'suite: linux (uname stub)'
}
if [ -n "$list" ]; then checks; exit 0; fi

n=0
step() {   # step NAME COMMAND... -- one check: ok and on, or FAIL with the end of its log and exit 1
    n=$((n + 1))
    if "$@" > "$logs/$n.log" 2>&1; then printf 'ok    %s\n' "$_name"
    else printf 'FAIL  %s\n' "$_name"; tail -20 "$logs/$n.log" | sed 's/^/      /'; exit 1; fi
}

# --- the lint job's checks, as ci.yml writes them
privacy() {
    terms=$(cat .privacy-terms "${SPARK_PRIVACY_TERMS:-${XDG_CONFIG_HOME:-$HOME/.config}/spark/privacy-terms}" 2>/dev/null \
            | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | sort -u | sed 's,[][\.*^$+?(){}|/],\\&,g' | paste -sd'|' -)
    if [ -n "$terms" ] && git grep -l -i -w -E "$terms" -- . ':(exclude).privacy-terms'; then echo "a listed word is in the tree"; return 1; fi
    hits=$(git grep -n -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -- . | sed -E 's/[A-Za-z0-9._-]+@[A-Za-z0-9.-]+\.(service|socket|timer|target)//g' \
           | grep -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' | grep -v 'you@example.com' | cut -d: -f1 | sort -u || true)
    [ -z "$hits" ] || { printf '%s\n' "$hits"; echo "an e-mail address is in the tree"; return 1; }
    if git grep -l -E '\b(10\.[0-9]+\.[0-9]+\.[0-9]+|192\.168\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)\b' -- .; then echo "a private IPv4 is in the tree"; return 1; fi
    if git grep -l -E '(^.|[^[:alnum:]/._-])/(home|Users)/[A-Za-z0-9_-]+' -- .; then echo "a home path naming a user is in the tree"; return 1; fi
}
ascii() {   # the file list of ci.yml's ascii step, read from it
    files=$(sed -n 's/^ *for f in \(.*\); do$/\1/p' "$ci" | head -1)
    [ -n "$files" ] || { echo "no file list in $ci's ascii step"; return 1; }
    tab=$(printf '\t')
    for f in $(eval "printf '%s\n' $files"); do
        if LC_ALL=C grep -n "[^ -~${tab}]" "$f"; then echo "non-ASCII in $f"; return 1; fi
    done
}
templates() { if grep -rnE '#[0-9a-fA-F]{6}' templates; then echo "a hex color is in a template"; return 1; fi; }
shellcheck_ci() {   # the run line of ci.yml's shellcheck step, as it is
    cmd=$(sed -n 's/^ *run: \(shellcheck .*\)$/\1/p' "$ci" | head -1)
    [ -n "$cmd" ] || { echo "no shellcheck step in $ci"; return 1; }
    eval "$cmd"
}
_name=privacy; step privacy
_name=ascii; step ascii
_name=templates; step templates
_name=shellcheck; step shellcheck_ci

# --- the dialog
_name='cargo fmt --check'; step sh -c 'cd dialog && cargo fmt --check'
_name='cargo clippy'; step sh -c 'cd dialog && cargo clippy --locked --all-targets -- -D warnings'
_name='cargo test'; step sh -c 'cd dialog && cargo test --locked'
_name='cargo build --release'; step sh -c 'cd dialog && cargo build --locked --release'

# --- every python3 test of ci.yml
py_tests > "$logs/py"
while IFS= read -r t; do
    _name=$t
    # shellcheck disable=SC2086   # the line as ci.yml writes it: python3, -I maybe, the file
    case $t in *dialog_pty.py) step $t dialog/target/release/spark-dialog ;; *) step $t ;; esac
done < "$logs/py"

[ -z "$quick" ] || { echo "gate: $n checks passed (the suites are not run with --quick)"; exit 0; }

# --- the suite's two halves, at once
if [ "$(uname -s)" = Darwin ]; then
    mkdir -p "$logs/stub"
    printf '#!/bin/sh\ncase "${1:-}" in -m) echo x86_64 ;; -r) echo 6.6.0 ;; *) echo Linux ;; esac\n' > "$logs/stub/uname"; chmod +x "$logs/stub/uname"
    # each half's status kept whatever it is: set -e would end the job before it is written
    { st=0; sh tests/shell_test.sh > "$logs/mac.log" 2>&1 || st=$?; echo "$st" > "$logs/mac.st"; } &
    { st=0; PATH=$logs/stub:$PATH sh tests/shell_test.sh > "$logs/linux.log" 2>&1 || st=$?; echo "$st" > "$logs/linux.st"; } &
    wait
    _bad=''
    for h in mac linux; do   # both halves said, a failing one with its lines, before the gate stops
        n=$((n + 1)); _l=$(tail -1 "$logs/$h.log")
        if [ "$(cat "$logs/$h.st")" = 0 ]; then printf 'ok    suite: %s (%s)\n' "$h" "$_l"
        else printf 'FAIL  suite: %s (%s)\n' "$h" "$_l"; grep '  FAIL' "$logs/$h.log" | head -20 | sed 's/^/      /'; _bad=1; fi
    done
    [ -z "$_bad" ] || exit 1
else
    _name='suite: this machine'; step sh tests/shell_test.sh
fi
echo "gate: $n checks passed"
