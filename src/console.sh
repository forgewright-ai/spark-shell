# shellcheck extended-analysis=false
# ------------------------------------------------------------- the console
# Four config keys, each written by its verb and applied by `on`: THEME
# (a palette name, or none), CONSOLE_FONT ("FACE SIZE", empty: the console
# keeps its font), QUIET_LOGIN and QUIET_BOOT (yes|no). `off` hands every
# one back. A root file is found by spark-shell's own marks and names:
#   ~/.config/spark/theme.env     the palette, 20 THEME_* keys (spark reads it too)
#   FILE.spark-shell-orig         a root file as it was before spark-shell
#   lines ending ` #spark-shell-palette#` or ` #spark-shell-quiet#`
#   zz-spark-shell-quiet.*        the GRUB and the kernel image drop-ins
# Every root path is under ROOT (SPARK_SHELL_ROOT in the tests), even the
# ones only read (/run/systemd, /sys, /proc), so a fixture pins the shape.
PALETTE_DIR=$CONFIG_DIR/themes                     # your NAME.env wins over gallery/theme/
CONSOLE_COLORS=$CONFIG_DIR/console-colors          # the escapes, sent at a console login
CONSOLE_RGB=$CONFIG_DIR/console-colors.rgb         # setvtrgb's three lines, read by root at boot
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell
mkdir_private() { [ -d "$1" ] || (umask 077 && mkdir -p "$1"); }   # mkdir_private DIR -- 0700, when absent
mkdir_state() { mkdir_private "$STATE_DIR" && mkdir -p "$@"; }     # mkdir_state DIR... -- under the state, made 0700 first
# a lock is a file made with O_EXCL (set -C), never mkdir's answer: uutils' mkdir before
# 0.11 (Ubuntu 26.04) says yes to a folder that is there
lock_take() { ( set -C; : > "$1" ) 2>/dev/null; }   # lock_take PATH -- true when this call made PATH, false when it was there
lock_drop() { rm -f "$1" 2>/dev/null || rmdir "$1" 2>/dev/null || :; }   # lock_drop PATH -- the lock gone, file or folder
private_dirs() {   # the state, the themes and the notes made 0700; a link is left as it is
    _pd=''
    for _d in "$STATE_DIR" "$PALETTE_DIR" "$NOTES_DIR"; do
        [ -d "$_d" ] && [ ! -L "$_d" ] || continue
        # shellcheck disable=SC2086   # the mode, the links, the owner's number: split on purpose
        _pl=$(ls -ldn "$_d"); set -- $_pl
        [ "$3" = "$(id -u)" ] || continue
        case $1 in ????------*) continue ;; esac   # nothing for the group or the others: private already
        if [ "$MODE" = dry ]; then row would private "${_d#"$HOME"/} yours alone (0700)"; continue; fi
        chmod go-rwx "$_d" 2>/dev/null && _pd="$_pd ${_d#"$HOME"/}"
    done
    [ -z "$_pd" ] || row ok private "yours alone now (0700):$_pd"
}
REBUILD=$STATE_DIR/boot-rebuild                    # a boot rebuild that has not held yet: grub | uki, one a line
TERMINAL_SEEN=$STATE_DIR/terminal.seen             # macOS: the palette and font Terminal.app's profile has
POINTER_SEEN=$STATE_DIR/pointer.seen               # the spark pointer's version a running sway last loaded
CONSOLE_UNIT=etc/systemd/system/spark-shell-console.service
PALETTE_MARK=' #spark-shell-palette#'
QUIET_MARK=' #spark-shell-quiet#'
SPLASH_MARK='#spark-shell-quiet# '
CURSOR_ON=$(printf '\033[?25h')
# the quiet kernel line: quiet and loglevel=3 silence the kernel, splash
# hands Plymouth the boot, systemd.show_status=false keeps the unit lines
# off, udev.log_level=3 quiets the initramfs, fbcon=nodefer stops the flicker
QUIET_WORDS='quiet splash loglevel=3 systemd.show_status=false udev.log_level=3 fbcon=nodefer'

