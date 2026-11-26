#!/bin/sh
# test/prove.sh -- prove a change on this machine before a push: what CI runs, the way CI runs it, and what
# CI's lane may leave for main (test/lane.sh): the desktop's proofs on this machine's own sway.
#
#   sh test/prove.sh           the gate, the suite as you and as CI's root, the desktop's proofs
#   sh test/prove.sh --quick   the gate and the suite as you
#   sh test/prove.sh --list    the steps, one a line; nothing runs
#
# A run is fenced before its first step:
#   - each step has a home, a runtime and a temp folder of its own under PROVE_DIR (/var/tmp/spark-shell-prove);
#   - the session's variables are unset, so no step reaches the desktop it was started from, and tmux looks for its
#     server in the run's own folder: spark-shell on reloads the server it finds, and that is yours;
#   - a proof starts here and in CI alone (SPARK_SHELL_FENCE, test/desk.py);
#   - a sudo and a doas that refuse stand first on PATH, so no step acts as root here whatever this
#     machine's sudoers say (a proof without a root of its own once turned a login screen off);
#   - the suite and the proofs find the system's tools alone, as CI's containers do: no folder of your own
#     home is on their PATH, so a spark or a spark-shell of yours never answers for the one under test;
#   - the system's files a desktop lives by are measured before and after: a difference fails the run;
#   - no process of the run may be left when it ends.
# The suite as CI's root runs in a user space where you are root over your own files alone, with a first
# process that reaps no orphan, as CI's containers have: no file mode stops a write there, and a process
# that ended with its parent gone stays listed. It is skipped, and said, where unshare cannot map your ids.
# PROVE_KNOWN names a file of the suite's failures this machine always shows, one name a line (the words
# after FAIL, to the three spaces): a failure not in it fails the step. The default is
# ~/.config/spark-shell/prove-known; with no such file every failure counts.
set -eu
cd "$(dirname "$0")/.."
REPO=$PWD
out=${PROVE_DIR:-/var/tmp/spark-shell-prove}
known=${PROVE_KNOWN:-${XDG_CONFIG_HOME:-$HOME/.config}/spark-shell/prove-known}
cargo_home=${CARGO_HOME:-$HOME/.cargo}; rustup_home=${RUSTUP_HOME:-$HOME/.rustup}
terms=${SPARK_PRIVACY_TERMS:-${XDG_CONFIG_HOME:-$HOME/.config}/spark/privacy-terms}   # your own word list: the gate reads it from your home, and a step has none
quick=''; list=''
case ${1:-} in
    '') ;;
    --quick) quick=1 ;;
    --list) list=1 ;;
    *) echo "usage: sh test/prove.sh [--quick | --list]" >&2; exit 2 ;;
esac

PROOFS='layout window desktop winpad voice bar journeys'   # the desktop job's, in its order; the journeys (test/journeys.py) in a bwrap of their own
steps() {
    printf '%s\n' gate 'suite'
    [ -n "$quick" ] || { printf '%s\n' 'suite as root'; for p in $PROOFS; do printf 'proof %s\n' "$p"; done; }
    printf '%s\n' 'nothing left running' "the system's files as they were"
}
if [ -n "$list" ]; then steps; exit 0; fi

sh test/lane.sh | sed -n 's/^lane=/prove: CI will run this change in the lane /p; s/^why=/prove:   why -- /p'
# the folder is removed whole before a run: only one a run of this made, by the file it left in it. A file a root
# of the user space made belongs to a sub id, so it is removed from such a space
if [ -e "$out" ]; then
    [ -f "$out/.spark-shell-prove" ] || { echo "prove: $out is there and is no folder of a prove run: not touched (PROVE_DIR names another)" >&2; exit 2; }
    unshare --user --map-root-user --map-auto -- rm -rf "$out" 2>/dev/null || rm -rf "$out"
