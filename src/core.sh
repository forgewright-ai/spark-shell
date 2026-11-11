# shellcheck extended-analysis=false
# --- core: the paths, the rows, the flags, the temp folder and the traps
# sets: CONFIG CONFIG_DIR MODE NL OS PLAYER PULSE ROOT SPARK_CONFIG_DIR STATE_DIR TAB THEME_ENV TMP VERBOSE YES
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
PLAYER=''   # a desk's player: windows | rooms, forced by --windows | --rooms; else where you ask from
todo=0
would=0   # the would rows printed: a dry run's last line counts them
acting=0
todos=0   # the todo rows printed: a verb's closing line says when one is left
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
    todo=$((todo + 1))
    if [ "$MODE" = dry ]; then row would "$1" "${2:-}"; return 1; fi
    acting=1
    return 0
}
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
trap 'rm -rf "$TMP"; [ -z "$PULSE" ] || kill "$PULSE" 2>/dev/null' EXIT
trap 'exit 141' PIPE   # dash otherwise skips EXIT when a caller closes stdout
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM   # a signal ends it through the EXIT trap: TMP never stays behind

