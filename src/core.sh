# shellcheck extended-analysis=false
# --- core: the paths, the rows, the flags, the temp folder and the traps
# sets: CONFIG CONFIG_DIR LAYOUT_NOT_APPS LAYOUT_ON LAYOUT_SHELLS MODE NL OS PULSE ROOT SPARK_CONFIG_DIR STATE_DIR TAB THEME_ENV TMP VERBOSE YES
OS=$(uname -s)
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/spark-shell
CONFIG=$CONFIG_DIR/config
SPARK_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/spark
THEME_ENV=$SPARK_CONFIG_DIR/theme.env
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell
mkdir_private() { [ -d "$1" ] || (umask 077 && mkdir -p "$1"); }   # mkdir_private DIR -- 0700, when absent
TAB=$(printf '\t')
NL='
'
# rows: ok | would | skip | todo; apply says what changed, --dry-run says all
MODE=apply
VERBOSE=0
YES=0       # --yes: on, on desktop and quiet boot on go ahead without asking
LAYOUT_ON=''   # where a layout opens: desktop | terminal, forced by --desktop | --terminal; else where you ask from
todo=0
would=0   # the would rows printed: a dry run's last line counts them
acting=0
todos=0   # the todo rows printed: a verb's closing line says when one is left
row_part=''   # the part the step under way names in its rows: a write as root that fails is said under it
run_verb=''   # an on or an off under way, as it was asked ("on desktop"): when it stops at a failure its last lines say the ways on
root_why=''   # the system's last words on a write as root that failed
row() {
    printf '%-6s %-12s %s\n' "$1" "$2" "${3:-}"
    [ "$1" != would ] || would=$((would + 1))
    [ "$1" != todo ] || todos=$((todos + 1))
}
dry_close() { if [ "$would" -eq 0 ]; then echo "Nothing to do"; else echo "$would to do"; fi; }
loud() { [ "$MODE" = dry ] || [ "$VERBOSE" = 1 ]; }
ok() { if loud || [ "$acting" = 1 ]; then row ok "$1" "${2:-}"; fi; acting=0; }
skip() { if loud; then row skip "$1" "${2:-}"; fi; acting=0; }
need() {
    row_part=$1
    todo=$((todo + 1))
    if [ "$MODE" = dry ]; then row would "$1" "${2:-}"; return 1; fi
    acting=1
    return 0
}
LAYOUT_SHELLS="sh bash zsh dash fish ksh sudo doas su pkexec"     # a shell or a way to root: in no layout
# what runs, writes, sends or ends what its arguments name, and is often a need's own word (watch, find, time): never the
# model's to open; a desktop entry that starts with one opens as the entry says
LAYOUT_NOT_APPS="$LAYOUT_SHELLS ash csh tcsh mksh yash rbash nu pwsh busybox run0 runuser sg newgrp chroot unshare nsenter bwrap setpriv \
flatpak-spawn distrobox-enter toolbox watch watchexec entr env xargs parallel nohup timeout time setsid nice ionice chrt taskset stdbuf \
unbuffer script expect flock strace ltrace gdb screen dtach abduco at batch crontab systemd-run systemctl loginctl busctl gdbus gio dex \
gtk-launch dbus-run-session dbus-launch dbus-send start-stop-daemon sv find fd rm rmdir unlink shred mv cp dd ln tee truncate install \
mkdir touch mkfifo mknod chmod chown chgrp split csplit tar unzip curl wget aria2c ssh sshpass scp sftp rsync nc ncat netcat socat telnet \
ftp openssl python python2 python3 pypy perl ruby node deno bun php lua luajit awk gawk mawk nawk sed tclsh wish guile java R Rscript julia ghci make \
cmake ninja cargo rustc go gcc cc clang git npm npx pnpm yarn pip pipx uv uvx kill pkill killall reboot poweroff halt shutdown zzz"
as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi; }
sudo_upfront() {
    # ask once, before anything is touched
    [ "$MODE" = apply ] || return 0
    [ "$(id -u)" -ne 0 ] || return 0
    [ "$OS" = Darwin ] && return 0              # brew never needs root
    command -v sudo >/dev/null 2>&1 || return 0
    sudo -n true 2>/dev/null && return 0
    [ -t 0 ] || return 0
    what="the packages"
    if desktop_wanted; then pm_detect; seat_needed && what="the packages and seatd for the desktop"; fi
    if login_wanted; then what="$what and the login screen"; fi
    if [ -n "$THEME$CONSOLE_FONT" ] || [ "$QUIET_LOGIN$QUIET_BOOT" != nono ]; then what="$what and the console"; fi
    printf 'spark-shell needs sudo once, now: %s.\n' "$what"
    sudo -v || { echo "spark-shell: sudo refused. Nothing was changed." >&2; exit 1; }
}
# ROOT is empty on a machine; SPARK_SHELL_ROOT=DIR (tests) prefixes every
# root path and makes root_do a plain call: no sudo, systemctl from PATH
ROOT=${SPARK_SHELL_ROOT:-}
root_do() { if [ -n "$ROOT" ]; then "$@"; else as_root "$@"; fi; }
root_said() { printf '%s\n' "$1" | tail -1 | sed 's/.*: //'; }   # root_said TEXT -> what a program said last, without its own name and the path before it
root_stop() {   # root_stop PATH -- a write as root failed, root_why its reason: one row says it and the run ends there. Nothing is undone and nothing more is tried: what is half done is the person's to see, with the ways on
    row todo "${row_part:-root}" "$1 could not be written${root_why:+: $root_why}"
    run_closing
    run_verb=''
    exit 1
}
run_closing() {   # the last lines of an on or an off that stopped at a step that failed: what stays, and the ways on from there. Proposed, never done for the person: on was asked for, not off
    case $run_verb in
        on*) printf '%s\n' "spark-shell $run_verb: stopped there. What it did before stays done" \
                 "  spark-shell $run_verb again goes on from there, once that is fixed" \
                 "  spark-shell off puts back what spark-shell changed (spark-shell off --dry-run shows it first)" ;;   # the whole off, whatever was asked: off desktop and off login put back a part, and this on did more than that part
        off*) printf '%s\n' "spark-shell $run_verb: stopped there. What it has not put back yet is still kept" \
                  "  spark-shell $run_verb again goes on from there, once that is fixed" ;;
    esac
}
root_can() {   # is there a root to write with (now, or at a tty)?
    [ -n "$ROOT" ] || [ "$(id -u)" -eq 0 ] || sudo -n true 2>/dev/null || { command -v sudo >/dev/null 2>&1 && [ -t 0 ]; }
}
root_sudo_once() {   # root_sudo_once [WHAT] -- the password, once, said why (a no-op after sudo_upfront)
    [ -z "$ROOT" ] || return 0
    [ "$(id -u)" -ne 0 ] || return 0
    sudo -n true 2>/dev/null && return 0
    printf 'spark-shell needs sudo once, now: %s.\n' "${1:-the console}"
    sudo -v
}
spark_bin() {   # -> spark's path, or nothing: PATH, then ~/.local/bin (a non-login ssh shell lacks it)
    if command -v spark >/dev/null 2>&1; then command -v spark
    elif [ -x "$HOME/.local/bin/spark" ]; then printf '%s\n' "$HOME/.local/bin/spark"; fi
}
TMP=$(mktemp -d)
PULSE=''
# an on or an off that ends badly, however it does (a step this program has no row for, a signal), says the ways on too
trap '_xs=$?; [ -z "$run_verb" ] || [ "$_xs" = 0 ] || run_closing; rm -rf "$TMP"; [ -z "$PULSE" ] || kill "$PULSE" 2>/dev/null' EXIT
trap 'exit 141' PIPE   # dash otherwise skips EXIT when a caller closes stdout
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # a signal ends it through the EXIT trap: TMP never stays behind