fi
mkdir -p "$out/no-root"; : > "$out/.spark-shell-prove"
for t in sudo doas; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/no-root/asked"\nexit 1\n' "$t" "$out" > "$out/no-root/$t"; chmod 755 "$out/no-root/$t"
done

measured() {   # -> one line that changes when a file a desktop lives by does
    for f in /etc/group /etc/passwd /etc/rc.local /etc/sudoers.d /etc/greetd/config.toml /etc/spark-shell/login /etc/spark-shell/login/boot /usr/local/lib/spark-shell/spark-dialog; do
        stat -c '%n %Y %s' "$f" 2>/dev/null || ls -ldn "$f" 2>/dev/null || echo "$f none"
    done | cksum
}
sys_path=$(printf '%s\n' "$PATH" | tr ':' '\n' | awk -v h="$HOME/" 'length && index($0, h) != 1' | paste -sd: -)
fenced() { fence "$PATH" "$@"; }     # fenced DIR COMMAND... -- with your PATH: the gate and the builds, whose cargo may live in your home
apart() { fence "$sys_path" "$@"; }   # apart DIR COMMAND... -- with the system's tools alone: the suite and the proofs
fence() {   # fence PATH DIR COMMAND... -- in a home of its own, away from the session, with no way to root
    fp=$1; d=$2; shift 2
    mkdir -p "$d/home" "$d/run" "$d/tmp" "$d/pts"; chmod 700 "$d/run"
    env -u SWAYSOCK -u WAYLAND_DISPLAY -u DISPLAY -u I3SOCK -u DBUS_SESSION_BUS_ADDRESS -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_DATA_HOME -u XDG_CACHE_HOME -u TMUX -u TMUX_PANE \
        PATH="$out/no-root:$fp" HOME="$d/home" XDG_RUNTIME_DIR="$d/run" TMPDIR="$d/tmp" TMUX_TMPDIR="$d/tmp" SPARK_SHELL_FENCE=prove CARGO_HOME="$cargo_home" RUSTUP_HOME="$rustup_home" \
        SPARK_SHELL_PTS_DIR="$d/pts" SPARK_SHELL_SEMANTIC_URL=none SPARK_SHELL_NO_APPLY=1 SPARK_PRIVACY_TERMS="$terms" REPO="$REPO" "$@" </dev/null
}
n=0
step() {   # step NAME COMMAND... -- one step: ok and its seconds, or FAIL with the end of its log, and the run ends
    name=$1; shift; n=$((n + 1)); log=$out/$n.log; t0=$(date +%s)
    if "$@" > "$log" 2>&1; then printf 'ok    %s (%s s)\n' "$name" "$(( $(date +%s) - t0 ))"
    else printf 'FAIL  %s -- %s\n' "$name" "$log"; tail -15 "$log" | sed 's/^/      /'; exit 1; fi
}
suite_said() {   # suite_said LOG -- the suite's failures, each known here; false at the first that is not
    new=$(sed -n 's/^  FAIL \(.*\)$/\1/p' "$1" | sed 's/   .*//' | sort -u | { if [ -f "$known" ]; then grep -vxF -f "$known" || :; else cat; fi; })
    [ -z "$new" ] || { echo "the suite failed, and not as this machine always does ($known):"; printf '%s\n' "$new"; return 1; }
    grep -q '^shell_test: [0-9]* ok' "$1" || { echo "the suite did not reach its end"; return 1; }
}
suite_user() {
    apart "$out/suite" timeout 2400 sh test/shell_test.sh --parallel > "$out/suite.log" 2>&1 || :
    tail -1 "$out/suite.log"; suite_said "$out/suite.log"
}
suite_root() {   # a user space where you are root over your own files and your sub ids, a first process that reaps nothing
    apart "$out/suite-root" unshare --user --map-root-user --map-auto --pid --fork --mount-proc --kill-child -- sh -c '
        ( timeout 2400 sh test/shell_test.sh --parallel > "$0/suite-root.log" 2>&1; echo $? > "$0/suite-root.done" ) &
        exec python3 -I -c "import os, sys, time
while not os.path.exists(sys.argv[1]): time.sleep(0.5)" "$0/suite-root.done"' "$out" || :
    tail -1 "$out/suite-root.log"; suite_said "$out/suite-root.log"
}
proof() {   # proof NAME -- one of the desktop job's proofs, on a headless sway of its own
    d=$out/proof-$1; pad=$REPO/component/target/release/spark-winpad; bar=$REPO/component/target/release/spark-bar
    mkdir -p "$d/evidence" "$d/home"
    (   # from its own home, as the desktop job's user starts it
        cd "$d/home"
        case $1 in
            layout) apart "$d" timeout 420 python3 -I "$REPO/test/layout_desktop_proof.py" ;;
            window) apart "$d" env SPARK_SHELL_WINPAD="$pad" timeout 420 python3 -I "$REPO/test/window_desktop_proof.py" ;;
            desktop) apart "$d" timeout 420 sh "$REPO/test/desktop_proof.sh" ;;
            winpad) apart "$d" env SPARK_SHELL_WINPAD="$pad" timeout 420 python3 -I "$REPO/test/winpad_desktop_proof.py" "$d/evidence" ;;
            voice) apart "$d" env SPARK_SHELL_WINPAD="$pad" timeout 420 python3 -I "$REPO/test/voice_desktop_proof.py" "$d/evidence" ;;
            journeys)
                for j in home live matrix loops notifications; do REPLAY_DIR="$d" apart "$d" timeout 480 python3 -I "$REPO/test/replay.py" "$j" here || exit 1; done ;;
            bar) apart "$d" env SPARK_SHELL_WINPAD="$pad" SPARK_SHELL_BAR="$bar" timeout 600 python3 -I "$REPO/test/bar_desktop_proof.py" "$d/evidence" ;;
        esac
    )
}
builds() {   # the builds the proofs run, made here from the tree
    for c in winpad bar dialog wallpaper; do (cd "component/$c" && fenced "$out/build-$c" cargo build --release --locked) || return 1; done
}
left() {   # no process of the run is left. Every step ran with its home under the run's folder: a process whose own HOME is there is the run's, whatever its command says
    sleep 2
    l=''
    for e in /proc/[0-9]*/environ; do
        tr '\0' '\n' 2>/dev/null < "$e" | grep -q "^HOME=$out/" || continue
        pid=${e#/proc/}; pid=${pid%/environ}
        l="$l$pid $(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | cut -c1-120)
"
    done
    [ -z "$l" ] || { echo "left running:"; printf '%s' "$l"; return 1; }
}

before=$(measured)
step gate fenced "$out/gate" sh test/gate.sh --quick
step suite suite_user
if [ -z "$quick" ]; then
    if unshare --user --map-root-user --map-auto true 2>/dev/null; then step 'suite as root' suite_root
    else echo "skip  suite as root (unshare cannot map your ids here: CI's rows run it)"; fi
    if command -v sway >/dev/null 2>&1 && command -v cargo >/dev/null 2>&1; then
        step "the builds the proofs run" builds
        for p in $PROOFS; do
            if [ "$p" = journeys ] && ! command -v bwrap >/dev/null 2>&1; then echo "skip  proof journeys (no bwrap here: CI's desktop job runs them)"; continue; fi
            step "proof $p" proof "$p"
        done
    else echo "skip  the desktop's proofs (no sway or no cargo here: CI's desktop job runs them)"; fi
fi
step 'nothing left running' left
after=$(measured)
if [ "$before" = "$after" ]; then echo "ok    the system's files as they were"
else echo "FAIL  a file the desktop lives by changed during the run: look at /etc before anything else"; exit 1; fi
[ ! -s "$out/no-root/asked" ] || echo "note  $(grep -c . "$out/no-root/asked") calls to sudo or doas were refused ($out/no-root/asked)"
echo "prove: $n steps passed"