is_wsl() {   # WSL, read once: WSL_DISTRO_NAME is set, or the kernel says microsoft
    if [ -z "${_WSL:-}" ]; then if [ "$OS" != Darwin ] && { [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qis microsoft "$ROOT/proc/version"; }; then _WSL=yes; else _WSL=no; fi; fi
    [ "$_WSL" = yes ]
}
init_shape() {   # -> systemd | runit | none: what boots this Linux
    if [ -d "$ROOT/run/systemd/system" ]; then echo systemd
    elif [ -d "$ROOT/etc/runit" ]; then echo runit
    else echo none; fi
}
console_linux() { [ "$OS" != Darwin ] && ! is_wsl; }   # a Linux with a console of its own
root_ready() {   # root_ready ROW -- a root to write with, asked once; else a todo row and false
    if ! root_can; then row todo "$1" "root is needed -- spark-shell on at a terminal (sudo once)"; acting=0; return 1; fi
    root_sudo_once "the console" || { row todo "$1" "sudo refused -- spark-shell on at a terminal (sudo once)"; acting=0; return 1; }
}
# under /boot (a vfat ESP, dmask 0077) a user cannot see a file: root tests
# and reads there, and a failed chmod is no error (vfat has no modes)
root_exists() { [ -e "$1" ] || root_do test -e "$1" 2>/dev/null; }   # root_exists PATH
root_put() {   # root_put SRC DST [MODE] -- a root file written from SRC; a new one takes MODE (0644)
    _new=0; root_exists "$2" || _new=1
    root_do mkdir -p "$(dirname "$2")"
    root_do cp "$1" "$2"
    [ "$_new" = 0 ] || root_do chmod "${3:-0644}" "$2" 2>/dev/null || true
}
root_swap() {   # root_swap SRC DST MODE -- a root program put in place by a rename: Linux refuses a write to a running binary
    root_do mkdir -p "$(dirname "$2")"
    root_do cp "$1" "$2.spark-shell-new"
    root_do chmod "$3" "$2.spark-shell-new"
    root_do mv -f "$2.spark-shell-new" "$2"
}
root_read() {   # root_read FILE -> its bytes (root when a user cannot read it); false when absent or unreadable
    if [ -r "$1" ]; then cat "$1"; else root_do cat "$1" 2>/dev/null; fi
}
# a marked line ends with the mark; off deletes exactly those (LC_ALL=C:
# the bytes pass through untouched, a last line with no newline stays so)
marked() {   # marked FILE MARK -> the lines carrying MARK, the mark off
    [ -f "$1" ] || return 0
    LC_ALL=C awk -v m="$2" 'length($0) >= length(m) && substr($0, length($0) - length(m) + 1) == m { print substr($0, 1, length($0) - length(m)) }' "$1"
}
marked_text() {   # marked_text FILE MARK [LINESFILE [exit]] -> FILE without MARK's lines, then LINESFILE's lines marked
    # (with exit: before a last `exit 0`, where rc.local still runs them)
    [ -f "$1" ] || { [ -z "${3:-}" ] || LC_ALL=C sed "s/\$/$2/" "$3"; return 0; }
    _open=0; [ -z "$(tail -c1 "$1")" ] || _open=1   # the last line has no newline
    LC_ALL=C awk -v m="$2" -v open="$_open" -v add="${3:-}" -v ex="${4:-}" '
        function add_lines(   l) { while ((getline l < add) > 0) print l m }
        { k = !(length($0) >= length(m) && substr($0, length($0) - length(m) + 1) == m); if (k) line[++n] = $0 }
        END {
            if (!k) open = 0
            last = n; while (last > 0 && line[last] ~ /^[ \t]*$/) last--
            at = n + 1; if (add != "" && ex != "" && last > 0 && line[last] ~ /^[ \t]*exit 0[ \t]*$/) at = last
            for (i = 1; i <= n; i++) {
                if (i == at) add_lines()
                printf "%s%s", line[i], (i == n && open && !(add != "" && at > n)) ? "" : "\n"
            }
            if (add != "" && at > n) add_lines()
        }' "$1"
}

