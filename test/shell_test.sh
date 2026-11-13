#!/bin/sh
# spark-shell tests -- a throwaway HOME, no network, no packages: the
# package row is forced to `todo` by an unknown distro fixture, and the
# prompt row is satisfied by a stub, so `on` exercises the render and
# link machinery only. Run: sh test/shell_test.sh (or --parallel, below)
# With SPARK=/path/to/spark's clone, section 13 renders its palettes too.
# shellcheck extended-analysis=false   # 0.11.0's data flow analysis of this file takes over 10 GB
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
fixture_python=$(command -v python3)
sys_timeout=$(command -v timeout || :)   # macOS has none: fresh puts a stand-in on PATH
# on a Mac the suite builds Terminal.app's profile and prints it, never
# applying it: the developer's own terminal and profiles stay as they are
[ "$(uname -s)" != Darwin ] || export SPARK_SHELL_NO_APPLY=1
pass=0; fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s   %s\n' "$1" "${2:-}"; }
tab=$(printf '\t')
plain() {   # plain FILE -- no hex color, no byte outside ASCII
    ! grep -Eq '#[0-9a-fA-F]{6}' "$1" && ! LC_ALL=C grep -q "[^ -~${tab}]" "$1"
}

# every throwaway folder the suite makes is listed here and goes at its end: the homes once stayed in /tmp, one a
# fresh, every run (v0.129.2). A folder a test left unreadable is made readable first
TMPDIRS=$(mktemp)
tmpd() { _td=$(mktemp -d) && printf '%s\n' "$_td" >> "$TMPDIRS" && printf '%s\n' "$_td"; }   # tmpd -> a new folder, gone at the end
# the suite's own exit status kept: under set -e a command of the trap that failed (a chmod in a tree a test left) ended
# the suite with 1 after 0 failed
_rc=0   # set again inside the trap; named here so shellcheck sees it
trap '_rc=$?; while IFS= read -r _td; do [ -z "$_td" ] || { chmod -R u+rwX "$_td" 2>/dev/null || :; rm -rf "$_td" 2>/dev/null || :; }; done < "$TMPDIRS" || :; rm -f "$TMPDIRS" || :; exit "$_rc"' EXIT
# never the person's own session: a test that notifies, locks or asks a compositor must reach none of it,
# whatever the shell that started the suite carries
unset WAYLAND_DISPLAY SWAYSOCK I3SOCK DISPLAY DBUS_SESSION_BUS_ADDRESS XDG_RUNTIME_DIR

fresh() {   # a new throwaway HOME with the stubs in place
    H=$(tmpd)
    export HOME=$H XDG_CONFIG_HOME=$H/.config XDG_STATE_HOME=$H/.local/state XDG_DATA_HOME=$H/.local/share
    unset XDG_CACHE_HOME   # never the caller's cache: the default, under the HOME each test sets
    mkdir -p "$H/.local/bin" "$H/.config/spark"
    printf '#!/bin/sh\necho starship 0.0-stub\n' > "$H/.local/bin/starship"   # the prompt row finds it
    chmod +x "$H/.local/bin/starship"
    printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/lpstat"   # no native print service is reached by the suite
    chmod +x "$H/.local/bin/lpstat"
    # Native audio clients can block on the real host. Tests replace these
    # refusals with their own working backends where audio is exercised.
    for client in amixer wpctl pactl; do
        printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/$client"
        chmod +x "$H/.local/bin/$client"
    done
    printf 'ID=fixture\n' > "$H/os-release"
    export SPARK_OS_RELEASE=$H/os-release
    # the root files land under a throwaway root, never in this
    # machine's /etc; systemctl is whatever PATH has (a stub)
    export SPARK_SHELL_ROOT=$H/root
    # the open terminals theme repaints: plain files under $H/pts, never
    # this machine's /dev/pts (a test must not repaint the terminal it runs in)
    export SPARK_SHELL_PTS_DIR=$H/pts
    # Device discovery must not reach the host's display or sound buses.
    export SPARK_SHELL_DEV=$H/dev
    mkdir -p "$H/dev"
    # no release to fetch the dialog from: on a tag the checkout is at its release, and a download
    # would race the release job (the dialog's own tests point it at a file:// folder)
    export SPARK_SHELL_DIALOG_URL=none
    # nor the model of the dialog's search: 310 MB, and a spark found on the developer's PATH would ask for it
    # (section 22b points it at a file:// one)
    export SPARK_SHELL_SEMANTIC_URL=none
    # no release to fetch the font from either (a test points it at a fixture zip), and
    # fontconfig a stub: it finds Monaspace Neon in the throwaway fonts, or where $H/fc-neon
    # says a package put it; fc-cache logs
    export SPARK_SHELL_FONT_URL=none
    printf '#!/bin/sh\ncase "$*" in *"Monaspace Neon"*) [ ! -f "%s/.local/share/fonts/monaspace-neon/MonaspaceNeon-Regular.otf" ] && [ ! -e "%s/fc-neon" ] || echo "Monaspace Neon" ;; esac\n' "$H" "$H" > "$H/.local/bin/fc-list"
    printf '#!/bin/sh\necho "fc-cache $*" >> "%s/fc.log"\n' "$H" > "$H/.local/bin/fc-cache"
    chmod +x "$H/.local/bin/fc-list" "$H/.local/bin/fc-cache"
    # the text the sections were written at, the default before v0.89: a FONT the config
    # lacks is the environment's, so their sizes and faces hold; the font's own section
    # unsets it and proves the default, Monaspace Neon at 11
    export FONT='DejaVu Sans Mono:size=12'
    # the tty is a stub: TEST_TTY=/dev/ttyN is a console, unset is ssh;
    # sway's runtime dir is a login manager's (the desktop tests unset it)
    printf '#!/bin/sh\n[ -n "${TEST_TTY:-}" ] || { echo "not a tty"; exit 1; }\necho "$TEST_TTY"\n' > "$H/.local/bin/tty"
    chmod +x "$H/.local/bin/tty"
    # sway's waits for a window end at the stubs' own events; where the system has no timeout (macOS), the command alone
    [ -n "$sys_timeout" ] || { printf '#!/bin/sh\nshift; exec "$@"\n' > "$H/.local/bin/timeout"; chmod +x "$H/.local/bin/timeout"; }
    export XDG_RUNTIME_DIR=$H/run
    PATH=$H/.local/bin:$PATH
}

without_tools() {   # a PATH with explicit absences, even on a desktop host
    "$fixture_python" - "$@" <<'PYTHON'
import os, pathlib, sys
out = pathlib.Path(sys.argv[1])
out.mkdir()
exclude = set(sys.argv[2:])
for folder in os.environ["PATH"].split(os.pathsep):
    try:
        paths = pathlib.Path(folder).iterdir()
        for path in paths:
            dest = out / path.name
            if path.name not in exclude and path.is_file() and os.access(path, os.X_OK) and not dest.exists():
                dest.symlink_to(path.absolute())
    except (FileNotFoundError, NotADirectoryError):
        continue
PYTHON
}

theme_fixture() {   # theme_fixture ACCENT [MUTED] -- a theme.env as today's spark writes it (THEME_BTOP too) over the VGA sixteen
    {
        printf 'THEME_BG=#000000\nTHEME_FG=#aaaaaa\nTHEME_ACCENT=%s\nTHEME_MUTED=%s\nTHEME_BTOP=TTY\n' "$1" "${2:-#555555}"
        i=0
        for c in 000000 aa0000 00aa00 aa5500 0000aa aa00aa 00aaaa aaaaaa 555555 ff5555 55ff55 ffff55 5555ff ff55ff 55ffff ffffff; do
            printf 'THEME_ANSI_%d=#%s\n' "$i" "$c"; i=$((i + 1))
        done
    } > "$HOME/.config/spark/theme.env"
}
RENDERS=".tmux.conf .config/btop/btop.conf .config/starship.toml .config/spark-shell/sgr.sh"

SH=$REPO/spark-shell
SRC=$(mktemp); cat "$SH" "$REPO"/src/*.sh > "$SRC"   # the program's text, the entry and its modules, for the checks that read the source
sys=$(dirname "$(command -v uname)"):/usr/bin:/bin   # the system's tools alone; a uname put first on PATH (the Linux halves on a Mac) stays

# --- the parts --------------------------------------------------------------
# sh test/shell_test.sh              every section, in a row
# sh test/shell_test.sh --part NAME  one part, the sections it holds alone
# sh test/shell_test.sh --parallel   every part at once, a process each, the
#                                     logs printed whole as they end: CI's way
# The parts are cut by time (section 19 in two, at the login screen), so the
# longest takes a quarter of the whole; a section's state carries only to
# the next section of the same part.
PARTS="base console screen providers theme"
sections_of() {   # sections_of PART -- the sections a part holds
    case $1 in
        base) echo "1 2 3 4 5 8 9 10 13 14 15 16 17 18" ;;
        console) echo "19" ;;
        screen) echo "19b" ;;
        providers) echo "20 21 22 22b 23" ;;
        theme) echo "24 25" ;;
        *) return 1 ;;
    esac
}
case ${1:-} in
    '') SECTIONS=all ;;
    --part)
        SECTIONS=$(sections_of "${2:-}") || { echo "shell_test: no part named '${2:-}' (the parts: $PARTS)" >&2; exit 2; } ;;
    --parallel)
        logs=$(mktemp -d); pids=
        for p in $PARTS; do
            sh "$0" --part "$p" > "$logs/$p.log" 2>&1 &
            pids="$pids $!"
        done
        # stopped before the parts end (CI's timeout): each part's last lines, so a hang says where it is
        trap 'for p in $PARTS; do printf "== %s, cut short\n" "$p"; tail -n 30 "$logs/$p.log"; done
            if [ -d /proc/1 ]; then echo "== what runs"; for q in /proc/[0-9]*; do [ -r "$q/cmdline" ] || continue; printf "%s %s: " "${q#/proc/}" "$(awk "/^PPid/ { print \$2 }" "$q/status" 2>/dev/null)"; tr "\000" " " < "$q/cmdline" | cut -c1-160; echo; done; fi
            kill $pids 2>/dev/null; exit 1' TERM INT
        rc=0
        for pid in $pids; do wait "$pid" || rc=1; done
        for p in $PARTS; do printf '== %s\n' "$p"; cat "$logs/$p.log"; done
        awk -F'[ ,]+' '/^shell_test: [0-9]+ ok, [0-9]+ failed$/ { ok += $2; bad += $4; n++ }
             END { printf "shell_test: %d ok, %d failed (%d parts side by side)\n", ok, bad, n }' "$logs"/*.log
        rm -rf "$logs"
        exit $rc ;;
    *) echo "usage: sh test/shell_test.sh [--part NAME | --parallel]" >&2; exit 2 ;;
esac
want() {   # want SECTION -- whether this run holds the section
    [ "$SECTIONS" = all ] || case " $SECTIONS " in *" $1 "*) ;; *) return 1 ;; esac
}

# --- the helpers the sections share, defined before any part runs --------
# (each was defined in the section that first needed it; a part that
# skips that section still needs them, so they stand here)
esc=$(printf '\033')
me=$(id -un)
noon_tz() {   # -> a zone whose clock reads about noon now, for a test of today and tomorrow: one never runs across midnight (a CI run at 23:56 UTC failed three)
    # an IANA zone, as the reminders verify theirs (Etc/GMT-N is N hours ahead of UTC); none where the zone files are not there
    _nh=$(TZ=UTC date +%H); _nh=${_nh#0}; _nd=$((12 - _nh))
    if [ "$_nd" -gt 0 ]; then _nz=Etc/GMT-$_nd; elif [ "$_nd" -lt 0 ]; then _nz=Etc/GMT+$((-_nd)); else _nz=Etc/GMT; fi
    if [ -f "/usr/share/zoneinfo/$_nz" ]; then echo "$_nz"; fi
}
py3=$(command -v python3 || :)   # the real one (console_stubs put a fake in $H/lx); a container without it: the stub makes no socket, and the start waits its 5 s
desktop_stubs() {
    for t in sway swaymsg foot; do
        printf '#!/bin/sh\necho "%s-stub $*" >&2\n' "$t" > "$H/.local/bin/$t"; chmod +x "$H/.local/bin/$t"
    done
}

layout_stubs() {   # after desktop_stubs: its swaymsg is replaced
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}"; printf '%s\n' "$@" > "${XDG_STATE_HOME:-$HOME/.local/state}/spark.argv"
if [ -e "$HOME/answer.json" ]; then cat "$HOME/answer.json"   # a test's own answer
elif [ -e "$HOME/two-screens" ]; then cat <<'JSON'
{"why": "photo work in gimp at the left, the feed at the right, notes beside the photo",
 "main": {"app": "gimp-3.0", "args": "", "width": 70, "screen": "left"},
 "side": [{"app": "firefox", "args": "https://instagram.com", "screen": "right"}, {"app": "micro", "args": ""}]}
JSON
else cat <<'JSON'
{"why": "photo work in gimp with the two feeds beside it and a notes file",
 "main": {"app": "gimp-3.0", "args": "", "width": 70},
 "side": [{"app": "firefox", "args": "https://instagram.com"}, {"app": "firefox", "args": "https://x.com"},
          {"app": "micro", "args": ""}, {"app": "player", "args": ""}, {"app": "ghostapp", "args": ""}]}
JSON
fi
EOF
    # the outputs carry make, model and serial like sway's (never to reach the model); two when $HOME/two-screens exists
    cat > "$H/.local/bin/swaymsg" <<'EOF'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/swaymsg.log; mkdir -p "$(dirname "$log")"
if [ "${1:-}" = -r ] && [ "${2:-}" = -t ] && [ "${3:-}" != subscribe ]; then shift; fi
case ${1:-} in
    -r) # -r -t subscribe -m EVENTS: sway's tick to a new subscriber at once, then a window's new event once an exec comes; with $HOME/no-new-window, the tick alone
        n=$(grep -c '^exec' "$log" 2>/dev/null) || :   # counted before the tick: the exec may follow it at once
        echo '{ "first": true, "payload": "" }'
        [ ! -e "$HOME/no-new-window" ] || exit 0
        while c=$(grep -c '^exec' "$log" 2>/dev/null) || :; [ "${c:-0}" -le "${n:-0}" ]; do sleep 0.05; done   # a log not made yet counts none
        echo '{ "change": "new", "container": { "id": 1000 } }' ;;
    -t) case $2 in
            get_version) echo '{"human_readable":"sway-stub"}' ;;
            get_outputs) o1='{"name":"DP-1","active":true,"make":"Fakemake","model":"Fakemodel","serial":"SN0001","rect":{"x":0,"y":0},"current_mode":{"width":2560,"height":1440}}'
                o2='{"name":"HDMI-A-1","active":true,"make":"Fakemake","model":"Fakemodel","serial":"SN0002","rect":{"x":2560,"y":0},"current_mode":{"width":1920,"height":1080}}'
                if [ -e "$HOME/two-screens" ]; then echo "[$o2,$o1]"; else echo "[$o1]"; fi ;;
            get_workspaces) echo '[{"num":1},{"num":2}]' ;;
            get_tree) echo tree >> "${log%.log}.trees"   # each count of the windows, for the tests that say none is polled
                ws=$(grep -n '^workspace number' "$log" 2>/dev/null | tail -1); from=${ws%%:*}; num=${ws##* }; [ -n "$from" ] || { from=0; num=3; }
                n=$({ if [ "$from" -gt 0 ]; then sed "1,${from}d" "$log"; else cat "$log"; fi; } 2>/dev/null | grep '^exec' | grep -vc 'exec gone' || :); [ -n "$n" ] || n=0; i=0
                printf '{"type":"root","nodes":[{"type":"output","name":"DP-1","nodes":[{"type":"workspace","name":"%s","num":%s,"focused":true,"fullscreen_mode":0,"nodes":[' "$num" "$num"
                # with $HOME/fullscreen: a fullscreen window (77) on the workspace, and the panel floating under it with the pid the test wrote
                [ ! -e "$HOME/aerc" ] || { printf '{"type":"con","id":79,"pid":300,"app_id":"foot","name":"aerc"}'; { [ -e "$HOME/fullscreen" ] || [ "$n" -gt 0 ]; } && printf ','; }   # a terminal running aerc
                [ ! -e "$HOME/fullscreen" ] || { printf '{"type":"con","id":77,"pid":200,"app_id":"firefox","fullscreen_mode":1}'; [ "$n" -eq 0 ] || printf ','; }
                while [ "$i" -lt "$n" ]; do [ "$i" -eq 0 ] || printf ','; printf '{"type":"con","pid":%d,"id":%d}' $((100 + i)) $((1000 + i)); i=$((i + 1)); done
                printf ']'
                [ ! -e "$HOME/fullscreen" ] || printf ',"floating_nodes":[{"type":"floating_con","id":78,"app_id":"spark-dialog","pid":%s,"fullscreen_mode":0}]' "$(cat "$HOME/panel.ppid" 2>/dev/null || echo 1)"
                echo '}]}]}' ;;
        esac ;;
    --) shift; echo "$*" >> "$log"
        case "$*" in '[con_id=77] kill') rm -f "$HOME/fullscreen" ;; '[con_id=79] kill') rm -f "$HOME/aerc" ;; esac ;;
esac
EOF
    for t in gimp-3.0 firefox micro gone player; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; done   # gone: an app that opens no window
    # the application the system opens text with, as xdg-mime answers it (#115): micro's entry; $HOME/text-app names another, $HOME/no-text-app none
    printf '#!/bin/sh\n[ "$*" = "query default text/plain" ] || exit 0\n[ ! -e "$HOME/no-text-app" ] || exit 0\nif [ -e "$HOME/text-app" ]; then cat "$HOME/text-app"; else echo micro.desktop; fi\n' > "$H/.local/bin/xdg-mime"; chmod +x "$H/.local/bin/xdg-mime"
    chmod +x "$H/.local/bin/spark" "$H/.local/bin/swaymsg" "$H/.local/bin/gimp-3.0" "$H/.local/bin/firefox" "$H/.local/bin/micro" "$H/.local/bin/gone" "$H/.local/bin/player"
    apps=$XDG_DATA_HOME/applications; mkdir -p "$apps" "$H/share"
    export XDG_DATA_DIRS=$H/share
    printf '[Desktop Entry]\nName=GNU Image Manipulation Program\nComment=Create images and edit photographs\nExec=gimp-3.0 %%U\nTerminal=false\nType=Application\n' > "$apps/gimp.desktop"
    printf '[Desktop Entry]\nName=Firefox\nGenericName=Web Browser\nExec=firefox %%u\nType=Application\n' > "$apps/firefox.desktop"
    printf '[Desktop Entry]\nName=Micro\nExec=micro %%F\nTerminal=true\nType=Application\n' > "$apps/micro.desktop"
    printf '[Desktop Entry]\nName=Hidden\nExec=hidden\nNoDisplay=true\nType=Application\n' > "$apps/hidden.desktop"
    printf '[Desktop Entry]\nName=Gone\nComment=Ends at once, no window\nExec=gone\nType=Application\n' > "$apps/gone.desktop"
    # an entry with its own flags and a file field (mpv's shape): opened as the entry says, the field dropped without args
    printf '[Desktop Entry]\nName=Player\nComment=Play music\nExec=/usr/bin/player --idle -- %%U\nType=Application\n' > "$apps/player.desktop"
}

sbom_stubs() {
    cat > "$H/.local/bin/pacman" <<'EOF'
#!/bin/sh
case ${1:-} in
    -Qi) printf 'Name            : gimp\nVersion         : 3.0.4-1\nLicenses        : GPL3\nDescription     : GNU Image Manipulation Program\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : reader\nVersion         : 1.0-1\nLicenses        : MIT\nDescription     : Text-based Web browser\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : libfoo\nVersion         : 2.1-3\nLicenses        : LGPL2.1\nDescription     : A library other packages need\nInstall Reason  : Installed as a dependency for another package\n\n' ;;
    -Ql) printf 'gimp %s/applications/gimp.desktop\ngimp /usr/bin/gimp-3.0\nreader /usr/bin/reader\nlibfoo /usr/lib/libfoo.so\n' "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
esac
EOF
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"
    # fzf: its rows and its arguments logged; it answers the rows in $HOME/fzf.pick, or leaves (Esc, 130)
    printf '#!/bin/sh\ncat > "$HOME/fzf.rows"; printf "%%s\\n" "$@" > "$HOME/fzf.args"\n[ -f "$HOME/fzf.pick" ] || exit 130\ncat "$HOME/fzf.pick"\n' > "$H/.local/bin/fzf"
    chmod +x "$H/.local/bin/pacman" "$H/.local/bin/reader" "$H/.local/bin/fzf"
    printf 'ID=arch\n' > "$H/os-arch"
}

rooms_stubs() {
    cat > "$H/.local/bin/tmux" <<'EOF'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/tmux.log; mkdir -p "$(dirname "$log")"
printf '%s\n' "$*" >> "$log"
case ${1:-} in has-session) [ -e "$HOME/tmux.has" ] ;; esac
EOF
    for t in newsboat w3m aerc; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; done
    chmod +x "$H/.local/bin/tmux" "$H/.local/bin/newsboat" "$H/.local/bin/w3m" "$H/.local/bin/aerc"
}

console_stubs() {   # console_stubs Linux|Darwin
    mkdir -p "$H/lx" "$H/root/sys/module/vt/parameters"
    # Debian console fixtures exercise on without reaching the host package manager.
    printf '#!/bin/sh\necho "install ok installed"\n' > "$H/lx/dpkg-query"
    printf '#!/bin/sh\nif [ "$1" = -s ]; then echo %s; else exec %s "$@"; fi\n' "$1" "$(command -v uname)" > "$H/lx/uname"
    vga_red='0,170,0,170,0,170,0,170,85,255,85,255,85,255,85,255'
    printf '%s\n' "$vga_red" > "$H/root/sys/module/vt/parameters/default_red"
    cat > "$H/lx/setvtrgb" <<EOF
#!/bin/sh
echo "setvtrgb \$*" >> "$H/log"
if [ "\$1" = vga ]; then echo '$vga_red'; else head -1 "\$1"; fi > "$H/root/sys/module/vt/parameters/default_red"
EOF
    for t in setfont setupcon; do printf '#!/bin/sh\necho "%s $*" >> "%s/log"\n' "$t" "$H" > "$H/lx/$t"; done
    cat > "$H/lx/update-grub" <<EOF
#!/bin/sh
echo "update-grub" >> "$H/log"
[ ! -e "$H/fail" ] || exit 1
mkdir -p "$H/root/boot/grub"
if [ -e "$H/root/etc/default/grub.d/zz-spark-shell-quiet.cfg" ] || grep -q 'spark-shell-quiet' "$H/root/etc/default/grub" 2>/dev/null; then
    echo 'linux /vmlinuz quiet loglevel=3' > "$H/root/boot/grub/grub.cfg"
else echo 'linux /vmlinuz' > "$H/root/boot/grub/grub.cfg"; fi
EOF
    printf '#!/bin/sh\necho "mkinitcpio $*" >> "%s/log"\n[ ! -e "%s/fail" ]\n' "$H" "$H" > "$H/lx/mkinitcpio"
    # the helper: has-profile fails once $H/gone is there, remove once $H/stuck is
    printf '#!/bin/sh\ncase $1 in */lib/reminders.py) exec "%s" "$@" ;; esac\necho "python3 $*" >> "%s/log"\ncase $2 in has-profile) [ ! -e "%s/gone" ] ;; remove) [ ! -e "%s/stuck" ] ;; esac\n' "$fixture_python" "$H" "$H" "$H" > "$H/lx/python3"
    cat > "$H/lx/systemctl" <<'EOF'
#!/bin/sh
st=${SPARK_SHELL_ROOT:-$HOME/root}/units
mkdir -p "$st"
echo "systemctl $*" >> "$HOME/log"
case $1 in
    enable) touch "$st/$2" ;;
    disable) rm -f "$st/$2" ;;
    is-enabled) [ -e "$st/$2" ] ;;
    is-active) [ -e "$st/active-$2" ] ;;
esac
EOF
    chmod +x "$H/lx"/*
    : > "$H/log"
}

L() { PATH=$H/lx:$PATH sh "$SH" "$@"; }   # spark-shell as the uname stub says

palette_fixture() {   # palette_fixture NAME ACCENT -- a palette of yours, gruvbox's sixteen
    mkdir -p "$HOME/.config/spark-shell/themes"
    {
        printf '# a test palette\nTHEME_BG=#282828\nTHEME_FG=#ebdbb2\nTHEME_ACCENT=%s\nTHEME_MUTED=#928374\n' "$2"
        i=0
        for c in 282828 cc241d 98971a d79921 458588 b16286 689d6a a89984 928374 fb4934 b8bb26 fabd2f 83a598 d3869b 8ec07c ebdbb2; do
            printf 'THEME_ANSI_%d=#%s\n' "$i" "$c"; i=$((i + 1))
        done
    } > "$HOME/.config/spark-shell/themes/$1.env"
}

psf2() { printf '\162\265\112\206\0\0\0\0\040\0\0\0\0\0\0\0\0\1\0\0\100\0\0\0\040\0\0\0\020\0\0\0' | gzip -c > "$1"; }   # a 16x32 PSF2 header, gzipped

psf1() { printf '\066\004\000\020' > "$1"; }                                                                          # an 8x16 PSF1 header

void_desktop() {   # void_desktop -- a fresh Void root: runit, seatd's service dir, /var/service, /etc/group
    fresh
    console_stubs Linux
    desktop_stubs
    printf 'NAME="Void"\nID="void"\n' > "$H/os-release"
    # Membership takes effect only at the fixture's next login. The host may
    # already be in _seatd; keep that session state outside this test.
    printf '#!/bin/sh\ncase "$*" in -Gn|-nG) echo users ;; *) exec "%s" "$@" ;; esac\n' "$(command -v id)" > "$H/lx/id"
    chmod +x "$H/lx/id"
    mkdir -p "$H/root/etc/runit" "$H/root/etc/sv/seatd" "$H/root/var/service"
    printf 'root:x:0:\nwheel:x:4:%s\n_seatd:x:990:\n' "$(id -un)" > "$H/root/etc/group"
    printf '#!/bin/sh\nexit 0\n' > "$H/lx/xbps-query"
    cat > "$H/lx/usermod" <<'EOF'
#!/bin/sh
echo "usermod $*" >> "$HOME/log"
[ "$1" = -aG ] || exit 2
awk -F: -v OFS=: -v g="$2" -v u="$3" '$1 == g { $4 = ($4 == "" ? u : $4 "," u) } { print }' "$SPARK_SHELL_ROOT/etc/group" > "$HOME/group.new" && cat "$HOME/group.new" > "$SPARK_SHELL_ROOT/etc/group"
EOF
    cat > "$H/lx/gpasswd" <<'EOF'
#!/bin/sh
echo "gpasswd $*" >> "$HOME/log"
[ "$1" = -d ] || exit 2
awk -F: -v OFS=: -v u="$2" -v g="$3" '$1 == g { n = split($4, m, ","); s = ""; for (i = 1; i <= n; i++) if (m[i] != u) s = (s == "" ? m[i] : s "," m[i]); $4 = s } { print }' "$SPARK_SHELL_ROOT/etc/group" > "$HOME/group.new" && cat "$HOME/group.new" > "$SPARK_SHELL_ROOT/etc/group"
EOF
    printf '#!/bin/sh\n[ -e "%s/sway-running" ]\n' "$H" > "$H/lx/pgrep"
    chmod +x "$H/lx"/*
}

void_sound() {   # void_sound -- a Void root with PipeWire installed, an audio group, the bar's old ALSA file
    void_desktop
    printf 'audio:x:12:\n' >> "$H/root/etc/group"
    mkdir -p "$H/root/usr/share/alsa/alsa.conf.d"; for f in 50-pipewire.conf 99-pipewire-default.conf; do : > "$H/root/usr/share/alsa/alsa.conf.d/$f"; done
    printf '#!/bin/sh\nexit 0\n' > "$H/lx/pipewire"; chmod +x "$H/lx/pipewire"
    share=/usr/share/alsa/alsa.conf.d; conf=$H/root/etc/alsa/conf.d
    mkdir -p "$HOME/.config/alsa"; printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.!card HDMI\ndefaults.ctl.!card HDMI\n' > "$HOME/.config/alsa/asoundrc"
}

void_svc() {   # void_svc -- void_sound, spark's supervisor dir, PipeWire's two examples; stubs: pipewire-pulse, wpctl (answers while ~/wp-up is there), sv (a log; status from ~/sv-status)
    void_sound
    mkdir -p "$HOME/.config/spark/sv/spark-check" "$H/root/usr/share/examples/wireplumber" "$H/root/usr/share/examples/pipewire" "$H/tmp"
    printf 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]\n' > "$H/root/usr/share/examples/wireplumber/10-wireplumber.conf"
    printf 'context.exec = [ { path = "/usr/bin/pipewire" args = "-c pipewire-pulse.conf" } ]\n' > "$H/root/usr/share/examples/pipewire/20-pipewire-pulse.conf"
    printf '#!/bin/sh\nexit 0\n' > "$H/lx/pipewire-pulse"
    printf '#!/bin/sh\n[ -e "$HOME/wp-up" ]\n' > "$H/lx/wpctl"
    cat > "$H/lx/sv" <<'EOF'
#!/bin/sh
echo "sv $*" >> "$HOME/sv.log"
[ "$3" != force-stop ] || [ ! -e "$4/down" ] || echo "down: there" >> "$HOME/sv.log"
[ "$1" != status ] || { [ -s "$HOME/sv-status" ] && cat "$HOME/sv-status"; }
EOF
    chmod +x "$H/lx/pipewire-pulse" "$H/lx/wpctl" "$H/lx/sv"
    svc=$HOME/.config/spark/sv/spark-shell-sound; pwc=$HOME/.config/pipewire/pipewire.conf.d; ex=$H/root/usr/share/examples
}

SV() { env -u XDG_RUNTIME_DIR TMPDIR="$H/tmp" PATH="$H/lx:$PATH" sh "$SH" "$@"; }   # spark-shell from a login with no runtime dir (ssh, a console on Void)

svrun() { rm -f "$HOME/wp.n" "$HOME/pw.ran" "$HOME/chpst.ran"; echo "$1" > "$HOME/wp.answers"; ( cd "$svc" && exec env -u XDG_RUNTIME_DIR TMPDIR="$H/rt" PATH="$rb:$sys" sh ./run 2>&1 ); }   # svrun ANSWERS -- the service's run, a wpctl that answers ANSWERS times

waitfor() { _i=0; while [ "$_i" -lt 10 ] && ! grep -qF "$1" "$2" 2>/dev/null; do sleep 1; _i=$((_i + 1)); done; }   # waitfor TEXT FILE -- up to 10 s for a line to show

fin() { rm -f "$HOME/sleep.ran" "$svc/pipewire.pid"; ( cd "$svc" && PATH="$rb:$sys" sh ./finish "$@" ); cat "$HOME/sleep.ran" 2>/dev/null || :; }   # fin CODE SIGNAL -> the sleep it took, if any (no pid kept: a stub's pid is long gone, and may be another's now)

old_greetd() {   # old_greetd [ORIG] -- a root as v0.41 left it; ORIG: a config.toml of the package's kept as .spark-orig
    fresh
    console_stubs Linux
    printf 'ID=debian\n' > "$H/os-release"
    printf '#!/bin/sh\necho "install ok installed"\n' > "$H/lx/dpkg-query"; chmod +x "$H/lx/dpkg-query"
    mkdir -p "$H/root/run/systemd/system" "$H/root/etc/greetd/spark-shell" "$H/root/etc/systemd/system/greetd.service.d" "$H/root/units"
    printf '# rendered by spark-shell from templates/etc/greetd/config.toml\n[terminal]\nvt = 1\n' > "$H/root/etc/greetd/config.toml"
    [ -z "${1:-}" ] || printf '[terminal]\nvt = 1\n# agreety\n' > "$H/root/etc/greetd/config.toml.spark-orig"
    for f in desktop console; do printf '# rendered by spark-shell\n' > "$H/root/etc/greetd/spark-shell/$f.desktop"; done
    printf '# rendered by spark-shell\n[Unit]\nAfter=spark-shell-console.service\n' > "$H/root/etc/systemd/system/greetd.service.d/spark-shell.conf"
    : > "$H/root/units/greetd.service"; : > "$H/log"
}

old_gone() {   # old_gone -- spark-shell's greetd files gone, getty@tty1 on, greetd off, nothing stopped
    [ ! -e "$H/root/etc/greetd/spark-shell" ] && [ ! -e "$H/root/etc/systemd/system/greetd.service.d" ] \
        && [ -e "$H/root/units/getty@tty1.service" ] && [ ! -e "$H/root/units/greetd.service" ] \
        && grep -qx 'systemctl enable getty@tty1.service' "$H/log" && grep -qx 'systemctl disable greetd.service' "$H/log" \
        && ! grep -Eq '^systemctl (start|stop|restart|kill)' "$H/log"
}

screen_mcp() {
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}' "$1" | SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" provide display 2>/dev/null | jq -c 'select(.id == 2)'
}

NL() { SWAYSOCK=$H/sock EDITOR=true PATH="$H/lx:$PATH" sh "$SH" bar panel "$@" 2>&1; }

ago() { date -d "-$1 min" "+%Y%m%dT%H%M00" 2>/dev/null || date -v-"$1"M "+%Y%m%dT%H%M00"; }   # ago MINUTES -> a local time that long ago

ago_utc() { date -u -d "-$1 min" "+%Y%m%dT%H%M00Z" 2>/dev/null || date -u -v-"$1"M "+%Y%m%dT%H%M00Z"; }

mcp_rem() { printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$1\",\"arguments\":{\"name\":\"$2\"}}}" | SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" provide reminders 2>/dev/null | jq -c 'select(.id == 2) | .result'; }

snap() { ( cd "$H" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort ); }

A() { SPARK_SHELL_TEST_TTY=1 PATH=$H/lx:$PATH sh "$SH" "$@"; }   # spark-shell with an answer on stdin (the assignments on sh, never kept)

bar_fixture() {   # a wire up, wifi up at 49/70, a bluetooth controller with a device, a battery at 80, two ALSA cards (0 plays and captures, 1 plays)
    S=$H/sys; P=$H/proc; export SPARK_SHELL_SYS=$S SPARK_SHELL_PROC=$P
    mkdir -p "$S/class/net/eth0" "$S/class/net/wlan0/wireless" "$S/class/net/lo" "$S/class/bluetooth/hci0" "$S/class/power_supply/BAT0" "$P/net" "$P/asound/card0/pcm0p/sub0" "$P/asound/card0/pcm0c/sub0" "$P/asound/card1/pcm0p/sub0"
    : > "$S/class/net/eth0/device"; echo 1 > "$S/class/net/eth0/type"; echo 1 > "$S/class/net/eth0/carrier"; echo up > "$S/class/net/eth0/operstate"; echo 1000 > "$S/class/net/eth0/speed"
    : > "$S/class/net/wlan0/device"; echo 1 > "$S/class/net/wlan0/type"; echo up > "$S/class/net/wlan0/operstate"
    echo 772 > "$S/class/net/lo/type"
    echo Battery > "$S/class/power_supply/BAT0/type"; echo 80 > "$S/class/power_supply/BAT0/capacity"; echo Discharging > "$S/class/power_supply/BAT0/status"
    echo 40000000 > "$S/class/power_supply/BAT0/energy_now"; echo 50000000 > "$S/class/power_supply/BAT0/energy_full"; echo 60000000 > "$S/class/power_supply/BAT0/energy_full_design"
    echo 20000000 > "$S/class/power_supply/BAT0/power_now"; echo 123 > "$S/class/power_supply/BAT0/cycle_count"
    printf 'Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE\n face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22\n wlan0: 0000   49.  -61.  -256        0      0      0      0      0        0\n' > "$P/net/wireless"
    printf ' 0 [Jabra          ]: USB-Audio - Jabra SPEAK 410 USB\n                      Jabra SPEAK 410 USB at usb-0000:00:14.0-2, full speed\n 1 [HDMI           ]: HDA-Intel - HD-Audio Generic\n                      HD-Audio Generic at 0xdc5c8000 irq 104\n' > "$P/asound/cards"
    for s in card0/pcm0p card0/pcm0c card1/pcm0p; do echo closed > "$P/asound/$s/sub0/status"; done
    cat > "$H/.local/bin/ip" <<'STUB'
#!/bin/sh
case "$*" in
    *route*) echo 'default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.10 metric 100' ;;
    *"dev eth0"*) echo '2: eth0    inet 192.0.2.10/24 brd 192.0.2.255 scope global eth0' ;;
    *"dev wlan0"*) echo '3: wlan0    inet 192.0.2.20/24 brd 192.0.2.255 scope global wlan0' ;;
esac
STUB
    printf '#!/bin/sh\necho "boolean true"\n' > "$H/.local/bin/dbus-send"
    chmod +x "$H/.local/bin/dbus-send"
    cat > "$H/.local/bin/bluetoothctl" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/bt.log; mkdir -p "$(dirname "$log")"
case "$*" in
    show) printf 'Controller 00:11:22:33:44:55 (public)\n\tPowered: yes\n' ;;
    "devices Connected") [ -e "$HOME/bt-none" ] || echo 'Device 00:25:D1:4A:C2:AA MAJOR V' ;;
    "devices Paired") echo 'Device 00:25:D1:4A:C2:AA MAJOR V' ;;
    devices) printf 'Device 00:25:D1:4A:C2:AA MAJOR V\nDevice 11:22:33:44:55:66 Buds\n' ;;
    "connect "*) echo "$*" >> "$log"; echo 'Connection successful' ;;
    "disconnect "*) echo "$*" >> "$log"; echo 'Successful disconnected' ;;
    *) echo "$*" >> "$log" ;;
esac
STUB
    cat > "$H/.local/bin/wpa_cli" <<'STUB'
#!/bin/sh
[ -n "${HOME:-}" ] || { HOME=${XDG_STATE_HOME%/.local/state}; touch "$HOME/wpa.nohome"; }   # run with HOME unset, as spark-shell runs it for a password (no history file)
log=${XDG_STATE_HOME:-$HOME/.local/state}/wpa.log; mkdir -p "$(dirname "$log")"
printf '%s\n' "$*" >> "${log%.log}.argv"   # every call's arguments, apart: a password is never among them (#62)
[ "$1" != -i ] || shift 2
if [ $# -eq 0 ]; then while IFS= read -r line; do printf '%s\n' "$line" >> "$log"; echo OK; done; exit 0; fi   # interactive: a command a line on stdin
sel=$(cat "$HOME/wpa.sel" 2>/dev/null || echo 0)
name() { case $1 in 0) echo home ;; 1) echo old ;; 2) cat "$HOME/wpa.name2" 2>/dev/null || echo open ;; esac; }
case "$*" in
    status) [ -e "$HOME/wpa.down" ] || printf 'bssid=00:11:22:33:44:55\nssid=%s\nwpa_state=COMPLETED\n' "$(name "$sel")" ;;
    scan) echo OK ;;
    scan_results) printf 'bssid / frequency / signal level / flags / ssid\n00:11:22:33:44:55\t2412\t-55\t[WPA2-PSK-CCMP][ESS]\thome\n00:11:22:33:44:66\t2437\t-80\t[WPA2-PSK-CCMP][ESS]\tcafe\n00:11:22:33:44:77\t2462\t-70\t[ESS]\topen\n' ;;
    list_networks) printf 'network id / ssid / bssid / flags\n0\thome\tany\t[CURRENT]\n1\told\tany\t\n' ;;
    add_network) echo 2 ;;
    "select_network "*) echo "$*" >> "$log"; echo "$2" > "$HOME/wpa.sel"; rm -f "$HOME/wpa.down"; echo OK ;;
    disconnect) echo "$*" >> "$log"; touch "$HOME/wpa.down"; echo OK ;;
    *) echo "$*" >> "$log"; echo OK ;;
esac
STUB
    # The native key derivation has no password argument. Fixed key: the test
    # checks the wire format, not the native program's cryptography.
    printf '#!/bin/sh\nIFS= read -r pw || exit 1\nprintf "\\tpsk=%%s\\n" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' > "$H/.local/bin/wpa_passphrase"
    chmod +x "$H/.local/bin/wpa_passphrase"
    # NetworkManager and iwd, off unless a test turns one on ($HOME/nm.on, $HOME/iw.on): no machine's own nmcli or iwctl is reached from here
    cat > "$H/.local/bin/nmcli" <<'STUB'
#!/bin/sh
[ -e "$HOME/nm.on" ] || exit 1
log=$XDG_STATE_HOME/nmcli.log; printf '%s\n' "$*" >> "$log.argv"
case "$*" in
    "-t -f RUNNING general") echo running ;;
    "-g GENERAL.NM-MANAGED device show wlan0") echo yes ;;
    "-t -e yes -f SIGNAL,SECURITY,SSID dev wifi list --rescan auto") printf '80:WPA2:cafe\n' ;;
    "--ask dev wifi connect cafe ifname wlan0 hidden no"|"--ask dev wifi connect cafe ifname wlan0 hidden yes") IFS= read -r pw || exit 4; printf '%s\n' "$pw" >> "$log"; printf 'Password (802-11-wireless-security.psk): \n'
        [ "$pw" != wrong ] || { echo 'Error: Connection activation failed: Secrets were required, but not provided.'; exit 4; }
        echo "Device 'wlan0' successfully activated with 'f00d'." ;;
    *) exit 0 ;;
esac
STUB
    cat > "$H/.local/bin/iwctl" <<'STUB'
#!/bin/sh
[ -e "$HOME/iw.on" ] || exit 1
log=$XDG_STATE_HOME/iwctl.log; printf '%s\n' "$*" >> "$log.argv"
case "$*" in
    "station wlan0 show") printf '  Station: wlan0\n  State  disconnected\n' ;;
    "station wlan0 get-networks") printf '  Available networks\n----\n  Network name  Security  Signal\n----\n  cafe  psk  ****\n' ;;
    "station wlan0 connect cafe"|"station wlan0 connect-hidden cafe")
        python3 -c 'import os,sys,tty
assert sys.stdin.isatty()
tty.setraw(0)
os.write(1,b"Passphrase: ")
pw=b""
while True:
    chunk=os.read(0,256)
    if b"\n" in chunk:
        assert chunk == b"\n"
        break
    pw += chunk
    os.write(1,b"*"*len(chunk))
with open(sys.argv[1],"ab") as f: f.write(pw+b"\n")' "$log" ;;
    *) exit 0 ;;
esac
STUB
    printf '#!/bin/sh\nprintf "%%s | %%s\\n" "$*" "${SPARK_SHELL_PANEL_AT:-}" >> "${XDG_STATE_HOME:-$HOME/.local/state}/foot.log"\n' > "$H/.local/bin/foot"
    cat > "$H/.local/bin/amixer" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/amixer.log; mkdir -p "$(dirname "$log")"
[ "$1" != -q ] || shift
case "$*" in *scontrols) [ ! -e "$HOME/amixer-refuse" ] || exit 1 ;; esac   # amixer-refuse: ALSA cannot read its configuration
case "$*" in
    "-D default info") exit 1 ;;
    "-D bluealsa sget MAJOR V - A2DP") m=on; [ ! -e "$HOME/bmuted" ] || m=off; level=$(cat "$HOME/blevel" 2>/dev/null || echo 60); printf "Simple mixer control 'MAJOR V - A2DP',0\n  Limits: Playback 0 - 127\n  Front Left: Playback 76 [%s%%] [0.00dB] [%s]\n" "$level" "$m" ;;
    "-D bluealsa sget MAJOR V - SCO") m=on; [ ! -e "$HOME/bcmuted" ] || m=off; printf "Simple mixer control 'MAJOR V - SCO',0\n  Mono: Playback 10 [67%%] [-5.82dB] [on] Capture 9 [60%%] [0.00dB] [%s]\n" "$m" ;;
    "-D bluealsa sset "*) echo "$*" >> "$log"
        case "$*" in *"A2DP mute") touch "$HOME/bmuted" ;; *"A2DP unmute") rm -f "$HOME/bmuted" ;; *"SCO nocap") touch "$HOME/bcmuted" ;; *"SCO cap") rm -f "$HOME/bcmuted" ;; *"A2DP "*%) level=${5%%%}; echo "$level" > "$HOME/blevel" ;; esac ;;
    "-c 0 scontrols") printf "Simple mixer control 'Master',0\nSimple mixer control 'PCM',0\nSimple mixer control 'Capture',0\n" ;;
    "-c 1 scontrols") printf "Simple mixer control 'IEC958',0\n" ;;
    "-c 0 sget Master") m=on; [ ! -e "$HOME/muted" ] || m=off; level=$(cat "$HOME/level" 2>/dev/null || echo 40); printf "Simple mixer control 'Master',0\n  Front Left: Playback 26214 [%s%%] [%s]\n  Front Right: Playback 26214 [%s%%] [%s]\n" "$level" "$m" "$level" "$m" ;;
    "-c 0 sget Capture") m=on; [ ! -e "$HOME/cmuted" ] || m=off; level=$(cat "$HOME/clevel" 2>/dev/null || echo 50); printf "Simple mixer control 'Capture',0\n  Front Left: Capture 1000 [%s%%] [%s]\n" "$level" "$m" ;;
    "-c "*" sset "*) echo "$*" >> "$log"   # the switches, as amixer keeps them: mute/unmute/toggle for a playback switch, cap/nocap/toggle for a capture one
        case "$*" in
            "-c 0 sset Master mute") touch "$HOME/muted" ;; "-c 0 sset Master unmute") rm -f "$HOME/muted" ;;
            "-c 0 sset Master toggle") if [ -e "$HOME/muted" ]; then rm -f "$HOME/muted"; else touch "$HOME/muted"; fi ;;
            "-c 0 sset Capture nocap") touch "$HOME/cmuted" ;; "-c 0 sset Capture cap") rm -f "$HOME/cmuted" ;;
            "-c 0 sset Capture toggle") if [ -e "$HOME/cmuted" ]; then rm -f "$HOME/cmuted"; else touch "$HOME/cmuted"; fi ;;
            "-c 0 sset Capture mute"|"-c 0 sset Capture unmute") echo "amixer: Invalid command!" >&2; exit 1 ;;
            "-c 0 sset Master "*%) level=${5%%%}; echo "$level" > "$HOME/level" ;;
            "-c 0 sset Capture "*%) level=${5%%%}; echo "$level" > "$HOME/clevel" ;;
        esac ;;
esac
STUB
    cat > "$H/.local/bin/bluealsa-aplay" <<'STUB'
#!/bin/sh
# bluez-alsa's list, as 3.1 prints it: a headset that plays on A2DP and plays and listens on SCO (only while bt-audio is there)
[ "$1" = -L ] && [ -e "$HOME/bt-audio" ] || exit 0
printf 'bluealsa:SRV=org.bluealsa,DEV=00:25:D1:4A:C2:AA,PROFILE=sco\n    MAJOR V, trusted audio-headset, playback\n    SCO (CVSD): S16_LE 1 channel 8000 Hz\n'
printf 'bluealsa:SRV=org.bluealsa,DEV=00:25:D1:4A:C2:AA,PROFILE=sco\n    MAJOR V, trusted audio-headset, capture\n    SCO (CVSD): S16_LE 1 channel 8000 Hz\n'
printf 'bluealsa:SRV=org.bluealsa,DEV=00:25:D1:4A:C2:AA,PROFILE=a2dp\n    MAJOR V, trusted audio-headset, playback\n    A2DP (AAC): S16_LE 2 channels 48000 Hz\n'
printf 'bluealsa:SRV=org.bluealsa,DEV=bad;dev,PROFILE=a2dp\n    Crafted, trusted audio-headset, playback\n'
STUB
    chmod +x "$H/.local/bin/bluealsa-aplay"
    printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/wpctl"; cp "$H/.local/bin/wpctl" "$H/.local/bin/pactl"
    cp "$H/.local/bin/wpctl" "$H/.local/bin/tmux"   # a tmux that is not running (this machine may run one)
    chmod +x "$H/.local/bin/ip" "$H/.local/bin/bluetoothctl" "$H/.local/bin/amixer" "$H/.local/bin/wpctl" "$H/.local/bin/pactl" "$H/.local/bin/tmux" "$H/.local/bin/wpa_cli" "$H/.local/bin/foot" "$H/.local/bin/nmcli" "$H/.local/bin/iwctl"
}

count() { printf '%s' "$1" | LC_ALL=C grep -o "$2" | wc -l | tr -d ' '; }   # count TEXT GLYPH -> how many

rq() { jq -cn --argjson i "$1" --arg m "$2" --argjson p "${3:-null}" '{jsonrpc: "2.0", id: $i, method: $m} + (if $p == null then {} else {params: $p} end)'; }   # rq ID METHOD [PARAMS] -> one request

call() { rq "$1" tools/call "$(jq -cn --arg n "$2" --argjson a "${3:-"{}"}" '{name: $n, arguments: $a}')"; }   # call ID TOOL [ARGUMENTS] (a quoted {} default: /bin/sh leaves {\} as it is, and jq refused it)

mcp() { _s=$1; shift; printf '%s\n' "$@" | sh "$SH" provide "$_s" > "$H/mcp.out" 2> "$H/mcp.err"; }   # mcp SECTION LINE... -> $H/mcp.out, its stderr apart

ans() { jq -c --argjson i "$1" 'select(.id == $i)' "$H/mcp.out"; }   # ans ID -> that answer

fcall() { call "$1" "$2" "$(jq -cn --arg p "$3" '{path: $p}')"; }

b64u() { printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_'; }   # b64u TEXT -> the uri part the providers read (#169)

# --- 1. dry-run: rows, nothing touched -----------------------------------
if want 1; then
fresh
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc' && ok "dry-run: would link the rc files" || bad "dry-run rc rows" "$out"
printf '%s\n' "$out" | grep -q '^would  look' && ok "dry-run: would render the look" || bad "dry-run look rows" "$out"
printf '%s\n' "$out" | grep -q '^todo   packages' && ok "dry-run: an unknown family is a todo, not a guess" || bad "dry-run packages row" "$out"
printf '%s\n' "$out" | grep -Eq '^[0-9]+ to do$' && ok "dry-run ends with the count of its would rows" || bad "dry-run count" "$out"
[ "$(printf '%s\n' "$out" | grep -c '^would ')" = "$(printf '%s\n' "$out" | sed -n 's/^\([0-9]*\) to do$/\1/p')" ] && ok "dry-run: the count is the number of would rows" || bad "dry-run count exact" "$out"
printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "a font row acts with CONSOLE_FONT unset" "$out" || ok "dry-run: no font row acts (CONSOLE_FONT unset)"
[ ! -e "$HOME/.tmux.conf" ] && ok "dry-run touched nothing" || bad "dry-run wrote files"
rc=0; out=$(sh "$SH" on nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: nonsense is not known here (only desktop and login are)" ] && [ ! -e "$HOME/.tmux.conf" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "on NOUN: an unknown noun is refused in one sentence before anything runs (exit 1)" || bad "on nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" off nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell off: nonsense is not known here (only desktop and login are)" ] && ok "off NOUN: the same refusal" || bad "off nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" apply nonsense 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: nonsense is not known here (only desktop and login are)" ] && ok "apply NOUN: the spelling refuses like on" || bad "apply nonsense" "rc=$rc $out"
rc=0; out=$(sh "$SH" desktop on extra 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: desktop extra is not known here (only desktop and login are)" ] && [ ! -e "$HOME/.tmux.conf" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "desktop on EXTRA: the spelling refuses an extra word, nothing written" || bad "desktop on extra" "rc=$rc $out"
rc=0; out=$(sh "$SH" on "" 2>&1) || rc=$?
[ "$rc" -eq 1 ] && [ "$out" = "spark-shell on: an empty word is not known here (only desktop and login are)" ] && [ ! -e "$HOME/.tmux.conf" ] && ok "on '': an empty word is refused (every word byte-exact)" || bad "on empty" "rc=$rc $out"

fi

# --- 2. on: links, renders, idempotence, the plain look ------------------
if want 2; then
theme_fixture '#ff5555'
printf 'yours\n' > "$HOME/.bashrc"     # a pre-existing rc file of the user's
out=$(sh "$SH" on --yes)
case $(uname -s) in Darwin) rc1=.zshrc ;; *) rc1=.bashrc ;; esac
[ -L "$HOME/$rc1" ] && ok "on: $rc1 is spark-shell's link" || bad "rc link" "$(ls -la "$HOME")"
if [ "$rc1" = .bashrc ]; then
    [ -f "$HOME/.bashrc.bak" ] && grep -q yours "$HOME/.bashrc.bak" && ok "on: yours went to .bak" || bad "rc backup"
fi
[ -f "$HOME/.tmux.conf" ] && grep -q 'fg=colour9,bold' "$HOME/.tmux.conf" && ok "on: the accent is its palette slot (colour9)" || bad "tmux render" "$(grep -n color "$HOME/.tmux.conf" 2>&1 | head -3)"
grep -q '@[A-Z_0-9]*@' "$HOME/.tmux.conf" && bad "unrendered placeholder left" || ok "on: no placeholder left"
for rel in $RENDERS; do
    [ -f "$HOME/$rel" ] || { bad "on: $rel not rendered"; continue; }
    plain "$HOME/$rel" && ok "on: $rel is plain (no hex, ASCII)" || bad "on: $rel not plain" "$(grep -nE '#[0-9a-fA-F]{6}' "$HOME/$rel" | head -2)"
done
grep -q 'SPARK_ASCII=1 spark bar line' "$HOME/.tmux.conf" && ok "on: the bar is asked in ASCII" || bad "bar ascii"
grep -qF "status-right \"#[fg=colour9]#($REPO/spark-shell bar due)#[default]#(SPARK_ASCII=1 spark bar line)\"" "$HOME/.tmux.conf" && ok "on: tmux's line asks for a reminder due, in the accent, before spark's line" || bad "tmux due" "$(grep -n status-right "$HOME/.tmux.conf")"
[ ! -e "$HOME/.gitconfig" ] && ok "on: no .gitconfig written (git's identity is git's)" || bad "gitconfig written" "$(cat "$HOME/.gitconfig")"
grep -q ':Tc' "$HOME/.tmux.conf" && bad "tmux advertises truecolor for the look" || ok "on: no Tc override (the look is slots)"
grep -q 'terminal-features ",foot\*:RGB"' "$HOME/.tmux.conf" && ok "on: content passes through in RGB under foot" || bad "foot RGB passthrough" "$(grep -n terminal- "$HOME/.tmux.conf")"
grep -q 'client-attached' "$HOME/.tmux.conf" && bad "the console hook survives" || ok "on: no console hook (the slots need none)"
grep -q '^force_tty = True' "$HOME/.config/btop/btop.conf" && grep -q '^graph_symbol = "tty"' "$HOME/.config/btop/btop.conf" \
    && ok "on: btop in tty mode, tty graphs" || bad "btop tty mode"
[ ! -e "$HOME/.config/micro" ] && ok "on: no editor configured (nothing under ~/.config/micro)" || bad "micro touched" "$(ls -R "$HOME/.config/micro")"
grep -q "EDITOR\|editor = " "$REPO/template/linux/.bashrc" "$REPO/template/macos/.zshrc" && bad "an editor is still configured" || ok "templates: no EDITOR, no git editor"
grep -q 'style = "bold bright-red"' "$HOME/.config/starship.toml" && ok "on: starship's accent is its color word (bright-red)" || bad "starship accent"
sgr=$HOME/.config/spark-shell/sgr.sh
grep -q "SPARK_ACCENT_SGR='1;91'" "$sgr" && grep -q "SPARK_MUTED_SGR='90'" "$sgr" && grep -q "SPARK_WARN_SGR='1;31'" "$sgr" \
    && ok "on: sgr.sh exports the slots as SGR (accent 1;91, muted 90, warn 1;31)" || bad "sgr render" "$(cat "$sgr" 2>&1)"
grep -q '^# rendered by spark-shell' "$sgr" && ok "on: sgr.sh carries the marker" || bad "sgr marker"
# shellcheck disable=SC1090   # the render just written, on purpose
(. "$sgr" && [ "$SPARK_ACCENT_SGR" = '1;91' ] && [ "$SPARK_MUTED_SGR" = 90 ] && [ "$SPARK_WARN_SGR" = '1;31' ]) \
    && ok "on: sgr.sh sources in sh and sets the three" || bad "sgr source"
# shellcheck disable=SC1090   # the render just written, on purpose
(TERM=foot; . "$sgr" && [ "$SPARK_ACCENT_SGR" = '1;91' ] && [ -z "${STARSHIP_CONFIG:-}" ]) && grep -q '^case \${TERM:-}:no in$' "$sgr" \
    && ok "on, no desktop: sgr.sh keeps the sixteen in foot too (no foot.ini of spark-shell's sets the five slots)" || bad "sgr no desktop" "$(cat "$sgr")"
grep -q 'custom' "$HOME/.config/starship.toml" && bad "starship carries a segment of its own" || ok "on: starship's prompt is starship's alone (no spark segment)"
# the bar row asks spark itself: a stub that answers, one that fails, none at all
printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
ck=$(sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     bar          spark bar line works$' && ok "check: ok bar when spark bar line answers" || bad "check bar ok" "$(printf '%s\n' "$ck" | grep bar)"
printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/spark"
ck=$(sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   bar          spark bar line failed -- spark check$' && ok "check: FAIL bar when spark bar line fails, the remedy is spark check" || bad "check bar fail" "$(printf '%s\n' "$ck" | grep bar)"
rm -f "$H/.local/bin/spark"
ck=$(PATH=$H/.local/bin:$sys sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     bar          na (spark not found -- the status line stays empty)$' && ok "check: bar is na without spark, still ok" || bad "check bar na" "$(printf '%s\n' "$ck" | grep bar)"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "second run: Nothing to do" || bad "idempotence" "$out"
# Debian's names: apt ships fd as fdfind and bat as batcat; check and status find them so
mkdir -p "$H/apt-bin"
for t in tmux fzf zoxide eza btop fdfind batcat; do printf '#!/bin/sh\n:\n' > "$H/apt-bin/$t"; chmod +x "$H/apt-bin/$t"; done
printf 'ID=debian\n' > "$H/os-debian"
ck=$(SPARK_OS_RELEASE=$H/os-debian PATH=$H/apt-bin:$sys sh "$SH" check || true)
printf '%s\n' "$ck" | grep -q '^ok     tools        tmux, fzf, zoxide, eza, bat, btop, fd$' && ok "check under apt: fdfind and batcat count as fd and bat" || bad "check apt tools" "$(printf '%s\n' "$ck" | grep tools)"
st=$(SPARK_OS_RELEASE=$H/os-debian PATH=$H/apt-bin:$sys sh "$SH" status)
printf '%s\n' "$st" | grep -q '^  tool  fd  *yes$' && printf '%s\n' "$st" | grep -q '^  tool  bat  *yes$' && ok "status under apt: the fd and bat rows say yes" || bad "status apt tools" "$(printf '%s\n' "$st" | grep tool)"

fi

# --- 3. on again follows the palette --------------------------------------
if want 3; then
theme_fixture '#ee8800'
sh "$SH" on --yes >/dev/null
grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && ok "on again: a new accent lands as its nearest slot (colour3)" || bad "on rerender" "$(grep -n color "$HOME/.tmux.conf" | head -2)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     look' && ok "check: the look matches the palette" || bad "check look row" "$out"
printf '%s\n' "$out" | grep -q '^ok     font         na (CONSOLE_FONT unset: the console keeps its font)$' && ok "check: the font row is na with CONSOLE_FONT unset" || bad "check: font row" "$out"
grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" && ok "on again: the new accent lands in sgr.sh (1;33)" || bad "on again sgr" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q 'accent slot 3, muted slot 8 (SGR 1;33 / 90)' && ok "status: the theme row names the slots and the SGR pair" || bad "status slots" "$(printf '%s\n' "$st" | grep theme)"
out=$(sh "$SH" on --yes)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on again with nothing changed: ends in Nothing to do" || bad "on nothing to do" "$out"
theme_fixture '#5555ff'
out=$(sh "$SH" on --dry-run); out2=$(sh "$SH" apply --dry-run)
[ "$out2" = "$out" ] && printf '%s\n' "$out" | grep -q '^would  look' && ok "apply is on: the same dry run, row for row (the new accent would render)" || bad "apply alias" "$out2"
sh "$SH" apply --yes >/dev/null
grep -q "SPARK_ACCENT_SGR='1;94'" "$HOME/.config/spark-shell/sgr.sh" && ok "apply: the accent lands in sgr.sh (1;94)" || bad "apply sgr" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
theme_fixture '#ee8800'; sh "$SH" on --yes >/dev/null   # the palette section 4 reads

fi

# --- 4. the prompt choices ------------------------------------------------
if want 4; then
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT=plain\n' > "$HOME/.config/spark-shell/config"
rm -f "$HOME/.config/starship.toml"
sh "$SH" on --yes >/dev/null
[ ! -e "$HOME/.config/starship.toml" ] && ok "PROMPT=plain renders no starship.toml" || bad "plain prompt"
printf 'PROMPT=starship\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on --yes >/dev/null
[ -f "$HOME/.config/starship.toml" ] && grep -q 'style = "bold yellow"' "$HOME/.config/starship.toml" \
    && plain "$HOME/.config/starship.toml" && ok "PROMPT_STYLE=full renders the full style, plain" || bad "full style"
# no starship and no package for it (the fixture family): the shell's own prompt, a skip, never a download
mv "$H/.local/bin/starship" "$H/starship.aside"
( PATH=$H/.local/bin:$sys without_tools "$H/no-starship" starship )
out=$(PATH=$H/no-starship sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q 'would  starship' && bad "a starship download survives" "$out" || ok "on: no starship row would fetch anything"
printf '%s\n' "$out" | grep -q '^skip   prompt       no starship package here' && ok "on: no starship package here is a skip (the shell's own prompt)" || bad "prompt skip" "$out"
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on: a prompt skip still ends in Nothing to do" || bad "prompt skip count" "$out"
# the machine's name on the tmux line: on a Mac LocalHostName, read by scutil's full path whatever the PATH,
# never hostname -s, the network's name (#58); here hostname says another name, and /usr/sbin is off the PATH
if [ "$(uname -s)" = Darwin ]; then
    lhn=$(/usr/sbin/scutil --get LocalHostName 2>/dev/null || :)
    if [ -n "$lhn" ]; then
        printf '#!/bin/sh\necho elsewhere\n' > "$H/.local/bin/hostname"; chmod +x "$H/.local/bin/hostname"
        PATH=$H/.local/bin:/usr/bin:/bin sh "$SH" on --yes >/dev/null 2>&1 || :
        grep -qF "]$lhn#[default]" "$HOME/.tmux.conf" && ok "on (macOS) with no /usr/sbin on the PATH: the tmux line names the machine by LocalHostName, never the network's name (#58)" || bad "mac host name" "$(grep status-left "$HOME/.tmux.conf")"
        rm -f "$H/.local/bin/hostname"
    fi
fi
mv "$H/starship.aside" "$H/.local/bin/starship"
out=$(sh "$SH" on --dry-run)
printf '%s\n' "$out" | grep -q '^ok     prompt       starship 0.0-stub draws the prompt$' && ok "on: the prompt row names the starship it found" || bad "prompt ok" "$out"
! grep -q 'STARSHIP_VERSION' "$SRC" && [ "$(grep -c 'curl -' "$SRC")" = 9 ] && grep -q '^    curl -fsIL --proto .=https,file. --proto-redir .=https. -o /dev/null "$DIALOG_URL/$1/spark-dialog-$_ut"' "$SRC" && grep -q '^    curl -fsSL --proto .=https,file. --proto-redir .=https. -o "$_df" "$DIALOG_URL/$_rt/spark-dialog-$_dt"' "$SRC" \
    && grep -q '^    curl -fsSL --proto .=https,file. --proto-redir .=https. -o "$_plf" "$DIALOG_URL/$_plr/spark-wallpaper-$_plt"' "$SRC" \
    && grep -q '^    curl -fsSL --proto .=https,file. --proto-redir .=https. -o "$_pdf" "$DIALOG_URL/$_pdr/spark-winpad-$_pdt"' "$SRC" \
    && grep -q '^    if ! curl -fsSL --proto .=https,file. --proto-redir .=https. --connect-timeout 30 -o "$_nz" "$NEON_URL"' "$SRC" && grep -q '^NEON_SHA256=[0-9a-f]\{64\} ' "$SRC" \
    && grep -q '^        if ! curl -fsSL --proto .=https,file. --proto-redir .=https. --connect-timeout 30 -o "$_nz" "$NEON_URL"' "$SRC" \
    && grep -q '^    curl -fsSL --proto .=https,file. --proto-redir .=https. -o "$SEMANTIC_MODEL.new" --connect-timeout 30 --speed-limit 1024 --speed-time 60 "$SEMANTIC_URL"' "$SRC" && grep -q '^SEMANTIC_SHA256=[0-9a-f]\{64\}$' "$SRC" \
    && grep -q 'curl --unix-socket "$SEMANTIC_SOCK" -sf -m 2 -o /dev/null http://localhost/health' "$SRC" \
    && grep -q '^    curl -fsSL --proto .=https,file. --proto-redir .=https. -o "$4" --connect-timeout 30 --speed-limit 1024 --speed-time 60 "$2"' "$SRC" \
    && ok "spark-shell: four downloads, the release files of the dialog, of spark-wallpaper (#187) and of spark-winpad (v0.133), the font's (fetched by the faces row too, when the font row did not, #247) and the semantic search's model (v0.130), each checked against the sha256 pinned for it; one look that keeps nothing, whether a release is up; and one at the semantic search's own socket; no pinned version of anything else" || bad "a download survives" "$(grep -n 'STARSHIP_VERSION\|curl ' "$SH")"

fi

# --- 5. off hands back ----------------------------------------------------
if want 5; then
# a yazi theme v0.35 rendered over one of yours (.bak): off hands yours back
mkdir -p "$HOME/.config/yazi"; printf '# rendered by spark-shell\n' > "$HOME/.config/yazi/theme.toml"; printf 'mine\n' > "$HOME/.config/yazi/theme.toml.bak"
: > "$HOME/.config/spark/hook.bash"; : > "$HOME/.config/spark/hook.zsh"   # spark installed here: off keeps its hook line
out=$(sh "$SH" off --dry-run)
printf '%s\n' "$out" | grep -q '^would  rc ' && printf '%s\n' "$out" | grep -q '^would  restore .*\.tmux\.conf' && printf '%s\n' "$out" | grep -q '^would  restore .*yazi/theme\.toml -- back from theme\.toml\.bak' && printf '%s\n' "$out" | grep -Eq '^[0-9]+ to do$' \
    && ok "off --dry-run: would rows for the rc link, the renders and the .bak, then the count" || bad "off dry-run rows" "$out"
printf '%s\n' "$out" | grep -q "^would  rc .*/$rc1 -- spark's hook line kept\$" && ok "off --dry-run: the hook line off would append is a would row" || bad "off dry-run hook row" "$out"
[ -L "$HOME/$rc1" ] && [ -f "$HOME/.tmux.conf" ] && [ -f "$HOME/.config/yazi/theme.toml.bak" ] && [ -f "$HOME/.config/spark-shell/sgr.sh" ] \
    && ok "off --dry-run: touched nothing (the rc link, the renders and the .bak still there)" || bad "off dry-run wrote" "$(ls -la "$HOME" "$HOME/.config/yazi")"
out=$(sh "$SH" off)
[ ! -e "$HOME/.config/yazi/theme.toml.bak" ] && [ "$(cat "$HOME/.config/yazi/theme.toml")" = mine ] && ok "off: a yazi theme of yours comes back from .bak (v0.35's render gone)" || bad "yazi hand-back" "$(ls -la "$HOME/.config/yazi")"
if [ "$rc1" = .bashrc ]; then
    [ ! -L "$HOME/.bashrc" ] && grep -q yours "$HOME/.bashrc" && ok "off: the rc file came back from .bak" || bad "rc restore" "$(ls -la "$HOME")"
fi
[ ! -e "$HOME/.tmux.conf" ] && ok "off: a render with no .bak is removed, never a husk" || bad "render removal"
[ ! -e "$HOME/.config/spark-shell/sgr.sh" ] && ok "off: sgr.sh is gone (the prompt goes plain)" || bad "sgr removal"
printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off: packages stay, said so" || bad "off closing" "$out"

# a second backup never takes the first's place: .bak stays the file off hands back, a later one sits beside it by its time
fresh
theme_fixture '#ff5555'
printf 'first of mine\n' > "$HOME/.tmux.conf"
sh "$SH" on --yes >/dev/null
printf 'second of mine\n' > "$HOME/.tmux.conf"
out=$(sh "$SH" on --yes)
[ "$(cat "$HOME/.tmux.conf.bak")" = 'first of mine' ] && [ "$(cat "$HOME"/.tmux.conf.bak.* 2>/dev/null)" = 'second of mine' ] && printf '%s\n' "$out" | grep -q 'tmux\.conf\.bak\.[0-9]' \
    && ok "on: a second backup never takes the first's place: .bak stays, the later one beside it by its time, the row says where" || bad "second backup" "$(ls -la "$HOME"/.tmux.conf* 2>&1) $out"
printf 'second of mine\n' > "$HOME/.tmux.conf"
sh "$SH" on --yes >/dev/null
[ "$(ls "$HOME"/.tmux.conf.bak.* 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "on: a file the same as one kept already is not kept twice (btop writes its conf back on every exit)" || bad "backup twice" "$(ls -la "$HOME"/.tmux.conf* 2>&1)"
sh "$SH" off >/dev/null
[ "$(cat "$HOME/.tmux.conf")" = 'first of mine' ] && ok "off: the first .bak comes back, the file you had before spark-shell" || bad "off first backup" "$(ls -la "$HOME"/.tmux.conf* 2>&1)"

fi

# --- 8. invoked through a symlink (~/.local/bin): the repo still found --
if want 8; then
fresh
theme_fixture '#ff55ff'
ln -s "$SH" "$H/.local/bin/spark-shell"
sh -c '"$0" on --yes' "$H/.local/bin/spark-shell" >/dev/null 2>&1 || true
[ -f "$HOME/.tmux.conf" ] && grep -q 'fg=colour13,bold' "$HOME/.tmux.conf" \
    && ok "a symlinked spark-shell still finds its templates" || bad "symlink invocation" "$(ls -la "$HOME" | head -4)"
case $(uname -s) in Darwin) r8=.zshrc ;; *) r8=.bashrc ;; esac
[ -L "$HOME/$r8" ] && [ -e "$HOME/$r8" ] && ok "the rc link resolves (no dangling target)" || bad "rc link dangles" "$(readlink "$HOME/$r8" 2>&1)"

fi

# --- 9. no theme.env: the color words, each its own slot -----------------
if want 9; then
fresh
sh "$SH" on --yes >/dev/null
grep -q 'fg=colour4,bold' "$HOME/.tmux.conf" && grep -q 'pane-border-style "fg=colour7"' "$HOME/.tmux.conf" \
    && ok "no theme.env: accent blue (colour4), muted white (colour7)" || bad "name defaults" "$(grep -n color "$HOME/.tmux.conf" | head -3)"
grep -q "SPARK_ACCENT_SGR='1;34'" "$HOME/.config/spark-shell/sgr.sh" && grep -q "SPARK_MUTED_SGR='37'" "$HOME/.config/spark-shell/sgr.sh" \
    && ok "no theme.env: sgr.sh says blue (1;34) and white (37)" || bad "sgr defaults" "$(cat "$HOME/.config/spark-shell/sgr.sh")"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q "none: the terminal's own 16 colors -- accent slot 4, muted slot 7 (SGR 1;34 / 37)" && ok "status: no theme.env, the slots still named" || bad "status none" "$(printf '%s\n' "$st" | grep theme)"

fi

# --- 10. the templates themselves: no truecolor flag, ASCII fzf ----------
if want 10; then
grep -q MICRO_TRUECOLOR "$REPO/template/linux/.bashrc" "$REPO/template/macos/.zshrc" && bad "MICRO_TRUECOLOR still exported" || ok "rc files: no MICRO_TRUECOLOR"
grep -q -- '--no-unicode' "$REPO/template/linux/.bashrc" && grep -q -- '--no-unicode' "$REPO/template/macos/.zshrc" && ok "rc files: fzf asked for ASCII" || bad "fzf opts"
grep -rEq '#[0-9a-fA-F]{6}' "$REPO/template" && bad "a template names a hex color" "$(grep -rnE '#[0-9a-fA-F]{6}' "$REPO/template" | head -2)" || ok "templates: no hex color anywhere"
for rc in linux/.bashrc macos/.zshrc; do
    grep -q 'spark-shell/sgr.sh' "$REPO/template/$rc" && ok "rc files: $rc sources spark-shell/sgr.sh" || bad "$rc: no sgr.sh"
    # the order: starship's init, then sgr.sh, then spark's hook line, then zoxide
    l_st=$(grep -n 'starship init' "$REPO/template/$rc" | head -1 | cut -d: -f1)
    l_sgr=$(grep -n '^[^#]*spark-shell/sgr.sh' "$REPO/template/$rc" | head -1 | cut -d: -f1)
    l_hook=$(grep -n '^[^#]*config/spark/hook\.' "$REPO/template/$rc" | head -1 | cut -d: -f1)
    l_zo=$(grep -n 'zoxide init' "$REPO/template/$rc" | head -1 | cut -d: -f1)
    [ "$l_st" -lt "$l_sgr" ] && [ "$l_sgr" -lt "$l_hook" ] && [ "$l_hook" -lt "$l_zo" ] \
        && ok "rc files: $rc keeps the order (starship, sgr.sh, spark's hook, zoxide)" || bad "$rc order" "starship $l_st sgr $l_sgr hook $l_hook zoxide $l_zo"
    l_you=$(grep -n 'config/spark-shell/rc' "$REPO/template/$rc" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)
    [ -n "$l_you" ] && [ "$l_you" -gt "$l_zo" ] && ok "rc files: $rc sources ~/.config/spark-shell/rc (yours) last" || bad "$rc yours" "line $l_you vs zoxide $l_zo"
done
for t in minimal full; do
    st_t=$REPO/template/.config/starship.toml.$t
    grep -q 'custom' "$st_t" && bad "starship $t: a segment of spark's" || ok "starship $t: no spark segment on the prompt"
done

fi

# --- 13. spark's own palettes, when its clone is at hand -------------------
if want 13; then
if [ -n "${SPARK:-}" ] && ls "$SPARK"/themes/*.env >/dev/null 2>&1; then
    for env in "$SPARK"/themes/*.env; do
        name=${env##*/}; name=${name%.env}
        fresh
        cp "$env" "$HOME/.config/spark/theme.env"
        sh "$SH" on --yes >/dev/null
        st=$(sh "$SH" status)
        allplain=1
        for rel in $RENDERS; do plain "$HOME/$rel" || allplain=0; done
        [ "$allplain" = 1 ] && grep -Eq 'fg=color(1[0-5]|[0-9]),bold' "$HOME/.tmux.conf" \
            && ok "$name: renders plain, $(printf '%s\n' "$st" | sed -n 's/.*read: \(accent color[0-9]*, muted color[0-9]*\).*/\1/p')" \
            || bad "$name: not plain or no accent slot" "$(grep -rnE '#[0-9a-fA-F]{6}' "$HOME/.tmux.conf" "$HOME/.config" | head -2)"
    done
else
    printf '  NOTICE: SPARK unset -- spark'"'"'s palettes not exercised (SPARK=/path/to/spark sh test/shell_test.sh)\n'
fi
# the key spark's next release stops writing: a theme.env without
# THEME_BTOP renders the same look, so both orders work meanwhile
fresh
theme_fixture '#aa0000'
sh "$SH" on --yes >/dev/null
with=$(sed "s|$H|HOME|g" "$HOME/.tmux.conf")
fresh
theme_fixture '#aa0000'
grep -v '^THEME_BTOP=' "$HOME/.config/spark/theme.env" > "$H/theme.env" && mv "$H/theme.env" "$HOME/.config/spark/theme.env"
st=0; out=$(sh "$SH" on --yes 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(sed "s|$H|HOME|g" "$HOME/.tmux.conf")" = "$with" ] \
    && ! grep -q 'color_theme\|THEME_BTOP' "$HOME/.config/btop/btop.conf" \
    && sh "$SH" status | grep 'in use: accent slot 1, muted slot 8' >/dev/null \
    && ok "theme.env without THEME_BTOP: the same render, no color_theme line in btop.conf" || bad "theme.env without THEME_BTOP" "st=$st $out"

fi

# --- 14. the desktop: sway and foot, asked for by DESKTOP=sway ---------
if want 14; then
# stubs stand in for sway, swaymsg and foot; the Linux half is guarded by
# uname (macOS has its own desktop) and runs in CI's linux and arch jobs
fresh
desktop_stubs
theme_fixture '#ff5555'
out=$(sh "$SH" on --dry-run)
[ ! -e "$HOME/.config/foot" ] && [ ! -e "$HOME/.config/sway" ] && ok "default: DESKTOP=none renders no foot.ini, no sway config" || bad "desktop rendered by default" "$(ls -R "$HOME/.config")"
printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "default dry-run acts on a font" "$out" || ok "default dry-run: no font row acts"
sh "$SH" on --yes >/dev/null
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desktop none' && ok "status: the desktop row says none" || bad "status desktop none" "$(printf '%s\n' "$st" | grep desktop)"
out=$(sh "$SH" check || true)
printf '%s\n' "$out" | grep -q '^ok     desktop      na (' && ok "check: desktop is na by default" || bad "check desktop na" "$out"
printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "check: a font row fails" "$out" || ok "check: the font row does not fail"
out=$(sh "$SH" desktop 2>&1 || true)
printf '%s\n' "$out" | grep -q '^spark-shell desktop: ' && ok "desktop: refused with DESKTOP=none (the default), one line" || bad "desktop none" "$out"
printf 'THEME=nord\n' > "$HOME/.config/spark-shell/config"
[ "$(THEME=dracula sh "$SH" theme | sed -n 1p | cut -d' ' -f1-3)" = 'theme  nord' ] && ok "config: the file wins over a key in the environment (a window started at login carries the old one)" || bad "file wins" "$(THEME=dracula sh "$SH" theme | sed -n 1p)"
printf 'DESKTOP=gnome\n' > "$HOME/.config/spark-shell/config"
sh "$SH" status >/dev/null 2>&1 && bad "DESKTOP=gnome accepted" || ok "config: DESKTOP=gnome is refused"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
if [ "$(uname -s)" = Darwin ]; then
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^skip   desktop      not on macOS' && ok "macOS: DESKTOP=sway is na, said in a row" || bad "macOS na row" "$out"
    sh "$SH" on --yes >/dev/null
    [ ! -e "$HOME/.config/sway" ] && ok "macOS: nothing rendered for the desktop" || bad "macOS rendered sway"
    out=$(sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS' && ok "macOS: desktop refuses, not on macOS" || bad "macOS desktop" "$out"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      na (macOS)' && ok "macOS: check says na" || bad "macOS check" "$out"
else
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^would  look .*foot/foot.ini' && printf '%s\n' "$out" | grep -q '^would  look .*sway/config' \
        && ok "DESKTOP=sway: dry-run would render foot.ini and sway/config" || bad "sway dry-run" "$out"
    sh "$SH" on --yes >/dev/null
    foot=$HOME/.config/foot/foot.ini; sway=$HOME/.config/sway/config
    [ -f "$foot" ] && [ -f "$sway" ] && ok "DESKTOP=sway: both rendered" || bad "sway renders missing" "$(ls -R "$HOME/.config")"
    grep -q '^background=000000$' "$foot" && grep -q '^foreground=aaaaaa$' "$foot" && grep -q '^regular1=aa0000$' "$foot" && grep -q '^bright1=ff5555$' "$foot" && grep -q '^title=terminal$' "$foot" \
        && ok "foot.ini: the palette's own hex (background 000000, regular1 aa0000, bright1 ff5555)" || bad "foot colors" "$(grep -n '=' "$foot" | head -8)"
    grep -q '^font=DejaVu Sans Mono:size=12$' "$foot" && ok "foot.ini: FONT's line (the suite's FONT, a face other than Monaspace Neon: verbatim)" || bad "foot font line" "$(grep -n '^font' "$foot")"
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: one color section, [colors-dark] (a foot with no version = 1.26+)" || bad "foot sections" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.21.0 (Debian)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" on --yes >/dev/null
    grep -q '^\[colors\]$' "$foot" && ! grep -q '^\[colors-dark\]$' "$foot" && ok "foot.ini: foot 1.21 gets [colors] alone" || bad "foot 1.21 section" "$(grep -n '^\[' "$foot")"
    printf '#!/bin/sh\n[ "$1" = --version ] && echo "foot version: 1.28.0 (Arch)"\n' > "$HOME/.local/bin/foot"
    sh "$SH" on --yes >/dev/null
    grep -q '^\[colors-dark\]$' "$foot" && ! grep -q '^\[colors\]$' "$foot" && ok "foot.ini: foot 1.28 gets [colors-dark] alone" || bad "foot 1.28 section" "$(grep -n '^\[' "$foot")"
    grep -q '^client.focused *#ff5555 #ff5555 #000000 #802b2b80 #ff5555$' "$sway" && grep -q '^client.unfocused *#060606 #060606 #555555 #060606 #060606$' "$sway" && ! grep -q '^client\.unfocused.*#ff5555' "$sway" && grep -q '^default_border normal 1$' "$sway" && grep -q '^default_floating_border normal 1$' "$sway" && grep -q '^titlebar_border_thickness 1$' "$sway" && grep -q '^title_align left$' "$sway" && ! grep -q '^smart_borders' "$sway" \
        && ok "sway: the chrome (v0.140): a title band and a one-pixel frame in one shade, the surface shade on the focused window (#0f0f0f), four percent above the ground on the others (#060606) with muted text; the accent only as the focused indicator, the drop area of a moving window (#47), at a quarter: #ff5555 halved with alpha 80, as sway takes it (#49)" || bad "sway focused" "$(grep -n 'client\|border' "$sway")"
    grep -qxF 'for_window [shell=".*"] title_format "  %title"' "$sway" && grep -qxF 'for_window [app_id="foot"] title_format "  terminal   %title"' "$sway" \
        && ok "sway: with no winpad on the machine the titles are plain: no button is drawn that does not click (v0.143)" || bad "band plain" "$(grep -n title_format "$sway")"
    printf '#!/bin/sh\n' > "$HOME/winpad-here"; chmod +x "$HOME/winpad-here"
    SPARK_SHELL_WINPAD=$HOME/winpad-here sh "$SH" on --yes >/dev/null
    _bg=' &#x2715;  &#x25BD;  &#x25A1; '
    grep -qxF "for_window [shell=\".*\"] title_format \"$_bg  %title\"" "$sway" && grep -qxF "for_window [app_id=\"foot\"] title_format \"$_bg  terminal   %title\"" "$sway" \
        && grep -qF 'pub const GLYPH_REFS: [&str; 3] = ["&#x2715;", "&#x25BD;", "&#x25A1;"];' "$REPO/component/winpad/src/buttons.rs" \
        && ok "sway: with a winpad, the close, minimize and fill buttons are the start of every title, sway's own pixels, so they move with the window (v0.142), written as character references so the render stays ASCII; the component's are the same three" || bad "band glyphs" "$(grep -n title_format "$sway")"
    printf 'VOICE_ENGINE=/bin/true\n' >> "$HOME/.config/spark-shell/config"
    SPARK_SHELL_WINPAD=$HOME/winpad-here sh "$SH" on --yes >/dev/null
    grep -qxF "for_window [app_id=\"foot\"] title_format \"$_bg <span foreground='#aa0000'>&#x25CB;</span>         terminal   %title\"" "$sway" && grep -qxF "for_window [shell=\".*\"] title_format \"$_bg  %title\"" "$sway" \
        && ok "sway: with a voice, a terminal's title has the mic after the buttons, a red ring (the palette's red) with the bars' room; other windows none (v0.144)" || bad "band mic" "$(grep -n title_format "$sway")"
    sed -i.bak '/^VOICE_ENGINE=/d' "$HOME/.config/spark-shell/config"; rm -f "$HOME/.config/spark-shell/config.bak"
    sh "$SH" on --yes >/dev/null; rm -f "$HOME/winpad-here"
    grep -qxF "bindsym Mod4+space exec $REPO/spark-shell desktop voice press" "$sway" \
        && grep -qxF "bindsym --release Mod4+space exec $REPO/spark-shell desktop voice release" "$sway" \
        && ! grep -q '^bindsym Mod4+[ds] ' "$sway" \
        && ok "sway: Super+Space opens home when tapped and listens while held, without separate desktop chat keys (v0.144)" || bad "sway home render" "$(grep -n 'desktop voice' "$sway")"
    grep -qxF "for_window [tiling] mark --add _spark-shell.new, exec $REPO/spark-shell desktop window new" "$sway" && [ "$(grep -c '^for_window \[tiling\]' "$sway")" = 1 ] \
        && ok "sway: one rule for a new tiled window runs desktop window new from the clone, which decides where it opens (#262)" || bad "sway new window render" "$(grep -n 'tiling' "$sway")"
    dini=$HOME/.config/foot/dialog.ini
    grep -qx 'resize-by-cells=no' "$dini" && ok "home: floating snaps honor the compositor's pixel dimensions" || bad "home pixel resize" "$(cat "$dini")"
    grep -qx "include=$HOME/.config/foot/foot.ini" "$dini" && [ "$(sed -n '/^include=/{n;p;}' "$dini")" = 'title=spark' ] && grep -qx 'initial-window-size-chars=60x40' "$dini" && grep -qx 'pad=0x0' "$dini" && grep -qx 'background=0f0f0f' "$dini" && grep -qx 'alpha=1.0' "$dini" && grep -qx '\[colors-dark\]' "$dini" \
        && [ "$(sed -n '/^\[environment\]$/,$p' "$dini" | grep -v '^#' | tr '\n' ' ')" = '[environment] SPARK_DIALOG_WINDOW=1 ' ] \
        && ok "dialog.ini: foot.ini included, then the dialog's size and surface, opaque, no air of foot's own (the dialog draws its margins, v0.124.5) (#33); the window says it is the dialog's, so its prompt is drawn the moment it maps (#138); its title is spark's, so the pad names it spark" || bad "dialog.ini" "$(cat "$dini" 2>&1)"
    grep -qx '16=ff5555' "$foot" && grep -qx '17=555555' "$foot" && grep -qx '18=0f0f0f' "$foot" && grep -qx '19=1e1e1e' "$foot" && grep -q '^20=[0-9a-f]\{6\}$' "$foot" && grep -qx '21=4b2020' "$foot" \
        && ok "foot.ini: the six slots after the sixteen, the accent, the muted color, the surface, the lit row, the quiet text (#34), the header's band, the accent at a quarter over the surface (v0.124.5)" || bad "foot slots" "$(grep -n '^[12][0-9]=' "$foot")"
    sgr=$HOME/.config/spark-shell/sgr.sh
    # shellcheck disable=SC1090   # the render just written, on purpose
    (TERM=foot; . "$sgr" && [ "$SPARK_ACCENT_SGR" = '1;38;5;16' ] && [ "$SPARK_MUTED_SGR" = '38;5;17' ] && [ "$SPARK_WARN_SGR" = '1;31' ]) \
        && (TERM=xterm-256color; . "$sgr" && [ "$SPARK_ACCENT_SGR" != '1;38;5;16' ] && [ -z "${STARSHIP_CONFIG:-}" ]) \
        && ok "sgr.sh on the desktop: in foot the accent and the muted color are the slots 16 and 17, elsewhere the sixteen (#34)" || bad "sgr slots" "$(cat "$sgr")"
    grep -q 'style = "bold 16"' "$HOME/.config/starship-foot.toml" && grep -q 'style = "bold bright-red"' "$HOME/.config/starship.toml" && plain "$HOME/.config/starship-foot.toml" \
        && ok "starship on the desktop: a foot twin of its config names the slot 16 for the accent, the sixteen's stays (#34)" || bad "starship foot twin" "$(grep -n style "$HOME/.config/starship-foot.toml" 2>&1 | head -3)"
    grep -q "^exec sh -c '\$term -e $REPO/spark-shell desktop --first; swaymsg exit'\$" "$sway" && ok "sway: the first window's line names the clone's spark-shell" || bad "sway --first render" "$(grep -n '^exec sh' "$sway")"
    grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.95$' "$foot" \
        && ok "sway: the default background is the ground (the palette's background a shade darker), the windows apart (gaps of 8), foot nearly solid" || bad "sway default bg" "$(grep -n 'output\|gaps' "$sway")"
    grep -q '@[A-Z_0-9]*@' "$foot" "$sway" && bad "a desktop render keeps a placeholder" "$(grep -n '@[A-Z_0-9]*@' "$foot" "$sway" | head -2)" || ok "desktop renders: no placeholder left"
    head -1 "$foot" | grep -q '^# rendered by spark-shell' && head -1 "$sway" | grep -q '^# rendered by spark-shell' && ok "desktop renders: both marked" || bad "desktop markers"
    LC_ALL=C grep -q "[^ -~${tab}]" "$foot" "$sway" && bad "a desktop render is not ASCII" || ok "desktop renders: ASCII"
    printf 'DESKTOP=sway\nFONT=Test Mono:size=14\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^font=Test Mono:size=14$' "$foot" && ok "FONT in the config lands in foot.ini verbatim" || bad "FONT override" "$(grep -n '^font' "$foot")"
    grep -q '^seat \* xcursor_theme spark-white 32$' "$sway" && ok "sway: the pointer line names spark-white at 32 on a dark palette with the text at 14 points (#22, #24)" || bad "sway pointer line" "$(grep -n xcursor "$sway")"
    printf 'DESKTOP=sway\nPOINTER=Adwaita 32\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^seat \* xcursor_theme Adwaita 32$' "$sway" && ok "POINTER=NAME SIZE in the config lands in the sway render" || bad "POINTER override" "$(grep -n xcursor "$sway")"
    printf 'DESKTOP=sway\nPOINTER=Adwaita\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^seat \* xcursor_theme Adwaita 24$' "$sway" && ok "POINTER=NAME alone: the size is 24" || bad "POINTER name alone" "$(grep -n xcursor "$sway")"
    printf 'DESKTOP=sway\nPOINTER=two words 24\n' > "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" on --yes 2>&1) || rc=$?
    [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^spark-shell: POINTER=two words 24 in .*: a cursor theme's NAME and, after a space, its SIZE in pixels" && ok "POINTER of a wrong shape is refused in one sentence (exit 1)" || bad "POINTER refusal" "rc=$rc $out"
    sed 's/^THEME_BG=.*/THEME_BG=#ffffff/' "$HOME/.config/spark/theme.env" > "$HOME/.config/spark/theme.light" && mv "$HOME/.config/spark/theme.light" "$HOME/.config/spark/theme.env"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^seat \* xcursor_theme spark-black 24$' "$sway" && ok "a light palette (background #ffffff) gets spark-black" || bad "light pointer" "$(grep -n xcursor "$sway")"
    theme_fixture '#ff5555'
    sh "$SH" on --yes >/dev/null
    pd=$HOME/.local/share/icons
    if command -v python3 >/dev/null 2>&1; then
        [ -f "$pd/spark-white/cursors/default" ] && [ -f "$pd/spark-black/cursors/pointer" ] && [ "$(head -c 4 "$pd/spark-white/cursors/default")" = Xcur ] && [ "$(readlink "$pd/spark-white/cursors/hand2")" = pointer ] \
            && [ "$(cat "$pd/spark-white/version")" = "$(sed -n 's/^VERSION = "\(.*\)".*/\1/p' "$REPO/lib/pointer.py")" ] && [ -f "$pd/spark-black/index.theme" ] \
            && ok "on desktop drew the spark pointer: two themes under ~/.local/share/icons, Xcursor files, hand2 an alias of pointer, the version stamped" || bad "pointer files" "$(ls -R "$pd" 2>&1 | head -12)"
        [ "$(readlink "$pd/spark-white/cursors/grab")" = grabbing ] && [ "$(readlink "$pd/spark-black/cursors/grab")" = grabbing ] && [ "$(readlink "$pd/spark-white/cursors/hand1")" = pointer ] \
            && ok "pointer: grab, the image sway asks for while a window moves, is the closed hand; the hand that points stays the pointer's (#46)" || bad "grab alias" "grab -> $(readlink "$pd/spark-white/cursors/grab"), hand1 -> $(readlink "$pd/spark-white/cursors/hand1")"
        pn=$(ls "$pd/spark-white/cursors" | wc -l | tr -d ' '); [ "$pn" -ge 60 ] && ok "pointer: $pn names in spark-white (the shapes and their aliases)" || bad "pointer names" "$pn"
        out=$(sh "$SH" on --yes)
        printf '%s\n' "$out" | grep -q 'pointer' && bad "pointer: a second on draws again or says a todo" "$out" || ok "pointer: a second on leaves the drawn themes alone, no row"
        out=$(sh "$SH" check || true)
        printf '%s\n' "$out" | grep -q '^ok     pointer      spark-white and spark-black are drawn; sway shows spark-white at 24' && ok "check: the pointer row says both themes are drawn and which one sway shows" || bad "check pointer" "$(printf '%s\n' "$out" | grep pointer)"
        sh "$SH" off desktop >/dev/null 2>&1 || true
        [ ! -d "$pd/spark-white" ] && [ ! -d "$pd/spark-black" ] && ok "off desktop removes the two spark themes" || bad "pointer off" "$(ls "$pd")"
    else
        out=$(sh "$SH" on --yes 2>&1 || true)
        [ ! -d "$pd/spark-white" ] && ok "no python3: the spark pointer is not drawn, the desktop renders still" || bad "pointer without python3" "$out"
        out=$(sh "$SH" check || true)
        printf '%s\n' "$out" | grep -q '^warn   pointer      python3 cannot draw the spark pointer here' && ok "check: without python3 the pointer row is a warn with its remedy" || bad "check pointer no python3" "$(printf '%s\n' "$out" | grep pointer)"
    fi
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desktop sway .*sway: ready' && ok "status: the desktop row says sway, ready" || bad "status desktop sway" "$(printf '%s\n' "$st" | grep desktop)"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot' && ok "check: desktop ok with the stubs and fresh renders" || bad "check desktop ok" "$out"
    printf '{"home.open":"Super+F3"}\n' > "$HOME/.config/spark-shell/desktop-keys.json"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   desktop .*out of date: .config/sway/config' \
        && ok "check: an unapplied named binding makes the desktop render stale" || bad "check pending home binding" "$out"
    sh "$SH" on --yes >/dev/null
    out=$(sh "$SH" check || true)
    grep -qxF "bindsym Mod4+F3 exec $REPO/spark-shell desktop voice press" "$sway" \
        && grep -qxF "bindsym --release Mod4+F3 exec $REPO/spark-shell desktop voice release" "$sway" \
        && printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot' \
        && ok "check: configured bindings use the same render as on" || bad "check configured home binding" "$out"
    rm "$HOME/.config/spark-shell/desktop-keys.json"
    sh "$SH" on --yes >/dev/null
    printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "check: a font row fails with DESKTOP=sway" "$out" || ok "check: the font row does not fail with DESKTOP=sway"
    out=$(env -u TEST_TTY -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'needs a console login (tty1 to tty9): ssh and terminal windows cannot start sway' && ok "desktop: refused with no console tty (ssh)" || bad "desktop no console" "$out"
    out=$(TEST_TTY=/dev/tty1 WAYLAND_DISPLAY=wayland-1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^no saved layouts yet' && ok "desktop: inside a desktop (WAYLAND_DISPLAY set) it lists the saved layouts, none yet" || bad "desktop inside" "$out"
    out=$(env -u WAYLAND_DISPLAY TEST_TTY=/dev/tty1 TERM=linux sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q 'sway-stub' "$HOME/.local/state/spark-shell/sway.log" && printf '%s' "$out" | od -c | grep -q '033   \[   ?   2   5   h' \
        && ok "desktop: runs sway as a child, its stderr in sway.log, the cursor back on TERM=linux" || bad "desktop run" "st=$st out=$out log=$(cat "$HOME/.local/state/spark-shell/sway.log" 2>&1)"
    printf 'DESKTOP=sway\nDESKTOP_BAR=no\n' > "$HOME/.config/spark-shell/config"
    out=$(SWAYSOCK=/nonexistent sh "$SH" on --yes)
    printf '%s\n' "$out" | grep -q '^ok     sway         reloaded' && ok "on: swaymsg reload when SWAYSOCK is set and sway's file changed" || bad "sway reload" "$out"
    out=$(SWAYSOCK=/nonexistent sh "$SH" on --yes)
    ! printf '%s\n' "$out" | grep -q 'reloaded' && ok "on: no reload when sway's file is as it was (#33: a reload restarts the wallpaper and the bar)" || bad "sway no reload" "$out"
    # a bar that started before spark-shell changed (an update) runs the code it read then: on reloads, so it starts again on the
    # new code with no logout; a bar started since, or one no longer running, is left (v0.131: the glyph family reached the bar
    # only after a logout)
    # a bar: on signals it to redraw (USR1), which the real one traps; it says when it is ready, so no signal meets a child
    # that has not dropped the suite's own traps yet
    rm -f "$H/fakebar.ready"; sh -c 'trap "" USR1; : > "$1"; exec sleep 120' sh "$H/fakebar.ready" & fakebar=$!
    i=0; while [ ! -e "$H/fakebar.ready" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    bpid=$HOME/.local/state/spark-shell/bar.pid; mkdir -p "$(dirname "$bpid")"; printf '%s\n' "$fakebar" > "$bpid"; touch -t 200001010000 "$bpid"
    out=$(SWAYSOCK=/nonexistent sh "$SH" on --yes)
    printf '%s\n' "$out" | grep -q '^ok     sway         reloaded (the bar starts again on this spark-shell)' && ok "on: a running bar older than spark-shell (an update) is started again by a reload" || bad "stale bar reload" "$out"
    touch "$bpid"; out=$(SWAYSOCK=/nonexistent sh "$SH" on --yes)
    ! printf '%s\n' "$out" | grep -q 'reloaded' && ok "on: a bar started after spark-shell changed is left as it is" || bad "fresh bar no reload" "$out"
    sleep 0 & dead=$!; wait "$dead" || :; printf '%s\n' "$dead" > "$bpid"; touch -t 200001010000 "$bpid"   # a bar gone: a process that ended by itself, no signal sent
    out=$(SWAYSOCK=/nonexistent sh "$SH" on --yes)
    ! printf '%s\n' "$out" | grep -q 'reloaded' && ok "on: a bar's file whose bar is gone asks no reload" || bad "dead bar no reload" "$out"
    rm -f "$bpid"; kill "$fakebar" 2>/dev/null; wait "$fakebar" 2>/dev/null || :
    # the pad runs for the session (v0.140), and sway starts it at login alone: on, in a session with no pad (one that
    # began before an update), has sway start it as login does; with a pad running, or a dry run, sway is not asked.
    # The stand-in holds its lock as the real pad does, so a pad on restarts (a new look) is still one running
    psd=$H/padsway; mkdir -p "$psd" "$H/padrun"; pslog=$H/padsway.log; plock=$H/padrun/spark-shell-winpad.pid
    printf '#!/bin/sh\ncase "$*" in "-t get_version") echo "{\\"human_readable\\":\\"1.10\\"}" ;; "-- "*) shift; echo "$*" >> "%s" ;; esac\n' "$pslog" > "$psd/swaymsg"
    printf '#!/bin/sh\ntrap '"'"'[ -z "${WINPAD_LOCK:-}" ] || rm -f "$WINPAD_LOCK"; exit 0'"'"' TERM\n[ -z "${WINPAD_LOCK:-}" ] || echo $$ > "$WINPAD_LOCK"\nwhile :; do sleep 0.1; done\n' > "$psd/spark-winpad"
    chmod +x "$psd/swaymsg" "$psd/spark-winpad"
    padon() { rm -f "$pslog"; XDG_RUNTIME_DIR=$H/padrun SPARK_SHELL_WINPAD=$psd/spark-winpad SWAYSOCK=/nonexistent PATH="$psd:$PATH" sh "$SH" on --yes "$@" 2>&1; }
    padasked() { grep -qxF "exec $REPO/spark-shell desktop pad start" "$pslog" 2>/dev/null; }
    out=$(padon || :)
    printf '%s\n' "$out" | grep -qx 'ok     pad          the pad runs for this session now' && padasked \
        && ok "on: a session with no pad (begun before an update to v0.140) has sway start it, as login does" || bad "pad session start" "$out | $(cat "$pslog" 2>&1)"
    WINPAD_LOCK=$plock "$psd/spark-winpad" & ppad=$!
    i=0; while [ ! -s "$plock" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    out=$(padon || :)
    ! printf '%s\n' "$out" | grep -q '^[a-z]* *pad  .*for this session' && ! padasked \
        && ok "on: a pad running, or one on started again, is left as it is, sway not asked for another" || bad "pad session running" "$out | $(cat "$pslog" 2>&1)"
    [ ! -s "$plock" ] || kill "$(cat "$plock")" 2>/dev/null || :; kill "$ppad" 2>/dev/null || :; wait "$ppad" 2>/dev/null || :; rm -f "$plock"
    out=$(padon --dry-run || :)
    printf '%s\n' "$out" | grep -qx 'would  pad          start the pad for this session, through sway as at login' && ! padasked \
        && ok "on --dry-run: the pad it would start is said, sway not asked" || bad "pad session dry" "$out | $(cat "$pslog" 2>&1)"
    # the pad's settings as a config from v0.142 or before names them, PAD_*: on says what it would do, then writes them
    # once under their WINPAD_ names; a setting the config holds under both keeps its new line (v0.143)
    _pc=$HOME/.config/spark-shell/config; cp "$_pc" "$H/cfg.renames"
    printf 'PAD_PLACE=left center\nPAD_SIDE_WIDTH=72\nPAD_VIEW=titles\nWINPAD_VIEW=icons\n' >> "$_pc"
    out=$(padon --dry-run || :)
    printf '%s\n' "$out" | grep -q '^would  config       3 settings of the pad take their WINPAD_ names, PAD_ before' && grep -qx 'PAD_PLACE=left center' "$_pc" \
        && ok "on --dry-run: the pad's settings it would rename are said, the config as it was (v0.143)" || bad "config renames dry" "$out"
    out=$(padon || :)
    printf '%s\n' "$out" | grep -q '^ok     config       3 settings of the pad are WINPAD_ now' && grep -qx 'WINPAD_PLACE=left center' "$_pc" && grep -qx 'WINPAD_SIDE_WIDTH=72' "$_pc" \
        && [ "$(grep -c '^WINPAD_VIEW=' "$_pc")" = 1 ] && grep -qx 'WINPAD_VIEW=icons' "$_pc" && ! grep -q '^PAD_' "$_pc" \
        && ok "on: the pad's settings named PAD_ are written under their WINPAD_ names, once; one held under both keeps its new line (v0.143)" || bad "config renames" "$out | $(grep 'PAD_' "$_pc")"
    out=$(padon || :)
    ! printf '%s\n' "$out" | grep -q ' config .*WINPAD_' && ok "on again: no setting is left to rename" || bad "config renames twice" "$out"
    cp "$H/cfg.renames" "$_pc"
    # the voice row (v0.144): VOICE=no leaves it out; your own engine is taken as it is; the check says the same
    printf 'VOICE=no\n' >> "$_pc"; out=$(padon --dry-run || :)
    printf '%s\n' "$out" | grep -q '^skip   voice        VOICE=no$' && ok "on: VOICE=no, the voice row skipped" || bad "voice row no" "$out"
    cp "$H/cfg.renames" "$_pc"; printf 'VOICE_ENGINE=/bin/true\n' >> "$_pc"; out=$(padon --dry-run || :)
    printf '%s\n' "$out" | grep -q '^ok     voice        your engine: /bin/true$' && ok "on: VOICE_ENGINE named, the voice row says so and fetches nothing" || bad "voice row engine" "$out"
    out=$(XDG_RUNTIME_DIR=$H/padrun PATH="$psd:$PATH" sh "$SH" check 2>&1 || :)
    printf '%s\n' "$out" | grep -q 'voice.*your engine: /bin/true' && ok "check: the voice row, your engine named" || bad "check voice" "$out"
    cp "$H/cfg.renames" "$_pc"
    # a new drawing of the pointer reaches a running sway once: sway loads a cursor theme again only for a new name or size (#48)
    pd=$HOME/.local/share/icons; seen=$HOME/.local/state/spark-shell/pointer.seen; cmds=$H/swaymsg.cmds
    printf '#!/bin/sh\n[ "$1" != -- ] || { shift; echo "$*" >> "%s"; }\n' "$cmds" > "$H/.local/bin/swaymsg"
    for t in spark-white spark-black; do mkdir -p "$pd/$t"; sed -n 's/^VERSION = "\(.*\)".*/\1/p' "$REPO/lib/pointer.py" > "$pd/$t/version"; done   # drawn, as far as on can tell: no python3 needed
    sz=$(sed -n 's/^seat \* xcursor_theme spark-white //p' "$sway"); rm -f "$cmds" "$seen"
    SWAYSOCK=/nonexistent sh "$SH" on --yes >/dev/null
    grep -q "; seat \* xcursor_theme spark-white $((sz + 1)); seat \* xcursor_theme spark-white $sz; " "$cmds" && [ "$(cat "$seen" 2>&1)" = "$(cat "$pd/spark-white/version")" ] \
        && ok "on: a drawing sway has not loaded reaches it, the pointer one pixel up, then back, its version kept (#48)" || bad "pointer fresh" "sz=$sz $(cat "$cmds" "$seen" 2>&1)"
    grep -q '^client.focused #[0-9a-f]* #[0-9a-f]* #[0-9a-f]* #802b2b80 #[0-9a-f]*; ' "$cmds" && ok "on: a running sway takes the drop area at a quarter of the accent too, with no reload (#49)" || bad "live drop area" "$(cut -c1-160 "$cmds")"
    grep -q '; gaps inner all set 8; gaps outer all set 8; \[tiling\] border normal 1$' "$cmds" && ok "on: a running sway takes the gaps of 8 and the title band on the open workspaces at once, with no reload (#265)" || bad "live gaps" "$(cut -c1-400 "$cmds")"
    : > "$cmds"; SWAYSOCK=/nonexistent sh "$SH" on --yes >/dev/null
    grep -q "; seat \* xcursor_theme spark-white $sz; " "$cmds" && ! grep -q "xcursor_theme spark-white $((sz + 1))" "$cmds" && ok "on: a drawing sway loaded goes once, the size alone after" || bad "pointer fresh again" "$(cat "$cmds")"
    printf 'DESKTOP=sway\nDESKTOP_BAR=no\nPOINTER=Adwaita 32\n' > "$HOME/.config/spark-shell/config"; rm -f "$seen"; : > "$cmds"
    SWAYSOCK=/nonexistent sh "$SH" on --yes >/dev/null
    grep -q '; seat \* xcursor_theme Adwaita 32; ' "$cmds" && ! grep -q 'Adwaita 33' "$cmds" && [ ! -e "$seen" ] && ok "on: a cursor theme of yours, never drawn here, is not loaded again" || bad "pointer fresh theirs" "$(cat "$cmds")"
    printf 'DESKTOP=sway\nDESKTOP_BAR=no\n' > "$HOME/.config/spark-shell/config"; SWAYSOCK=/nonexistent sh "$SH" on --yes >/dev/null; had=0; [ ! -e "$seen" ] || had=1
    sh "$SH" off desktop >/dev/null 2>&1 || true
    [ "$had" = 1 ] && [ ! -e "$seen" ] && [ ! -d "$pd/spark-white" ] && ok "off desktop: the version sway loaded is forgotten with the two themes" || bad "pointer seen off" "had=$had $(ls "$pd" "$seen" 2>&1)"
    desktop_stubs
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"; sh "$SH" on --yes >/dev/null
    rm -f "$H/.local/bin/sway"
    # Exclude sway from every PATH entry, even on a desktop developer's host.
    without_tools "$H/no-sway" sway
    out=$(PATH="$H/no-sway" sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^FAIL   desktop      missing: sway -- spark-shell on' && ok "check: FAIL without sway, the remedy is spark-shell on" || bad "check no sway" "$out"
    out=$(env -u WAYLAND_DISPLAY PATH="$H/no-sway" TEST_TTY=/dev/tty1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'not installed: sway' && ok "desktop: refused without sway" || bad "desktop no sway" "$out"
    desktop_stubs
    sh "$SH" off >/dev/null
    [ ! -e "$foot" ] && [ ! -e "$sway" ] && ok "off: both desktop renders are gone" || bad "desktop off" "$(ls -R "$HOME/.config")"
    mkdir -p "$HOME/.config/sway"; printf 'mine\n' > "$sway"
    sh "$SH" off >/dev/null
    grep -q mine "$sway" && ok "off: a sway config of yours (no marker) is left alone" || bad "yours removed"
    sh "$SH" on --yes >/dev/null
    [ -f "$sway.bak" ] && grep -q mine "$sway.bak" && grep -q '^# rendered by spark-shell' "$sway" && ok "on: yours moves to .bak, the render takes its place" || bad "sway backup" "$(ls "$HOME/.config/sway")"
    rm -f "$foot"
    out=$(env -u WAYLAND_DISPLAY TEST_TTY=/dev/tty1 sh "$SH" desktop 2>&1 || true)
    printf '%s\n' "$out" | grep -q 'the sway and foot settings are missing (spark-shell on)' && ok "desktop: refused when a render is missing" || bad "desktop not rendered" "$out"
    # no theme.env: foot's own sixteen on the desktop (the starlight set, v0.86); the console keeps VGA
    fresh
    desktop_stubs
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^regular4=24acd4$' "$HOME/.config/foot/foot.ini" && grep -q '^background=242424$' "$HOME/.config/foot/foot.ini" && grep -q '^foreground=ffffff$' "$HOME/.config/foot/foot.ini" && grep -q '^bright0=616161$' "$HOME/.config/foot/foot.ini" \
        && ok "no theme.env: foot.ini takes foot's own sixteen (regular4 24acd4, bg 242424, fg ffffff), never the console's VGA (#25)" || bad "foot own colors" "$(grep -n '=' "$HOME/.config/foot/foot.ini" | head -6)"
    grep -q '^client.focused *#24acd4 #24acd4 ' "$HOME/.config/sway/config" && ok "no theme.env: the focused band is foot's own blue (#24acd4)" || bad "foot focused" "$(grep -n client "$HOME/.config/sway/config")"
fi

# --- the terminal's font: Monaspace Neon (#26) ----------------------------
# on installs it where foot is wanted, and on a Mac, from the release's zip
# whose sha256 the program pins. Here the zip is a fixture made like the
# release's (the faces under Static Fonts/Monaspace Neon), fetched from a
# file:// URL by a copy of spark-shell whose pin is the fixture's sha256:
# the pin decides, and the real program refuses the same file. FONT, or a
# Mac's CONSOLE_FONT, on the old default face moves to it once, at its size;
# until it is installed foot draws the old face. No test downloads.
fresh
unset FONT   # the default, not the suite's
desktop_stubs
theme_fixture '#ff5555'
fz=$H/fz; mkdir -p "$fz/repo"
cfg=$HOME/.config/spark-shell/config; mkdir -p "$HOME/.config/spark-shell"
if [ "$(uname -s)" = Darwin ]; then
    fdir=$HOME/Library/Fonts; key=CONSOLE_FONT; was='Menlo-Regular 18'; now='MonaspaceNeon-Regular 18'; old=Menlo-Regular; keep='Terminal.app keeps its font'
else
    fdir=$HOME/.local/share/fonts/monaspace-neon; key=FONT; was='DejaVu Sans Mono:size=11'; now='Monaspace Neon:size=11'; old='DejaVu Sans Mono'; keep='foot draws DejaVu Sans Mono'
    printf 'DESKTOP=sway\n' > "$cfg"
fi
printf '%s=%s\n' "$key" "$was" >> "$cfg"
if command -v curl >/dev/null 2>&1; then
    printf 'not the release\n' > "$fz/other.zip"
    out=$(SPARK_SHELL_FONT_URL="file://$fz/other.zip" sh "$SH" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -qxF "todo   font         the file fetched is not the Monaspace Neon 1.400 spark-shell pins: nothing installed, $keep" \
        && [ ! -e "$fdir/MonaspaceNeon-Regular.otf" ] && grep -qxF "$key=$was" "$cfg" && [ ! -e "$HOME/.local/state/spark-shell/font.moved" ] \
        && ok "font: a file that is not the pinned zip is refused: nothing installed, $key kept, no move" || bad "font: sha refused" "$out"
    out=$(SPARK_SHELL_FONT_URL="file://$fz/none.zip" sh "$SH" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -qxF "todo   font         could not fetch Monaspace Neon: $keep until spark-shell on fetches it" && [ ! -e "$fdir/MonaspaceNeon-Regular.otf" ] && grep -qxF "$key=$was" "$cfg" \
        && ok "font: offline, a todo row and nothing installed, never a failure of on" || bad "font: offline" "$out"
    if [ "$(uname -s)" != Darwin ]; then
        grep -qx 'font=DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" && ok "font: offline, foot.ini keeps the old face" || bad "font: offline render" "$(grep -n '^font' "$HOME/.config/foot/foot.ini")"
    fi
else
    printf '  note font: curl not found; the fetch is not proven here\n'
fi
if command -v python3 >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
    # the fixture zip: the four faces, a fifth face and another family, which stay in it; and Monaspace's four other
    # curated faces, four styles each, which the faces row takes (#247)
    python3 -I -c 'import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w")
for s in ("Regular", "Bold", "Italic", "BoldItalic", "Light"):
    z.writestr("Static Fonts/Monaspace Neon/MonaspaceNeon-%s.otf" % s, "a fixture face, %s\n" % s)
for f in ("Argon", "Xenon", "Radon", "Krypton"):
    for s in ("Regular", "Bold", "Italic", "BoldItalic", "Light"):
        z.writestr("Static Fonts/Monaspace %s/Monaspace%s-%s.otf" % (f, f, s), "a fixture %s, %s\n" % (f, s))
z.writestr("Static Fonts/Other/Other-Regular.otf", "another family\n")
z.close()' "$fz/monaspace.zip"
    fsha=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$fz/monaspace.zip"; else shasum -a 256 "$fz/monaspace.zip"; fi | cut -d' ' -f1)
    for f in "$REPO"/*; do ln -s "$f" "$fz/repo/"; done
    rm "$fz/repo/spark-shell" "$fz/repo/src"; cp "$SH" "$fz/repo/spark-shell"; FX=$fz/repo/spark-shell; chmod +x "$FX"   # a real entry, so its REPO is the fixture's
    mkdir "$fz/repo/src"; for f in "$REPO"/src/*.sh; do ln -s "$f" "$fz/repo/src/"; done; rm "$fz/repo/src/font.sh"
    sed "s/^NEON_SHA256=[0-9a-f]*/NEON_SHA256=$fsha/" "$REPO/src/font.sh" > "$fz/repo/src/font.sh"
    [ "$(diff "$REPO/src/font.sh" "$fz/repo/src/font.sh" | grep -c '^[<>]')" = 2 ] && grep -q "^NEON_SHA256=$fsha " "$fz/repo/src/font.sh" && ok "font: the fixture copy differs from spark-shell by its pin alone" || bad "font: fixture pin" "$(diff "$REPO/src/font.sh" "$fz/repo/src/font.sh" | head -4)"
    export SPARK_SHELL_FONT_URL="file://$fz/monaspace.zip"
    out=$(sh "$FX" on --dry-run)
    printf '%s\n' "$out" | grep -qxF "would  font         fetch Monaspace Neon 1.400 from GitHub (56 MB), check its sha256 and put its four faces in $fdir" \
        && printf '%s\n' "$out" | grep -qxF "would  font         $key=$now, the new default face at your size ($old was the old one)" \
        && [ ! -e "$fdir/MonaspaceNeon-Regular.otf" ] && grep -qxF "$key=$was" "$cfg" \
        && ok "font: the dry run says the fetch and the move, and does neither" || bad "font: dry run" "$out"
    out=$(sh "$FX" on --yes 2>&1); installed=$out
    printf '%s\n' "$out" | grep -qxF "ok     font         Monaspace Neon 1.400 installed in $fdir, its sha256 checked" \
        && [ "$(cat "$fdir/MonaspaceNeon-Regular.otf")" = 'a fixture face, Regular' ] && [ "$(cat "$fdir/MonaspaceNeon-BoldItalic.otf")" = 'a fixture face, BoldItalic' ] \
        && [ ! -e "$fdir/MonaspaceNeon-Light.otf" ] && [ ! -e "$fdir/MonaspaceArgon-Regular.otf" ] && [ -z "$(find "$fdir" -name '*.new')" ] \
        && ok "font: on fetches the zip, checks its sha256 and puts the four faces foot uses in your fonts, nothing else" || bad "font: install" "$out $(ls -la "$fdir" 2>&1)"
    printf '%s\n' "$out" | grep -qxF "ok     font         $key=$now, the new default face at your size ($old was the old one)" && grep -qxF "$key=$now" "$cfg" && [ -e "$HOME/.local/state/spark-shell/font.moved" ] \
        && ok "font: $key on the old default face moves to Monaspace Neon at its size, once, with a row" || bad "font: the move" "$out $(cat "$cfg")"
    out=$(sh "$FX" on --yes 2>&1); printf '%s\n' "$out" | grep -Eq '^[a-z]+ +font ' && bad "font: a second on says a font row" "$out" || ok "font: a second on does nothing for the font"
    out=$(sh "$FX" on --dry-run); printf '%s\n' "$out" | grep -qxF "ok     font         Monaspace Neon is in $fdir" && ! printf '%s\n' "$out" | grep -q '^would  font' \
        && ok "font: the dry run after it says the font is in place" || bad "font: second dry run" "$out"
    if [ "$(uname -s)" = Darwin ]; then
        [ ! -s "$H/fc.log" ] && ok "font: no fontconfig cache on a Mac" || bad "font: mac fc-cache" "$(cat "$H/fc.log")"
        out=$(sh "$FX" font); [ "$out" = "font  MonaspaceNeon-Regular 18: Terminal.app's profile" ] && ok "font: Terminal.app's font is MonaspaceNeon-Regular, at the size you had" || bad "font: mac show" "$out"
        sed 's/^CONSOLE_FONT=.*/CONSOLE_FONT=/' "$cfg" > "$cfg.new" && mv "$cfg.new" "$cfg"
        out=$(sh "$FX" font); [ "$out" = "font  MonaspaceNeon-Regular 13: Terminal.app's profile (the default)" ] && ok "font: CONSOLE_FONT empty, Terminal.app's default is Monaspace Neon once it is installed" || bad "font: mac default" "$out"
        printf 'THEME=nord\n' >> "$cfg"
        out=$(SPARK_SHELL_NO_APPLY=1 sh "$FX" on --yes 2>&1)
        printf '%s\n' "$out" | grep -qxF "ok     terminal     Terminal.app's profile is the palette, in MonaspaceNeon-Regular 13" \
            && ok "font: the Terminal.app profile takes it just installed: the helper finds its file before Spotlight does (never applied here)" || bad "font: mac profile" "$out"
        out=$(SPARK_SHELL_NO_APPLY=1 sh "$FX" font MonaspaceNeon-Regular 15 2>&1); grep -qx 'CONSOLE_FONT=MonaspaceNeon-Regular 15' "$cfg" && ok "font MonaspaceNeon-Regular 15: the face is taken once it is in ~/Library/Fonts" || bad "font: mac verb" "$out"
        printf 'CONSOLE_FONT=Menlo-Regular 14\n' >> "$cfg"
        SPARK_SHELL_NO_APPLY=1 sh "$FX" on --yes >/dev/null 2>&1; grep -qx 'CONSOLE_FONT=Menlo-Regular 14' "$cfg" && ok "font: after the move, Menlo-Regular set again is a choice: on leaves it" || bad "font: mac choice" "$(cat "$cfg")"
    else
        grep -qxF "fc-cache -f $fdir" "$H/fc.log" && ok "font: fontconfig's cache is made for the folder (fc-cache -f)" || bad "font: fc-cache" "$(cat "$H/fc.log" 2>&1)"
        grep -qx 'font=Monaspace Neon:size=11,DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" && grep -q '^    font pango:Monaspace Neon 11$' "$HOME/.config/sway/config" \
            && ok "font: foot.ini names Monaspace Neon, then DejaVu Sans Mono for a glyph it lacks; the bar's font follows" || bad "font: renders" "$(grep -n 'font' "$HOME/.config/foot/foot.ini" "$HOME/.config/sway/config")"
        # the curated faces (#247): the four beside Neon, from the same zip, four styles each in a folder of their own
        fonts=$HOME/.local/share/fonts
        printf '%s\n' "$installed" | grep -qxF "ok     faces        Monaspace Argon, Xenon, Radon and Krypton installed in $fonts, the zip's sha256 checked" \
            && [ "$(cat "$fonts/monaspace-argon/MonaspaceArgon-Regular.otf")" = 'a fixture Argon, Regular' ] && [ "$(cat "$fonts/monaspace-krypton/MonaspaceKrypton-BoldItalic.otf")" = 'a fixture Krypton, BoldItalic' ] \
            && [ ! -e "$fonts/monaspace-xenon/MonaspaceXenon-Light.otf" ] && [ "$(find "$fonts" -name 'Other*' | wc -l | tr -d ' ')" = 0 ] && grep -qxF "fc-cache -f $fonts/monaspace-radon" "$H/fc.log" \
            && ok "faces: on puts Monaspace Argon, Xenon, Radon and Krypton beside Neon, the four styles each, from the zip the font row checked" || bad "faces: install" "$out $(ls -R "$fonts" 2>&1 | head -20)"
        out=$(sh "$FX" theme face xenon 2>&1); st=0; again=$(sh "$FX" theme face xenon 2>&1) || st=$?
        [ "$out" = "text in xenon $(printf '\302\267') new windows and the bar take it" ] && grep -qx 'FONT=Monaspace Xenon:size=11' "$cfg" \
            && grep -qx 'font=Monaspace Xenon:size=11,DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" && grep -q '^    font pango:Monaspace Xenon 11$' "$HOME/.config/sway/config" \
            && [ "$st" = 1 ] && [ "$again" = 'the text is in xenon already' ] \
            && ok "theme face xenon (#247): the face swapped, its size kept, foot and the bar in it; the face in use again refused" || bad "theme face" "$out | $st $again | $(grep -n 'font' "$HOME/.config/foot/foot.ini" "$cfg")"
        rc=0; out=$(sh "$FX" theme face comic 2>&1) || rc=$?; [ "$rc" = 1 ] && [ "$out" = 'face takes neon, argon, xenon, radon or krypton' ] && ok "theme face: a face not of the five is refused" || bad "theme face refuse" "rc=$rc $out"
        rm -rf "$fonts/monaspace-radon"; sh "$FX" theme face radon >/dev/null 2>&1
        grep -qx 'FONT=Monaspace Radon:size=11' "$cfg" && grep -qx 'font=Monaspace Neon:size=11,DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" \
            && ok "theme face: a face not installed yet shows in Neon, at its size, until on installs it" || bad "face missing" "$(grep -n 'font' "$HOME/.config/foot/foot.ini" "$cfg")"
        sh "$FX" on --yes >/dev/null 2>&1; [ -f "$fonts/monaspace-radon/MonaspaceRadon-Regular.otf" ] && grep -qx 'font=Monaspace Radon:size=11,DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" \
            && ok "faces: on installs the face that was missing, and foot takes it" || bad "face back" "$(ls "$fonts" 2>&1; grep -n 'font' "$HOME/.config/foot/foot.ini")"
        sh "$FX" theme face neon >/dev/null 2>&1
        out=$(sh "$FX" check || :); printf '%s\n' "$out" | grep -qx 'ok     desktop      sway and foot are installed and up to date' && ok "font: check's desktop row is ok with the font in place" || bad "font: check ok" "$(printf '%s\n' "$out" | grep desktop)"
        sed 's/^FONT=.*/FONT=DejaVu Sans Mono:size=13/' "$cfg" > "$cfg.new" && mv "$cfg.new" "$cfg"
        sh "$FX" on --yes >/dev/null 2>&1; grep -qx 'FONT=DejaVu Sans Mono:size=13' "$cfg" && grep -qx 'font=DejaVu Sans Mono:size=13' "$HOME/.config/foot/foot.ini" \
            && ok "font: after the move, DejaVu Sans Mono set again is a choice: on leaves it" || bad "font: choice" "$(cat "$cfg")"
        printf 'DESKTOP=sway\nFONT=Iosevka Term:size=12\n' > "$cfg"; rm -rf "$fdir" "$HOME/.local/state/spark-shell/font.moved"
        out=$(sh "$FX" on --yes 2>&1); [ ! -e "$fdir" ] && grep -qx 'FONT=Iosevka Term:size=12' "$cfg" && grep -qx 'font=Iosevka Term:size=12' "$HOME/.config/foot/foot.ini" \
            && ok "font: a FONT of your own stays yours: nothing fetched, nothing moved" || bad "font: yours" "$out $(cat "$cfg")"
        printf 'DESKTOP=sway\n' > "$cfg"
        SPARK_SHELL_FONT_URL=none sh "$SH" on --yes >/dev/null 2>&1; grep -qx 'font=DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" && grep -q '^    font pango:DejaVu Sans Mono 11$' "$HOME/.config/sway/config" \
            && ok "font: the default (no FONT line) before the font is installed: its size, in the old face" || bad "font: default missing" "$(grep -n 'font' "$HOME/.config/foot/foot.ini" "$HOME/.config/sway/config")"
        out=$(sh "$SH" check || :); printf '%s\n' "$out" | grep -qxF 'warn   desktop      Monaspace Neon is not installed, so foot draws DejaVu Sans Mono -- spark-shell on' && ok "font: check warns while foot draws the old face" || bad "font: check warn" "$(printf '%s\n' "$out" | grep desktop)"
        : > "$H/fc-neon"
        out=$(SPARK_SHELL_FONT_URL=none sh "$SH" on --yes 2>&1); grep -qx 'font=Monaspace Neon:size=11,DejaVu Sans Mono:size=11' "$HOME/.config/foot/foot.ini" && [ ! -e "$fdir" ] \
            && ok "font: one fontconfig finds elsewhere (a package's) is used as it is, nothing fetched" || bad "font: elsewhere" "$out $(grep -n '^font' "$HOME/.config/foot/foot.ini")"
        rm -f "$H/fc-neon"
        printf 'ID=void\n' > "$H/os-void"
        out=$(printf 'n\n' | SPARK_OS_RELEASE="$H/os-void" SPARK_SHELL_TEST_TTY=1 sh "$SH" on desktop 2>&1 || :)
        printf '%s\n' "$out" | grep -qx '  font         Monaspace Neon 1.400 from GitHub to your fonts, sha256 checked' && ok "warning: on desktop says the font's download where the family has no package (Void)" || bad "font: warning" "$out"
    fi
    export SPARK_SHELL_FONT_URL=none
else
    printf '  note font: python3 or curl not found; the install is not proven here\n'
fi

# --- follow: the login hook re-renders the look when theme.env changed
fresh
theme_fixture '#ff5555'
sh "$SH" on --yes >/dev/null
out=$(sh "$SH" follow)
[ -z "$out" ] && ok "follow: nothing to say right after on (the palette was seen)" || bad "follow after on" "$out"
theme_fixture '#ee8800'
out=$(sh "$SH" follow)
printf '%s\n' "$out" | grep -q '^spark-shell: [0-9]* files updated for the new palette\.$' && grep -q 'fg=colour3,bold' "$HOME/.tmux.conf" && grep -q "SPARK_ACCENT_SGR='1;33'" "$HOME/.config/spark-shell/sgr.sh" \
    && ok "follow: a changed palette re-renders the look, one line says so" || bad "follow changed" "$out"
out=$(sh "$SH" follow)
[ -z "$out" ] && ok "follow: quiet when the palette did not change since" || bad "follow quiet" "$out"
rm -f "$HOME/.config/spark/theme.env"
out=$(sh "$SH" follow)
printf '%s\n' "$out" | grep -q 'updated for the new palette' && grep -q 'fg=colour4,bold' "$HOME/.tmux.conf" && ok "follow: theme none (no theme.env) is a change too" || bad "follow none" "$out"
grep -q 'spark-shell follow' "$REPO/template/linux/.bash_profile" && grep -q 'spark-shell follow' "$REPO/template/macos/.zprofile" && ok "the login profiles run spark-shell follow" || bad "profiles follow"

# --- the wallpaper: a verb that sets and applies; gaps and a translucent foot
if [ "$(uname -s)" != Darwin ]; then
    fresh; desktop_stubs
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\nPROMPT_STYLE=full\n' > "$HOME/.config/spark-shell/config"
    theme_fixture '#ff5555'
    sh "$SH" on --yes >/dev/null
    sway=$HOME/.config/sway/config; foot=$HOME/.config/foot/foot.ini
    out=$(sh "$SH" theme wallpaper)
    printf '%s\n' "$out" | grep -q "^wallpaper default -- the ground, the palette's background a shade darker (#000000); it follows the palette\$" && ok "theme wallpaper (bare): the default is the forge" || bad "wallpaper bare default" "$out"
    [ ! -e "$REPO/gallery/wallpapers" ] && ok "wallpapers/: no picture ships with the repo; the ground is the default" || bad "wallpapers dir" "$(ls "$REPO/gallery/wallpapers")"
    sh "$SH" theme wallpaper none >/dev/null
    grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.95$' "$foot" && grep -q '^default_border normal 1$' "$sway" && grep -q '^client.focused *#ff5555 #ff5555 #000000 #[0-9a-f]\{6\}80 #ff5555$' "$sway" \
        && ok "wallpaper none: the ground (#35), the windows apart and as transparent as ALPHA says, their band and frame (the indicator is the accent, #47)" || bad "wallpaper none render" "$(grep -n 'bg\|gaps\|border' "$sway"; grep -n alpha "$foot")"
    out=$(sh "$SH" theme wallpaper)
    printf '%s\n' "$out" | grep -q '^wallpaper default -- the ground' && ok "theme wallpaper (bare): none is said as the ground" || bad "wallpaper bare" "$out"
    sh "$SH" theme wallpaper default >/dev/null
    grep -q '^WALLPAPER=default$' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps outer 8$' "$sway" && ok "theme wallpaper default: the ground again" || bad "wallpaper default" "$(grep -n 'bg\|gaps' "$sway")"
    pic="$HOME/pictures/one two.jpg"; mkdir -p "$HOME/pictures"; printf x > "$pic"
    out=$(sh "$SH" theme wallpaper "$pic")
    grep -q "^WALLPAPER=$pic\$" "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" \
        && ok "theme wallpaper PATH: WALLPAPER in the config, the other lines kept" || bad "wallpaper config" "$(cat "$HOME/.config/spark-shell/config")"
    grep -q "^output \* bg \"$pic\" fill\$" "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.95$' "$foot" \
        && ok "wallpaper PATH: sway fills it (quoted: a space in the path), gaps of 8, foot alpha 0.95" || bad "wallpaper render" "$(grep -n 'bg\|gaps' "$sway"; grep -n alpha "$foot")"
    printf '%s\n' "$out" | grep -q 'a running sway shows it now' && ok "theme wallpaper PATH: says what happens" || bad "wallpaper words" "$out"
    sh "$SH" theme wallpaper | grep -q "^wallpaper $pic\$" && ok "theme wallpaper (bare): names the picture" || bad "wallpaper bare after"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q "^  wall  picture *$pic\$" && ok "status: the wall row names the picture" || bad "status wall" "$(sh "$SH" status | grep wall)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     desktop' && ok "check: the desktop renders match with a wallpaper" || bad "check with wallpaper" "$(sh "$SH" check)"
    rm -f "$pic"
    out=$(sh "$SH" on --yes)
    printf '%s\n' "$out" | grep -q '^todo   wallpaper .*is missing -- the ground instead' && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^alpha=0.95$' "$foot" \
        && ok "a picture that went missing: a todo row, the ground, the transparency kept, never a black screen" || bad "missing wallpaper" "$out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  wall  missing' && ok "status: wall missing" || bad "status wall missing" "$(sh "$SH" status | grep wall)"
    rc=0; out=$(sh "$SH" theme wallpaper /nowhere/at/all.jpg 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'not a readable file' && ok "theme wallpaper: a path that is not there is refused" || bad "wallpaper refuse missing" "$out"
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell theme: /nowhere/at/all.jpg is not a readable file or a color\. Give a picture.s path, default (the ground), one of the drawings (skyline, fjord, forest, sunset, hills, dunes, orbit, ripples, contours, morning, meadow, kites, fields, grove, arches, shore, flight, embers, onsen, duck, reef, campfire, ufo, pigeons, garoa, horizon, watch, problem, continue, crossing), #rrggbb or one of these colors: black, white, gray, silver, navy, blue, teal, green, olive, maroon, red, purple, brown, orange$' \
        && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && ok "theme wallpaper: the refusal is one line that lists what is accepted" || bad "wallpaper refusal words" "$out"
    # a path from where you are, and a quoted ~: saved as the full path
    printf x > "$pic"; printf x > "$HOME/pictures/two.png"
    rc=0; out=$(cd "$HOME/pictures" && sh "$SH" theme wallpaper two.png 2>&1) || rc=$?
    full=$(cd "$HOME/pictures" && pwd)/two.png
    [ $rc = 0 ] && grep -qxF "WALLPAPER=$full" "$HOME/.config/spark-shell/config" && grep -qxF "output * bg \"$full\" fill" "$sway" \
        && ok "theme wallpaper x.png: a path from where you are is saved as the full path" || bad "wallpaper relative" "rc=$rc $out $(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    rc=0; out=$(cd "$HOME" && sh "$SH" theme wallpaper ./pictures/../pictures/two.png 2>&1) || rc=$?
    [ $rc = 0 ] && grep -qxF "WALLPAPER=$full" "$HOME/.config/spark-shell/config" && ok "theme wallpaper ./a/../a/x.png: the dots are resolved" || bad "wallpaper dots" "rc=$rc $out $(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    tl='~'   # a literal ~, on purpose: what a quoted one gives spark-shell
    rc=0; out=$(sh "$SH" theme wallpaper "$tl/pictures/one two.jpg" 2>&1) || rc=$?
    [ $rc = 0 ] && grep -qxF "WALLPAPER=$HOME/pictures/one two.jpg" "$HOME/.config/spark-shell/config" && ok "theme wallpaper '~/x.jpg': a quoted ~ is your home" || bad "wallpaper tilde" "rc=$rc $out $(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    rc=0; out=$(sh "$SH" theme wallpaper '~' 2>&1) || rc=$?
    rc2=0; out2=$(sh "$SH" theme wallpaper "$HOME/pictures" 2>&1) || rc2=$?
    [ $rc = 1 ] && [ $rc2 = 1 ] && printf '%s\n' "$out" "$out2" | grep -c 'is not a readable file' | grep -qx 2 && ok "theme wallpaper: a directory is not a picture (~ alone too)" || bad "wallpaper dir" "$out $out2"
    rm -f "$pic"
    # a plain color: #rrggbb or a name, saved as #rrggbb; a palette with a drawing of its own replaces it (#25)
    out=$(sh "$SH" theme wallpaper navy)
    grep -qx 'WALLPAPER=#000080' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000080 solid_color$' "$sway" && grep -q '^gaps inner 8$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.95$' "$foot" && grep -q '^        background #000000f2$' "$sway" \
        && ok "theme wallpaper navy: #000080 in the config, sway paints it solid, with the gaps and the translucent foot and bar a picture has" || bad "wallpaper navy" "$out $(grep -n 'bg\|gaps\|background' "$sway"; grep -n alpha "$foot")"
    [ "$(printf '%s\n' "$out" | tail -1)" = "a running sway shows #000080 now, and the windows keep their transparency, 5%; a palette with a drawing of its own replaces it" ] && ok "theme wallpaper navy: says what happens" || bad "wallpaper navy words" "$out"
    [ "$(sh "$SH" theme wallpaper)" = "wallpaper #000080 -- a plain color; a palette with a drawing of its own replaces it" ] && ok "theme wallpaper (bare): names the color" || bad "wallpaper bare color" "$(sh "$SH" theme wallpaper)"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  wall  color  *#000080, a plain color; a palette with a drawing of its own replaces it$' && ok "status: the wall row names the color" || bad "status wall color" "$(printf '%s\n' "$st" | grep wall)"
    printf '%s\n' "$(sh "$SH" on --yes)" | grep -q '^todo   wallpaper' && bad "a color is reported missing" || ok "on: a color is never a missing picture"
    sh "$SH" theme dracula >/dev/null
    grep -qx 'WALLPAPER=dunes' "$HOME/.config/spark-shell/config" && grep -qF "output * bg \"$REPO/gallery/wallpaper/dunes.png\" fill" "$sway" && grep -q '^background=282a36$' "$foot" && ok "a palette with a drawing of its own replaces a color (dracula brings dunes, foot takes dracula) (#25)" || bad "color under a palette" "$(grep WALLPAPER "$HOME/.config/spark-shell/config"; grep -n 'output' "$sway"; grep -n '^background' "$foot")"
    sh "$SH" theme wallpaper default >/dev/null
    grep -q '^output \* bg #1c1e26 solid_color$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.95$' "$foot" && ok "theme wallpaper default: the ground follows the palette (dracula's background a shade darker, #1c1e26)" || bad "ground dracula" "$(grep -n 'bg\|gaps' "$sway")"
    [ "$(sh "$SH" theme wallpaper)" = "wallpaper default -- the ground, the palette's background a shade darker (#1c1e26); it follows the palette" ] && ok "theme wallpaper (bare): names the ground and its hex" || bad "wallpaper bare ground" "$(sh "$SH" theme wallpaper)"
    theme_fixture '#ff5555'   # the fixture's palette again, for the rows below
    for c in black:000000 white:ffffff gray:808080 grey:808080 silver:c0c0c0 navy:000080 blue:0000ff teal:008080 green:008000 olive:808000 maroon:800000 red:ff0000 purple:800080 brown:a52a2a orange:ffa500 Teal:008080; do
        sh "$SH" theme wallpaper "${c%%:*}" >/dev/null && grep -qx "WALLPAPER=#${c#*:}" "$HOME/.config/spark-shell/config" || printf '%s\n' "$c"
    done > "$H/names.bad"
    [ ! -s "$H/names.bad" ] && ok "theme wallpaper NAME: the 15 names are the CSS colors" || bad "wallpaper names" "$(cat "$H/names.bad")"
    # the wallpapers spark-shell ships (issue 10): stored by name, drawn from the clone's own file
    sh "$SH" theme wallpaper skyline >/dev/null
    if command -v rsvg-convert >/dev/null 2>&1 || command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then skypic="$HOME/.local/state/spark-shell/wallpapers/skyline-dracula.png"; skysaid="wallpaper skyline -- drawn in dracula"; else skypic="$REPO/gallery/wallpaper/skyline.png"; skysaid="wallpaper skyline"; fi   # under dracula: drawn in dracula where gdk-pixbuf is, the clone's picture where it is not
    grep -qx 'WALLPAPER=skyline' "$HOME/.config/spark-shell/config" && grep -qF "output * bg \"$skypic\" fill" "$sway" && grep -q '^gaps outer 8$' "$sway" \
        && [ "$(sh "$SH" theme wallpaper)" = "$skysaid" ] \
        && ok "theme wallpaper skyline: the name in the config, sway draws the drawing (in the palette in use where gdk-pixbuf is) with the gaps a picture has" || bad "wallpaper shipped" "$(grep WALLPAPER "$HOME/.config/spark-shell/config"); $(grep -n ' bg ' "$sway")"
    sh "$SH" theme wallpaper default >/dev/null
    sh "$SH" theme wallpaper '#ABCdef' >/dev/null
    grep -qx 'WALLPAPER=#abcdef' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #abcdef solid_color$' "$sway" && ok "theme wallpaper #ABCdef: saved and drawn as #abcdef" || bad "wallpaper hex" "$(grep WALLPAPER "$HOME/.config/spark-shell/config")"
    for w in chartreuse '#12345' '#1234567' 'abcdef' '#ggg000'; do
        rc=0; out=$(sh "$SH" theme wallpaper "$w" 2>&1) || rc=$?
        [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'is not a readable file or a color' || printf '%s\n' "$w"
    done > "$H/words.bad"
    [ ! -s "$H/words.bad" ] && grep -qx 'WALLPAPER=#abcdef' "$HOME/.config/spark-shell/config" && ok "theme wallpaper: a word that is no color is refused, the config untouched" || bad "wallpaper bad colors" "$(cat "$H/words.bad")"
    out=$(sh "$SH" theme wallpaper none)
    grep -q '^WALLPAPER=default$' "$HOME/.config/spark-shell/config" && grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.95$' "$foot" \
        && [ "$(printf '%s\n' "$out" | tail -1)" = "the ground is back: none is the ground now, and the windows keep their transparency, 5%" ] \
        && ok "theme wallpaper none: the ground, and the windows keep their transparency and their gaps (#35)" || bad "wallpaper none" "$out $(grep -n 'alpha\|gaps' "$foot" "$sway")"
    printf 'DESKTOP=sway\nWALLPAPER=none\nALPHA=0.7\n' > "$HOME/.config/spark-shell/config"; sh "$SH" on --yes >/dev/null
    grep -q '^output \* bg #000000 solid_color$' "$sway" && grep -q '^gaps outer 8$' "$sway" && grep -q '^alpha=0.7$' "$foot" && ok "WALLPAPER=none in a config of before: read as the ground, the transparency kept (#35)" || bad "wallpaper none read" "$(grep -n 'alpha\|gaps\|bg' "$foot" "$sway")"
    printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" theme wallpaper "$HOME/.config/spark-shell/config" 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'spark-shell on desktop first' && ok "theme wallpaper: refused without the desktop" || bad "wallpaper without desktop" "$out"
    printf 'DESKTOP=sway\nALPHA=0.7\n' > "$HOME/.config/spark-shell/config"; sh "$SH" on --yes >/dev/null
    grep -q '^alpha=0.7$' "$foot" && ok "ALPHA in the config lands in foot.ini" || bad "alpha key" "$(grep -n alpha "$foot")"
    sed 's/^ALPHA=.*/ALPHA=2/' "$HOME/.config/spark-shell/config" > "$HOME/c.tmp"; mv "$HOME/c.tmp" "$HOME/.config/spark-shell/config"
    rc=0; out=$(sh "$SH" on --yes 2>&1) || rc=$?
    [ $rc = 1 ] && printf '%s\n' "$out" | grep -q 'ALPHA=2' && ok "ALPHA outside 0..1 is refused in one line" || bad "alpha refuse" "$out"
fi
grep -q '@FONT@' "$REPO/template/.config/foot/foot.ini" && grep -q '@FOOT_ALPHA@' "$REPO/template/.config/foot/foot.ini" \
    && grep -q 'output \* bg @WALL_BG@' "$REPO/template/.config/sway/config" && grep -q '^gaps inner @GAPS_INNER@' "$REPO/template/.config/sway/config" \
    && ok "templates: foot.ini and sway/config carry placeholders, the hex and the wallpaper land at render time" || bad "desktop template placeholders"
grep -q '^bar {' "$REPO/template/.config/sway/config" && grep -q '^    position @BAR_POSITION@$' "$REPO/template/.config/sway/config" && grep -q '^    tray_output @BAR_TRAY@$' "$REPO/template/.config/sway/config" && grep -q '^    status_command @REPO@/spark-shell bar status' "$REPO/template/.config/sway/config" && ok "sway template: a bar where BAR_POSITION puts it, its tray as BAR_TRAY says, drawn by spark-shell bar status" || bad "sway template: the bar block" "$(grep -n '^bar\|position\|status_command' "$REPO/template/.config/sway/config")"
grep -q '^xwayland enable$' "$REPO/template/.config/sway/config" && ! grep -q '^xwayland disable' "$REPO/template/.config/sway/config" && ok "sway template: Xwayland on, so Steam and other X11 apps open (#170)" || bad "sway xwayland"
[ "$(grep -v '^$' "$REPO/template/.config/sway/config" | tail -1)" = 'include @HOME@/.config/sway/config.d/*' ] && ok "sway template: your own lines in config.d, read last so they win (#170)" || bad "sway own lines" "$(tail -3 "$REPO/template/.config/sway/config")"
grep -qxF 'bindsym $mod+Ctrl+Left exec @REPO@/spark-shell desktop window left' "$REPO/template/.config/sway/config" && grep -qxF 'bindsym $mod+Shift+space exec @REPO@/spark-shell desktop window float' "$REPO/template/.config/sway/config" \
    && grep -qxF 'bindsym $mod+minus exec @REPO@/spark-shell desktop pad keys' "$REPO/template/.config/sway/config" && grep -qxF 'bindsym $mod+m exec @REPO@/spark-shell desktop window min' "$REPO/template/.config/sway/config" \
    && grep -qxF 'bindsym $mod+Left focus left' "$REPO/template/.config/sway/config" && grep -qxF 'bindsym $mod+h focus left' "$REPO/template/.config/sway/config" && grep -qxF 'bindsym $mod+Tab exec @REPO@/spark-shell desktop window back' "$REPO/template/.config/sway/config" \
    && grep -qxF 'bindsym $mod+Shift+Left exec @REPO@/spark-shell desktop window move left' "$REPO/template/.config/sway/config" && grep -qxF 'bindsym $mod+q kill' "$REPO/template/.config/sway/config" && ! grep -q 'mod+Shift+q \|mod+Mod1+Left' "$REPO/template/.config/sway/config" \
    && ok "sway template: Super+arrow the focus, Super+Ctrl+arrow places the window, Super+Shift+arrow moves it, Super+Tab the window before, Super+m the pad, Super+q closes (v0.140)" || bad "sway window keys" "$(grep -n 'mod+Left\|mod+Shift+space\|mod+h ' "$REPO/template/.config/sway/config")"
grep -qxF 'for_window [tiling] mark --add _spark-shell.new, exec @REPO@/spark-shell desktop window new' "$REPO/template/.config/sway/config" \
    && ok "sway template: a window that opens tiled wears the new mark and runs desktop window new, one rule (#262)" || bad "sway new window rule" "$(grep -n 'for_window' "$REPO/template/.config/sway/config")"
swt=$REPO/template/.config/sway/config
grep -qxF 'bindsym $mod+Prior workspace prev' "$swt" && grep -qxF 'bindsym $mod+Next workspace next' "$swt" \
    && grep -qxF 'bindsym $mod+Shift+Next move container to workspace next, workspace next' "$swt" && grep -qxF 'bindsym $mod+Shift+Prior move container to workspace prev, workspace prev' "$swt" \
    && [ -z "$(awk '$1 == "bindsym" { print $2 }' "$swt" | sort | uniq -d)" ] \
    && ok "sway template: Super+PageUp/PageDown the workspace before or after, with Shift the window along; no key bound twice (#185)" || bad "sway workspace keys" "$(awk '$1 == "bindsym" { print $2 }' "$swt" | sort | uniq -d)"
grep -v '^#' "$REPO/template/.config/sway/config" | grep -q 'tmux' && bad "sway: a window starts tmux (it runs the login shell)" || ok "sway template: a new foot runs the login shell, never tmux"
grep -q "^exec sh -c '\$term -e @REPO@/spark-shell desktop --first; swaymsg exit'$" "$REPO/template/.config/sway/config" && ok "sway template: the desktop ends with its first terminal (desktop --first: the keys once, then your shell)" || bad "sway template: exec line" "$(grep -n '^exec' "$REPO/template/.config/sway/config")"
sway_t=$REPO/template/.config/sway/config
grep -qxF 'bindsym $mod+space exec @REPO@/spark-shell desktop voice press' "$sway_t" && grep -qxF 'bindsym --release $mod+space exec @REPO@/spark-shell desktop voice release' "$sway_t" && ! grep -q '^bindsym \$mod+[ds] ' "$sway_t" && ok "sway template: Super+Space is the sole home entry, pressed and released (v0.144)" || bad "sway template: home entry"
! grep -q 'spark-chat\|mod+p ' "$sway_t" && ok "sway template: no chat window of its own and no Super+p: one window, two keys" || bad "sway template: old keys" "$(grep -n 'spark-chat\|mod+p ' "$sway_t")"
grep -q '^bindsym \$mod+Shift+s layout stacking$' "$sway_t" && ! grep -q '^bindsym \$mod+s layout' "$sway_t" && ok "sway template: stacking moved to Super+Shift+s, Super+s is spark's" || bad "sway template: stacking key" "$(grep -n 'layout stacking' "$sway_t")"

# --- the AI one key away: desktop --chat execs spark chat with the palette's exports (all OSes)
fresh
cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
{ printf '%s\n' "$@"; echo "SPARK_ACCENT_SGR=${SPARK_ACCENT_SGR:-unset}"; } > "$HOME/spark.argv"
EOF
chmod +x "$H/.local/bin/spark"
theme_fixture '#ff5555'
sh "$SH" on --yes >/dev/null
st=0; out=$(sh "$SH" panel chat 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(head -1 "$H/spark.argv")" = chat ] && grep -q "^SPARK_ACCENT_SGR=1;91$" "$H/spark.argv" \
    && ok "terminal panel chat: execs spark chat, sgr.sh sourced first (the accent's SGR 1;91 reaches it)" || bad "desktop --chat" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
rm -f "$H/spark.argv"; st=0; out=$(sh "$SH" panel spark chat 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(head -1 "$H/spark.argv")" = chat ] && ok "panel spark chat: the row's step execs spark chat the same way" || bad "panel spark chat" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
mv "$H/.local/bin/spark" "$H/spark.away"
st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" panel chat 2>&1 </dev/null) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^spark is not installed, so there is no chat' && printf '%s\n' "$out" | grep -q 'Enter closes' \
    && ok "desktop --chat without spark: the window says so and waits for Enter, exit 0" || bad "desktop --chat no spark" "st=$st $out"
st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" panel chat 2>&1 </dev/null) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^spark is not installed, so there is no chat' && ok "panel chat without spark: the same line, exit 0" || bad "panel chat no spark" "st=$st $out"

# --- the first hour: desktop keys any time, the card once in the first window (all OSes)
keys=$(sh "$SH" desktop keys)
[ "$(printf '%s\n' "$keys" | wc -l | tr -d ' ')" -ge 8 ] && ok "desktop keys: the template's key sentences, eight or more" || bad "desktop keys count" "$keys"
printf '%s\n' "$keys" | grep -vq '\.$' && bad "desktop keys: a line that is not a whole sentence" "$(printf '%s\n' "$keys" | grep -v '\.$')" || ok "desktop keys: every line is a sentence ending with a period"
printf '%s\n' "$keys" | grep -q '^Super+space home.open.$' && ok "desktop keys: the configured home entry is listed" || bad "desktop keys home.open" "$keys"
grep -q 'desktop-keys.json' "$REPO/README.md" && grep -q 'home-keys.json' "$REPO/README.md" && ok "README documents both named binding maps" || bad "README key maps"

[ ! -e "$H/.local/state/spark-shell/desktop.seen" ] && ok "desktop keys: no stamp written" || bad "desktop keys wrote the stamp"
printf '#!/bin/sh\necho shell-stub\n' > "$H/.local/bin/shellstub"; chmod +x "$H/.local/bin/shellstub"
out=$(SHELL=$H/.local/bin/shellstub sh "$SH" desktop --first)
[ "$out" = shell-stub ] && [ -f "$H/.local/state/spark-shell/desktop.seen" ] && [ "$(printf '%s\n' "$out" | tail -1)" = shell-stub ] \
    && ok "desktop --first: the stamp written, no card in the shell (the splash is a window, when there is one), then the shell" || bad "desktop --first" "$out"
out=$(SHELL=$H/.local/bin/shellstub sh "$SH" desktop --first)
[ "$out" = shell-stub ] && [ ! -f "$H/first.splash" ] && ok "desktop --first again: the shell alone" || bad "desktop --first twice" "$out"
printf '#!/bin/sh\necho "${PROMPT-unset} ${DESKTOP-unset} ${FONT-unset}"\n' > "$H/.local/bin/envstub"; chmod +x "$H/.local/bin/envstub"
out=$(SHELL=$H/.local/bin/envstub sh "$SH" desktop --first)
[ "$out" = 'unset unset unset' ] && ok "desktop --first: the config's exports (PROMPT, DESKTOP, FONT) never reach your shell" || bad "desktop --first env" "$out"

fi

# --- 15. the login screen: getty's own, a login on tty1 starts the desktop
if want 15; then
# No root file and no unit for the desktop on Debian or Arch: on desktop
# writes DESKTOP=sway and renders sway and foot, and the rc file starts
# the desktop at a login on tty1. systemctl is a stub that logs (it must
# never be asked for greetd). The tty is the stub fresh puts on PATH.
fresh
desktop_stubs
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"
printf 'PROMPT_STYLE=full\nDESKTOP=none\n' > "$HOME/.config/spark-shell/config"
st=$(PATH=$H/.local/bin:$sys sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next  spark .*Install spark, the local AI: github.com/forgewright-ai/spark\.$' && ok "status: next says install spark first, without spark on PATH" || bad "status next spark" "$(printf '%s\n' "$st" | grep next)"
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" on desktop --yes 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS' \
        && ok "macOS: on desktop refuses, one line, exit 1" || bad "macOS on desktop" "st=$st $out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && ok "macOS: on desktop wrote nothing" || bad "macOS on desktop wrote" "$(cat "$HOME/.config/spark-shell/config")"
else
    printf '#!/bin/sh\necho "$*" >> "%s/units.log"\n[ "$1" != is-enabled ] || exit 1\n' "$H" > "$H/.local/bin/systemctl"; chmod +x "$H/.local/bin/systemctl"
    out=$(sh "$SH" on desktop --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       DESKTOP=sway' && printf '%s\n' "$out" | grep -q '^would  look .*sway/config' \
        && ok "on desktop --dry-run: would write DESKTOP=sway and render sway" || bad "on desktop dry-run rows" "$out"
    grep -q 'DESKTOP=none' "$HOME/.config/spark-shell/config" && [ ! -e "$H/root/etc" ] && [ ! -e "$H/.config/sway" ] && ok "on desktop --dry-run: wrote nothing (the config kept)" || bad "on desktop dry-run wrote" "$(find "$H/root" "$H/.config")"
    printf '%s\n' "$out" | grep -Eq '^(would|todo|FAIL|warn) +font' && bad "on desktop --dry-run acts on a font" "$out" || ok "on desktop --dry-run: no font row acts"
    out2=$(sh "$SH" desktop on --dry-run)
    [ "$out2" = "$out" ] && ok "desktop on is on desktop: the same dry run, row for row" || bad "desktop on alias" "$out2"
    out=$(sh "$SH" on desktop --yes 2>&1); st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" \
        && [ "$(grep -c '^DESKTOP=' "$HOME/.config/spark-shell/config")" -eq 1 ] \
        && ok "on desktop: DESKTOP=sway written into the config, the other line kept" || bad "on desktop config" "st=$st $(cat "$HOME/.config/spark-shell/config")"
    [ -f "$HOME/.config/foot/foot.ini" ] && [ -f "$HOME/.config/sway/config" ] && ok "on desktop: foot.ini and sway/config rendered" || bad "on desktop user renders" "$out"
    [ ! -e "$H/root/etc/greetd" ] && [ ! -e "$H/root/etc/systemd" ] && ! grep -q 'greetd\|getty' "$H/units.log" 2>/dev/null \
        && ok "on desktop: no root file, no greetd, getty left alone" || bad "on desktop root" "$(find "$H/root" 2>&1; cat "$H/units.log" 2>&1)"
    printf '%s\n' "$out" | grep -qi 'greet\|login box' && bad "on desktop names greetd or a login box" "$out" || ok "on desktop: no word of greetd or a login box"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  desktop sway .*(log in on tty1 to start it)$' && ok "status: the desktop row says log in on tty1 to start it" || bad "status desktop row" "$(printf '%s\n' "$st" | grep desktop)"
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    st=$(env -u WAYLAND_DISPLAY sh "$SH" status); printf '%s\n' "$st" | grep -q '^  next' && bad "status: a next row with nothing off" "$(printf '%s\n' "$st" | grep next)" || ok "status: no next row when the desktop is ready (Debian, Arch: no reboot, no root)"
    rm -f "$H/.local/bin/spark"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot' && ! printf '%s\n' "$out" | grep -q 'greeter' && ok "check: ok desktop, no greeter row" || bad "check desktop" "$out"
    out=$(sh "$SH" on --dry-run)
    printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on --dry-run after on desktop: Nothing to do" || bad "on desktop idempotence" "$out"
    out=$(sh "$SH" off desktop --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       DESKTOP=none' && printf '%s\n' "$out" | grep -q '^would  restore .*sway/config' && printf '%s\n' "$out" | grep -q '^would  restore .*foot/foot\.ini' \
        && ok "off desktop --dry-run: would rows for the config and the two renders" || bad "off desktop dry-run rows" "$out"
    grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && [ -f "$HOME/.config/sway/config" ] && ok "off desktop --dry-run: touched nothing" || bad "off desktop dry-run wrote" "$(cat "$HOME/.config/spark-shell/config")"
    out=$(sh "$SH" off desktop)
    grep -q '^DESKTOP=none$' "$HOME/.config/spark-shell/config" && grep -q '^PROMPT_STYLE=full$' "$HOME/.config/spark-shell/config" && ok "off desktop: DESKTOP=none written, the other line kept" || bad "off desktop config" "$(cat "$HOME/.config/spark-shell/config")"
    [ ! -e "$HOME/.config/foot/foot.ini" ] && [ ! -e "$HOME/.config/sway/config" ] && ok "off desktop: the two user renders are gone" || bad "off desktop user renders" "$(ls -R "$HOME/.config")"
    [ ! -e "$HOME/.config/fontconfig/conf.d/50-spark-shell.conf" ] && ok "off desktop: the wifi bars' fontconfig rule is gone too (#43)" || bad "off desktop fontconfig" "$(ls -R "$HOME/.config/fontconfig" 2>&1)"
    printf '%s\n' "$out" | grep -q 'packages stay installed' && ok "off desktop: packages stay, said so" || bad "off desktop closing" "$out"
    out=$(sh "$SH" desktop off)
    printf '%s\n' "$out" | grep -Eq '^ok +(login|desktop|restore) ' && bad "desktop off (a spelling of off desktop) twice acts twice" "$out" || ok "desktop off, the spelling, twice: nothing to undo, nothing said"
    # the old login screen, still running until the next boot, runs `desktop` on Enter: your shell
    printf '#!/bin/sh\necho "shell-stub $* ${DESKTOP-unset}"\n' > "$H/.local/bin/offshell"; chmod +x "$H/.local/bin/offshell"
    st=0; out=$(TEST_TTY=/dev/tty1 SHELL=$H/.local/bin/offshell env -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^The desktop is off (spark-shell on desktop brings it back)\. This is your shell\.$' && [ "$(printf '%s\n' "$out" | tail -1)" = 'shell-stub -l unset' ] \
        && ok "desktop with the desktop off, from a console: one line, then your login shell (never a dead end)" || bad "desktop off console landing" "st=$st $out"
    # no theme.env: the desktop still starts from a console, and a word with no console is refused
    fresh; desktop_stubs
    sh "$SH" on desktop --yes >/dev/null
    out=$(TEST_TTY=/dev/tty1 env -u WAYLAND_DISPLAY sh "$SH" desktop 2>&1); st=$?
    [ "$st" -eq 0 ] && ok "desktop (start now) starts sway from a console" || bad "desktop start" "$out"
    out=$(env -u TEST_TTY -u SWAYSOCK sh "$SH" desktop sideways --windows 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^spark-shell desktop: needs a console login' && [ ! -e "$HOME/.local/state/spark-shell/layout.pending" ] \
        && ok "desktop --windows: a word with no desktop and no console is refused in one line, nothing left pending" || bad "desktop word no console" "$out"
fi
[ ! -e "$REPO/template/etc/greetd" ] && [ ! -e "$REPO/template/etc/systemd/system/greetd.service.d" ] && [ -f "$REPO/template/etc/systemd/system/spark-shell-console.service" ] \
    && ok "template/etc: no greetd file, the console palette's unit stays" || bad "template/etc greetd" "$(find "$REPO/template/etc" -type f)"
grep -q 'PKG_GREETER' "$REPO"/distro/*.env && bad "distro/*.env: a PKG_GREETER line" || ok "distro/*.env: no greeter packages"
grep -rq 'font' "$REPO/template/etc" && bad "a root template names a font" || ok "template/etc: no font word"
grep -v '^ *#' "$SRC" | grep -q 'XDG_VTNR\|tuigreet\|greet_background' && bad "spark-shell reads XDG_VTNR or draws tuigreet" "$(grep -n 'XDG_VTNR\|tuigreet' "$SRC" | grep -v ':[ ]*#' | head -3)" || ok "spark-shell: no XDG_VTNR, no tuigreet in the code (the tty says console)"

# the rc file: a login on tty1 starts the desktop, nothing else does.
# The block is run alone in an interactive bash, with stubs for tty and
# spark-shell; `exit` after a desktop that ran ends that login.
bp=$REPO/template/linux/.bash_profile
awk '/^# The desktop at a login on tty1/ {on = 1} on {print} on && /^fi$/ {exit}' "$bp" > "$H/autostart.sh"
grep -q '"\$(tty 2>/dev/null)" = /dev/tty1' "$H/autostart.sh" && grep -q 'spark-shell desktop && exit' "$H/autostart.sh" && grep -q 'WAYLAND_DISPLAY' "$H/autostart.sh" \
    && ok ".bash_profile: one block, tty1 exactly, no WAYLAND_DISPLAY, then spark-shell desktop" || bad ".bash_profile block" "$(cat "$H/autostart.sh")"
l_pal=$(grep -n 'console-colors' "$bp" | head -1 | cut -d: -f1); l_auto=$(grep -n '^# The desktop at a login on tty1' "$bp" | cut -d: -f1)
[ -n "$l_pal" ] && [ -n "$l_auto" ] && [ "$l_auto" -gt "$l_pal" ] && ok ".bash_profile: the desktop starts after the palette lines" || bad ".bash_profile order" "palette $l_pal desktop $l_auto"
if command -v bash >/dev/null 2>&1; then
    ab=$H/ab; mkdir -p "$ab/bin" "$ab/.config/spark-shell"
    printf '#!/bin/sh\necho "${TEST_TTY:-not a tty}"\n[ -n "${TEST_TTY:-}" ]\n' > "$ab/bin/tty"
    printf '#!/bin/sh\necho "spark-shell $*" >> "%s/ran"\n[ ! -e "%s/fails" ]\n' "$ab" "$ab" > "$ab/bin/spark-shell"
    chmod +x "$ab/bin/tty" "$ab/bin/spark-shell"
    autostart() {   # autostart TTY DESKTOP [VAR=VALUE] -> what ran, then "after" when the shell went on
        rm -f "$ab/ran"; printf 'DESKTOP=%s\n' "$2" > "$ab/.config/spark-shell/config"
        env -u WAYLAND_DISPLAY HOME="$ab" XDG_CONFIG_HOME="$ab/.config" TEST_TTY="$1" PATH="$ab/bin:$PATH" ${3:+"$3"} \
            bash --norc --noprofile -i -c ". '$H/autostart.sh'; echo after" 2>/dev/null </dev/null
        cat "$ab/ran" 2>/dev/null || true
    }
    [ "$(autostart /dev/tty1 sway)" = 'spark-shell desktop' ] && ok ".bash_profile: a login on tty1 with DESKTOP=sway starts the desktop, and leaving it ends the login" || bad "autostart tty1" "$(autostart /dev/tty1 sway)"
    [ "$(autostart /dev/tty2 sway)" = after ] && ok ".bash_profile: tty2 (Alt+F2) stays a plain shell" || bad "autostart tty2" "$(autostart /dev/tty2 sway)"
    [ "$(autostart /dev/tty10 sway)" = after ] && ok ".bash_profile: tty10 is not tty1" || bad "autostart tty10" "$(autostart /dev/tty10 sway)"
    [ "$(autostart /dev/pts/0 sway)" = after ] && ok ".bash_profile: ssh and terminal windows (/dev/pts) never start it" || bad "autostart pts" "$(autostart /dev/pts/0 sway)"
    [ "$(autostart /dev/tty1 none)" = after ] && ok ".bash_profile: DESKTOP=none on tty1 is a plain shell" || bad "autostart none" "$(autostart /dev/tty1 none)"
    [ "$(autostart /dev/tty1 sway WAYLAND_DISPLAY=wayland-1)" = after ] && ok ".bash_profile: inside a desktop it never starts another" || bad "autostart wayland" "$(autostart /dev/tty1 sway WAYLAND_DISPLAY=wayland-1)"
    : > "$ab/fails"
    [ "$(autostart /dev/tty1 sway | paste -sd' ' -)" = 'after spark-shell desktop' ] && ok ".bash_profile: a desktop that cannot start leaves its reason and the shell goes on" || bad "autostart fails" "$(autostart /dev/tty1 sway)"
fi

fi

# --- 16. desks: a desk from your words -----------------------------------
if want 16; then
# stubs: spark logs its argv and answers one fixed desk (main gimp-3.0 at
# 70, two firefox pages, micro in a terminal, and ghostapp, which this machine
# lacks); swaymsg logs every line it is sent and answers the queries --
# its tree holds one window per exec line already sent, so the wait after
# an exec returns at once. jq is the real one. The inventory is a fixture
# of desktop entries under XDG_DATA_HOME; XDG_DATA_DIRS points at an empty
# dir so the machine's own entries stay out. The Linux half is guarded by
# uname like 14 and 15.
fresh
desktop_stubs
layout_stubs
need='photo editing for instagram and x'
argv=$H/.local/state/spark.argv; swlog=$H/.local/state/swaymsg.log
layout_last=$H/.local/state/spark-shell/layout.last; layout_pending=$H/.local/state/spark-shell/layout.pending
desks=$H/.config/spark-shell/layouts
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on --yes >/dev/null
if [ "$(uname -s)" = Darwin ]; then
    na_form() {   # na_form WORDS... -> one line, na, exit 1
        st=0; out=$(sh "$SH" desktop "$@" 2>&1) || st=$?
        [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS, which has its own desktop$' \
            && ok "macOS: desktop $1 refuses, na, one line, exit 1" || bad "macOS desktop $*" "st=$st $out"
    }
    na_form apps   # a desk itself plays as rooms here (18)
    [ ! -e "$layout_last" ] && [ ! -e "$layout_pending" ] && [ ! -e "$desks" ] && [ ! -e "$argv" ] && [ ! -e "$swlog" ] \
        && ok "macOS: the picker wrote nothing (no layout.last, no pending, no desks dir, spark and swaymsg never called)" || bad "macOS desk wrote" "$(find "$H/.local/state" "$H/.config/spark-shell")"
else
    export SWAYSOCK=$H/sway.sock WAYLAND_DISPLAY=wayland-1    # inside the desktop
    mkdir -p "$H/.local/state/spark-shell"; printf '{"words":"old"}\n' > "$H/.local/state/spark-shell/desk.last"   # v0.137 wrote desk.*: moved to the new name on the next run
    sh "$SH" status >/dev/null 2>&1 || :
    [ ! -e "$H/.local/state/spark-shell/desk.last" ] && [ "$(cat "$layout_last" 2>/dev/null)" = '{"words":"old"}' ] \
        && ok "layout.last: a desk.last of v0.137 is moved to the new name on the next run, its content kept" || bad "desk.last moved" "$(ls "$H/.local/state/spark-shell" 2>&1)"
    rm -f "$layout_last"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  layouts none .*spark-shell layout "WORDS" makes one' && ok "status: the layouts row says none before any" || bad "status layouts none" "$(printf '%s\n' "$st" | grep layouts)"
    out=$(sh "$SH" layout)
    printf '%s\n' "$out" | grep -q '^no saved layouts yet -- try: spark-shell layout "' && ok "layout (bare): no saved layouts yet, a try line" || bad "layout list empty" "$out"
    # the need: spark asked once, the lines played, the missing app named
    st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
        && ok "layout WORDS: partial failure for the missing app, the layout> line and why line" || bad "desk need" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  ghostapp is not on this machine -- laid out without it$' && ok "desktop WORDS: an app the model named that is not here is said" || bad "ghostapp line" "$out"
    printf '%s\n' "$out" | grep -q '^  refused  exec ghostapp  (ghostapp is not on this machine)$' && ok "desktop WORDS: its exec line is refused with the reason" || bad "ghostapp refused" "$out"
    printf '%s\n' "$out" | grep -q '^spark-shell layout: the layout did not finish; some windows may already be open$' && ok "layout WORDS: missing app leaves an honest partial failure" || bad "on workspace" "$out"
    printf '%s\n' "$out" | grep -q 'no window after\|sway refused' && bad "desktop WORDS: a wait ran out or sway refused" "$out" || ok "desktop WORDS: every window came up, sway took every line"
    [ -f "$argv" ] && [ "$(sed -n '1,3p' "$argv" | paste -sd ' ' -)" = 'edit --type json' ] && grep -qx -- '--name' "$argv" && grep -qx layout.json "$argv" && grep -qx -- '--about' "$argv" \
        && ok "spark: asked as spark edit --type json --name layout.json --about" || bad "spark argv" "$(cat "$argv" 2>&1)"
    [ "$(tail -1 "$argv")" = "write the layout for this need: $need" ] && ok "spark: the prompt ends with the need's words" || bad "spark prompt" "$(tail -1 "$argv")"
    grep -q 'on one screen, 2560x1440\. ' "$argv" && ok "spark: the about says one screen and its size (from swaymsg get_outputs)" || bad "about screen" "$(grep -o 'on one screen[^.]*' "$argv")"
    grep -q 'screen is left\|"screen"' "$argv" && bad "about: the screen rule or field reached the model with one screen" "$(grep -o 'A window is on one screen[^.]*' "$argv")" || ok "spark: one screen, no screen field and no screen rule in the about"
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ok "inventory: a desktop entry's Comment (gimp-3.0)" || bad "inventory gimp" "$(grep -o 'gimp-3.0: [^;]*' "$argv")"
    grep -q 'firefox: Web Browser' "$argv" && ok "inventory: GenericName when there is no Comment (firefox)" || bad "inventory firefox" "$(grep -o 'firefox: [^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory: Name when there is nothing else (micro)" || bad "inventory micro" "$(grep -o 'micro: [^;]*' "$argv")"
    grep -q ', terminal' "$argv" && bad "inventory: the terminal mark reached the model" "$(grep -o '[^;]*, terminal[^;]*' "$argv")" || ok "inventory: the terminal mark is kept from the model (sway's business)"
    grep -qi 'hidden' "$argv" && bad "inventory: a NoDisplay entry is in" "$(grep -oi '[^;]*hidden[^;]*' "$argv")" || ok "inventory: a NoDisplay entry is dropped"
    grep -q 'for:' "$argv" && bad "inventory: the keyword for counts as a program" "$(grep -o 'for: [^;]*' "$argv")" || ok "inventory: a need word that is a keyword (for) is not a program"
    grep -q 'foot:\|footclient:\|xdg-open:' "$argv" && bad "inventory: foot or xdg-open is in" || ok "inventory: no foot, footclient or xdg-open"
    printf '%s\n' 'workspace number 3' 'rename workspace to "3 photo editing for"' 'exec gimp-3.0' splith 'exec firefox https://instagram.com' splitv 'exec firefox https://x.com' 'exec foot -e micro' 'exec player --idle --' 'focus left' 'resize set width 70 ppt' > "$H/expected.lines"
    sed 's/^rename workspace to .*/rename workspace to "3 studio"/' "$H/expected.lines" > "$H/expected.studio"   # a saved layout names its workspace after itself
    cmp -s "$swlog" "$H/expected.lines" && ok "sway got exactly the ten lines in order (main, the workspace named after the words, splith, side, splitv, micro in foot, focus left, resize 70 ppt; ghostapp never)" || bad "swaymsg lines" "$(cat "$swlog" 2>&1)"
    jq -e --arg w "$need" '(keys_unsorted[0] == "words") and .words == $w and (.why | startswith("photo work in gimp")) and .main.app == "gimp-3.0" and .main.width == 70 and (.side | length) == 5 and .side[0].args == "https://instagram.com"' "$layout_last" >/dev/null 2>&1 \
        && ok "layout.last: the model's answer as JSON, the words first, then why, main and side as answered" || bad "layout.last" "$(cat "$layout_last" 2>&1)"
    grep -q '^exec\|^workspace\|^#' "$layout_last" && bad "layout.last holds sway lines or a header" "$(head -3 "$layout_last")" || ok "layout.last: no sway line, no header (rendered when it opens)"
    # the inventory: unmarked, every app with a desktop entry and never a package
    # (the fake pacman answers -Qi and -Ql, as sbom_collect asks); marked (the
    # apps file), exactly those names -- an entry's words, a package's words or
    # yours; a shell never, a name that is nowhere silently left out
    cat > "$H/.local/bin/pacman" <<'EOF'
#!/bin/sh
case ${1:-} in
    -Qi) printf 'Name            : reader\nVersion         : 1.0-1\nLicenses        : GPL2\nDescription     : Text-based Web browser\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : bash\nVersion         : 5.2-1\nLicenses        : GPL3\nDescription     : The GNU Bourne Again shell\nInstall Reason  : Explicitly installed\n\n'
         printf 'Name            : linux\nVersion         : 6.1-1\nLicenses        : GPL2\nDescription     : The Linux kernel\nInstall Reason  : Explicitly installed\n\n' ;;
    -Ql) printf 'reader /usr/bin/reader\nbash /usr/bin/bash\nlinux /boot/vmlinuz-linux\n' ;;
esac
EOF
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"; chmod +x "$H/.local/bin/pacman" "$H/.local/bin/reader"
    printf 'ID=arch\n' > "$H/os-arch"
    SPARK_OS_RELEASE=$H/os-arch SWAYSOCK=/tmp/x sh "$SH" layout "$need" >/dev/null 2>&1 || true
    grep -q 'micro: Micro' "$argv" && ! grep -q 'reader:' "$argv" && ! grep -q 'bash:' "$argv" \
        && ok "inventory unmarked: the entries (micro), never a package (reader, bash)" || bad "inventory unmarked" "$(grep -o 'micro: [^;]*\|reader:[^;]*\|bash:[^;]*' "$argv")"
    apps_file=$HOME/.config/spark-shell/apps
    printf '# the apps a desk may open\nreader: my browser\nmicro\nbash\nghost\n' > "$apps_file"
    SPARK_OS_RELEASE=$H/os-arch SWAYSOCK=/tmp/x sh "$SH" layout "$need" >/dev/null 2>&1 || true
    grep -q 'reader: my browser' "$argv" && ok "inventory marked: a package with your note, in your words" || bad "inventory marked note" "$(grep -o 'reader[^;]*' "$argv")"
    grep -q 'micro: Micro' "$argv" && ok "inventory marked: a marked entry in the entry's words" || bad "inventory marked entry" "$(grep -o 'micro[^;]*' "$argv")"
    grep -q 'firefox' "$argv" && bad "inventory marked: an unmarked entry is in" "$(grep -o 'firefox[^;]*' "$argv")" || ok "inventory marked: an unmarked entry (firefox) is out"
    grep -q 'bash:' "$argv" && bad "inventory marked: a shell is offered to the model" "$(grep -o 'bash:[^;]*' "$argv")" || ok "inventory marked: a shell is never offered"
    grep -q 'ghost' "$argv" && bad "inventory marked: a name that is nowhere is in" "$(grep -o 'ghost[^;]*' "$argv")" || ok "inventory marked: a name that is nowhere is silently left out"
    rm -f "$apps_file" "$H/.local/bin/pacman" "$H/.local/bin/reader"
    # the old Super+d spelling: the panel with the layouts first; no terminal, so the list as text
    : > "$swlog"; SEP=$(printf '\302\267'); GO=$(printf '\342\226\270')
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" layout --ask </dev/null 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = "layout     none saved yet" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "  layout     none saved: ask at the prompt or save this workspace	layout show" ] && [ ! -s "$swlog" ] \
        && ok "layout --ask: the panel with the layouts first, as text without a terminal; nothing played" || bad "ask form" "st=$st $out $(head -2 "$swlog")"
    printf '%s' "$out" | grep -q "$(printf '\033')" && bad "the pulse reached a pipe" "unexpected escape byte" || ok "no pulse on a pipe (a tty only, like spark's)"
    # keep, list, replay, status, forget
    out=$(sh "$SH" layout save studio)
    printf '%s\n' "$out" | grep -q "^saved studio -- spark-shell layout studio opens it ($desks/studio)\$" && [ "$(jq -S 'del(.suggested)' "$layout_last")" = "$(jq -S . "$desks/studio")" ] && ! jq -e 'has("suggested")' "$desks/studio" >/dev/null \
        && ok "layout save NAME: layout.last saved as layouts/NAME without what was only suggested, said in one line" || bad "keep" "$out"
    # keep takes all the words; bare keep names the desk after its own words
    out=$(sh "$SH" layout save Photo Work, please)
    printf '%s\n' "$out" | grep -q "^saved photo-work-please -- " && [ -f "$desks/photo-work-please" ] && ok "layout save WORDS: every word, lowercased, joined by -" || bad "keep words" "$out $(ls "$desks")"
    out=$(sh "$SH" layout save)
    printf '%s\n' "$out" | grep -q "^saved photo-editing-for-instagram-and-x -- " && [ -f "$desks/photo-editing-for-instagram-and-x" ] && ok "layout save (bare): named after the layout's own words" || bad "keep bare" "$out $(ls "$desks")"
    rm -f "$desks/photo-work-please" "$desks/photo-editing-for-instagram-and-x"
    out=$(sh "$SH" layout)
    printf '%s\n' "$out" | grep -q "^  studio  *$need\$" && printf '%s\n' "$out" | grep -q '^spark-shell layout NAME opens one -- layout save \[NAME\] saves the last layout, layout delete NAME deletes one$' \
        && ok "layout (bare): lists the saved layout with its words" || bad "desk list" "$out"
    rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" layout studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp' && printf '%s\n' "$out" | grep -q 'the layout did not finish' && cmp -s "$swlog" "$H/expected.studio" \
        && ok "layout NAME: replays the same lines on the next free workspace (3), named studio, with its why" || bad "replay" "st=$st $out $(cat "$swlog" 2>&1)"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout Studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && head -1 "$swlog" | grep -q '^workspace number 3$' && [ ! -e "$argv" ] && ok "layout WORDS that name a saved layout (any case): a replay, no model" || bad "replay by words" "st=$st $out"
    : > "$swlog"
    st=0; out=$(ASKED=1 SWAYSOCK=/tmp/x sh "$SH" panel layout open studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && head -1 "$swlog" | grep -q '^\[app_id=spark-dialog\] move container to workspace number 3$' && ! tail -1 "$swlog" | grep -q '^\[app_id=spark-dialog\] focus$' \
        && printf '%s\n' "$out" | grep -q 'photo work in gimp' && ! printf '%s\n' "$out" | grep -q 'layout> ' \
        && ok "a partial saved layout keeps the panel open with the failure, the why said, no layout> line" || bad "replay ask" "st=$st $out $(cat "$swlog")"
    st=0; out=$(ASKED=1 SWAYSOCK=/tmp/x sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q 'the layout did not finish' && ok "a partial layout asked from the panel reports failure" || bad "asked closing" "st=$st $out"
    rm -f "$argv"   # that one asked spark; the replay tests below must see no call
    out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "layout     1 saved $SEP last: $need" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$GO layout     studio	layout open studio" ] \
        && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "  layout     rename studio	layout rename studio" ] \
        && ok "panel layout --list: the count and the last one on the title, a saved layout by the name it was saved under (#51) and its rename row (#54)" || bad "panel layout list" "$out"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout open nowhere 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: layout: no saved layout named nowhere' ] && ok "panel layout open NAME: a name that is not saved is refused in one line" || bad "layout open gate" "st=$st $out"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout new 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: layout: new takes the words for it' ] && ok "panel layout new: without words, refused in one line" || bad "layout new gate" "st=$st $out"
    [ ! -e "$argv" ] && ok "layout NAME: no model call" || bad "replay called spark" "$(cat "$argv")"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  layouts 1 saved  *studio (spark-shell layout NAME)$' && ok "status: the layouts row counts and names the saved ones" || bad "status layouts" "$(printf '%s\n' "$st" | grep layouts)"
    # a new name for a saved layout, made as a save makes one; its lines in the history follow it (#54)
    kh=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell/layout.history; mkdir -p "$(dirname "$kh")"; printf '%s\tstudio\n' "$(date +%s)" >> "$kh"
    out=$(sh "$SH" layout rename studio Photo Studio)
    [ "$out" = "studio renamed to photo-studio" ] && [ -f "$desks/photo-studio" ] && [ ! -e "$desks/studio" ] \
        && grep -q '	photo-studio$' "$kh" && ! grep -q '	studio$' "$kh" \
        && ok "layout rename NAME NEW: the file and its history lines under the new name, said in one line (#54)" || bad "rename" "$out $(ls "$desks") $(cat "$kh")"
    st=0; out=$(sh "$SH" layout rename studio x 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: no saved layout named studio" ] && ok "layout rename: a name not saved is refused in one line" || bad "rename missing" "st=$st $out"
    st=0; out=$(sh "$SH" layout rename photo-studio Photo Studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: photo-studio is its name already" ] && ok "layout rename to its own name: refused" || bad "rename same" "st=$st $out"
    sh "$SH" layout rename photo-studio studio >/dev/null
    out=$(sh "$SH" layout delete studio)
    [ "$out" = "deleted studio" ] && [ ! -e "$desks/studio" ] && ok "layout delete NAME: gone, one line" || bad "delete" "$out"
    # a named app twice with the same args is the model's padding: once; main fullscreen fills the screen once the window is there
    mv "$H/.local/bin/spark" "$H/spark.keep"
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"the browser, full\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"args\\": \\"\\", \\"fullscreen\\": true}, \\"side\\": [{\\"app\\": \\"firefox\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "firefox fullscreen" 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(grep -c '^exec firefox' "$swlog")" = 1 ] && [ "$(grep -A1 '^exec firefox' "$swlog" | sed -n 2p)" = 'fullscreen enable' ] && ! grep -q '^splith' "$swlog" \
        && ok "layout: firefox named twice opens once; fullscreen true on main sends fullscreen enable right after its window" || bad "layout once full" "st=$st $out $(cat "$swlog")"
    # the words decide what the machine can read in them: fullscreen when they say so (the model said false), and workspace N
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"the editor\\", \\"main\\": {\\"app\\": \\"micro\\", \\"args\\": \\"\\", \\"fullscreen\\": false}, \\"side\\": []}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "micro workspace 7 fullscreen" 2>&1) || st=$?
    [ "$st" -eq 0 ] && head -1 "$swlog" | grep -q '^workspace number 7$' && grep -q '^fullscreen enable$' "$swlog" && [ "$(jq -r .main.fullscreen "$layout_last")" = true ] \
        && ok "layout WORDS with workspace 7 and fullscreen: that workspace, and fullscreen, by the words themselves (the model had said false)" || bad "words decide" "st=$st $out $(cat "$swlog")"
    # every window tied to words of the need (its quote): notes -> micro stays, firefox stays, a shell for "fullscreen" or for nothing is padding and only suggested
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"notes beside the browser\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"quote\\": \\"Firefox\\", \\"args\\": \\"\\"}, \\"side\\": [{\\"app\\": \\"micro\\", \\"quote\\": \\"notes\\", \\"args\\": \\"\\"}, {\\"app\\": \\"shell\\", \\"quote\\": \\"fullscreen\\", \\"args\\": \\"\\"}, {\\"app\\": \\"btop\\", \\"quote\\": \\"\\", \\"args\\": \\"\\"}, {\\"app\\": \\"player\\", \\"quote\\": \\"some music\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "notes and Firefox fullscreen" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^exec firefox' "$swlog" && grep -q '^exec foot -e micro' "$swlog" && ! grep -q 'btop\|player\|exec foot$' "$swlog" && printf '%s\n' "$out" | grep -q 'also suggested: shell and player' \
        && ok "layout: a window tied to words of the need opens (micro for notes); one tied to the layout's own word, to nothing, or to words the need lacks is padding, only suggested (btop is not even on this list)" || bad "grounded" "st=$st $out $(cat "$swlog")"
    # his layout (#45): "a terminal window" asks for a terminal, so the shell the model ties to those words opens; terminal grounds a shell and no other window
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"three side by side\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"quote\\": \\"firefox\\", \\"args\\": \\"\\"}, \\"side\\": [{\\"app\\": \\"micro\\", \\"quote\\": \\"micro\\", \\"args\\": \\"\\"}, {\\"app\\": \\"shell\\", \\"quote\\": \\"a terminal window\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "firefox, micro, a terminal window" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^exec firefox' "$swlog" && grep -q '^exec foot -e micro' "$swlog" && grep -q '^exec foot$' "$swlog" && ! printf '%s\n' "$out" | grep -q 'also suggested' \
        && ok "layout: \"a terminal window\" grounds the shell the model ties to it, so a terminal opens beside firefox and micro (#45)" || bad "terminal grounds a shell" "st=$st $out $(cat "$swlog")"
    # what spark also suggested is one Enter away: a row per app, opening it on this workspace, gone once taken
    printf '#!/bin/sh\nprintf "{\\"why\\": \\"notes beside the browser\\", \\"main\\": {\\"app\\": \\"firefox\\", \\"args\\": \\"\\"}, \\"side\\": [{\\"app\\": \\"micro\\", \\"args\\": \\"\\"}]}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "notes and firefox" 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q 'also suggested: micro' && [ "$(jq -r '.suggested | join(",")' "$layout_last")" = micro ] && sh "$SH" panel layout --list | grep -q "also open micro	layout add micro$" \
        && ok "layout: what spark also suggested is kept with the last layout and offered as a panel row" || bad "suggested row" "st=$st $out $(jq -c . "$layout_last")"
    : > "$swlog"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout add micro 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'opened micro' ] && grep -q '^exec foot -e micro' "$swlog" && ! sh "$SH" panel layout --list | grep -q 'also open micro' \
        && ok "panel layout add NAME: the suggested app opens on this workspace, and its row is gone" || bad "suggested add" "st=$st $out $(cat "$swlog")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel layout add gimp 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: layout: gimp was not suggested for the last layout' ] && ok "panel layout add: an app that was not suggested is refused in one line" || bad "suggested gate" "st=$st $out"
    mv "$H/spark.keep" "$H/.local/bin/spark"; : > "$swlog"
    # the editor the system names may be a windowed application (#115): it opens as itself, no terminal window around it
    printf '[Desktop Entry]\nName=Text Editor\nExec=gedit %%U\nType=Application\n' > "$apps/gedit.desktop"; printf '#!/bin/sh\n:\n' > "$H/.local/bin/gedit"; chmod +x "$H/.local/bin/gedit"
    echo gedit.desktop > "$HOME/text-app"
    printf '{"why": "notes", "main": {"app": "editor", "args": "notes.txt"}, "side": []}\n' > "$HOME/answer.json"
    : > "$swlog"; st=0; out=$(sh "$SH" layout "notes in the editor" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx 'exec gedit notes.txt' "$swlog" && ! grep -q 'foot -e gedit' "$swlog" \
        && ok "layout: a windowed editor (the system names gedit's entry, no Terminal=true) opens as itself, no terminal around it (#115)" || bad "windowed editor" "st=$st $out $(cat "$swlog")"
    rm -f "$HOME/text-app" "$HOME/answer.json" "$apps/gedit.desktop" "$H/.local/bin/gedit"; : > "$swlog"
    st=0; out=$(sh "$SH" layout delete studio 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: no saved layout named studio" ] && ok "layout delete NAME twice: refused in one line" || bad "delete twice" "st=$st $out"
    printf 'workspace number 1\nexec firefox\n' > "$desks/mine"
    st=0; out=$(sh "$SH" layout delete mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && [ "$out" = "spark-shell layout: $desks/mine is not a layout spark-shell made (one JSON object: words, why, main, side) -- left alone." ] && [ -f "$desks/mine" ] \
        && ok "layout delete NAME: a file that is not one JSON object is refused, named, and left in place" || bad "forget yours" "st=$st $out"
    st=0; out=$(sh "$SH" layout mine 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q 'left alone\.$' && ok "layout NAME on a file that is not a layout: refused, left alone" || bad "open yours" "st=$st $out"
    # a desk kept before v0.36 (sway lines under a header): refused on open and on forget, the file named, the words to make it again
    printf '# desk: news and mail -- rendered by spark-shell (spark-shell desktop keep NAME keeps it)\nworkspace number 1\nexec firefox\n' > "$desks/old"
    old_why="spark-shell layout: $desks/old is a layout of the old shape (sway lines). spark-shell layout \"news and mail\" makes it again, then spark-shell layout save saves it."
    st=0; out=$(sh "$SH" layout old 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "$old_why" ] && ok "layout NAME on a file of the old shape: one sentence names the file and the words that make it again" || bad "open old" "st=$st $out"
    st=0; out=$(sh "$SH" layout delete old 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "$old_why" ] && [ -f "$desks/old" ] && ok "layout delete NAME on a file of the old shape: the same sentence, the file left" || bad "forget old" "st=$st $out"
    rm -f "$desks/old"
    cp "$layout_last" "$H/layout.last.json"; printf '# desk: old -- rendered by spark-shell\nworkspace number 1\n' > "$layout_last"
    st=0; out=$(sh "$SH" layout save 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^spark-shell layout: $layout_last is a layout of the old shape" && ok "layout save with a layout.last of the old shape: refused, the file named" || bad "save old" "st=$st $out"
    cp "$H/layout.last.json" "$layout_last"
    st=0; out=$(sh "$SH" layout save a b 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^saved a-b -- ' && [ -f "$desks/a-b" ] && ok "layout save: words with a space become one name (a-b)" || bad "save name" "st=$st $out"
    rm -f "$desks/a-b"
    # the gate on a kept desk edited by hand: every rendered line read, the bad ones named, the rest runs
    cat > "$desks/gate" <<'EOF'
{"words": "the gate", "main": {"app": "rm", "args": "x"},
 "side": [{"app": "gimp-3.0", "args": "$(id)"}, {"app": "sudo", "args": "ls"}, {"app": "firefox", "args": "a|b"}, {"app": "firefox", "args": "https://x, exec rm y"}, {"app": "micro", "args": "notes.txt"}]}
EOF
    rm -f "$swlog"
    st=0; out=$(sh "$SH" layout gate 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | grep -c '^  refused  ')" -eq 4 ] && ok "gate: four lines refused, remaining windows open with partial failure" || bad "gate count" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^  rm x$' && ok "gate: a kept desk you edited may open a program the machine has (rm x ran; it is yours)" || bad "gate rm" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec gimp-3.0 $(id)  (shell syntax' && printf '%s\n' "$out" | grep -qF '  refused  exec firefox a|b  (shell syntax' \
        && ok "gate: shell syntax (\$(id), a pipe) never reaches sh -c" || bad "gate syntax" "$out"
    printf '%s\n' "$out" | grep -qF '  refused  exec firefox https://x, exec rm y  (a comma starts a second sway command)' \
        && ok "gate: a comma in an exec is refused (sway would run the rest as its own command)" || bad "gate comma" "$out"
    printf '%s\n' "$out" | grep -qE '^  refused  exec (foot -e )?sudo ls  \(sudo is not an app\)$' && ok "gate: sudo is not an app (in foot when this machine has a sudo, plain when not)" || bad "gate sudo" "$out"
    printf '%s\n' 'workspace number 3' 'rename workspace to "3 gate"' 'exec foot -e rm x' 'splith' 'exec foot -e micro notes.txt' 'focus left' 'resize set width 70 ppt' > "$H/expected.gate"
    cmp -s "$swlog" "$H/expected.gate" && ok "gate: sway got the workspace line, the two good execs and their layout, nothing else" || bad "gate lines" "$(cat "$swlog" 2>&1)"
    # a kept desk may open any program the machine has (you kept it); the model's answer may not
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"; chmod +x "$H/.local/bin/reader"
    printf '{"words": "a reader you kept", "main": {"app": "reader"}, "side": [{"app": "sudo", "args": "ls"}]}\n' > "$desks/kept-reader"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout kept-reader 2>&1) || st=$?
    [ "$st" -eq 1 ] && grep -q '^exec foot -e reader$' "$swlog" && printf '%s\n' "$out" | grep -qE '^  refused  exec (foot -e )?sudo ls  \(sudo is not an app\)$' \
        && ok "a kept desk: a program on the machine but not in the inventory opens; sudo never" || bad "kept gate" "st=$st $out $(cat "$swlog")"
    rm -f "$desks/kept-reader" "$H/.local/bin/reader"
    # the gate reads a line as sh does, and a model's words past the app are pages and files (v0.129.3)
    gate_answer() { printf '%s\n' "$1" > "$HOME/answer.json"; : > "$swlog"; st=0; out=$(sh "$SH" layout "read the news in firefox" 2>&1) || st=$?; rm -f "$HOME/answer.json"; }
    gate_one() { jq -cn --arg a "$1" --arg g "$2" '{main: {app: "firefox", quote: "firefox"}, side: [{app: $a, args: $g, quote: "read the news"}]}'; }
    gate_answer "$(gate_one "X=/firefox sh -c \"touch $H/pwned\"" '')"
    ! grep -q 'X=/firefox' "$swlog" && printf '%s\n' "$out" | grep -qF '(a variable before a program is shell syntax)' \
        && ok "gate: a first word with a = is a variable, and the program after it is what sh runs: refused" || bad "gate variable" "st=$st $out $(cat "$swlog")"
    gate_answer "$(gate_one /tmp/nowhere/firefox '')"
    ! grep -q nowhere "$swlog" && printf '%s\n' "$out" | grep -qF '(an app is named, not a path)' \
        && ok "gate: a model's app is a name, never a path whose last part is an allowed name" || bad "gate path" "st=$st $out $(cat "$swlog")"
    gate_answer "$(gate_one firefox --renderer-cmd-prefix=/tmp/a)"
    ! grep -q 'renderer-cmd-prefix' "$swlog" && printf '%s\n' "$out" | grep -qF '(a page or a file, not a flag)' \
        && ok "gate: a flag in a model's args is an app's own way to run a command: refused" || bad "gate flag" "st=$st $out $(cat "$swlog")"
    gate_answer "$(gate_one 'firefox --renderer-cmd-prefix=/tmp/a' '')"
    ! grep -q 'renderer-cmd-prefix' "$swlog" && ok "gate: a flag written into a model's app word: refused the same" || bad "gate flag in app" "st=$st $out $(cat "$swlog")"
    gate_answer "$(gate_one micro '-c "term curl -o /tmp/a http://x.invalid/a"')"
    ! grep -q 'term curl' "$swlog" && ok "gate: a terminal app's flags from a model: refused in foot -e too" || bad "gate term flag" "st=$st $out $(cat "$swlog")"
    gate_answer "$(gate_one firefox 'https://x.com/?a=1')"
    grep -qxF 'exec firefox https://x.com/?a=1' "$swlog" && ok "gate: a page with = and ? in it is still a page" || bad "gate page" "st=$st $out $(cat "$swlog")"
    # a layout in the history is the model's answer, kept with no act of yours: it stays to the model's rule; a saved one is yours
    printf '#!/bin/sh\n:\n' > "$H/.local/bin/reader"; chmod +x "$H/.local/bin/reader"
    gate_answer '{"main": {"app": "firefox", "quote": "firefox"}, "side": [{"app": "reader", "quote": "read the news"}]}'
    _gk=$(ls -t "$H/.local/state/spark-shell/layouts" | head -1)
    : > "$swlog"; st=0; out=$(sh "$SH" layout "$_gk" 2>&1) || st=$?
    ! grep -q reader "$swlog" && printf '%s\n' "$out" | grep -qF '(reader is not one of the allowed apps' \
        && ok "gate: a window refused when the model named it is refused again from the history" || bad "gate history" "st=$st $_gk $out $(cat "$swlog")"
    rm -f "$H/.local/bin/reader"
    # a window that never comes (mpv with nothing to play): the split meant for it is skipped,
    # so the next window lands beside the main one instead of cutting it
    printf '{"words": "gone", "main": {"app": "micro", "width": 70}, "side": [{"app": "gone"}, {"app": "firefox"}]}\n' > "$desks/gone"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout gone 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  gone -- no window$' && printf '%s\n' "$out" | grep -q '^  micro$' && printf '%s\n' "$out" | grep -q '^  firefox$' \
        && ! printf '%s\n' "$out" | grep -q 'splitv\|focus left\|resize set' \
        && ok "a window that never comes: said in the app's own words; no sway grammar on the screen" || bad "gone window" "st=$st $out"
    : > "$swlog"
    st=0; out=$(sh "$SH" layout gone -v 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  skipped  splitv  (no window to split)$' && printf '%s\n' "$out" | grep -q '^  exec foot -e micro$' \
        && ok "-v after the words is a flag, not a word: the sway lines and the skipped split shown" || bad "gone verbose" "st=$st $out"
    printf '%s\n' 'workspace number 3' 'rename workspace to "3 gone"' 'exec foot -e micro' 'splith' 'exec gone' 'exec firefox' 'focus left' 'resize set width 70 ppt' > "$H/expected.gone"
    cmp -s "$swlog" "$H/expected.gone" && ok "a window that never comes: sway never got the splitv" || bad "gone lines" "$(cat "$swlog" 2>&1)"
    # two screens: the brief says them and the rule; each screen its own workspace, the main's first,
    # focus output before each; the outputs' make, model and serial never reach the model
    printf '{"words":"ruled", "main":{"app":"micro","floating":true,"border":"pixel"},"side":[]}\n' > "$desks/ruled"
    : > "$swlog"; out=$(sh "$SH" layout ruled 2>&1)
    grep -qxF '[con_id=1000] floating enable' "$swlog" && grep -qxF '[con_id=1000] border pixel' "$swlog" && ! grep -q for_window "$swlog" \
        && ok "saved window rules: native actions target only the new container, no lasting rule" || bad "window rules" "$out $(cat "$swlog")"
    printf '{"words":"missing rule", "main":{"app":"gone","floating":true},"side":[]}\n' > "$desks/missing-rule"
    : > "$swlog"; st=0; out=$(sh "$SH" layout missing-rule 2>&1) || st=$?
    [ "$st" -eq 1 ] && ! grep -q floating "$swlog" && printf '%s\n' "$out" | grep -q 'window rule skipped' \
        && ok "saved window rules: no new window means no setting on an existing one" || bad "missing window rule" "$out $(cat "$swlog")"
    touch "$H/two-screens"; rm -f "$argv" "$swlog"
    st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q 'on screens: left 2560x1440, right 1920x1080\. ' "$argv" && grep -q ' A window is on one screen; screen is left or right; one screen unless the need names two or the work needs two\. ' "$argv" \
        && grep -q '"screen": "left"' "$argv" && ok "two screens: the brief names them left to right with their sizes, the rule, the screen field" || bad "two screens brief" "st=$st $(grep -o 'on screens[^.]*' "$argv") $out"
    grep -q 'Fakemake\|Fakemodel\|SN000' "$argv" && bad "two screens: an output's make, model or serial reached the model" "$(grep -o '[^ ]*Fake[^ ]*\|SN000[0-9]' "$argv" | head -3)" || ok "two screens: the outputs' make, model and serial never reach the model"
    printf '%s\n' 'focus output DP-1' 'workspace number 3' 'rename workspace to "3 photo editing for"' 'exec gimp-3.0' splith 'exec foot -e micro' 'focus left' 'resize set width 70 ppt' 'focus output HDMI-A-1' 'workspace number 4' 'rename workspace to "4 photo editing for"' 'exec firefox https://instagram.com' > "$H/expected.two"
    cmp -s "$swlog" "$H/expected.two" && ok "two screens: the main's group first (focus output, workspace 3, main, micro beside it, sized), then the right screen's (focus output, workspace 4, firefox)" || bad "two screens lines" "$(cat "$swlog" 2>&1)"
    printf '%s\n' "$out" | grep -q '^on workspace 3 and 4 -- spark-shell layout save NAME saves it$' && ok "two screens: the closing line says both workspaces" || bad "two screens closing" "$out"
    printf '%s\n' "$out" | grep -q 'is not here' && bad "two screens: a screen that is here was said to be missing" "$(printf '%s\n' "$out" | grep 'is not here')" || ok "two screens: both named screens are here, no line says one is missing"
    grep -q 'workspace .* output\|floating\|sticky' "$swlog" && bad "two screens: a line that pins (workspace N output, floating, sticky)" "$(grep 'output\|floating\|sticky' "$swlog")" || ok "two screens: nothing pins a window (no workspace N output, no floating, no sticky)"
    sh "$SH" layout save two >/dev/null
    jq -e '.main.screen == "left" and .side[0].screen == "right" and (.side[1] | has("screen") | not)' "$desks/two" >/dev/null 2>&1 && ok "two screens: the kept desk carries screen on main and one side entry, as answered" || bad "two kept" "$(cat "$desks/two")"
    rm -f "$H/two-screens"; : > "$swlog"
    st=0; out=$(sh "$SH" layout two 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  the right screen is not here -- all on DP-1$' && ! printf '%s\n' "$out" | grep -q 'all on *$' && [ "$(grep -c '^workspace number' "$swlog")" -eq 1 ] && ! grep -q '^focus output' "$swlog" \
        && printf '%s\n' "$out" | grep -q '^on workspace 3 -- the saved layout two$' && ok "a desk kept on two screens opens on one: said in one line, one workspace, no focus output" || bad "two on one" "st=$st $out $(cat "$swlog")"
    printf '{"words": "nine", "main": {"app": "micro", "screen": "DP-9"}, "side": [{"app": "firefox", "screen": "right"}]}\n' > "$desks/nine"
    touch "$H/two-screens"; : > "$swlog"
    st=0; out=$(sh "$SH" layout nine 2>&1) || st=$?
    printf '%s\n' 'focus output DP-1' 'workspace number 3' 'rename workspace to "3 nine"' 'exec foot -e micro' 'focus output HDMI-A-1' 'workspace number 4' 'rename workspace to "4 nine"' 'exec firefox' > "$H/expected.nine"
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  the DP-9 screen is not here -- all on DP-1$' && cmp -s "$swlog" "$H/expected.nine" \
        && ok "a kept screen name that is not here (DP-9) maps to the first screen; a side on the right keeps its own" || bad "nine" "st=$st $out $(cat "$swlog")"
    st=0; out=$(sh "$SH" layout nine -v 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  focus output HDMI-A-1$' && ok "-v shows the focus output lines" || bad "nine verbose" "$out"
    rm -f "$H/two-screens" "$desks/nine" "$desks/two"
    # no jq: check says so, a desk is refused
    mkdir -p "$H/nojq"
    for d in $(printf '%s' "$PATH" | tr ':' ' '); do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
            n=${f##*/}
            if [ "$n" != jq ] && [ -x "$f" ] && [ ! -e "$H/nojq/$n" ]; then ln -s "$f" "$H/nojq/$n"; fi
        done
    done
    out=$(PATH=$H/nojq sh "$SH" check 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^FAIL   desktop      jq is missing (.*) -- spark-shell on$' && ok "check: FAIL desktop without jq, the remedy is spark-shell on" || bad "check no jq" "$out"
    st=0; out=$(PATH=$H/nojq sh "$SH" layout "$need" 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: jq is not installed (spark-shell on)" ] && ok "layout WORDS without jq: refused in one line" || bad "desk no jq" "st=$st $out"
    out=$(sh "$SH" check || true)
    printf '%s\n' "$out" | grep -q '^ok     desktop      sway and foot are installed and up to date$' && ok "check: the desktop row says installed and up to date" || bad "check desk row" "$out"
    # the rendered sway config: Super+d, the floating prompt, --pending before the first terminal
    sway=$HOME/.config/sway/config
    grep -qF "bindsym Mod4+space exec $REPO/spark-shell desktop voice press" "$sway" && grep -qx 'initial-window-size-chars=60x40'  "$HOME/.config/foot/dialog.ini" && grep -qx 'background=0f0f0f' "$HOME/.config/foot/dialog.ini" \
        && ok "sway render: Super+space opens the dialog (the clone's spark-shell) in foot with dialog.ini: 60x40 with air and the surface a shade of black towards the text (no theme: 0f0f0f)" || bad "sway render bind" "$(grep -n 'mod+d' "$sway"; cat "$HOME/.config/foot/dialog.ini" 2>&1)"
    grep -qF 'for_window [app_id="spark-dialog"] floating enable, border none, move position center, opacity 0' "$sway" && ok "sway render: the dialog floats in the middle, no frame, and maps unseen until its opening is drawn (#167)" || bad "sway render for_window" "$(grep -n spark-dialog "$sway")"
    l_p=$(grep -nF "exec $REPO/spark-shell desktop --pending" "$sway" | head -1 | cut -d: -f1); l_t=$(grep -n "^exec sh -c '" "$sway" | tail -1 | cut -d: -f1)
    [ -n "$l_p" ] && [ -n "$l_t" ] && [ "$l_p" -lt "$l_t" ] && ok "sway render: desktop --pending runs before the first terminal" || bad "sway render pending" "pending $l_p terminal $l_t"
    unset SWAYSOCK WAYLAND_DISPLAY
fi
grep -qxF 'bindsym $mod+space exec @REPO@/spark-shell desktop voice press' "$REPO/template/.config/sway/config" && grep -qxF 'bindsym $mod+Mod1+space focus mode_toggle' "$REPO/template/.config/sway/config" && ok "home entry and displaced focus action stay reachable" || bad "home entry/focus bindings"
! grep -q 'spark-desk' "$REPO/template/.config/sway/config" && ok "sway template: no spark-desk window any more, the panel is the one window" || bad "sway template spark-desk"
l_p=$(grep -n '^exec @REPO@/spark-shell desktop --pending$' "$REPO/template/.config/sway/config" | head -1 | cut -d: -f1); l_t=$(grep -n "^exec sh -c '" "$REPO/template/.config/sway/config" | tail -1 | cut -d: -f1)
[ -n "$l_p" ] && [ -n "$l_t" ] && [ "$l_p" -lt "$l_t" ] && ok "sway template: desktop --pending is the exec before the last exec sh -c" || bad "sway template pending" "pending $l_p terminal $l_t"

fi

# --- 17. sbom and the apps a desk may open --------------------------------
if want 17; then
# a fake pacman answers -Qi (three packages) and -Ql (their files); the
# entries are the fixture's (layout_stubs) plus the tmux entry that `on`
# renders with DESKTOP=sway; fzf is a stub (the picker is asked with no
# terminal, so it never runs); jq is the real one. ID=arch is pinned per
# call, so `on` keeps the fixture's todo packages row. Linux-guarded like
# 14-16. The fake -Ql maps gimp's entry to the fixture's applications dir,
# so gimp is the one app, reader the tool, libfoo the part.
fresh
desktop_stubs
layout_stubs
sbom_stubs
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
apps_file=$HOME/.config/spark-shell/apps; argv=$H/.local/state/spark.argv
if [ "$(uname -s)" = Darwin ]; then
    sh "$SH" on --yes >/dev/null
    st=0; out=$(sh "$SH" desktop apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$(printf '%s\n' "$out" | wc -l)" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: not on macOS, which has its own desktop$' \
        && ok "macOS: desktop apps refuses, na, one line, exit 1" || bad "macOS desktop apps" "st=$st $out"
    st=0; out=$(sh "$SH" apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell apps: not on macOS, which has its own desktop" ] && ok "macOS: apps refuses, na, one line, exit 1" || bad "macOS apps" "st=$st $out"
    ck=$(sh "$SH" check || true)
    printf '%s\n' "$ck" | grep -q '^ok     apps         na (' && ok "macOS: the check apps row says na" || bad "macOS check apps" "$(printf '%s\n' "$ck" | grep apps)"
else
    sh "$SH" on --yes >/dev/null
    tmuxd=$HOME/.local/share/applications/spark-shell-tmux.desktop
    [ -f "$tmuxd" ] && head -1 "$tmuxd" | grep -q '^# rendered by spark-shell' && grep -q '^Exec=tmux$' "$tmuxd" && grep -q '^Terminal=true$' "$tmuxd" \
        && ok "on with DESKTOP=sway: tmux declares itself (spark-shell-tmux.desktop, marked, Exec=tmux, Terminal=true)" || bad "tmux entry" "$(cat "$tmuxd" 2>&1)"
    plain "$tmuxd" && ok "tmux entry: plain (no hex, ASCII)" || bad "tmux entry not plain"
    # the table and the kinds: the counts line, exit 0, one row per package
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^1 apps, 1 tools, 1 parts -- an app is a package with a desktop entry (spark-shell apps chooses the allowed apps)$' \
        && ok "sbom: exit 0 and the counts line (one of each kind)" || bad "sbom counts" "st=$st $out"
    printf '%s\n' "$out" | grep -q '^tool  reader  *1.0-1  *MIT  *Text-based Web browser$' \
        && ok "sbom: a command without an entry is a tool (reader, its version, licence and words)" || bad "sbom tool row" "$out"
    printf '%s\n' "$out" | grep -q '^part  libfoo  *2.1-3  *LGPL2.1  *A library other packages need$' && ok "sbom: a package with neither is a part (libfoo)" || bad "sbom part row" "$out"
    printf '%s\n' "$out" | grep -q '^app   gimp  *3.0.4-1  *GPL3  *GNU Image Manipulation Program$' && ok "sbom: a package that ships an entry is an app (gimp)" || bad "sbom gimp row" "$out"
    [ "$(printf '%s\n' "$out" | grep -c '^[a-z]*  ')" -eq 3 ] && ok "sbom: three packages, three rows" || bad "sbom row count" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom tools 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^tool  reader ' && ! printf '%s\n' "$out" | grep -q '^part ' && ok "sbom tools: the tools alone" || bad "sbom tools" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom parts 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^part  libfoo ' && ! printf '%s\n' "$out" | grep -q '^tool ' && ok "sbom parts: the parts alone" || bad "sbom parts" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom apps 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^tool \|^part ' && bad "sbom apps: a tool or a part in the apps" "$out" || ok "sbom apps: no tool, no part"
    # one name: the detail block; an unknown name: one line, exit 1
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom reader 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^tool  reader 1.0-1$' && printf '%s\n' "$out" | grep -q '^  licence   MIT$' \
        && printf '%s\n' "$out" | grep -q '^  reason    chosen$' && printf '%s\n' "$out" | grep -q '^  commands  reader$' && printf '%s\n' "$out" | grep -q '^  entries   -$' \
        && ok "sbom NAME: the detail block (licence, reason, commands, entries)" || bad "sbom detail" "st=$st $out"
    out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom libfoo 2>&1 || true)
    printf '%s\n' "$out" | grep -q '^  reason    dependency$' && printf '%s\n' "$out" | grep -q '^  commands  -$' && ok "sbom NAME: a dependency with no command says so" || bad "sbom libfoo detail" "$out"
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom nosuch 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell sbom: no package named nosuch" ] && ok "sbom NAME: an unknown name is refused in one line, exit 1" || bad "sbom unknown" "st=$st $out"
    # --json: CycloneDX 1.5 under the state dir, one line names it
    cdx=$H/.local/state/spark-shell/sbom.cdx.json
    st=0; out=$(SPARK_OS_RELEASE=$H/os-arch sh "$SH" sbom --json 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$cdx -- CycloneDX 1.5, 3 components" ] && [ -s "$cdx" ] \
        && ok "sbom --json: writes sbom.cdx.json under the state dir, one line names it and the count" || bad "sbom json line" "st=$st $out"
    jq -e '.bomFormat == "CycloneDX" and .specVersion == "1.5" and .metadata.tools[0].name == "spark-shell" and (.components | length) == 3' "$cdx" >/dev/null 2>&1 \
        && ok "sbom.cdx.json: CycloneDX 1.5, the tool named, three components" || bad "cdx shape" "$(head -c 400 "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "reader") | .type == "library" and .version == "1.0-1" and .purl == "pkg:pacman/arch/reader@1.0-1" and .licenses[0].license.name == "MIT" and .description == "Text-based Web browser"' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: a tool is a library component with its purl (pkg:pacman/arch/reader@1.0-1), licence and words" || bad "cdx reader" "$(jq -c '.components[] | select(.name == "reader")' "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "reader") | .properties | (map(select(.name == "spark-shell:kind"))[0].value == "tool") and (map(select(.name == "spark-shell:reason"))[0].value == "chosen") and (map(select(.name == "spark-shell:commands"))[0].value == "reader")' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: the properties carry spark-shell:kind, :reason and :commands" || bad "cdx properties" "$(jq -c '.components[] | select(.name == "reader") | .properties' "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "libfoo") | .type == "library" and (.properties | map(select(.name == "spark-shell:kind"))[0].value == "part") and (.properties | map(select(.name == "spark-shell:reason"))[0].value == "dependency") and (.properties | map(select(.name == "spark-shell:commands")) | length == 0)' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: a part is a library with kind part, reason dependency, no commands property" || bad "cdx libfoo" "$(jq -c '.components[] | select(.name == "libfoo")' "$cdx" 2>&1)"
    jq -e '.components[] | select(.name == "gimp") | .type == "application" and (.properties | map(select(.name == "spark-shell:entries"))[0].value == "gimp-3.0=")' "$cdx" >/dev/null 2>&1 \
        && ok "cdx: an app is an application component with its entries property (gimp-3.0)" || bad "cdx application" "$(jq -c '.components[] | select(.name == "gimp")' "$cdx" 2>&1)"
    plain "$cdx" && ok "sbom.cdx.json: plain (no hex, ASCII)" || bad "cdx not plain"
    # no package manager this repo knows: one line, exit 1
    st=0; out=$(sh "$SH" sbom 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell sbom: no package manager here that this repo knows (pacman, apt, xbps, brew)" ] && ok "sbom with ID=fixture: no known package manager, one line, exit 1" || bad "sbom fixture" "st=$st $out"
    # the picker with no terminal: refused in one line naming the file (apps, and the old desktop apps|tools)
    st=0; out=$(sh "$SH" apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell apps: the picker needs a terminal -- the file is $apps_file (name[: your words], one per line)" ] \
        && ok "apps without a terminal: refused in one line naming the file, exit 1" || bad "apps no tty" "st=$st $out"
    st=0; out=$(sh "$SH" desktop tools </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell desktop: the picker needs a terminal' && ok "old spellings: desktop tools is the same picker, the same refusal" || bad "tools refusal" "st=$st $out"
    st=0; out=$(sh "$SH" desktop apps </dev/null 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: the picker needs a terminal -- the file is $apps_file (name[: your words], one per line)" ] \
        && ok "old spellings: desktop apps without a terminal, refused in one line naming the file" || bad "desktop apps no tty" "st=$st $out"
    [ ! -e "$apps_file" ] && ok "apps without a terminal: wrote nothing" || bad "apps wrote" "$(cat "$apps_file")"
    # the one picker at a terminal (script lends it one): the apps first, then the tools, in
    # one list; Enter saves the allowed apps, a second pick flips one off, Esc leaves the file
    if command -v script >/dev/null 2>&1; then
        on_tty() { if script --version >/dev/null 2>&1; then script -qec "$*" /dev/null; else script -q /dev/null "$@"; fi; }
        printf '  gimp-3.0: Create images and edit photographs  [app]\n  reader: Text-based Web browser  [tool]\n' > "$HOME/fzf.pick"
        st=0; out=$(on_tty env SPARK_OS_RELEASE="$H/os-arch" sh "$SH" apps </dev/null 2>&1) || st=$?
        printf '%s\n' '  gimp-3.0: Create images and edit photographs  [app]' '  reader: Text-based Web browser  [tool]' > "$H/expected.rows"
        [ "$st" -eq 0 ] && cmp -s "$HOME/fzf.rows" "$H/expected.rows" && ok "apps: one picker, the app row first, then the tool row" || bad "apps rows" "st=$st $out $(cat "$HOME/fzf.rows" 2>&1)"
        grep -qx 'gimp-3.0' "$apps_file" && grep -qx reader "$apps_file" && printf '%s\n' "$out" | grep -qF "allowed apps: gimp-3.0 reader ($apps_file)" \
            && ok "apps: Enter saves the picked rows as the allowed apps, said in one line" || bad "apps save" "$out $(cat "$apps_file" 2>&1)"
        grep -qx 'apps> ' "$HOME/fzf.args" && grep -q '^The allowed apps: what a layout may open' "$HOME/fzf.args" && ! grep -qi 'mark' "$HOME/fzf.args" \
            && ok "apps: the prompt is apps>, the header says allowed apps" || bad "apps header" "$(cat "$HOME/fzf.args")"
        printf '* reader: Text-based Web browser  [tool]\n' > "$HOME/fzf.pick"
        st=0; out=$(on_tty env SPARK_OS_RELEASE="$H/os-arch" sh "$SH" desktop tools </dev/null 2>&1) || st=$?
        [ "$st" -eq 0 ] && grep -q '^\* gimp-3.0: ' "$HOME/fzf.rows" && grep -q '^\* reader: ' "$HOME/fzf.rows" && grep -qx 'gimp-3.0' "$apps_file" && ! grep -q '^reader' "$apps_file" \
            && ok "old spellings: desktop tools opens the same picker; an allowed row wears *, picking it again takes it off" || bad "apps flip" "st=$st $out $(cat "$HOME/fzf.rows" "$apps_file" 2>&1)"
        cp "$apps_file" "$H/apps.before"; rm -f "$HOME/fzf.pick"
        st=0; out=$(on_tty env SPARK_OS_RELEASE="$H/os-arch" sh "$SH" apps </dev/null 2>&1) || st=$?
        [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q 'nothing changed' && cmp -s "$apps_file" "$H/apps.before" && ok "apps: Esc leaves the file as it was" || bad "apps esc" "st=$st $out"
        rm -f "$apps_file" "$HOME/fzf.rows" "$HOME/fzf.args"
    fi
    # status and check, unmarked: every entry (the five fixtures and tmux)
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  apps  all  *every app with a desktop entry (spark-shell apps picks the allowed apps)$' && ok "status: the apps row says all, every app with a desktop entry" || bad "status apps unmarked" "$(printf '%s\n' "$st" | grep apps)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         6 apps installed, all allowed (spark-shell apps chooses)$' \
        && ok "check: the apps row counts the entries (five fixtures and tmux), all allowed" || bad "check apps unmarked" "$(printf '%s\n' "$ck" | grep apps)"
    # the unmarked inventory: tmux in its entry's words, a terminal app
    rm -f "$argv"
    SWAYSOCK=/tmp/x WAYLAND_DISPLAY=wayland-1 sh "$SH" layout "$need" >/dev/null 2>&1 || true
    if command -v tmux >/dev/null 2>&1; then
        grep -q 'tmux: A shell with panes, sessions and the status line' "$argv" && ok "inventory unmarked: tmux in its entry's words" || bad "inventory tmux" "$(grep -o 'tmux[^;]*' "$argv" 2>&1)"
    fi
    grep -q 'gimp-3.0: Create images and edit photographs' "$argv" && ! grep -q 'gimp:' "$argv" && ok "inventory unmarked: an entry's Exec name, never the package name (gimp-3.0, not gimp)" || bad "inventory gimp" "$(grep -o 'gimp[^;]*' "$argv" 2>&1)"
    # marked: the names, the rows; a name that is gone is a FAIL with the remedy
    printf '# mine\nreader: my browser\nmicro\n' > "$apps_file"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  apps  2 allowed  *reader, micro (spark-shell apps)$' && ok "status: the apps row counts and names the allowed apps" || bad "status apps marked" "$(printf '%s\n' "$st" | grep apps)"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         2 allowed apps, 6 apps installed$' && ok "check: ok apps when every allowed name is here" || bad "check apps marked" "$(printf '%s\n' "$ck" | grep apps)"
    printf 'reader: my browser\nmicro\nghost\n' > "$apps_file"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^FAIL   apps         allowed but not here: ghost -- spark-shell apps$' && ok "check: FAIL apps naming the allowed name that is gone, the remedy is spark-shell apps" || bad "check apps gone" "$(printf '%s\n' "$ck" | grep apps)"
    rm -f "$apps_file"
    # off hands the tmux entry back
    sh "$SH" off >/dev/null
    [ ! -e "$tmuxd" ] && ok "off: the tmux entry is gone (no .bak: there was none before)" || bad "tmux entry off" "$(ls "$HOME/.local/share/applications")"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         5 apps installed, all allowed' && ok "check after off: tmux is out of the count (five entries)" || bad "check apps after off" "$(printf '%s\n' "$ck" | grep apps)"
    printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
    ck=$(sh "$SH" check || true); printf '%s\n' "$ck" | grep -q '^ok     apps         na (no desktop)$' && ok "check: apps na with DESKTOP=none" || bad "check apps none" "$(printf '%s\n' "$ck" | grep apps)"
fi
grep -q '^Exec=tmux$' "$REPO/template/.local/share/applications/spark-shell-tmux.desktop" && grep -q '^Terminal=true$' "$REPO/template/.local/share/applications/spark-shell-tmux.desktop" \
    && ok "template: spark-shell-tmux.desktop runs tmux in a terminal" || bad "tmux template"
# the same table through rpm, the one database under Fedora's dnf and openSUSE's zypper: rpm -qa the rows, rpm -ql the files, dnf alone remembers who asked for a package
if [ "$(uname -s)" != Darwin ]; then
    fresh; desktop_stubs
    cat > "$H/.local/bin/rpm" <<'EOF'
#!/bin/sh
case ${1:-} in
    -qa) printf 'reader\t1.0-1\tMIT\t?\tText-based Web browser\nlibfoo\t2.1-3\tLGPL-2.1\t?\tA library other packages need\n' ;;
    -ql) case $2 in reader) echo /usr/bin/reader ;; libfoo) echo /usr/lib64/libfoo.so ;; esac ;;
esac
EOF
    printf '#!/bin/sh\ncase "$*" in *--userinstalled*) echo reader ;; esac\n' > "$H/.local/bin/dnf"
    chmod +x "$H/.local/bin/rpm" "$H/.local/bin/dnf"
    printf 'ID=fedora\n' > "$H/os-fedora"; printf 'ID=opensuse-tumbleweed\nID_LIKE="suse opensuse"\n' > "$H/os-opensuse"
    st=0; out=$(SPARK_OS_RELEASE=$H/os-fedora sh "$SH" sbom 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^tool  reader  *1.0-1  *MIT  *Text-based Web browser$' && printf '%s\n' "$out" | grep -q '^part  libfoo  *2.1-3  *LGPL-2.1 ' \
        && ok "sbom (Fedora): the rows through rpm -qa and rpm -ql, a command a tool, a library a part" || bad "sbom rpm" "st=$st $out"
    out=$(SPARK_OS_RELEASE=$H/os-fedora sh "$SH" sbom reader 2>&1 || :); printf '%s\n' "$out" | grep -q '^  reason    chosen$' && ok "sbom (Fedora): dnf remembers that reader was asked for" || bad "sbom dnf reason" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-fedora sh "$SH" sbom libfoo 2>&1 || :); printf '%s\n' "$out" | grep -q '^  reason    dependency$' && ok "sbom (Fedora): the rest came as dependencies" || bad "sbom dnf dep" "$out"
    out=$(SPARK_OS_RELEASE=$H/os-opensuse sh "$SH" sbom reader 2>&1 || :); printf '%s\n' "$out" | grep -q '^  reason    ?$' && ok "sbom (openSUSE): zypper keeps no reason, so the row says ?" || bad "sbom zypper reason" "$out"
    SPARK_OS_RELEASE=$H/os-opensuse sh "$SH" sbom --json >/dev/null 2>&1; [ "$(jq -r '.components[0].purl' "$HOME/.local/state/spark-shell/sbom.cdx.json")" = 'pkg:zypper/opensuse/libfoo@2.1-3' ] && ok "sbom --json (openSUSE): the purl names zypper and the family" || bad "sbom purl" "$(cat "$HOME/.local/state/spark-shell/sbom.cdx.json" 2>&1 | head -c 400)"
fi

fi

# --- 18. rooms: the same desk as a tmux session --------------------------
if want 18; then
# No sway here (SWAYSOCK unset): a desk plays as rooms through a fake
# tmux that logs each call as one line; has-session finds a session
# only while $H/tmux.has exists. newsboat, w3m and aerc are stubs, mpv
# is absent on purpose, the spark and swaymsg stubs are 16's. Not
# uname-guarded: rooms run on macOS too; only the two forms that start
# or address sway are Linux's.
fresh
desktop_stubs
layout_stubs
rooms_stubs
unset SWAYSOCK WAYLAND_DISPLAY TMUX EDITOR
need='photo editing for instagram and x'; sname=photo-editing-for-instagram-and-x
argv=$H/.local/state/spark.argv; swlog=$H/.local/state/swaymsg.log; tlog=$H/.local/state/tmux.log
layout_last=$H/.local/state/spark-shell/layout.last; desks=$H/.config/spark-shell/layouts
# a need with no sway: the rooms player, the terminal apps offered, one room per app that is one
st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && printf '%s\n' "$out" | grep -q '^  photo work in gimp with the two feeds' \
    && ok "tmux windows: words with no sway open as tmux windows: exit 0, the layout> line, the why" || bad "rooms need" "st=$st $out"
printf '%s\n' "has-session -t =$sname" "new-session -d -s $sname -n micro micro" > "$H/expected.rooms"
cmp -s "$tlog" "$H/expected.rooms" && ok "rooms: tmux got has-session, then one new-session with micro as its first window, nothing else" || bad "rooms tmux log" "$(cat "$tlog" 2>&1)"
printf '%s\n' "$out" | grep -q '^  gimp-3.0 -- needs the desktop$' && printf '%s\n' "$out" | grep -q '^  firefox https://instagram.com -- needs the desktop$' && printf '%s\n' "$out" | grep -q '^  micro$' \
    && ok "rooms: a graphical app is one line (needs the desktop), a terminal app runs" || bad "rooms outcome lines" "$out"
printf '%s\n' "$out" | grep -q '^  refused  window ghostapp ghostapp  (ghostapp is not on this machine)$' && ok "rooms: the gate reads a tmux window line like an exec" || bad "rooms gate" "$out"
printf '%s\n' "$out" | grep -q "^tmux session $sname -- spark-shell layout save NAME saves it\$" && printf '%s\n' "$out" | grep -q "^tmux session $sname -- tmux attach-session -t $sname joins it\$" \
    && ok "rooms: the closing line names the session and keep; on a pipe, the line that joins them" || bad "rooms closing" "$out"
grep -q 'attach-session\|switch-client' "$tlog" && bad "rooms: attached on a pipe" "$(cat "$tlog")" || ok "rooms: no attach on a pipe"
grep -q '^A layout of tmux windows: the apps for one need, each in a terminal window, on a [0-9]*x[0-9]* terminal\. ' "$argv" && ok "rooms brief: tmux windows, a terminal, its columns and lines" || bad "rooms brief" "$(grep -o 'A layout[^.]*' "$argv")"
grep -q 'micro: Micro' "$argv" && grep -q 'shell: a terminal with a prompt' "$argv" && ! grep -q 'gimp-3.0\|firefox\|"screen"\|on one screen\|on screens' "$argv" \
    && ok "rooms brief: the terminal apps and shell only; no graphical app, no screen field, no screens" || bad "rooms brief apps" "$(grep -o 'Apps on this machine[^.]*' "$argv")"
jq -e --arg w "$need" '.words == $w and .main.app == "gimp-3.0"' "$layout_last" >/dev/null 2>&1 && ok "rooms: layout.last is the same JSON shape (keep works the same)" || bad "rooms layout.last" "$(cat "$layout_last" 2>&1)"
[ ! -e "$swlog" ] && ok "rooms: swaymsg never sent a line" || bad "rooms swaymsg" "$(cat "$swlog")"
# a need of * from a directory with files: the word, never the file names
rm -f "$argv"
(cd "$H/.local/bin" && sh "$SH" layout '*' >/dev/null 2>&1) || true
[ "$(tail -1 "$argv")" = 'write the layout for this need: *' ] && ok "a need of * reaches the model as *, not as the cwd's file names" || bad "glob need" "$(tail -1 "$argv" 2>&1)"
rm -f "$argv"
sh "$SH" layout 'notes\nand a backslash' >/dev/null 2>&1 || true
[ "$(tail -1 "$argv")" = 'write the layout for this need: notes\nand a backslash' ] && ok "a need with a literal backslash reaches the model byte-exact" || bad "backslash need" "$(tail -1 "$argv" 2>&1)"
# inside tmux: switch-client; a session already open is joined, not built again
: > "$tlog"
st=0; out=$(TMUX=/x sh "$SH" layout "$need" --terminal 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$tlog")" = "switch-client -t =$sname" ] && ok "inside tmux (TMUX set, --terminal): switch-client to the session" || bad "rooms switch" "st=$st $(cat "$tlog")"
: > "$tlog"
st=0; out=$(TMUX=/x sh "$SH" desktop "$need" --rooms 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$tlog")" = "switch-client -t =$sname" ] && printf '%s\n' "$out" | grep -q "^layout> $need\$" && ok "old spellings: desktop WORDS --rooms still opens the tmux windows" || bad "alias rooms" "st=$st $out $(cat "$tlog")"
touch "$H/tmux.has"; : > "$tlog"
st=0; out=$(sh "$SH" layout "$need" 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^  the tmux session $sname is open already\$" && ! grep -q 'new-session' "$tlog" \
    && ok "rooms open already: said in one line, no session built, joined" || bad "rooms has-session" "st=$st $out $(cat "$tlog")"
rm -f "$H/tmux.has"
# a kept desk named studio; shell and editor are desk words
mkdir -p "$desks"
cat > "$desks/studio" <<'EOF2'
{"words": "studio",
 "why": "a shell, the editor, the feeds, the web and the mail, one room each",
 "main": {"app": "shell", "args": "", "width": 70},
 "side": [{"app": "editor", "args": ""},
          {"app": "newsboat", "args": ""},
          {"app": "w3m", "args": "duckduckgo.com"},
          {"app": "aerc", "args": ""}]}
EOF2
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" layout studio 2>&1) || st=$?
printf '%s\n' 'has-session -t =studio' 'new-session -d -s studio -n shell' 'new-window -t =studio -n editor micro' 'new-window -t =studio -n newsboat newsboat' 'new-window -t =studio -n w3m w3m duckduckgo.com' 'new-window -t =studio -n aerc aerc' > "$H/expected.studio"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.studio" && [ ! -e "$argv" ] \
    && ok "desktop studio: the session with a bare shell window, then one window per room, the editor micro with EDITOR unset; no model call" || bad "studio play" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -q '^layout> studio$' && printf '%s\n' "$out" | grep -q '^  a shell, the editor, the feeds' && printf '%s\n' "$out" | grep -q '^  editor micro$' && printf '%s\n' "$out" | grep -q '^  w3m duckduckgo.com$' \
    && printf '%s\n' "$out" | grep -q '^tmux session studio -- the saved layout studio$' && ok "layout studio: the layout> line, the why, one line per window, the closing line" || bad "studio lines" "$out"
printf '#!/bin/sh\n:\n' > "$H/.local/bin/nano"; chmod +x "$H/.local/bin/nano"   # the containers have no nano; a kept desk runs what is on PATH
: > "$tlog"
st=0; out=$(EDITOR=/usr/bin/nano sh "$SH" layout studio 2>&1) || st=$?
grep -q '^new-window -t =studio -n editor nano$' "$tlog" && ok "editor is EDITOR's basename (nano)" || bad "editor nano" "$(cat "$tlog")"
rm -f "$H/.local/bin/nano"; : > "$tlog"
st=0; out=$(EDITOR=/usr/bin/nosucheditor sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^  refused  window editor nosucheditor  (nosucheditor is not on this machine)$' && grep -q '^new-window -t =studio -n newsboat newsboat$' "$tlog" \
    && ok "EDITOR naming a program that is not here: its room is refused, the rest opens" || bad "editor absent" "st=$st $out"
mkdir -p "$H/noed"; : > "$HOME/no-text-app"   # a PATH with everything but micro and vi (this machine may have the real ones), and no text application named by the system
for d in $(printf '%s' "$PATH" | tr ':' ' '); do
    [ -d "$d" ] || continue
    for f in "$d"/*; do n=${f##*/}; if [ "$n" != micro ] && [ "$n" != vi ] && [ -x "$f" ] && [ ! -e "$H/noed/$n" ]; then ln -s "$f" "$H/noed/$n"; fi; done
done
: > "$tlog"
st=0; out=$(PATH=$H/noed sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -qx '  editor -- no editor on this machine: set EDITOR in ~/.config/spark-shell/rc' && ! grep -q ' -n editor' "$tlog" \
    && grep -q '^new-session -d -s studio -n shell$' "$tlog" && grep -q '^new-window -t =studio -n newsboat newsboat$' "$tlog" \
    && ok "no EDITOR, no text application, no vi: that one window is skipped in one line, the rest opens" || bad "no editor" "st=$st $out $(cat "$tlog")"
printf '#!/bin/sh\n:\n' > "$H/noed/vi"; chmod +x "$H/noed/vi"   # a vi of our own: the containers may lack one
: > "$tlog"
st=0; out=$(PATH=$H/noed sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-window -t =studio -n editor vi$' "$tlog" && ! printf '%s\n' "$out" | grep -q 'no editor' \
    && ok "no EDITOR and no text application: the editor is vi when vi is here" || bad "editor vi" "st=$st $out $(cat "$tlog")"
rm -f "$HOME/no-text-app"; : > "$tlog"
st=0; out=$(PATH=$H/noed sh "$SH" layout studio 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-window -t =studio -n editor micro$' "$tlog" && ! printf '%s\n' "$out" | grep -q 'no editor' \
    && ok "no EDITOR: the editor is the program your system opens text with (xdg-mime names micro's entry), never a guess (#115)" || bad "editor system" "st=$st $out $(cat "$tlog")"
st=0; out=$(sh "$SH" layout studio -v 2>&1) || st=$?
printf '%s\n' "$out" | grep -q '^  window shell$' && printf '%s\n' "$out" | grep -q '^  window editor micro$' && printf '%s\n' "$out" | grep -q '^  window w3m w3m duckduckgo.com$' \
    && ok "-v shows the tmux lines (window NAME [CMD ARGS])" || bad "rooms verbose" "$out"
printf '%s\n' "$out" | grep -q '^  session studio$' && ok "-v: the session line" || bad "rooms verbose session" "$out"
printf '{"words": "pipe", "main": {"app": "w3m", "args": "a|b"}}\n' > "$desks/pipe"; : > "$tlog"
st=0; out=$(sh "$SH" layout pipe 2>&1) || st=$?
[ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -qF '  refused  window w3m w3m a|b  (shell syntax' && ! grep -q 'new-session' "$tlog" && printf '%s\n' "$out" | grep -q 'nothing ran$' \
    && ok "a kept desk edited by hand: shell syntax in a room is refused; with no room left, nothing ran" || bad "rooms pipe" "st=$st $out"
# --terminal inside sway: the session is built, then a foot window of its own on a fresh workspace
export SWAYSOCK=$H/sway.sock; : > "$tlog"; rm -f "$swlog"
st=0; out=$(sh "$SH" layout studio --terminal 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-session -d -s studio -n shell$' "$tlog" && [ "$(head -1 "$swlog")" = 'workspace number 3' ] && [ "$(tail -1 "$swlog")" = 'exec foot -e tmux attach-session -t =studio' ] \
    && ! grep -q 'attach-session\|switch-client' "$tlog" && ok "--terminal inside sway: the tmux windows built, then workspace 3 and one foot that attaches to them" || bad "rooms in sway" "st=$st $out $(cat "$swlog" "$tlog" 2>&1)"
: > "$tlog"; rm -f "$swlog"
st=0; out=$(sh "$SH" desktop studio --rooms 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-session -d -s studio -n shell$' "$tlog" && [ "$(tail -1 "$swlog")" = 'exec foot -e tmux attach-session -t =studio' ] \
    && ok "old spellings: desktop NAME --rooms inside sway, the same as layout NAME --terminal" || bad "alias rooms in sway" "st=$st $out $(cat "$swlog" "$tlog" 2>&1)"
unset SWAYSOCK
# the saved layouts live in layouts/; the old desks/ folder is not read, not moved, not deleted
mkdir -p "$H/.config/spark-shell/desks"; cp "$desks/studio" "$H/.config/spark-shell/desks/olddesk"
out=$(sh "$SH" layout)
printf '%s\n' "$out" | grep -q '^  studio ' && ! printf '%s\n' "$out" | grep -q olddesk && ok "layout (bare): lists layouts/, never the old desks/ folder" || bad "layouts list" "$out"
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" layout olddesk 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$(tail -1 "$argv" 2>&1)" = 'write the layout for this need: olddesk' ] && [ -f "$H/.config/spark-shell/desks/olddesk" ] && [ ! -e "$desks/olddesk" ] \
    && ok "layout NAME of a file in desks/: words for the model, the old file left where it is" || bad "desks ignored" "st=$st $out"
st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  layouts [0-9]* saved  *pipe, studio (spark-shell layout NAME)$' && ok "status: the layouts row counts layouts/ alone" || bad "status layouts dir" "$(printf '%s\n' "$st" | grep layouts)"
rm -rf "$H/.config/spark-shell/desks"
# the old spellings of save and delete land in layouts/ too
sh "$SH" layout "$need" >/dev/null 2>&1 || true
out=$(sh "$SH" desktop keep oldword 2>&1)
[ "$out" = "saved oldword -- spark-shell layout oldword opens it ($desks/oldword)" ] && [ -f "$desks/oldword" ] && ok "old spellings: desktop keep NAME saves to layouts/" || bad "alias keep" "$out"
out=$(sh "$SH" desktop forget oldword 2>&1)
[ "$out" = "deleted oldword" ] && [ ! -e "$desks/oldword" ] && ok "old spellings: desktop forget NAME deletes it" || bad "alias forget" "$out"
st=0; out=$(sh "$SH" desktop forget oldword 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$out" = "spark-shell desktop: no saved layout named oldword" ] && ok "old spellings: a refusal names the verb as typed (desktop)" || bad "alias forget twice" "st=$st $out"
st=0; out=$(sh "$SH" layout delete 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$out" = "spark-shell layout: delete NAME -- which layout?" ] && ok "layout delete with no name: refused in one line" || bad "delete bare" "st=$st $out"
: > "$tlog"; rm -f "$argv"
st=0; out=$(sh "$SH" desktop --ask </dev/null 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | sed -n 1p | grep -q '^layout     ' && [ ! -e "$argv" ] \
    && ok "old spellings: desktop --ask is the panel with the layouts first" || bad "alias ask" "st=$st $out"
# named apps open, the others are suggestions: the model answers $HOME/answer.json
printf '[Desktop Entry]\nName=btop\nComment=Resource monitor\nExec=btop\nTerminal=true\nType=Application\n' > "$XDG_DATA_HOME/applications/btop.desktop"
for t in btop vi; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; chmod +x "$H/.local/bin/$t"; done
printf '{"why": "vi to write, btop to watch, a shell", "main": {"app": "vi", "args": "", "width": 70}, "side": [{"app": "btop", "args": ""}, {"app": "shell", "args": ""}]}\n' > "$H/answer.json"
wname=writing-with-vi-and-the-prompt-shell; : > "$tlog"
st=0; out=$(sh "$SH" layout "writing with vi and the prompt shell" 2>&1) || st=$?
printf '%s\n' "has-session -t =$wname" "new-session -d -s $wname -n vi vi" "new-window -t =$wname -n shell" > "$H/expected.named"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.named" && ok "named: the words name vi and shell, only those two open" || bad "named open" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -qx '  also suggested: btop -- add it to your words to open it' && ok "named: the one app not named is said in one line, a suggestion" || bad "named suggestion" "$out"
jq -e '.main.app == "vi" and (.side | map(.app)) == ["shell"] and .suggested == ["btop"] and (has("why") | not)' "$layout_last" >/dev/null 2>&1 \
    && ok "named: layout.last holds what opened (vi and shell), btop as suggested for the panel's row, and no why" || bad "named layout.last" "$(cat "$layout_last")"
printf '%s\n' "$out" | grep -q 'vi to write, btop to watch' && bad "named: the model's why said though btop was dropped" "$out" || ok "named: btop dropped, so the model's why is not said"
# the same gate on a room: a first word with a = is a variable, and sh runs the word after it
printf '{"main": {"app": "vi", "args": ""}, "side": [{"app": "X=/vi", "args": "sh -c id", "quote": "the prompt shell"}]}\n' > "$H/answer.json"
: > "$tlog"; st=0; out=$(sh "$SH" layout "writing with vi and the prompt shell" 2>&1) || st=$?
! grep -q 'X=/vi' "$tlog" && printf '%s\n' "$out" | grep -qF '(a variable before a program is shell syntax)' && ok "gate: a room's first word with a = is refused too" || bad "gate room" "st=$st $out $(cat "$tlog")"
printf '{"main": {"app": "btop", "args": "", "width": 60}, "side": [{"app": "newsboat", "args": ""}, {"app": "shell", "args": ""}, {"app": "micro", "args": ""}]}\n' > "$H/answer.json"
dname=the-feeds-in-newsboat-and-a-shell; : > "$tlog"
st=0; out=$(sh "$SH" layout "the feeds in Newsboat and a shell" 2>&1) || st=$?
printf '%s\n' "has-session -t =$dname" "new-session -d -s $dname -n newsboat newsboat" "new-window -t =$dname -n shell" > "$H/expected.dropped"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.dropped" && printf '%s\n' "$out" | grep -qx '  also suggested: btop and micro -- add them to your words to open them' \
    && jq -e '.main.app == "newsboat" and .main.width == 60 and (.side | map(.app)) == ["shell"]' "$layout_last" >/dev/null 2>&1 \
    && ok "named: the main window not named, the first named takes its place (its width kept); two suggestions in one line" || bad "named main dropped" "st=$st $out $(cat "$tlog" "$layout_last")"
printf '{"why": "micro for notes, btop to watch", "main": {"app": "micro", "args": ""}, "side": [{"app": "btop", "args": ""}]}\n' > "$H/answer.json"
nname=news-reading-and-music; : > "$tlog"
st=0; out=$(sh "$SH" layout "news reading and music" 2>&1) || st=$?
printf '%s\n' "has-session -t =$nname" "new-session -d -s $nname -n micro micro" "new-window -t =$nname -n btop btop" > "$H/expected.none"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.none" && ! printf '%s\n' "$out" | grep -q 'also suggested' && printf '%s\n' "$out" | grep -qx '  micro for notes, btop to watch' \
    && jq -e '.why == "micro for notes, btop to watch"' "$layout_last" >/dev/null 2>&1 \
    && ok "named: words that name no app open the model's picks as they are, with its why (said and kept)" || bad "named none" "st=$st $out $(cat "$tlog" "$layout_last")"
printf '{"main": {"app": "editor", "args": "notes.txt"}, "side": [{"app": "btop", "args": ""}]}\n' > "$H/answer.json"
ename=notes-in-micro; : > "$tlog"
st=0; out=$(sh "$SH" layout "notes in micro" 2>&1) || st=$?
printf '%s\n' "has-session -t =$ename" "new-session -d -s $ename -n editor micro notes.txt" > "$H/expected.editor"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.editor" && printf '%s\n' "$out" | grep -qx '  also suggested: btop -- add it to your words to open it' \
    && ok "named: the editor's own program (micro) names the editor window" || bad "named editor" "st=$st $out $(cat "$tlog")"
# the box's case: the words name vi and shell, the answer has shell, tmux and btop; vi is added
printf '[Desktop Entry]\nName=tmux\nComment=Terminal multiplexer\nExec=tmux\nTerminal=true\nType=Application\n' > "$XDG_DATA_HOME/applications/tmux.desktop"
printf '{"why": "a shell to write in, tmux to split it, btop to watch", "main": {"app": "shell", "args": "", "width": 60}, "side": [{"app": "tmux", "args": ""}, {"app": "btop", "args": ""}]}\n' > "$H/answer.json"
bname=writing-with-vi-and-shell-window; : > "$tlog"
st=0; out=$(sh "$SH" layout "writing with vi and shell window" 2>&1) || st=$?
printf '%s\n' "has-session -t =$bname" "new-session -d -s $bname -n shell" "new-window -t =$bname -n vi vi" > "$H/expected.box"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.box" && ok "named: the box's words (vi and shell) open shell and vi, vi added though the answer lacks it" || bad "named box" "st=$st $out $(cat "$tlog")"
printf '%s\n' "$out" | grep -qx '  also suggested: tmux and btop -- add them to your words to open them' && ok "named: the box's case suggests tmux and btop" || bad "named box suggested" "$out"
printf '%s\n' "$out" | grep -q 'tmux to split it' && bad "named: the box's case said the model's why" "$out" || ok "named: the box's case says no why (the set changed)"
jq -e '.main.app == "shell" and .main.width == 60 and .side == [{"app": "vi", "args": ""}] and (has("why") | not)' "$layout_last" >/dev/null 2>&1 \
    && ok "named: layout.last holds shell and vi, no why" || bad "named box layout.last" "$(cat "$layout_last")"
sh "$SH" layout save box-case >/dev/null; : > "$tlog"
st=0; out=$(sh "$SH" layout box-case 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q "^new-window -t =$bname -n vi vi\$" "$tlog" && [ "$(printf '%s\n' "$out" | sed -n 2p)" = '  shell' ] \
    && ok "named: the saved layout replays shell and vi with no stale why" || bad "named box replay" "st=$st $out $(cat "$tlog")"
# no named app in the answer: the named ones are the layout (the first the main), the model's picks suggested
printf '{"why": "btop to watch, micro for notes", "main": {"app": "btop", "args": "", "width": 50}, "side": [{"app": "micro", "args": ""}]}\n' > "$H/answer.json"
fname=feeds-in-newsboat-beside-vi; : > "$tlog"
st=0; out=$(sh "$SH" layout "feeds in newsboat beside vi" 2>&1) || st=$?
printf '%s\n' "has-session -t =$fname" "new-session -d -s $fname -n newsboat newsboat" "new-window -t =$fname -n vi vi" > "$H/expected.added"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.added" && printf '%s\n' "$out" | grep -qx '  also suggested: btop and micro -- add them to your words to open them' \
    && ! printf '%s\n' "$out" | grep -q 'btop to watch' && jq -e '.main.app == "newsboat" and .main.width == 50 and (.side | map(.app)) == ["vi"] and (has("why") | not)' "$layout_last" >/dev/null 2>&1 \
    && ok "named: none of the answer named, the words name newsboat and vi: those two open, the answer suggested, no why" || bad "named added" "st=$st $out $(cat "$tlog" "$layout_last")"
# editor and its own program are one app: added once
printf '{"why": "btop to watch", "main": {"app": "btop", "args": ""}}\n' > "$H/answer.json"
oname=notes-in-the-editor-with-vi; : > "$tlog"
st=0; out=$(EDITOR="vi" sh "$SH" layout "notes in the editor with vi" 2>&1) || st=$?
printf '%s\n' "has-session -t =$oname" "new-session -d -s $oname -n editor vi" > "$H/expected.once"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.once" && printf '%s\n' "$out" | grep -qx '  also suggested: btop -- add it to your words to open it' \
    && ok "named: the words say editor and vi (EDITOR=vi), one editor window opens" || bad "named once" "st=$st $out $(cat "$tlog")"
# the answer is what the words name: unchanged, so its why is said and kept
printf '{"why": "vi to write and btop to watch", "main": {"app": "editor", "args": ""}, "side": [{"app": "btop", "args": ""}]}\n' > "$H/answer.json"
sname_=notes-in-vi-and-btop; : > "$tlog"
st=0; out=$(EDITOR="vi" sh "$SH" layout "notes in vi and btop" 2>&1) || st=$?
printf '%s\n' "has-session -t =$sname_" "new-session -d -s $sname_ -n editor vi" "new-window -t =$sname_ -n btop btop" > "$H/expected.same"
[ "$st" -eq 0 ] && cmp -s "$tlog" "$H/expected.same" && printf '%s\n' "$out" | grep -qx '  vi to write and btop to watch' && ! printf '%s\n' "$out" | grep -q 'also suggested' \
    && jq -e '.why == "vi to write and btop to watch"' "$layout_last" >/dev/null 2>&1 \
    && ok "named: the answer opens unchanged (vi names the editor), so its why is said and kept" || bad "named same" "st=$st $out $(cat "$tlog" "$layout_last")"
rm -f "$XDG_DATA_HOME/applications/tmux.desktop" "$desks/box-case"
sh "$SH" layout save named-one >/dev/null
printf '{"words": "saved as is", "main": {"app": "micro", "args": ""}, "side": [{"app": "btop", "args": ""}]}\n' > "$desks/as-is"; : > "$tlog"
st=0; out=$(sh "$SH" layout as-is 2>&1) || st=$?
[ "$st" -eq 0 ] && grep -q '^new-window -t =saved-as-is -n btop btop$' "$tlog" && ! printf '%s\n' "$out" | grep -q 'also suggested' \
    && ok "named: a saved layout opens as saved, nothing narrowed" || bad "named saved" "st=$st $out $(cat "$tlog")"
rm -f "$H/answer.json" "$desks/as-is" "$desks/named-one"
if [ "$(uname -s)" != Darwin ]; then
    # --desktop from a console: the words wait, sway starts, --pending lays them out once
    printf '{"main":{"app":"micro"},"side":[{"app":"firefox"}]}\n' > "$H/answer.json"   # every required app exists in this positive pending proof
    theme_fixture '#ff5555'; mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    layout_pending=$H/.local/state/spark-shell/layout.pending; rm -f "$argv" "$swlog"
    st=0; out=$(TEST_TTY=/dev/tty1 sh "$SH" layout "news and music" --desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$layout_pending" 2>&1)" = 'news and music' ] && grep -q 'sway-stub' "$H/.local/state/spark-shell/sway.log" && [ ! -e "$argv" ] \
        && ok "layout WORDS --desktop from a console: the words wait in layout.pending, sway starts, no model call yet" || bad "pending write" "st=$st $out $(cat "$layout_pending" 2>&1)"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" layout --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^layout> news and music$' && printf '%s\n' "$out" | grep -q '^on workspace 3' && [ ! -e "$layout_pending" ] \
        && [ "$(tail -1 "$argv")" = 'write the layout for this need: news and music' ] && grep -qx 'exec foot -e micro' "$swlog" && grep -qx 'exec firefox' "$swlog" \
        && ok "layout --pending: lays the waiting words out as sway windows, the file is gone" || bad "pending play" "st=$st $out"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" layout --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ -z "$out" ] && ok "layout --pending twice: a quiet no-op" || bad "pending twice" "st=$st $out"
    rm -f "$argv"
    st=0; out=$(TEST_TTY=/dev/tty1 sh "$SH" desktop "news and music" --windows 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$layout_pending" 2>&1)" = 'news and music' ] && [ ! -e "$argv" ] \
        && ok "old spellings: desktop WORDS --windows from a console waits the same" || bad "alias windows" "st=$st $out"
    st=0; out=$(SWAYSOCK=$H/sway.sock sh "$SH" desktop --pending 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^layout> news and music$' && [ ! -e "$layout_pending" ] \
        && ok "old spellings: desktop --pending (the sway config's line) lays them out" || bad "alias pending" "st=$st $out"
    rm -f "$H/answer.json"
fi

fi

# --- 19. the console: theme, font, quiet (spark 1.62 handed them over) ----
if want 19; then
# Every Linux shape runs on any OS: a uname stub says Linux (or Darwin),
# root paths live under SPARK_SHELL_ROOT, and stubs stand in for
# setvtrgb, setfont, setupcon, update-grub, mkinitcpio, systemctl and
# python3, each logging its arguments to $H/log. A fixture file is
# compared byte for byte with its copy after the hand-back.

# theme, systemd: the three files, the unit, the kernel's defaults, then none
fresh
console_stubs Linux
mkdir -p "$H/root/run/systemd/system"
palette_fixture test '#fe8019'
out=$(L theme list)
printf '%s\n' "$out" | grep -q '^  none  *the console' && printf '%s\n' "$out" | grep -q '^  test  *yours$' && ok "theme list: none, and a palette of yours says so" || bad "theme list" "$out"
rc=0; out=$(L theme nosuch 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell theme: no palette named nosuch -- spark-shell theme list shows them" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "theme NAME: an unknown palette is one sentence, exit 1, the config untouched" || bad "theme nosuch" "rc=$rc $out"
sed 's/^THEME_ANSI_3=.*/THEME_ANSI_3=yellow/' "$HOME/.config/spark-shell/themes/test.env" > "$HOME/.config/spark-shell/themes/broken.env"
rc=0; out=$(L theme broken 2>&1) || rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'THEME_ANSI_3 is not #rrggbb' && [ ! -e "$HOME/.config/spark/theme.env" ] && ok "theme NAME: a palette with a key that is not #rrggbb is refused" || bad "theme broken" "rc=$rc $out"
rm -f "$HOME/.config/spark-shell/themes/broken.env"
rc=0; out=$(L theme test 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'THEME=test' "$HOME/.config/spark-shell/config" && ok "theme test: THEME=test in the config" || bad "theme test config" "rc=$rc $out"
te=$HOME/.config/spark/theme.env
head -1 "$te" | grep -q '^# rendered by spark-shell from the palette test' && [ "$(grep -c '^THEME_' "$te")" = 20 ] && grep -qx 'THEME_ACCENT=#fe8019' "$te" \
    && ok "theme test: theme.env holds the marker and the 20 keys" || bad "theme.env" "$(cat "$te")"
[ "$(cat "$HOME/.config/spark-shell/console-colors")" = "${esc}]P0282828${esc}]P1cc241d${esc}]P298971a${esc}]P3d79921${esc}]P4458588${esc}]P5b16286${esc}]P6689d6a${esc}]P7a89984${esc}]P8928374${esc}]P9fb4934${esc}]Pab8bb26${esc}]Pbfabd2f${esc}]Pc83a598${esc}]Pdd3869b${esc}]Pe8ec07c${esc}]Pfebdbb2" ] \
    && ok "theme test: console-colors holds the 16 escapes, slot 10 as a" || bad "console-colors" "$(od -c "$HOME/.config/spark-shell/console-colors" | head -3)"
[ "$(sed -n 1p "$HOME/.config/spark-shell/console-colors.rgb")" = '40,204,152,215,69,177,104,168,146,251,184,250,131,211,142,235' ] && [ "$(wc -l < "$HOME/.config/spark-shell/console-colors.rgb" | tr -d ' ')" = 3 ] \
    && ok "theme test: console-colors.rgb is setvtrgb's three lines" || bad "console-colors.rgb" "$(cat "$HOME/.config/spark-shell/console-colors.rgb")"
unit=$H/root/etc/systemd/system/spark-shell-console.service
grep -qx "ExecStart=/usr/bin/setvtrgb $HOME/.config/spark-shell/console-colors.rgb" "$unit" && grep -q '^# rendered by spark-shell' "$unit" && grep -q 'systemctl enable spark-shell-console.service' "$H/log" \
    && ok "theme test (systemd): spark-shell-console.service written and enabled" || bad "console unit" "$(cat "$unit" 2>&1; cat "$H/log")"
grep -qx "setvtrgb $HOME/.config/spark-shell/console-colors.rgb" "$H/log" && ok "theme test: the kernel's defaults set now (setvtrgb)" || bad "setvtrgb now" "$(cat "$H/log")"
out=$(L theme test --dry-run)
[ "$(printf '%s\n' "$out" | tail -1)" = "Nothing to do" ] && ! printf '%s\n' "$out" | grep -q '^would' && ok "theme test again: Nothing to do" || bad "theme idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^ok     theme        test: theme.env and the console's palette are current$" && ok "check: the theme row is ok" || bad "check theme ok" "$(printf '%s\n' "$ck" | grep theme)"
echo '1,2,3' > "$H/root/sys/module/vt/parameters/default_red"
st=0; ck=$(L check) || st=$?
printf '%s\n' "$ck" | grep -q '^warn   theme        test: the console uses another palette until the next boot -- spark-shell on$' && ok "check: another palette live is a warn with its remedy" || bad "check theme warn" "$(printf '%s\n' "$ck" | grep theme)"
rm -f "$unit"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   theme        test: spark-shell-console.service does not set it at boot -- spark-shell on (sudo once)$' && ok "check: a missing unit is a FAIL with its remedy" || bad "check theme fail" "$(printf '%s\n' "$ck" | grep theme)"
L theme test >/dev/null
[ -f "$unit" ] && ok "theme test again: the unit is back" || bad "unit back"
: > "$H/log"
out=$(L theme none)
[ ! -e "$te" ] && [ ! -e "$unit" ] && [ ! -e "$HOME/.config/spark-shell/console-colors" ] && [ ! -e "$HOME/.config/spark-shell/console-colors.rgb" ] \
    && grep -q 'systemctl disable spark-shell-console.service' "$H/log" && grep -qx 'setvtrgb vga' "$H/log" && grep -qx 'THEME=none' "$HOME/.config/spark-shell/config" \
    && ok "theme none: theme.env, the unit and the console files gone, VGA set" || bad "theme none" "$out $(cat "$H/log")"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^ok     theme        none: the console's and the terminal's default colors" && ok "check: theme none is ok" || bad "check none" "$(printf '%s\n' "$ck" | grep theme)"

# the repository's palettes (gallery/theme/*.env): each one a theme NAME takes
if ls "$REPO"/gallery/theme/*.env >/dev/null 2>&1; then
    for env in "$REPO"/gallery/theme/*.env; do
        name=${env##*/}; name=${name%.env}
        rc=0; out=$(L theme "$name" 2>&1) || rc=$?
        [ "$rc" = 0 ] && [ "$(grep -c '^THEME_\(BG\|FG\|ACCENT\|MUTED\|ANSI_[0-9]*\)=#' "$HOME/.config/spark/theme.env")" = 20 ] \
            && ok "theme $name: the repository's palette is taken, 20 keys" || bad "theme $name" "rc=$rc $out"
    done
else
    printf '  NOTICE: no gallery/theme/*.env in this clone -- the repository'"'"'s palettes not exercised\n'
fi

# theme repaints the open terminals: plain files stand in for /dev/pts/N
# (SPARK_SHELL_PTS_DIR). 0 is yours and a tmux client's, 1 is not
# writable, 2 is a tmux pane, 3 is not yours, ptmx is never a terminal.
fresh
console_stubs Linux
palette_fixture test '#fe8019'
mkdir -p "$H/pts"
: > "$H/pts/0"; : > "$H/pts/1"; : > "$H/pts/2"; : > "$H/pts/ptmx"; chmod 0444 "$H/pts/1"
if [ "$(id -u)" = 0 ]; then : > "$H/pts/3"; chown 65534 "$H/pts/3"   # root: a file of nobody's
else ln -s /dev/null "$H/pts/3"; fi                                 # a user: root's /dev/null, writable by all
cat > "$H/lx/tmux" <<EOF
#!/bin/sh
echo "tmux \$*" >> "$H/tmux.log"
case \$1 in
    list-panes) echo "$H/pts/2" ;;
    list-clients) echo "$H/pts/0" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$H/lx/tmux"
want=$H/osc.want; : > "$want"
i=0
for c in 282828 cc241d 98971a d79921 458588 b16286 689d6a a89984 928374 fb4934 b8bb26 fabd2f 83a598 d3869b 8ec07c ebdbb2; do
    printf '\033]4;%d;#%s\033\\' "$i" "$c" >> "$want"; i=$((i + 1))
done
printf '\033]10;#ebdbb2\033\\\033]11;#282828\033\\' >> "$want"
cp "$want" "$H/osc.base"; printf '\033]112\033\\' >> "$want"
out=$(L theme test)
cmp -s "$want" "$H/pts/0" && ok "theme test: an open terminal of yours gets OSC 4 for the 16 slots, then OSC 10 and 11, and 112 (no cursor color of its own), byte for byte" || bad "repaint bytes" "$(od -c "$H/pts/0" | head -4)"
[ ! -s "$H/pts/2" ] && grep -q '^tmux list-panes -a -F #{pane_tty}$' "$H/tmux.log" && ok "theme test: a tmux pane gets nothing (tmux would keep the codes), its client's terminal gets them" || bad "repaint tmux pane" "$(od -c "$H/pts/2" | head -2; cat "$H/tmux.log")"
[ ! -s "$H/pts/ptmx" ] && ok "theme test: ptmx is never painted" || bad "repaint ptmx"
if [ "$(id -u)" = 0 ]; then
    [ ! -s "$H/pts/3" ] && ok "theme test: a terminal that is not yours gets nothing" || bad "repaint not yours"
    n=2   # root writes a file whatever its mode, and 1 is root's
else
    [ ! -s "$H/pts/1" ] && ok "theme test: a terminal you cannot write gets nothing" || bad "repaint not writable"
    ok "theme test: /dev/null (root's) is not yours, so it is skipped (the count says so)"
    n=1
fi
if [ "$n" = 1 ]; then said="Repainted 1 open terminal."; else said="Repainted $n open terminals."; fi
[ "$(printf '%s\n' "$out" | tail -2 | head -1)" = "$said" ] && [ "$(printf '%s\n' "$out" | tail -1)" = "The palette is test. A program that is already running, such as btop, takes it when it starts again." ] \
    && ok "theme test: one line counts the terminals, then the closing line" || bad "repaint line" "$out"
printf 'THEME_CURSOR=#FE8019\n' >> "$HOME/.config/spark-shell/themes/test.env"
cp "$H/osc.base" "$want"; printf '\033]12;#fe8019\033\\' >> "$want"
L theme test >/dev/null
cmp -s "$want" "$H/pts/0" && ok "theme test: a palette with THEME_CURSOR adds OSC 12, lowercase" || bad "repaint cursor" "$(od -c "$H/pts/0" | tail -3)"
: > "$H/pts/0"
out=$(L theme test --dry-run)
[ ! -s "$H/pts/0" ] && ! printf '%s\n' "$out" | grep -q '^Repainted' && ok "theme test --dry-run: no terminal is painted" || bad "repaint dry" "$out"
out=$(L theme none)
want_none=''; i=0; for h in 242424 f62b5a 47b413 e3c401 24acd4 f2affd 13c299 e6e6e6 616161 ff4d51 35d450 e9e836 5dc5f8 feabf2 24dfc4 ffffff; do want_none="$want_none${esc}]4;$i;#$h${esc}\\"; i=$((i + 1)); done
[ "$(cat "$H/pts/0")" = "$want_none${esc}]10;#ffffff${esc}\\${esc}]11;#242424${esc}\\${esc}]112${esc}\\" ] && [ ! -s "$H/pts/2" ] \
    && ok "theme none on Linux: foot's sixteen said outright with OSC 4, 10 and 11, the cursor reset; a reset alone takes a running foot back to the colors it started with (#29)" || bad "repaint none" "$(od -c "$H/pts/0" | head -3)"
[ "$(printf '%s\n' "$out" | tail -2 | head -1)" = "$said" ] && ok "theme none: the same line counts them" || bad "repaint none line" "$out"
rm -f "$H/pts/0" "$H/pts/1" "$H/pts/3"
out=$(L theme test)
! printf '%s\n' "$out" | grep -q '^Repainted' && ok "theme test: with no terminal to paint, no line" || bad "repaint nothing" "$out"
# on the desktop: a pty under foot (however deep) gets the five slots and the windows' transparency as foot's [NN];
# the dialog's own pty its surface, opaque; any other pty of yours the sixteen alone (#33, #34). ps says whose each is
printf 'DESKTOP=sway\nTHEME=test\nALPHA=0.75\n' > "$HOME/.config/spark-shell/config"
: > "$H/pts/4"; : > "$H/pts/5"; : > "$H/pts/6"
printf '#!/bin/sh\nprintf "%%s\\n" "  100     1 ?        foot" "  101   100 pts/4    sh" "  102   101 pts/4    bash" "  200     1 ?        foot" "  201   200 pts/5    sh" "  202   201 pts/5    spark-dialog" "  300     1 ?        sshd" "  301   300 pts/6    bash"\n' > "$H/lx/ps"
chmod +x "$H/lx/ps"
out=$(L theme test)
slots=$(printf '\033]4;16;#fe8019\033\\\033]4;17;#928374\033\\\033]4;18;#393834\033\\\033]4;19;#4b4840\033\\\033]4;20;#')
band=$(printf '\033]4;21;#6a4a2e\033\\')
grep -qF "$slots" "$H/pts/4" && grep -qF "$band" "$H/pts/4" && grep -qF "$(printf '\033]11;[75]#282828\033\\')" "$H/pts/4" \
    && grep -qF "$slots" "$H/pts/5" && grep -qF "$band" "$H/pts/5" && grep -qF "$(printf '\033]11;#393834\033\\')" "$H/pts/5" \
    && ! grep -qF "$(printf '\033]4;16;')" "$H/pts/6" && ! grep -qF "$band" "$H/pts/6" && grep -qF "$(printf '\033]11;#282828\033\\')" "$H/pts/6" \
    && printf '%s\n' "$out" | grep -qx 'Repainted 3 open terminals.' \
    && ok "theme test on the desktop: a window of foot takes the six slots (the header's band among them, v0.124.5) and its transparency ([75]), the dialog's window its surface, opaque; an ssh pty the sixteen alone" || bad "repaint kinds" "$(od -c "$H/pts/4" | tail -4; od -c "$H/pts/5" | tail -3; od -c "$H/pts/6" | tail -3; printf '%s\n' "$out" | tail -3)"
rm -f "$H/lx/ps" "$H/pts/4" "$H/pts/5" "$H/pts/6"
# macOS: Terminal.app is its profile's, no pty is written
fresh
console_stubs Darwin
palette_fixture test '#fe8019'
mkdir -p "$H/pts"; : > "$H/pts/0"
out=$(L theme test)
[ ! -s "$H/pts/0" ] && ! printf '%s\n' "$out" | grep -q '^Repainted' && ok "macOS: theme test writes to no pty (the profile does it)" || bad "mac repaint" "$out"

# theme, runit: one marked line in /etc/rc.local, and off hands it back byte for byte
fresh
console_stubs Linux
mkdir -p "$H/root/etc/runit"
printf '#!/bin/sh\n# yours\necho hello\n' > "$H/root/etc/rc.local"; cp "$H/root/etc/rc.local" "$H/rc.local.orig"
palette_fixture test '#fe8019'
L theme test >/dev/null
[ "$(grep -c ' #spark-shell-palette#$' "$H/root/etc/rc.local")" = 1 ] && head -3 "$H/root/etc/rc.local" | cmp -s - "$H/rc.local.orig" \
    && grep -q "^\[ -r '$HOME/.config/spark-shell/console-colors.rgb' \] && setvtrgb '$HOME/.config/spark-shell/console-colors.rgb' #spark-shell-palette#\$" "$H/root/etc/rc.local" \
    && [ ! -e "$H/root/etc/systemd" ] && ok "theme test (runit): one marked line at the end of /etc/rc.local, no unit" || bad "rc.local line" "$(cat "$H/root/etc/rc.local")"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     theme        test:' && ok "check (runit): the theme row is ok" || bad "check runit" "$(printf '%s\n' "$ck" | grep theme)"
L theme none >/dev/null
cmp -s "$H/root/etc/rc.local" "$H/rc.local.orig" && ok "theme none (runit): /etc/rc.local byte for byte as it was" || bad "rc.local back" "$(cat "$H/root/etc/rc.local")"
printf '#!/bin/sh\necho hello\nexit 0' > "$H/root/etc/rc.local"; cp "$H/root/etc/rc.local" "$H/rc.local.orig"   # a last line with no newline
L theme test >/dev/null
sed -n 3p "$H/root/etc/rc.local" | grep -q ' #spark-shell-palette#$' && [ "$(tail -c 6 "$H/root/etc/rc.local")" = 'exit 0' ] \
    && printf '%s\n' "$(L check || true)" | grep -q '^ok     theme        test:' && ok "theme test (runit): the line goes before a last exit 0, and check reads it there" || bad "rc.local exit 0" "$(cat "$H/root/etc/rc.local")"
L theme none >/dev/null
cmp -s "$H/root/etc/rc.local" "$H/rc.local.orig" && ok "theme none (runit): byte for byte again, the last line still without a newline" || bad "rc.local exit back" "$(od -c "$H/root/etc/rc.local" | tail -3)"
rm -f "$H/root/etc/rc.local"
L theme test >/dev/null
[ "$(head -1 "$H/root/etc/rc.local")" = '#!/bin/sh' ] && [ "$(wc -l < "$H/root/etc/rc.local" | tr -d ' ')" = 2 ] && ok "theme test (runit): no rc.local, one made with the shebang and the line" || bad "rc.local made" "$(cat "$H/root/etc/rc.local" 2>&1)"
L theme none >/dev/null
[ ! -e "$H/root/etc/rc.local" ] && ok "theme none (runit): the rc.local spark-shell made is gone" || bad "rc.local made gone" "$(cat "$H/root/etc/rc.local")"
# no root file (no systemd, no runit): theme none asks no root, sets no VGA with setvtrgb
fresh
console_stubs Linux
palette_fixture test '#fe8019'
L theme test >/dev/null; : > "$H/log"
L theme none >/dev/null
[ ! -e "$HOME/.config/spark-shell/console-colors" ] && ! grep -q setvtrgb "$H/log" && ok "theme none: only the files in ~/.config, no root asked" || bad "palette off no root" "$(cat "$H/log")"

# on applies THEME from the config before the renders; off hands the palette back
fresh
console_stubs Linux
mkdir -p "$H/root/run/systemd/system" "$HOME/.config/spark-shell"
palette_fixture test '#fb4934'
printf 'THEME=test\n' > "$HOME/.config/spark-shell/config"
out=$(L on --yes)
grep -q 'fg=colour9,bold' "$HOME/.tmux.conf" && [ -f "$H/root/etc/systemd/system/spark-shell-console.service" ] && ok "on: THEME=test is the palette the renders read (colour9), the unit written" || bad "on theme" "$out"
out=$(L on --dry-run)
printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "on again: Nothing to do with THEME set" || bad "on theme idempotent" "$out"
L theme test >/dev/null
palette_fixture test '#b8bb26'
out=$(L theme test)
grep -q 'fg=colour10,bold' "$HOME/.tmux.conf" && ok "theme NAME with the seat on: the renders follow (colour10)" || bad "theme follows" "$out $(grep color "$HOME/.tmux.conf" | head -2)"
out=$(L off --dry-run)
printf '%s\n' "$out" | grep -q '^would  palette ' && printf '%s\n' "$out" | grep -q '^would  theme ' && [ -f "$HOME/.config/spark/theme.env" ] \
    && ok "off --dry-run: would rows for the palette, nothing touched" || bad "off dry palette" "$out"
out=$(L off)
[ ! -e "$HOME/.config/spark/theme.env" ] && [ ! -e "$H/root/etc/systemd/system/spark-shell-console.service" ] && [ ! -e "$HOME/.config/spark-shell/console-colors" ] \
    && grep -qx 'THEME=test' "$HOME/.config/spark-shell/config" && ok "off: theme.env, the unit and the console files handed back, the config kept" || bad "off palette" "$out"
# a theme.env that is not spark-shell's stays on off
fresh
console_stubs Linux
theme_fixture '#ff5555'
L on --yes >/dev/null; L off >/dev/null
[ -f "$HOME/.config/spark/theme.env" ] && ok "off: a theme.env spark-shell did not write stays" || bad "foreign theme.env removed"

# font: console-setup (Debian), vconsole.conf (Arch), rc.conf (Void)
fresh
console_stubs Linux
mkdir -p "$H/root/etc/default" "$H/root/usr/share/consolefonts"
printf 'ACTIVE_CONSOLES="/dev/tty[1-6]"\nCHARMAP="UTF-8"\nCODESET="guess"\nFONTFACE="Fixed"\nFONTSIZE="8x16"\n' > "$H/root/etc/default/console-setup"
cp "$H/root/etc/default/console-setup" "$H/cs.orig"
: > "$H/root/usr/share/consolefonts/Uni2-Terminus32x16.psf.gz"; : > "$H/root/usr/share/consolefonts/Uni2-Fixed16.psf.gz"; : > "$H/root/usr/share/consolefonts/Lat15-TerminusBold32x16.psf.gz"
out=$(L font list)
printf '%s\n' "$out" | grep -q '^  Terminus  *16x32$' && printf '%s\n' "$out" | grep -q '^  Fixed  *8x16$' && printf '%s\n' "$out" | grep -q 'puts one in .*/etc/default/console-setup\.$' \
    && ok "font list (console-setup): the composed faces, WxH" || bad "font list setup" "$out"
rc=0; out=$(L font Terminus 8x16 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: Terminus comes in 16x32, not 8x16" ] && ok "font FACE SIZE: a size the face lacks is refused" || bad "font size refused" "rc=$rc $out"
rc=0; out=$(L font Nope 8x16 2>&1) || rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell font: no console font named Nope here' && ok "font FACE SIZE: an unknown face is refused" || bad "font face refused" "rc=$rc $out"
out=$(L font Terminus 16x32)
f=$H/root/etc/default/console-setup
grep -qx 'FONTFACE="Terminus"' "$f" && grep -qx 'FONTSIZE="16x32"' "$f" && grep -qx 'CODESET="guess"' "$f" && cmp -s "$f.spark-shell-orig" "$H/cs.orig" && grep -qx 'setupcon --force' "$H/log" \
    && grep -qx 'CONSOLE_FONT=Terminus 16x32' "$HOME/.config/spark-shell/config" && ok "font Terminus 16x32: console-setup set, its copy kept, setupcon ran" || bad "font setup" "$out $(cat "$f")"
[ "$(L font)" = "font  Terminus 16x32 ($f)" ] && ok "font: bare says the one in use" || bad "font show" "$(L font)"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^ok     font         Terminus 16x32 ($f)$" && ok "check: the font row is ok" || bad "check font" "$(printf '%s\n' "$ck" | grep font)"
printf '%s\n' "$(sed 's/^FONTFACE=.*/FONTFACE="VGA"/' "$f")" > "$f"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^FAIL   font         $f says VGA 16x32 -- spark-shell on (sudo once)$" && ok "check: a changed font is a FAIL with its remedy" || bad "check font fail" "$(printf '%s\n' "$ck" | grep font)"
L font none >/dev/null
cmp -s "$f" "$H/cs.orig" && [ ! -e "$f.spark-shell-orig" ] && ok "font none: console-setup byte for byte as it was, the copy gone" || bad "font none setup" "$(diff "$H/cs.orig" "$f")"
# vconsole.conf: a kbd font file's stem, its size from its own header
fresh
console_stubs Linux
mkdir -p "$H/root/etc" "$H/root/usr/share/kbd/consolefonts"
printf 'KEYMAP=us\n' > "$H/root/etc/vconsole.conf"; cp "$H/root/etc/vconsole.conf" "$H/vc.orig"
psf2 "$H/root/usr/share/kbd/consolefonts/ter-132n.psf.gz"; psf1 "$H/root/usr/share/kbd/consolefonts/lat2-16.psfu"
out=$(L font list)
printf '%s\n' "$out" | grep -q '^  ter-132n  *16x32$' && printf '%s\n' "$out" | grep -q '^  lat2-16  *8x16$' && ok "font list (vconsole): sizes read from each file's header (PSF2, PSF1)" || bad "font list vconsole" "$out"
L font ter-132n 16x32 >/dev/null
grep -qx 'FONT=ter-132n' "$H/root/etc/vconsole.conf" && grep -qx 'systemctl restart systemd-vconsole-setup' "$H/log" && ok "font ter-132n 16x32: vconsole.conf FONT= added, the console redrawn" || bad "font vconsole" "$(cat "$H/root/etc/vconsole.conf")"
L font none >/dev/null
cmp -s "$H/root/etc/vconsole.conf" "$H/vc.orig" && ok "font none: vconsole.conf as it was (the added line gone)" || bad "font none vconsole" "$(cat "$H/root/etc/vconsole.conf")"
# rc.conf beside /etc/runit: the commented FONT= line is the one taken over, and given back
fresh
console_stubs Linux
mkdir -p "$H/root/etc/runit" "$H/root/usr/share/kbd/consolefonts"
printf '# /etc/rc.conf\nHARDWARECLOCK="UTC"\n#FONT="lat9w-16"\n#FONT_MAP=\n' > "$H/root/etc/rc.conf"; cp "$H/root/etc/rc.conf" "$H/rc.orig"
psf2 "$H/root/usr/share/kbd/consolefonts/ter-132n.psf.gz"
L font ter-132n 16x32 >/dev/null
[ "$(sed -n 3p "$H/root/etc/rc.conf")" = 'FONT="ter-132n"' ] && grep -qx '#FONT_MAP=' "$H/root/etc/rc.conf" && grep -qx 'setfont ter-132n' "$H/log" \
    && ok "font ter-132n 16x32 (rc.conf): the #FONT= line taken over, FONT_MAP kept, setfont now" || bad "font rcconf" "$(cat "$H/root/etc/rc.conf")"
L font none >/dev/null
cmp -s "$H/root/etc/rc.conf" "$H/rc.orig" && ok "font none (rc.conf): byte for byte as it was" || bad "font none rcconf" "$(cat "$H/root/etc/rc.conf")"
# no console file, and WSL: one sentence each
fresh
console_stubs Linux
rc=0; out=$(L font ter-132n 16x32 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: this Linux has no console-setup, vconsole.conf or rc.conf." ] && ok "font: no console file here, one sentence" || bad "font no shape" "rc=$rc $out"
rc=0; out=$(WSL_DISTRO_NAME=Debian L font ter-132n 16x32 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: WSL has no console: the font is Windows Terminal's." ] && ok "font on WSL: one sentence" || bad "font wsl" "rc=$rc $out"

# quiet login: the motd, the issue and 10-uname, back only while still spark-shell's
fresh
console_stubs Linux
mkdir -p "$H/root/etc/update-motd.d"
printf 'The programs included with Debian are free software.\n' > "$H/root/etc/motd"; printf 'Debian GNU/Linux 13 \\n \\l\n\n' > "$H/root/etc/issue"
printf '#!/bin/sh\nuname -snrvm\n' > "$H/root/etc/update-motd.d/10-uname"; chmod +x "$H/root/etc/update-motd.d/10-uname"
cp "$H/root/etc/motd" "$H/motd.orig"; cp "$H/root/etc/issue" "$H/issue.orig"
L quiet login on >/dev/null
[ ! -s "$H/root/etc/motd" ] && [ "$(cat "$H/root/etc/issue")" = "${esc}[?25h" ] && [ ! -x "$H/root/etc/update-motd.d/10-uname" ] && grep -qx 'QUIET_LOGIN=yes' "$HOME/.config/spark-shell/config" \
    && cmp -s "$H/root/etc/motd.spark-shell-orig" "$H/motd.orig" && ok "quiet login on: motd empty, issue the cursor escape, 10-uname off, copies kept" || bad "quiet login on" "$(ls -la "$H/root/etc")"
out=$(L quiet login on --dry-run)
[ "$(printf '%s\n' "$out" | tail -1)" = "Nothing to do" ] && ! printf '%s\n' "$out" | grep -q '^would' && ok "quiet login on again: Nothing to do" || bad "quiet login idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     quiet        login quiet, ' && ok "check: the quiet row says login quiet" || bad "check quiet login" "$(printf '%s\n' "$ck" | grep quiet)"
L quiet login off >/dev/null
cmp -s "$H/root/etc/motd" "$H/motd.orig" && cmp -s "$H/root/etc/issue" "$H/issue.orig" && [ -x "$H/root/etc/update-motd.d/10-uname" ] && [ ! -e "$H/root/etc/motd.spark-shell-orig" ] \
    && ok "quiet login off: motd and issue byte for byte, 10-uname runs again" || bad "quiet login off" "$(ls -la "$H/root/etc")"
L quiet login on >/dev/null
printf 'mine now\n' > "$H/root/etc/motd"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/motd")" = 'mine now' ] && [ ! -e "$H/root/etc/motd.spark-shell-orig" ] && cmp -s "$H/root/etc/issue" "$H/issue.orig" \
    && ok "quiet login off: a motd you changed since stays yours, only the stale copy goes" || bad "quiet login yours" "$(cat "$H/root/etc/motd")"
[ "$(L quiet login)" = "login  off: the distro's notice and the kernel line (spark-shell quiet login on)" ] && ok "quiet login: bare says the state" || bad "quiet login show" "$(L quiet login)"
# only spark-shell's own records: never an escape-only issue it did not
# write, nothing while spark core's /etc/issue.orig is there
printf '%s' "${esc}[?25h" > "$H/root/etc/issue"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/issue")" = "${esc}[?25h" ] && ok "quiet login off: an escape-only issue spark-shell did not write stays" || bad "foreign issue" "$(od -c "$H/root/etc/issue")"
printf 'Debian\n' > "$H/root/etc/issue.orig"; printf 'ours\n' > "$H/root/etc/issue.spark-shell-orig"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/issue")" = "${esc}[?25h" ] && [ -e "$H/root/etc/issue.orig" ] && [ -e "$H/root/etc/issue.spark-shell-orig" ] \
    && ok "quiet login off: nothing moves while spark core's /etc/issue.orig is there" || bad "spark core issue" "$(ls "$H/root/etc")"
rm -f "$H/root/etc/issue.orig"; : > "$H/root/etc/issue"
L quiet login off >/dev/null
[ "$(cat "$H/root/etc/issue")" = ours ] && [ ! -e "$H/root/etc/issue.spark-shell-orig" ] && ok "quiet login off: an empty issue comes back from spark-shell's copy" || bad "empty issue" "$(cat "$H/root/etc/issue")"
# Debian 13 has no /etc/motd: 10-uname comes back by its own mark
rm -f "$H/root/etc/motd"; chmod +x "$H/root/etc/update-motd.d/10-uname"
L quiet login on >/dev/null
[ ! -x "$H/root/etc/update-motd.d/10-uname" ] && [ -e "$HOME/.local/state/spark-shell/uname.off" ] && ok "quiet login on, no motd: 10-uname off, its mark kept" || bad "uname off" "$(ls -la "$H/root/etc/update-motd.d")"
L quiet login off >/dev/null
[ -x "$H/root/etc/update-motd.d/10-uname" ] && [ ! -e "$HOME/.local/state/spark-shell/uname.off" ] && ok "quiet login off, no motd: 10-uname runs again" || bad "uname back" "$(ls -la "$H/root/etc/update-motd.d")"
rc=0; out=$(L quiet loud on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: loud is not known here (login or boot)" ] && ok "quiet WORD: an unknown word is one sentence" || bad "quiet word" "rc=$rc $out"

# quiet boot, Debian: one GRUB drop-in, /etc/default/grub never edited, a failed rebuild runs again
fresh
console_stubs Linux
printf 'ID=debian\n' > "$H/os-release"
mkdir -p "$H/root/etc/default"
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' > "$H/root/etc/default/grub"; cp "$H/root/etc/default/grub" "$H/grub.orig"
L quiet boot on --yes >/dev/null
d=$H/root/etc/default/grub.d/zz-spark-shell-quiet.cfg
[ "$(cat "$d")" = "GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_CMDLINE_LINUX_DEFAULT=\"\$GRUB_CMDLINE_LINUX_DEFAULT quiet splash loglevel=3 systemd.show_status=false udev.log_level=3 fbcon=nodefer\"" ] \
    && cmp -s "$H/root/etc/default/grub" "$H/grub.orig" && grep -qx update-grub "$H/log" && [ ! -e "$HOME/.local/state/spark-shell/boot-rebuild" ] \
    && ok "quiet boot on (Debian): the drop-in, update-grub, /etc/default/grub untouched" || bad "quiet boot grub" "$(cat "$d" 2>&1)"
out=$(L quiet boot on --dry-run)
[ "$(printf '%s\n' "$out" | tail -1)" = "Nothing to do" ] && ! printf '%s\n' "$out" | grep -q '^would' && ok "quiet boot on again: Nothing to do" || bad "quiet boot idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     quiet        login loud, boot quiet$' && ok "check: boot quiet" || bad "check boot quiet" "$(printf '%s\n' "$ck" | grep quiet)"
mkdir -p "$H/root/proc"; echo 'BOOT_IMAGE=/vmlinuz ro quiet' > "$H/root/proc/cmdline"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^warn   quiet        login loud, boot quiet after a reboot -- reboot: the next boot is quiet$' && ok "check: a running kernel without the line is a warn" || bad "check boot warn" "$(printf '%s\n' "$ck" | grep quiet)"
: > "$H/fail"
out=$(L quiet boot off)
[ ! -e "$d" ] && grep -qx grub "$HOME/.local/state/spark-shell/boot-rebuild" && printf '%s\n' "$out" | grep -q '^todo   quiet        boot: update-grub failed -- spark-shell on runs it again$' \
    && ok "quiet boot off, update-grub failing: the drop-in gone, the rebuild pending, a todo" || bad "boot off fail" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   quiet        login loud, boot still quiet (QUIET_BOOT=no) -- spark-shell on (sudo once)$' && ok "check: a pending rebuild is a FAIL" || bad "check pending" "$(printf '%s\n' "$ck" | grep quiet)"
rm -f "$H/fail"; : > "$H/log"
L on --yes >/dev/null
grep -qx update-grub "$H/log" && [ ! -e "$HOME/.local/state/spark-shell/boot-rebuild" ] && cmp -s "$H/root/etc/default/grub" "$H/grub.orig" \
    && ok "on: the pending update-grub runs again and the mark goes" || bad "rebuild retry" "$(cat "$H/log")"
# quiet boot, Void: marked lines at the end of three files, byte for byte back
fresh
console_stubs Linux
printf 'ID="void"\n' > "$H/os-release"
mkdir -p "$H/root/etc/default" "$H/root/etc/runit" "$H/root/etc/sv/agetty-tty1"
printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5' > "$H/root/etc/default/grub"   # no final newline: the first marked line must not glue on
printf '# /etc/rc.conf\nKEYMAP="us"\n' > "$H/root/etc/rc.conf"; printf 'GETTY_ARGS="--noclear"\n' > "$H/root/etc/sv/agetty-tty1/conf"
cp "$H/root/etc/rc.conf" "$H/rc.orig"; cp "$H/root/etc/sv/agetty-tty1/conf" "$H/getty.orig"
L quiet boot on --yes >/dev/null
[ "$(grep -c ' #spark-shell-quiet#$' "$H/root/etc/default/grub")" = 3 ] && [ "$(grep -c ' #spark-shell-quiet#$' "$H/root/etc/rc.conf")" = 10 ] && [ "$(grep -c ' #spark-shell-quiet#$' "$H/root/etc/sv/agetty-tty1/conf")" = 2 ] \
    && grep -qx 'GRUB_TIMEOUT=5' "$H/root/etc/default/grub" && grep -qx 'GRUB_TIMEOUT=0 #spark-shell-quiet#' "$H/root/etc/default/grub" && grep -qx update-grub "$H/log" \
    && ok "quiet boot on (Void): 3, 10 and 2 marked lines, nothing glued, update-grub" || bad "quiet boot void" "$(cat "$H/root/etc/default/grub")"
sh -n "$H/root/etc/rc.conf" && sh -n "$H/root/etc/sv/agetty-tty1/conf" && ok "quiet boot on (Void): rc.conf and the getty's conf still parse" || bad "void lines parse"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     quiet        login loud, boot quiet$' && ok "check (Void): boot quiet" || bad "check void boot" "$(printf '%s\n' "$ck" | grep quiet)"
L quiet boot off >/dev/null
[ "$(cat "$H/root/etc/default/grub")" = "$(printf 'GRUB_DEFAULT=0\nGRUB_TIMEOUT=5')" ] && cmp -s "$H/root/etc/rc.conf" "$H/rc.orig" && cmp -s "$H/root/etc/sv/agetty-tty1/conf" "$H/getty.orig" \
    && ok "quiet boot off (Void): the three files as they were (grub's lines, rc.conf and the getty's byte for byte)" || bad "void off" "$(cat "$H/root/etc/rc.conf")"
# quiet boot, Arch with a unified kernel image: the cmdline drop-in, the splash marked, loader.conf's wait
fresh
console_stubs Linux
printf 'ID=arch\n' > "$H/os-release"
mkdir -p "$H/root/etc/mkinitcpio.d" "$H/root/boot/loader"
printf 'ALL_kver="/boot/vmlinuz-linux"\ndefault_uki="/efi/EFI/Linux/arch-linux.efi"\ndefault_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"\n' > "$H/root/etc/mkinitcpio.d/linux.preset"
printf 'timeout 3\n#console-mode max\n' > "$H/root/boot/loader/loader.conf"
cp "$H/root/etc/mkinitcpio.d/linux.preset" "$H/preset.orig"; cp "$H/root/boot/loader/loader.conf" "$H/loader.orig"
L quiet boot on --yes >/dev/null
[ "$(cat "$H/root/etc/cmdline.d/zz-spark-shell-quiet.conf")" = 'quiet splash loglevel=3 systemd.show_status=false udev.log_level=3 fbcon=nodefer' ] \
    && grep -q '^#spark-shell-quiet# default_options=' "$H/root/etc/mkinitcpio.d/linux.preset" && [ "$(head -1 "$H/root/boot/loader/loader.conf")" = 'timeout 0' ] && grep -qx 'mkinitcpio -P' "$H/log" \
    && ok "quiet boot on (Arch UKI): the drop-in, the splash marked off, timeout 0, mkinitcpio -P" || bad "quiet boot uki" "$(cat "$H/root/etc/mkinitcpio.d/linux.preset" "$H/root/boot/loader/loader.conf")"
L quiet boot off >/dev/null
[ ! -e "$H/root/etc/cmdline.d/zz-spark-shell-quiet.conf" ] && cmp -s "$H/root/etc/mkinitcpio.d/linux.preset" "$H/preset.orig" && cmp -s "$H/root/boot/loader/loader.conf" "$H/loader.orig" \
    && [ "$(grep -c 'mkinitcpio -P' "$H/log")" = 2 ] && ok "quiet boot off (Arch UKI): the preset and loader.conf byte for byte, the image rebuilt" || bad "uki off" "$(cat "$H/root/boot/loader/loader.conf")"
# the ESP is vfat: a chmod there fails, and quiet boot on still reaches mkinitcpio -P
mkdir -p "$H/esp"
printf '#!/bin/sh\nfor a; do case $a in %s/root/boot/*) echo "chmod: not permitted" >&2; exit 1 ;; esac; done\nexec /bin/chmod "$@"\n' "$H" > "$H/esp/chmod"; /bin/chmod +x "$H/esp/chmod"
rm -f "$H/root/boot/loader/loader.conf"; : > "$H/log"
rc=0; PATH=$H/esp:$H/lx:$PATH sh "$SH" quiet boot on --yes >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$H/root/boot/loader/loader.conf")" = 'timeout 0' ] && [ -e "$H/root/boot/loader/loader.conf.spark-shell-orig" ] && grep -qx 'mkinitcpio -P' "$H/log" \
    && ok "quiet boot on (Arch UKI, vfat ESP): a failed chmod is no error, timeout 0 and mkinitcpio -P" || bad "uki vfat" "rc=$rc $(cat "$H/log")"
PATH=$H/esp:$H/lx:$PATH sh "$SH" quiet boot off >/dev/null 2>&1
[ ! -s "$H/root/boot/loader/loader.conf" ] && [ ! -e "$H/root/boot/loader/loader.conf.spark-shell-orig" ] && ok "quiet boot off (Arch UKI, vfat ESP): no timeout line of spark-shell's left" || bad "uki vfat off" "$(cat "$H/root/boot/loader/loader.conf")"
# refused in one sentence: an Arch without a UKI, WSL, macOS
rm -f "$H/root/etc/mkinitcpio.d/linux.preset"
rc=0; out=$(L quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: This Arch has no unified kernel image, so its kernel line is the boot loader's and stays as it is." ] && grep -qx 'QUIET_BOOT=no' "$HOME/.config/spark-shell/config" \
    && ok "quiet boot on (Arch, no UKI): one sentence, the config untouched" || bad "arch no uki" "rc=$rc $out"
rc=0; out=$(WSL_DISTRO_NAME=Debian L quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: WSL has no boot of its own: Windows boots it." ] && ok "quiet boot on (WSL): one sentence" || bad "wsl boot" "rc=$rc $out"
# Fedora and openSUSE boot through GRUB 2 with grub2-mkconfig, which spark-shell does not run: one sentence, nothing run, status says na
# (the system's tools alone on PATH: an Ubuntu runner has update-grub under /usr/sbin)
fresh
console_stubs Linux
rm -f "$H/lx/update-grub"; printf '#!/bin/sh\necho "grub2-mkconfig $*" >> "%s/log"\n' "$H" > "$H/lx/grub2-mkconfig"; chmod +x "$H/lx/grub2-mkconfig"
printf 'ID=fedora\n' > "$H/os-release"
mkdir -p "$H/root/etc/default"; printf 'GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX="rhgb quiet"\n' > "$H/root/etc/default/grub"; cp "$H/root/etc/default/grub" "$H/grub.orig"
( PATH=$H/lx:$sys without_tools "$H/grub2-only" update-grub grub-mkconfig )
rc=0; out=$(PATH=$H/grub2-only sh "$SH" quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: This Linux boots through grub2-mkconfig, whose boot entries spark-shell does not edit, so the boot stays as it is (Fedora and openSUSE boot quiet already)." ] \
    && cmp -s "$H/root/etc/default/grub" "$H/grub.orig" && ! grep -q grub2-mkconfig "$H/log" && ok "quiet boot on (Fedora, grub2-mkconfig): one sentence, nothing run, nothing written" || bad "grub2 boot" "rc=$rc $out"
out=$(PATH=$H/grub2-only sh "$SH" quiet); printf '%s\n' "$out" | grep -q '^boot   na: This Linux boots through grub2-mkconfig' && ok "quiet (Fedora): boot na, the sentence" || bad "grub2 quiet" "$out"
st=$(PATH=$H/grub2-only sh "$SH" status); printf '%s\n' "$st" | grep -q '^  quiet login off  *boot na ' && ok "status (Fedora): boot na" || bad "grub2 status" "$(printf '%s\n' "$st" | grep quiet)"
# WSL 2 (Ubuntu): the terminal seat alone; the desktop and the login screen are refused in one sentence, nothing written
fresh
console_stubs Linux
printf 'ID=ubuntu\nID_LIKE=debian\n' > "$H/os-release"
rc=0; out=$(WSL_DISTRO_NAME=Ubuntu L on desktop --yes 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: not on WSL, where Windows draws the desktop" ] && [ ! -e "$HOME/.config/spark-shell/config" ] && ok "on desktop (WSL): one sentence, the config untouched" || bad "wsl on desktop" "rc=$rc $out"
rc=0; out=$(WSL_DISTRO_NAME=Ubuntu L on login --yes 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell login: not on WSL, which has no tty1 for a login screen" ] && [ ! -e "$HOME/.config/spark-shell/config" ] && ok "on login (WSL): one sentence, the config untouched" || bad "wsl on login" "rc=$rc $out"
rc=0; out=$(WSL_DISTRO_NAME=Ubuntu L desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: not on WSL, where Windows draws the desktop" ] && ok "desktop (WSL): one sentence" || bad "wsl desktop" "rc=$rc $out"
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\nLOGIN=yes\n' > "$HOME/.config/spark-shell/config"   # a config carried over from a Linux machine
out=$(WSL_DISTRO_NAME=Ubuntu L on --dry-run 2>&1)
printf '%s\n' "$out" | grep -q '^skip   desktop      not on WSL, where Windows draws the desktop$' && ! printf '%s\n' "$out" | grep -q 'sway/config' && ! printf '%s\n' "$out" | grep -q '^would  login' \
    && ok "on (WSL) with DESKTOP=sway and LOGIN=yes: a skip row, no desktop render, no login screen" || bad "wsl on sway" "$out"
st=$(WSL_DISTRO_NAME=Ubuntu L status)
printf '%s\n' "$st" | grep -q '^  desktop sway  *not on WSL, where Windows draws the desktop$' && printf '%s\n' "$st" | grep -q '^  login na  *not on WSL, which has no tty1 for a login screen$' \
    && ok "status (WSL): the desktop and login rows say na" || bad "wsl status" "$(printf '%s\n' "$st" | grep -E 'desktop|login')"
ck=$(WSL_DISTRO_NAME=Ubuntu L check || true)
printf '%s\n' "$ck" | grep -q '^ok     desktop      na (WSL)$' && printf '%s\n' "$ck" | grep -q '^ok     pointer      na (no desktop)$' && printf '%s\n' "$ck" | grep -q '^ok     login        na (' \
    && ok "check (WSL): the desktop, pointer and login rows are na" || bad "wsl check" "$(printf '%s\n' "$ck" | grep -E 'desktop|pointer|login')"

# on and off: every key applied from the config, then everything handed back byte for byte
fresh
console_stubs Linux
printf 'ID=debian\n' > "$H/os-release"
mkdir -p "$H/root/run/systemd/system" "$H/root/etc/default" "$H/root/usr/share/consolefonts" "$HOME/.config/spark-shell"
printf 'FONTFACE="Fixed"\nFONTSIZE="8x16"\n' > "$H/root/etc/default/console-setup"; : > "$H/root/usr/share/consolefonts/Uni2-Terminus32x16.psf.gz"
printf 'GRUB_TIMEOUT=5\n' > "$H/root/etc/default/grub"; printf 'motd\n' > "$H/root/etc/motd"; printf 'issue\n' > "$H/root/etc/issue"
( cd "$H/root" && find etc -type f | sort | while read -r f; do cksum "$f"; done ) > "$H/before"
palette_fixture test '#fe8019'
printf 'THEME=test\nCONSOLE_FONT=Terminus 16x32\nQUIET_LOGIN=yes\nQUIET_BOOT=yes\n' > "$HOME/.config/spark-shell/config"
L on --yes >/dev/null
ck=$(L check || true)
[ "$(printf '%s\n' "$ck" | grep -cE '^ok     (theme|font|quiet) ')" = 3 ] && ok "on: THEME, CONSOLE_FONT and QUIET_* applied from the config, three ok rows" || bad "on console" "$(printf '%s\n' "$ck" | grep -E 'theme|font|quiet')"
st=$(L status)
printf '%s\n' "$st" | grep -q '^  font  Terminus 16x32 ' && printf '%s\n' "$st" | grep -q '^  quiet login on  *boot on (' && printf '%s\n' "$st" | grep -q '^  theme test ' \
    && ok "status: the theme, font and quiet rows" || bad "status console" "$st"
L off >/dev/null
( cd "$H/root" && find etc -type f | sort | while read -r f; do cksum "$f"; done ) > "$H/after"
cmp -s "$H/before" "$H/after" && [ ! -e "$HOME/.config/spark/theme.env" ] && ok "off: every root file byte for byte as before, no copy, no unit, no drop-in" || bad "off console" "$(diff "$H/before" "$H/after")"

# Void: the terminal setup; the package names looked up through xbps
fresh
console_stubs Linux
printf 'NAME="Void"\nID="void"\n' > "$H/os-release"
printf '#!/bin/sh\nexit 0\n' > "$H/lx/xbps-query"; chmod +x "$H/lx/xbps-query"
out=$(L on --dry-run)
printf '%s\n' "$out" | grep -q '^ok     packages     installed$' && printf '%s\n' "$out" | grep -q '^skip   desktop      DESKTOP=none (the config)$' \
    && ok "Void: xbps finds the packages, the desktop row is the config's" || bad "void dry-run" "$out"
L on --yes >/dev/null
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     desktop      na (DESKTOP=none)$' && ok "Void: check says the desktop is na while DESKTOP=none" || bad "void check" "$(printf '%s\n' "$ck" | grep desktop)"
grep -q '^PKG_CONSOLE=kbd$' "$REPO/distro/void.env" && ok "distro/void.env: kbd for the console" || bad "void.env"
if command -v jq >/dev/null 2>&1; then
    mkdir -p "$H/root/var/db/xbps"
    printf '<key>files</key><string>/usr/bin/tmux</string>\n' > "$H/root/var/db/xbps/.tmux-files.plist"
    cat > "$H/lx/xbps-query" <<'EOF'
#!/bin/sh
case "$1" in
    -m) echo tmux-3.7c_1 ;;
    -l) echo 'ii tmux-3.7c_1                        Terminal Multiplexer'; echo 'ii ncurses-libs-6.6_1                Libraries' ;;
    -p) [ "$3" = tmux ] && echo ISC ;;
esac
exit 0
EOF
    out=$(L sbom tmux)
    printf '%s\n' "$out" | grep -q '^tool  tmux 3.7c_1$' && printf '%s\n' "$out" | grep -q '^  licence   ISC$' && printf '%s\n' "$out" | grep -q '^  reason    chosen$' && printf '%s\n' "$out" | grep -q '^  commands  tmux$' \
        && ok "Void: sbom reads xbps (version, licence, chosen, commands)" || bad "void sbom" "$out"
fi

# Void: the desktop too. No logind there, so on desktop links seatd into
# /var/service and adds you to _seatd, each with a record of its own, and
# off desktop undoes exactly what the records say. The package manager,
# usermod, gpasswd and pgrep are stubs; /etc/group is the root's.
void_desktop
out=$(L on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -q '^would  desktop      seatd: link /etc/sv/seatd into /var/service' && printf '%s\n' "$out" | grep -q "^would  desktop      add $me to the _seatd group (sudo)\$" \
    && [ ! -e "$H/root/var/service/seatd" ] && ! grep -q 'usermod' "$H/log" && [ ! -e "$HOME/.config/spark-shell/config" ] \
    && ok "Void: on desktop --dry-run says seatd and the group, touches nothing" || bad "void desktop dry-run" "$out"
out=$(L on desktop --yes </dev/null 2>&1); st=$?
[ "$st" -eq 0 ] && [ -L "$H/root/var/service/seatd" ] && [ "$(readlink "$H/root/var/service/seatd")" = /etc/sv/seatd ] \
    && ok "Void: on desktop links /etc/sv/seatd into /var/service" || bad "void seatd link" "st=$st $out"
grep -q "^_seatd:x:990:$me\$" "$H/root/etc/group" && grep -qx "usermod -aG _seatd $me" "$H/log" && ok "Void: on desktop adds you to _seatd (usermod -aG)" || bad "void group" "$(cat "$H/root/etc/group" "$H/log")"
[ -f "$HOME/.local/state/spark-shell/seatd.linked" ] && [ -f "$HOME/.local/state/spark-shell/seatd.group" ] && ok "Void: both steps recorded (seatd.linked, seatd.group)" || bad "void records" "$(ls "$HOME/.local/state/spark-shell" 2>&1)"
printf '%s\n' "$out" | grep -q "^ok     desktop      $me is in the _seatd group now: it takes effect at your next login\$" && ok "Void: one line says the group takes effect at the next login" || bad "void group line" "$out"
grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" && [ -f "$HOME/.config/sway/config" ] && [ -f "$HOME/.config/foot/foot.ini" ] && ok "Void: on desktop writes DESKTOP=sway and renders sway and foot" || bad "void renders" "$out"
[ ! -e "$H/root/etc/greetd" ] && ! grep -q 'greetd\|getty' "$H/log" && ok "Void: no greetd, getty left alone" || bad "void greetd" "$(cat "$H/log")"
: > "$H/log"; out=$(L on --dry-run </dev/null)
[ "$(printf '%s\n' "$out" | tail -1)" = 'Nothing to do' ] && ok "Void: on --dry-run after on desktop: Nothing to do" || bad "void idempotent" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     desktop      sway and foot' && ok "Void: check says the desktop is ok" || bad "void check ok" "$(printf '%s\n' "$ck" | grep desktop)"
printf '#!/bin/sh\n:\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
st=$(L status); printf '%s\n' "$st" | grep -q '^  next  desktop .*Log out and in again: the _seatd group takes effect at the next login\.$' && ok "Void: status next says to log in again for the group" || bad "void next group" "$(printf '%s\n' "$st" | grep next)"
rm -f "$H/root/var/service/seatd"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^FAIL   desktop      seatd does not start at boot (Void has no logind) -- spark-shell on desktop$' && ok "Void: check FAILs without seatd at boot, the remedy is on desktop" || bad "void check seatd" "$(printf '%s\n' "$ck" | grep desktop)"
st=$(L status); printf '%s\n' "$st" | grep -q '^  next  desktop .*spark-shell on desktop at a terminal sets up seatd (sudo once)\.$' && ok "Void: status next says on desktop sets up seatd" || bad "void next seatd" "$(printf '%s\n' "$st" | grep next)"
rm -f "$H/.local/bin/spark"
L on --yes >/dev/null </dev/null
[ -L "$H/root/var/service/seatd" ] && ok "Void: on (DESKTOP=sway) links seatd again" || bad "void relink"
out=$(L theme wallpaper none 2>&1) && grep -q '^WALLPAPER=default$' "$HOME/.config/spark-shell/config" && ok "Void: desktop wallpaper is no longer refused (none is the ground, #35)" || bad "void wallpaper" "$out"
# off desktop while a desktop runs: seatd stays (stopping it would end it), the group goes
: > "$H/sway-running"; : > "$H/log"
out=$(L off desktop 2>&1)
[ -L "$H/root/var/service/seatd" ] && [ -f "$HOME/.local/state/spark-shell/seatd.linked" ] && printf '%s\n' "$out" | grep -q '^todo   desktop      seatd stays while a desktop runs' \
    && ok "Void: off desktop with a desktop running keeps seatd, one todo row" || bad "void off running" "$out"
! grep -q "^_seatd:x:990:.*$me" "$H/root/etc/group" && grep -qx "gpasswd -d $me _seatd" "$H/log" && [ ! -e "$HOME/.local/state/spark-shell/seatd.group" ] \
    && ok "Void: off desktop takes you out of _seatd (gpasswd -d), the record gone" || bad "void off group" "$(cat "$H/root/etc/group" "$H/log")"
rm -f "$H/sway-running"
out=$(L off desktop --dry-run)
printf '%s\n' "$out" | grep -q "^would  desktop      seatd's link and your _seatd membership removed" && [ -L "$H/root/var/service/seatd" ] && ok "Void: off desktop --dry-run says seatd, touches nothing" || bad "void off dry" "$out"
out=$(L off desktop 2>&1)
[ ! -e "$H/root/var/service/seatd" ] && [ ! -L "$H/root/var/service/seatd" ] && [ ! -e "$HOME/.local/state/spark-shell/seatd.linked" ] && printf '%s\n' "$out" | grep -q '^ok     desktop      seatd no longer starts at boot' \
    && ok "Void: off desktop after leaving the desktop removes the link spark-shell made" || bad "void off link" "$out"
[ -d "$H/root/etc/sv/seatd" ] && ok "Void: off desktop leaves the package's /etc/sv/seatd alone" || bad "void sv dir"
: > "$H/log"; out=$(L off desktop 2>&1)
! printf '%s\n' "$out" | grep -q 'seatd' && ! grep -q 'gpasswd\|usermod' "$H/log" && ok "Void: off desktop twice: nothing of seatd's left to undo, nothing said" || bad "void off twice" "$out"
# a seatd you set up yourself: on desktop records nothing, off desktop leaves it
void_desktop
ln -s /etc/sv/seatd "$H/root/var/service/seatd"
printf 'root:x:0:\n_seatd:x:990:%s\n' "$me" > "$H/root/etc/group"; cp "$H/root/etc/group" "$H/group.orig"
L on desktop --yes >/dev/null </dev/null
[ ! -e "$HOME/.local/state/spark-shell/seatd.linked" ] && [ ! -e "$HOME/.local/state/spark-shell/seatd.group" ] && ! grep -q usermod "$H/log" && ok "Void: a seatd and a group already there are not recorded as spark-shell's" || bad "void yours on" "$(ls "$HOME/.local/state/spark-shell")"
L off >/dev/null
[ -L "$H/root/var/service/seatd" ] && cmp -s "$H/root/etc/group" "$H/group.orig" && ! grep -q gpasswd "$H/log" && ok "Void: off leaves your own seatd link and membership as they were" || bad "void yours off" "$(cat "$H/log")"
# seatd not installed yet: a todo row after the packages, nothing linked
void_desktop
rm -rf "$H/root/etc/sv/seatd"
out=$(L on desktop --yes </dev/null 2>&1)
printf '%s\n' "$out" | grep -q '^todo   desktop      seatd is not installed -- spark-shell on desktop (the packages)$' && [ ! -e "$H/root/var/service/seatd" ] && ok "Void: no seatd package, a todo row, no link" || bad "void no seatd" "$out"
# the sound on Void: PipeWire's two ALSA files linked into /etc/alsa/conf.d
# (Void's package leaves them in /usr/share) and you in the audio group (no
# logind), each recorded; off desktop undoes exactly those
void_sound
out=$(L on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -q '^would  sound        ALSA programs play through PipeWire: link 50-pipewire.conf 99-pipewire-default.conf into /etc/alsa/conf.d (sudo)$' \
    && printf '%s\n' "$out" | grep -q "^would  sound        add $me to the audio group: the sound devices open to you (sudo)\$" \
    && printf '%s\n' "$out" | grep -q "^would  sound        remove $HOME/.config/alsa/asoundrc: PipeWire picks the output now\$" \
    && [ ! -e "$conf" ] && [ -f "$HOME/.config/alsa/asoundrc" ] && ! grep -q usermod "$H/log" \
    && ok "Void: on desktop --dry-run says the ALSA links, the audio group and the bar's old file, touches nothing" || bad "void sound dry" "$out"
out=$(L on desktop --yes </dev/null 2>&1)
[ "$(readlink "$conf/50-pipewire.conf")" = "$share/50-pipewire.conf" ] && [ "$(readlink "$conf/99-pipewire-default.conf")" = "$share/99-pipewire-default.conf" ] \
    && ok "Void: on desktop links PipeWire's two ALSA files into /etc/alsa/conf.d" || bad "void alsa links" "$(ls -l "$conf" 2>&1) $out"
grep -q "^audio:x:12:$me\$" "$H/root/etc/group" && grep -qx "usermod -aG audio $me" "$H/log" && [ -f "$HOME/.local/state/spark-shell/sound.alsa" ] && [ -f "$HOME/.local/state/spark-shell/sound.group" ] \
    && ok "Void: on desktop adds you to audio; both steps recorded (sound.alsa, sound.group)" || bad "void audio group" "$(cat "$H/root/etc/group" "$H/log")"
[ ! -e "$HOME/.config/alsa/asoundrc" ] && printf '%s\n' "$out" | grep -q "^ok     sound        $me is in the audio group now: it takes effect at your next login\$" \
    && ok "Void: the bar's own ALSA file is gone (PipeWire picks the output), one line says the group takes effect at the next login" || bad "void sound lines" "$out"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^ok     sound        PipeWire starts with the desktop$' && ! printf '%s\n' "$ck" | grep -q '^warn   sound' \
    && ok "Void: check says PipeWire starts with the desktop, and no warn" || bad "void sound check" "$(printf '%s\n' "$ck" | grep sound)"
: > "$H/log"; out=$(L on desktop --yes </dev/null 2>&1)
! printf '%s\n' "$out" | grep -q 'sound' && ! grep -q usermod "$H/log" && ok "Void: on desktop again: nothing of the sound left to do, nothing said" || bad "void sound twice" "$out"
rm -f "$conf/99-pipewire-default.conf"
awk -F: -v OFS=: '$1 == "audio" { $4 = "" } { print }' "$H/root/etc/group" > "$H/g" && cat "$H/g" > "$H/root/etc/group"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q '^warn   sound        ALSA programs skip PipeWire: /etc/alsa/conf.d lacks 99-pipewire-default.conf -- spark-shell on desktop$' \
    && printf '%s\n' "$ck" | grep -q "^warn   sound        $me is not in the audio group, so the sound devices stay closed -- spark-shell on desktop\$" \
    && ok "Void: check warns when a link or the group is gone, the remedy on desktop" || bad "void sound check warns" "$(printf '%s\n' "$ck" | grep sound)"
L on desktop --yes </dev/null >/dev/null 2>&1
: > "$H/log"; out=$(L off desktop 2>&1)
[ ! -e "$conf/50-pipewire.conf" ] && [ ! -e "$conf/99-pipewire-default.conf" ] && grep -qx "gpasswd -d $me audio" "$H/log" && ! grep -q "^audio:x:12:.*$me" "$H/root/etc/group" \
    && [ ! -e "$HOME/.local/state/spark-shell/sound.alsa" ] && [ ! -e "$HOME/.local/state/spark-shell/sound.group" ] && [ -f "$H/root$share/50-pipewire.conf" ] \
    && printf '%s\n' "$out" | grep -q '^ok     sound        ALSA programs no longer play through PipeWire (the links spark-shell made are gone)$' \
    && ok "Void: off desktop removes the links and the membership it made, the records with them; the package's files stay" || bad "void sound off" "$out $(cat "$H/log")"
# one link yours, the other spark-shell's: the record names its own, and off removes only that one
void_sound
mkdir -p "$conf"; ln -s "$share/50-pipewire.conf" "$conf/50-pipewire.conf"
L on desktop --yes </dev/null >/dev/null 2>&1
[ "$(cat "$HOME/.local/state/spark-shell/sound.alsa")" = 99-pipewire-default.conf ] && L off desktop >/dev/null 2>&1 && [ -L "$conf/50-pipewire.conf" ] && [ ! -e "$conf/99-pipewire-default.conf" ] \
    && ok "Void: a link of yours beside one spark-shell made: the record names its own, off removes only that" || bad "void sound half" "$(ls -l "$conf"; cat "$HOME/.local/state/spark-shell/sound.alsa" 2>&1)"
# the brightness's groups: video and i2c, where they exist, each recorded; off desktop takes back only those
void_sound
printf 'video:x:13:\ni2c:x:20:\n' >> "$H/root/etc/group"
L on desktop --yes </dev/null >/dev/null 2>&1
grep -q "^video:x:13:$me\$" "$H/root/etc/group" && grep -q "^i2c:x:20:$me\$" "$H/root/etc/group" && [ "$(cat "$HOME/.local/state/spark-shell/light.groups")" = "$(printf 'video\ni2c')" ] \
    && L off desktop >/dev/null 2>&1 && ! grep -q "^video:x:13:.*$me" "$H/root/etc/group" && ! grep -q "^i2c:x:20:.*$me" "$H/root/etc/group" && [ ! -e "$HOME/.local/state/spark-shell/light.groups" ] \
    && ok "on desktop adds you to video and i2c for the brightness, recorded; off desktop takes you out of both" || bad "light groups" "$(cat "$H/root/etc/group" "$H/log")"
# links and a membership that were there before: nothing recorded, nothing undone
void_sound
mkdir -p "$conf"; for f in 50-pipewire.conf 99-pipewire-default.conf; do ln -s "$share/$f" "$conf/$f"; done
awk -F: -v OFS=: -v u="$me" '$1 == "audio" { $4 = u } { print }' "$H/root/etc/group" > "$H/g" && cat "$H/g" > "$H/root/etc/group"
L on desktop --yes </dev/null >/dev/null 2>&1; L off desktop >/dev/null 2>&1
[ -L "$conf/50-pipewire.conf" ] && [ -L "$conf/99-pipewire-default.conf" ] && grep -q "^audio:x:12:$me\$" "$H/root/etc/group" && ! grep -q 'gpasswd -d [^ ]* audio\|usermod -aG audio' "$H/log" \
    && ok "Void: links and a membership of yours are not recorded, and off desktop leaves them" || bad "void sound yours" "$(ls -l "$conf"; cat "$H/log")"
# the sound from boot (runit, #23): on desktop writes one service under spark's
# supervisor (~/.config/spark/sv/spark-shell-sound) and PipeWire's own links that
# start WirePlumber and its PulseAudio server; off desktop stops it through its
# runsv and removes both; check says where PipeWire runs from
void_svc
out=$(SV on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -qxF "would  sound        PipeWire starts WirePlumber and its PulseAudio server itself: link 10-wireplumber.conf 20-pipewire-pulse.conf into $pwc" \
    && printf '%s\n' "$out" | grep -qxF "would  sound        PipeWire from boot: $svc, a service under spark's supervisor" && [ ! -e "$svc" ] && [ ! -e "$pwc" ] \
    && ok "Void with spark: on desktop --dry-run says PipeWire's two links and the service from boot, and writes neither" || bad "boot dry" "$out"
out=$(SV on desktop --yes </dev/null 2>&1)
[ -x "$svc/run" ] && [ -x "$svc/finish" ] && [ -x "$svc/log/run" ] && sed -n 2p "$svc/run" | grep -q '^# rendered by spark-shell from templates/.config/spark/sv/spark-shell-sound/run' \
    && [ ! -e "$HOME/.config/spark/sv/.spark-shell-sound.new" ] && printf '%s\n' "$out" | grep -qxF "ok     sound        PipeWire runs from boot ($svc)" \
    && ok "Void with spark: on desktop writes the service whole (run, finish, log/run, 0755, spark-shell's line), one row names it" || bad "boot service" "$out $(ls -laR "$svc" 2>&1)"
[ "$(readlink "$pwc/10-wireplumber.conf")" = "$ex/wireplumber/10-wireplumber.conf" ] && [ "$(readlink "$pwc/20-pipewire-pulse.conf")" = "$ex/pipewire/20-pipewire-pulse.conf" ] \
    && [ "$(cat "$HOME/.local/state/spark-shell/sound.pipewire")" = "$(printf '10-wireplumber.conf\n20-pipewire-pulse.conf')" ] \
    && printf '%s\n' "$out" | grep -qxF "ok     sound        PipeWire starts WirePlumber and its PulseAudio server itself ($pwc)" \
    && ok "Void with spark: PipeWire starts WirePlumber and its PulseAudio server itself, by the handbook's per-user links, recorded" || bad "boot links" "$(ls -l "$pwc" 2>&1) $out"
grep -qF "for c in $H/root/dev/snd/controlC*; do" "$svc/run" && grep -qxF "exec svlogd -tt \"$HOME/.local/state/spark-shell/log/sound\"" "$svc/log/run" && ! grep -q '@[A-Z_]*@' "$svc/run" "$svc/finish" "$svc/log/run" \
    && ok "the service: the sound devices read under the root, its log in spark-shell's state, no placeholder left" || bad "boot render" "$(cat "$svc/run" "$svc/log/run")"
out=$(SV on desktop --yes </dev/null 2>&1)
! printf '%s\n' "$out" | grep -q 'sound' && [ "$(SV on --dry-run </dev/null | tail -1)" = 'Nothing to do' ] && ok "Void with spark: on desktop again says nothing of the sound, and on --dry-run has nothing to do" || bad "boot twice" "$out"
# check: where PipeWire runs from -- the service's runsv runs PipeWire itself (boot), or its run waits for the desktop's
printf 'run: %s: (pid 4242) 9s; run: log: (pid 4241) 9s\n' "$svc" > "$HOME/sv-status"; mkdir -p "$H/root/proc/4242"; echo pipewire > "$H/root/proc/4242/comm"; : > "$HOME/wp-up"
ck=$(SV check || true)
printf '%s\n' "$ck" | grep -qxF 'ok     sound        PipeWire runs from boot: out none, mic none' && [ "$(printf '%s\n' "$ck" | grep -c '^[a-zA-Z]* *sound ')" = 1 ] \
    && ok "check: PipeWire runs from boot when the service's runsv runs PipeWire itself, one sound row" || bad "check boot" "$(printf '%s\n' "$ck" | grep sound)"
echo run > "$H/root/proc/4242/comm"
ck=$(SV check || true)
printf '%s\n' "$ck" | grep -qxF 'ok     sound        PipeWire runs from the desktop: out none, mic none' \
    && ok "check: while the service waits for a desktop's PipeWire to end, PipeWire runs from the desktop" || bad "check waits" "$(printf '%s\n' "$ck" | grep sound)"
rm -f "$HOME/wp-up"
ck=$(SV check || true)
printf '%s\n' "$ck" | grep -qxF "warn   sound        PipeWire runs from boot, and does not answer -- tail $HOME/.local/state/spark-shell/log/sound/current" \
    && ok "check: the service up and PipeWire silent: a warn, its log named" || bad "check boot silent" "$(printf '%s\n' "$ck" | grep sound)"
cp "$svc/finish" "$H/finish.ok"; echo '# changed' >> "$svc/finish"
ck=$(SV check || true)
printf '%s\n' "$ck" | grep -qxF "warn   sound        $svc is out of date: finish -- spark-shell on desktop" && ok "check: a service file that differs from spark-shell's is out of date, the remedy on desktop" || bad "check boot stale" "$(printf '%s\n' "$ck" | grep sound)"
out=$(SV on desktop --yes </dev/null 2>&1)
cmp -s "$svc/finish" "$H/finish.ok" && [ -x "$svc/finish" ] && printf '%s\n' "$out" | grep -qxF "ok     sound        PipeWire from boot: $svc updated, in effect from its next start" \
    && ok "on desktop: a service file that differs is written again (a rename: a run that runs keeps its own), 0755" || bad "boot stale on" "$out"
# off desktop: the service down through its runsv, out of runsvdir's sight, then gone; PipeWire's links by their record
rm -f "$HOME/sv-status" "$HOME/sv.log"
out=$(SV off desktop --dry-run)
printf '%s\n' "$out" | grep -qxF "would  sound        PipeWire no longer runs from boot: $svc stopped and removed" && printf '%s\n' "$out" | grep -qxF "would  sound        PipeWire's links in $pwc removed, as spark-shell made them" \
    && [ -f "$svc/run" ] && [ -L "$pwc/10-wireplumber.conf" ] && [ ! -e "$HOME/sv.log" ] && ok "off desktop --dry-run: says the service and PipeWire's links, touches nothing" || bad "boot off dry" "$out"
out=$(SV off desktop 2>&1)
[ ! -e "$svc" ] && [ ! -e "$HOME/.config/spark/sv/.spark-shell-sound.off" ] && [ -d "$HOME/.config/spark/sv/spark-check" ] \
    && [ "$(sed -n 1,2p "$HOME/sv.log" | paste -sd'|' -)" = "sv -w 10 force-stop $svc|down: there" ] && grep -qxF "sv exit $HOME/.config/spark/sv/.spark-shell-sound.off" "$HOME/sv.log" \
    && printf '%s\n' "$out" | grep -qxF "ok     sound        PipeWire no longer runs from boot ($svc is gone)" \
    && ok "off desktop: the service's down file, sv force-stop, a dot name runsvdir lets go of, sv exit, then removed; spark's own services stay" || bad "boot off" "$out $(cat "$HOME/sv.log" 2>&1)"
[ ! -e "$HOME/.config/pipewire" ] && [ ! -e "$HOME/.local/state/spark-shell/sound.pipewire" ] && [ -f "$ex/wireplumber/10-wireplumber.conf" ] \
    && printf '%s\n' "$out" | grep -qxF 'ok     sound        PipeWire no longer starts WirePlumber or its PulseAudio server itself (the links spark-shell made are gone)' \
    && ok "off desktop: PipeWire's links by their record, their empty folders with them; the packages' examples stay" || bad "boot off links" "$out $(ls -laR "$HOME/.config/pipewire" 2>&1)"
# the live case: a PipeWire answers in the runtime dir when the service comes (a desktop runs): one row says it stays until it ends
void_svc
: > "$HOME/wp-up"
out=$(SV on desktop --yes </dev/null 2>&1)
printf '%s\n' "$out" | grep -qxF "ok     sound        PipeWire runs from boot ($svc); the one running now stays until it ends" && ok "on desktop with a PipeWire running: the service comes, and one row says that PipeWire stays until it ends" || bad "boot live" "$out"
# the service's own scripts, run as runsv runs them: the stubs log, wpctl answers its first N asks, chpst runs the rest
rb=$H/rb; mkdir -p "$rb"; rrd=$H/rt/$(id -u)-runtime-dir
printf '#!/bin/sh\necho "chpst $*" > "$HOME/chpst.ran"\n[ "$1" != -P ] || shift\nexec "$@"\n' > "$rb/chpst"
printf '#!/bin/sh\necho "$$ $XDG_RUNTIME_DIR" > "$HOME/pw.ran"\n' > "$rb/pipewire"
printf '#!/bin/sh\nn=$(cat "$HOME/wp.n" 2>/dev/null || echo 0); echo $((n + 1)) > "$HOME/wp.n"\n[ "$n" -lt "$(cat "$HOME/wp.answers")" ]\n' > "$rb/wpctl"
chmod +x "$rb/chpst" "$rb/pipewire" "$rb/wpctl"
mkdir -p "$H/rt"
rc=0; out=$(svrun 0) || rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && [ -d "$rrd" ] && [ ! -L "$rrd" ] && [ "$(ls -ld "$rrd" | cut -c1-10)" = drwx------ ] && [ "$(cut -d' ' -f2- "$HOME/pw.ran")" = "$rrd" ] \
    && [ "$(cat "$HOME/chpst.ran")" = 'chpst -P pipewire' ] && [ "$(cut -d' ' -f1 "$HOME/pw.ran")" = "$(cat "$svc/pipewire.pid")" ] \
    && ok "the service's run, no PipeWire answering: the private runtime dir made (0700), PipeWire run in it in a group of its own, its pid kept for finish" || bad "svc run start" "rc=$rc $out $(cat "$HOME/pw.ran" "$HOME/chpst.ran" 2>&1)"
rc=0; out=$(svrun 1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = "a PipeWire answers in $rrd already: this waits until it is gone" ] && [ -s "$HOME/pw.ran" ] \
    && ok "the service's run: a PipeWire that answers is left as it is, and once it is gone this one starts" || bad "svc run takeover" "rc=$rc $out"
rm -f "$HOME/wp.n" "$HOME/pw.ran"; echo 1000 > "$HOME/wp.answers"   # the run itself in the background (exec: its pid is the one runsv signals)
( cd "$svc" && exec env -u XDG_RUNTIME_DIR TMPDIR="$H/rt" PATH="$rb:$sys" sh ./run ) > "$H/run.out" 2>&1 & rp=$!
waitfor 'this waits until it is gone' "$H/run.out"; kill -TERM "$rp" 2>/dev/null || :; rc=0; wait "$rp" || rc=$?
[ "$rc" = 0 ] && [ ! -e "$HOME/pw.ran" ] && grep -qxF "a PipeWire answers in $rrd already: this waits until it is gone" "$H/run.out" \
    && ok "the service's run: while that PipeWire answers it waits, starts no second one, and sv down's TERM ends the wait at once (exit 0)" || bad "svc run waits" "rc=$rc $(cat "$H/run.out")"
rm -rf "$rrd"; mkdir -p "$H/rt-else"; ln -s "$H/rt-else" "$rrd"
( cd "$svc" && exec env -u XDG_RUNTIME_DIR TMPDIR="$H/rt" PATH="$rb:$sys" sh ./run ) > "$H/run.out" 2>&1 & rp=$!
waitfor 'is not a private directory of yours' "$H/run.out"; kill -TERM "$rp" 2>/dev/null || :; rc=0; wait "$rp" || rc=$?
[ "$rc" = 0 ] && [ ! -e "$HOME/pw.ran" ] && [ -L "$rrd" ] && grep -qxF "$rrd is not a private directory of yours: no sound, and it looks again in a minute" "$H/run.out" \
    && ok "the service's run: a symlink in the runtime dir's place is refused, nothing started, and it looks again in a minute" || bad "svc run refused" "rc=$rc $(cat "$H/run.out")"
rm -f "$rrd"
if [ "$(id -u)" != 0 ]; then   # root opens every device, so a closed one is a user's case only
    mkdir -p "$H/root/dev/snd"; : > "$H/root/dev/snd/controlC0"; chmod 000 "$H/root/dev/snd/controlC0"
    printf '#!/bin/sh\necho "sg $*" > "$HOME/sg.ran"\nexec sh -c "$3"\n' > "$rb/sg"
    printf '#!/bin/sh\nif [ "$1" = -Gn ]; then echo "users audio"; else exec %s "$@"; fi\n' "$(command -v id)" > "$rb/id"
    chmod +x "$rb/sg" "$rb/id"
    rc=0; out=$(svrun 0) || rc=$?
    [ "$rc" = 0 ] && [ "$(cat "$HOME/sg.ran" 2>&1)" = 'sg audio -c exec pipewire' ] && [ "$(cat "$HOME/chpst.ran")" = 'chpst -P sg audio -c exec pipewire' ] && [ -s "$HOME/pw.ran" ] \
        && ok "the service's run: a sound device closed to it while the group file lists you in audio: PipeWire through sg audio, as spark's render group" || bad "svc run sg" "rc=$rc $out $(cat "$HOME/chpst.ran" 2>&1)"
    rm -f "$rb/sg" "$rb/id"; chmod 600 "$H/root/dev/snd/controlC0"
fi
printf '#!/bin/sh\necho "sleep $*" >> "$HOME/sleep.ran"\n' > "$rb/sleep"; chmod +x "$rb/sleep"
[ -z "$(fin 0 0)" ] && [ -z "$(fin -1 15)" ] && [ "$(fin 1 0)" = 'sleep 10' ] && [ "$(fin -1 11)" = 'sleep 10' ] \
    && ok "the service's finish: a clean exit or sv down's TERM starts again at once; a failed start or a crash waits 10 seconds, never a loop" || bad "svc finish wait" "$(fin 1 0)"
rm -f "$rb/sleep"
if command -v setsid >/dev/null 2>&1; then   # a group of its own, as chpst -P gives PipeWire
    setsid sleep 30 & g=$!
    _i=0; while [ "$_i" -lt 10 ] && [ "$(awk '{print $5}' "/proc/$g/stat" 2>/dev/null)" != "$g" ]; do sleep 1; _i=$((_i + 1)); done   # its own group once setsid ran
    echo "$g" > "$svc/pipewire.pid"
    ( cd "$svc" && PATH="$rb:$sys" sh ./finish 0 0 )
    kill -KILL "$g" 2>/dev/null || :; rc=0; wait "$g" || rc=$?
    [ "$rc" = 143 ] && [ ! -e "$svc/pipewire.pid" ] && ok "the service's finish: what PipeWire started stops with it, by its process group (TERM)" || bad "svc finish group" "rc=$rc"
fi
printf '#!/bin/sh\necho "svlogd $*" > "$HOME/svlogd.ran"\n' > "$rb/svlogd"; chmod +x "$rb/svlogd"
( cd "$svc/log" && PATH="$rb:$sys" sh ./run )
[ -d "$HOME/.local/state/spark-shell/log/sound" ] && [ "$(cat "$HOME/svlogd.ran")" = "svlogd -tt $HOME/.local/state/spark-shell/log/sound" ] \
    && ok "the service's log: svlogd into spark-shell's state (log/sound), its folder made first" || bad "svc log" "$(cat "$HOME/svlogd.ran" 2>&1)"
# a spark-shell-sound of yours, no spark supervisor, a login manager's runtime dir, systemd, PipeWire's links of the system
void_svc
mkdir -p "$svc"; printf '#!/bin/sh\nexec my-sound\n' > "$svc/run"
out=$(SV on desktop --yes </dev/null 2>&1)
[ "$(cat "$svc/run")" = "$(printf '#!/bin/sh\nexec my-sound')" ] && printf '%s\n' "$out" | grep -qxF "todo   sound        $svc is not spark-shell's: left as it is, and PipeWire starts with the desktop" && [ ! -e "$pwc" ] \
    && SV off desktop >/dev/null 2>&1 && [ -f "$svc/run" ] && ok "a spark-shell-sound of yours: on desktop and off desktop leave it as it is, one todo row, no links" || bad "boot yours" "$out"
void_sound; mkdir -p "$H/tmp"
out=$(SV on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -qxF "skip   sound        spark's supervisor is not here ($HOME/.config/spark/sv): PipeWire starts with the desktop" && ! printf '%s\n' "$out" | grep -q 'pipewire.conf.d\|from boot' \
    && ok "Void without spark: no service and no links, a skip row says PipeWire starts with the desktop" || bad "boot no spark" "$out"
void_svc
out=$(L on desktop --dry-run </dev/null)
printf '%s\n' "$out" | grep -qxF "skip   sound        a login manager set the runtime dir ($H/run): PipeWire starts with the desktop" && ! printf '%s\n' "$out" | grep -q 'pipewire.conf.d\|from boot' \
    && ok "a runtime dir a login manager set (elogind): no service beside it, a skip row says so" || bad "boot login manager" "$out"
mkdir -p "$H/root/etc/pipewire/pipewire.conf.d"; ln -s "$ex/wireplumber/10-wireplumber.conf" "$ex/pipewire/20-pipewire-pulse.conf" "$H/root/etc/pipewire/pipewire.conf.d/"
SV on desktop --yes </dev/null >/dev/null 2>&1
[ -f "$svc/run" ] && [ ! -e "$pwc" ] && [ ! -e "$HOME/.local/state/spark-shell/sound.pipewire" ] && ok "PipeWire's links of the system (/etc/pipewire): none of yours made, the service written" || bad "boot system links" "$(ls -la "$HOME/.config" 2>&1)"
void_svc; mkdir -p "$H/root/run/systemd/system"
out=$(SV on desktop --dry-run </dev/null)
! printf '%s\n' "$out" | grep -q 'pipewire.conf.d\|from boot' && ok "systemd: no service and no links (the packages' own user units)" || bad "boot systemd" "$out"
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"; : > "$HOME/wp-up"
ck=$(SV check || true)
printf '%s\n' "$ck" | grep -qxF 'ok     sound        PipeWire runs from login: out none, mic none' && ok "check on systemd: PipeWire runs from login" || bad "check login" "$(printf '%s\n' "$ck" | grep sound)"
# an older install on runit with spark: PipeWire starts with the desktop until on desktop runs again
void_svc
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
ck=$(SV check || true)
printf '%s\n' "$ck" | grep -qxF 'ok     sound        PipeWire starts with the desktop' && printf '%s\n' "$ck" | grep -qxF 'warn   sound        PipeWire starts with the desktop, so a console has no sound -- spark-shell on desktop' \
    && ok "check, an older install (no service yet): PipeWire starts with the desktop, and a warn names on desktop" || bad "check older" "$(printf '%s\n' "$ck" | grep sound)"
# a console login reaches that PipeWire: .bash_profile takes the private runtime dir when no login manager set one
awk '/^# The sound at a login with no XDG_RUNTIME_DIR/ {on = 1} on {print} on && /^fi$/ {exit}' "$REPO/template/linux/.bash_profile" > "$H/rtd.sh"
if command -v bash >/dev/null 2>&1; then
    brd=$H/brt/$(id -u)-runtime-dir; mkdir -p "$H/brt"; mkdir -m 0700 "$brd"
    rtd() { env -u XDG_RUNTIME_DIR TMPDIR="$H/brt" "$@" bash --norc --noprofile -c ". '$H/rtd.sh'; echo \"\${XDG_RUNTIME_DIR:-none}\""; }   # rtd [VAR=VALUE] -> the runtime dir a login ends with
    [ "$(rtd)" = "$brd" ] && ok ".bash_profile: a login with no XDG_RUNTIME_DIR takes the private one PipeWire runs in (a console reaches it)" || bad "bash_profile rtd" "$(rtd)"
    chmod 0755 "$brd"; v=$(rtd); chmod 0700 "$brd"
    rmdir "$brd"; mkdir -p "$H/brt-else"; chmod 0700 "$H/brt-else"; ln -s "$H/brt-else" "$brd"
    [ "$v" = none ] && [ "$(rtd)" = none ] && ok ".bash_profile: a runtime dir others can read, or a symlink in its place, is not taken" || bad "bash_profile rtd refused" "$v $(rtd)"
    [ "$(rtd XDG_RUNTIME_DIR=/run/user/7)" = /run/user/7 ] && ok ".bash_profile: a runtime dir a login manager set is kept" || bad "bash_profile rtd kept" "$(rtd XDG_RUNTIME_DIR=/run/user/7)"
fi
# Arch with pulseaudio: pipewire-pulse left out (pacman --noconfirm would refuse the conflict, and every package with it), one todo says how
fresh
console_stubs Linux
desktop_stubs
printf 'ID=arch\n' > "$H/os-release"
printf '#!/bin/sh\n[ "$*" = "-Qq pulseaudio" ]\n' > "$H/lx/pacman"; chmod +x "$H/lx/pacman"
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
out=$(L on --dry-run </dev/null 2>&1)
pk=$(printf '%s\n' "$out" | grep -E '^(would|todo) +packages ')
printf '%s\n' "$out" | grep -q '^todo   sound        pulseaudio is installed, and pipewire-pulse takes its place -- sudo pacman -S pipewire-pulse (it asks before removing pulseaudio)$' \
    && printf '%s' "$pk" | grep -q ' pipewire-alsa' && ! printf '%s' "$pk" | grep -q 'pipewire-pulse' \
    && ok "Arch with pulseaudio: pipewire-pulse is left out of the install, one todo says how to take it" || bad "arch pulseaudio" "$out"
grep -q '^PKG_SOUND=pipewire wireplumber alsa-pipewire libspa-bluetooth$' "$REPO/distro/void.env" && grep -q '^PKG_SOUND=pipewire wireplumber pipewire-pulse pipewire-alsa libspa-0.2-bluetooth$' "$REPO/distro/debian.env" \
    && grep -q '^PKG_SOUND=pipewire wireplumber pipewire-pulse pipewire-alsa$' "$REPO/distro/arch.env" && ok "distro: the sound's packages, each family's names" || bad "PKG_SOUND" "$(grep -h PKG_SOUND "$REPO"/distro/*.env)"
grep -q '^PKG_DESKTOP=sway swaybg foot foot-terminfo dejavu-fonts-ttf mesa-dri seatd curl openssh swayidle swaylock grim slurp wl-clipboard brightnessctl ddcutil i2c-tools librsvg librsvg-utils poppler mako libnotify udisks2 dbus xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk gsettings-desktop-schemas bluez python3-dbus python3-gobject mpv mesa-vaapi python3-numpy xorg-server-xwayland xrandr wtype$' "$REPO/distro/void.env" && ok "distro/void.env: the desktop's packages, seatd, librsvg and rsvg-convert, poppler, mako, notify-send, udisks2, the session bus, mpv, the VA-API driver, numpy, Xwayland and xrandr among them" || bad "void.env desktop"

fi

# --- 19b. the console, continued: the login screen, the lock, the display and
#          the keyboard, notes and reminders, the warnings, macOS ----------
if want 19b; then
# the login screen of v0.41 (greetd on tty1, spark-shell's files in
# /etc/greetd): handed back to getty at the next boot by on, on desktop,
# off desktop and off -- greetd is disabled, never stopped
old_greetd
out=$(L on --dry-run </dev/null)
printf '%s\n' "$out" | grep -q "^would  login        the normal console login on tty1 from the next boot: the login screen turned off, its files removed (sudo)\$" \
    && [ -f "$H/root/etc/greetd/config.toml" ] && [ -e "$H/root/units/greetd.service" ] && ok "v0.41 upgrade: on --dry-run says the login screen goes back to getty, touches nothing" || bad "upgrade dry-run" "$out"
out=$(L on --yes </dev/null 2>&1)
old_gone && [ ! -e "$H/root/etc/greetd/config.toml" ] && ok "v0.41 upgrade: on hands tty1 back to getty at the next boot, greetd disabled (never stopped), its files gone" || bad "upgrade on" "$(find "$H/root/etc" "$H/root/units"; cat "$H/log")"
[ "$(printf '%s\n' "$out" | grep -c '^ok     login ')" = 1 ] && printf '%s\n' "$out" | grep -q '^ok     login        the normal console login is back on tty1 from the next boot: the login screen is off, its packages stay$' \
    && ok "v0.41 upgrade: one plain line says so" || bad "upgrade line" "$out"
: > "$H/log"; out=$(L on --yes </dev/null 2>&1)
! printf '%s\n' "$out" | grep -q 'login ' && ! grep -q greetd "$H/log" && ok "v0.41 upgrade: on again has nothing to hand back" || bad "upgrade twice" "$out"
old_greetd orig
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"
L on desktop --yes </dev/null >/dev/null 2>&1
old_gone && grep -q agreety "$H/root/etc/greetd/config.toml" && [ ! -e "$H/root/etc/greetd/config.toml.spark-orig" ] && grep -q '^DESKTOP=sway$' "$HOME/.config/spark-shell/config" \
    && ok "v0.41 upgrade: on desktop hands it back too, the package's config.toml restored from .spark-orig" || bad "upgrade on desktop" "$(ls -a "$H/root/etc/greetd"; cat "$H/log")"
old_greetd
out=$(L off desktop --dry-run)
printf '%s\n' "$out" | grep -q '^would  login ' && [ -e "$H/root/units/greetd.service" ] && ok "v0.41 upgrade: off desktop --dry-run says it, touches nothing" || bad "upgrade off dry" "$out"
L off desktop >/dev/null 2>&1
old_gone && ok "v0.41 upgrade: off desktop hands it back" || bad "upgrade off desktop" "$(cat "$H/log")"
old_greetd
L off >/dev/null 2>&1
old_gone && ok "v0.41 upgrade: off hands it back" || bad "upgrade off" "$(cat "$H/log")"

# the console is the tty, never XDG_VTNR (logind's; Void has none), and
# sway gets a private XDG_RUNTIME_DIR when no login manager made one
fresh
console_stubs Linux
desktop_stubs
printf '#!/bin/sh\necho "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" >&2\n' > "$H/.local/bin/sway"
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
L on --yes >/dev/null </dev/null
slog=$HOME/.local/state/spark-shell/sway.log
mkdir -p "$H/tmp"
rc=0; out=$(TEST_TTY=/dev/pts/3 XDG_VTNR=1 env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: needs a console login (tty1 to tty9): ssh and terminal windows cannot start sway' ] \
    && ok "desktop: a terminal window (/dev/pts) is refused even with XDG_VTNR set" || bad "desktop pts" "rc=$rc $out"
rc=0; out=$(TEST_TTY=/dev/tty2 env -u XDG_VTNR -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR TMPDIR="$H/tmp/" PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
rd=$H/tmp/$(id -u)-runtime-dir
[ "$rc" = 0 ] && grep -qx "XDG_RUNTIME_DIR=$rd" "$slog" && ok "desktop: by hand on tty2 with no XDG_VTNR, sway starts" || bad "desktop tty2" "rc=$rc $out $(cat "$slog" 2>&1)"
[ -d "$rd" ] && [ ! -L "$rd" ] && [ "$(ls -ld "$rd" | cut -c1-10)" = drwx------ ] && [ "$(ls -ldn "$rd" | awk '{print $3}')" = "$(id -u)" ] \
    && ok "desktop: no XDG_RUNTIME_DIR, a private one made under TMPDIR (0700, yours) and handed to sway" || bad "runtime dir" "$(ls -ld "$rd" 2>&1)"
chmod 0755 "$rd"
rc=0; out=$(TEST_TTY=/dev/tty1 env -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR TMPDIR="$H/tmp" PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx "XDG_RUNTIME_DIR=$rd" "$slog" && [ "$(ls -ld "$rd" | cut -c1-10)" = drwx------ ] && ok "desktop: the same directory again, back to 0700" || bad "runtime dir again" "rc=$rc $out"
rm -rf "$rd"; mkdir -p "$H/elsewhere"; ln -s "$H/elsewhere" "$rd"
rc=0; out=$(TEST_TTY=/dev/tty1 env -u WAYLAND_DISPLAY -u XDG_RUNTIME_DIR TMPDIR="$H/tmp" PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: $rd is not a private directory of yours, and the desktop needs one (XDG_RUNTIME_DIR)" ] && ok "desktop: a symlink in its place is refused, sway never starts" || bad "runtime dir symlink" "rc=$rc $out"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/run env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx "XDG_RUNTIME_DIR=$H/run" "$slog" && ok "desktop: an XDG_RUNTIME_DIR a login manager set is kept" || bad "runtime dir kept" "rc=$rc $out $(cat "$slog")"
# no systemd: PipeWire, WirePlumber and the PulseAudio server start before
# sway and stop after it; with systemd (its user units) or one already
# answering, none is started
for t in pipewire wireplumber pipewire-pulse; do
    { printf '#!/bin/sh\necho $$ > "$HOME/%s.pid"\n' "$t"
      [ "$t" != pipewire ] || [ -z "$py3" ] || printf '%s -c "import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$XDG_RUNTIME_DIR/pipewire-0"\n' "$py3"
      printf 'exec sleep 60\n'; } > "$H/lx/$t"
done
printf '#!/bin/sh\nn=0; while [ ! -f "$HOME/pipewire-pulse.pid" ] && [ "$n" -lt 100 ]; do sleep 0.05; n=$((n + 1)); done; for t in pipewire wireplumber pipewire-pulse; do [ -f "$HOME/$t.pid" ] && kill -0 "$(cat "$HOME/$t.pid")" 2>/dev/null && echo "$t runs" >&2; done; exit 0\n' > "$H/.local/bin/sway"
chmod +x "$H/lx/pipewire" "$H/lx/wireplumber" "$H/lx/pipewire-pulse" "$H/.local/bin/sway"
mkdir -p "$H/rt"; chmod 700 "$H/rt"
t0=$(date +%s); rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$(grep -c ' runs$' "$slog")" = 3 ] \
    && ok "desktop, no systemd: PipeWire, WirePlumber and pipewire-pulse run while sway does (WirePlumber once PipeWire's socket is there)" || bad "sound start" "rc=$rc $(($(date +%s) - t0))s $out $(cat "$slog" "$HOME/.local/state/spark-shell/sound.log" 2>&1)"
alive=''; for t in pipewire wireplumber pipewire-pulse; do ! kill -0 "$(cat "$HOME/$t.pid")" 2>/dev/null || alive="$alive $t"; done
[ -z "$alive" ] && ok "desktop: all three stop when sway ends, waited for" || bad "sound stop" "still running:$alive"
for t in pipewire wireplumber pipewire-pulse; do kill "$(cat "$HOME/$t.pid")" 2>/dev/null || :; done
printf '#!/bin/sh\nsleep 1; for t in pipewire wireplumber pipewire-pulse; do [ -f "$HOME/$t.pid" ] && kill -0 "$(cat "$HOME/$t.pid")" 2>/dev/null && echo "$t runs" >&2; done; exit 0\n' > "$H/.local/bin/sway"
# the Void handbook's way: pipewire.conf.d files have PipeWire start WirePlumber and its PulseAudio server itself
rm -f "$HOME"/*.pid "$H/rt/pipewire-0"; mkdir -p "$H/root/etc/pipewire/pipewire.conf.d"
printf 'context.exec = [ { path = "/usr/bin/wireplumber" args = "" } ]\n' > "$H/root/etc/pipewire/pipewire.conf.d/10-wireplumber.conf"
printf 'context.exec = [ { path = "/usr/bin/pipewire" args = "-c pipewire-pulse.conf" } ]\n' > "$H/root/etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'pipewire runs' "$slog" && [ ! -e "$HOME/wireplumber.pid" ] && [ ! -e "$HOME/pipewire-pulse.pid" ] \
    && ok "desktop: pipewire.conf.d files that start WirePlumber and pipewire-pulse: PipeWire alone, no second of either" || bad "sound by pipewire" "rc=$rc $(cat "$slog")"
rm -rf "$H/root/etc/pipewire"
rm -f "$HOME"/*.pid "$H/rt/pipewire-0"; mkdir -p "$H/root/run/systemd/system"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && ! grep -q ' runs$' "$slog" && [ ! -e "$HOME/pipewire.pid" ] && ok "desktop, systemd: none started (the packages' user units start them)" || bad "sound systemd" "rc=$rc $(cat "$slog")"
rm -rf "$H/root/run/systemd"
printf '#!/bin/sh\nexit 0\n' > "$H/lx/wpctl"; chmod +x "$H/lx/wpctl"
rc=0; out=$(TEST_TTY=/dev/tty1 XDG_RUNTIME_DIR=$H/rt env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop 2>&1) || rc=$?
[ "$rc" = 0 ] && [ ! -e "$HOME/pipewire.pid" ] && ok "desktop: a PipeWire that answers already is left as it is, none started" || bad "sound running" "rc=$rc $(cat "$slog")"
rm -f "$H/lx/wpctl" "$H/lx/pipewire" "$H/lx/wireplumber" "$H/lx/pipewire-pulse"

# the lock and screen capture: the template's keys and swayidle, then the
# verbs against stubs (swaylock, pgrep, grim, slurp, wl-copy, swaymsg, date)
sw_t=$REPO/template/.config/sway/config
grep -qx 'exec @IDLE_EXEC@' "$sw_t" && grep -qx 'bindsym $mod+Escape exec @REPO@/spark-shell desktop lock || swaylock -f' "$sw_t" \
    && ok "sway template: ten idle minutes bring the idle screen, fifteen the lock, and it locks before sleep; Super+Escape locks now" || bad "lock template" "$(grep -n 'swayidle\|Escape' "$sw_t")"
grep -qx 'bindsym Print exec @REPO@/spark-shell desktop capture screen' "$sw_t" && grep -qx 'bindsym Shift+Print exec @REPO@/spark-shell desktop capture area' "$sw_t" && grep -qx 'bindsym $mod+Print exec @REPO@/spark-shell desktop capture window' "$sw_t" \
    && ok "sway template: Print the screen, Shift+Print an area, Super+Print the window" || bad "capture keys" "$(grep -n Print "$sw_t")"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/swaylock.args"\n' > "$H/lx/swaylock"
printf '#!/bin/sh\n[ "$*" = "-u %s -x swaylock" ] && [ -e "$HOME/locked" ]\n' "$(id -u)" > "$H/lx/pgrep"
printf '#!/bin/sh\necho "$*" >> "$HOME/grim.log"\nfor a; do f=$a; done\n[ ! -e "$HOME/grim-fails" ] || exit 1\nprintf PNG > "$f"\n' > "$H/lx/grim"
printf '#!/bin/sh\n[ -e "$HOME/slurp-none" ] && exit 1\necho "10,20 300x200"\n' > "$H/lx/slurp"
printf '#!/bin/sh\necho "$*" >> "$HOME/wlcopy.log"; cat > "$HOME/clip"\n' > "$H/lx/wl-copy"
cat > "$H/lx/swaymsg" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/swaymsg.log"
case "$*" in
    "-t get_version") echo '{"major":1}' ;;
    "-t get_outputs") echo '[{"name":"DP-1","focused":false},{"name":"HDMI-A-1","focused":true}]' ;;
    "-t get_tree") [ -e "$HOME/no-window" ] && echo '{"type":"root","nodes":[{"type":"workspace","focused":true,"rect":{"x":0,"y":0,"width":1,"height":1}}]}' \
        || echo '{"type":"root","nodes":[{"type":"output","nodes":[{"type":"workspace","focused":false,"nodes":[{"type":"con","focused":true,"rect":{"x":10,"y":40,"width":800,"height":600}}]}]}]}' ;;
esac
STUB
printf '#!/bin/sh\ncase "$1" in +%%Y-%%m-%%d-%%H%%M%%S) echo 2026-10-19-153012 ;; *) exec %s "$@" ;; esac\n' "$(command -v date)" > "$H/lx/date"
chmod +x "$H/lx/swaylock" "$H/lx/pgrep" "$H/lx/grim" "$H/lx/slurp" "$H/lx/wl-copy" "$H/lx/swaymsg" "$H/lx/date"
theme_fixture '#ff5555'
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock 2>&1) || rc=$?
args=$(paste -sd ' ' - < "$HOME/swaylock.args" 2>/dev/null)
[ "$rc" = 0 ] && case " $args " in *" --daemonize --color 000000 --font DejaVu Sans Mono --font-size 20 "*) true ;; *) false ;; esac \
    && case " $args " in *" --ring-color ff5555 "*) true ;; *) false ;; esac && case " $args " in *" --ring-wrong-color aa0000 "*) true ;; *) false ;; esac \
    && ! case " $args " in *indicator-idle-visible*) true ;; *) false ;; esac \
    && ok "desktop lock: swaylock, daemonized, over the ground, the ring in the accent, wrong in the red, no ring at rest" || bad "lock args" "rc=$rc $out $args"
case " $args " in *" --inside-color 000000e6 "*" --layout-text-color aaaaaa --layout-bg-color 000000e6 --layout-border-color 00000000 "*) ok "desktop lock: the keyboard's layout under the ring sits on the ring's own inside, in the text color, no border (#57)" ;; *) bad "lock layout label" "$args" ;; esac
printf 'DESKTOP=sway\nWALLPAPER=ripples\n' > "$HOME/.config/spark-shell/config"; rm -f "$HOME/swaylock.args"
WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || :
args=$(paste -sd ' ' - < "$HOME/swaylock.args" 2>/dev/null)
case " $args " in *" --image $REPO/gallery/wallpaper/ripples.png --scaling fill "*) ok "desktop lock: a wallpaper picture is the lock's picture, filled" ;; *) bad "lock picture" "$args" ;; esac
# a theme.env that will not load: the lock still comes up, in the VGA's colors
printf 'THEME_BG=$(oops)\n' > "$HOME/.config/spark/theme.env.bad"; cp "$HOME/.config/spark/theme.env" "$HOME/.config/spark/theme.env.good"; cp "$HOME/.config/spark/theme.env.bad" "$HOME/.config/spark/theme.env"; rm -f "$HOME/swaylock.args"
rc=0; WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && grep -qx -- --daemonize "$HOME/swaylock.args" && ok "desktop lock with a theme.env that will not load: the lock comes up anyway" || bad "lock bad theme" "rc=$rc $(cat "$HOME/swaylock.args" 2>&1)"
mv "$HOME/.config/spark/theme.env.good" "$HOME/.config/spark/theme.env"; rm -f "$HOME/.config/spark/theme.env.bad"
touch "$HOME/locked"; rm -f "$HOME/swaylock.args"
rc=0; WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] && [ ! -e "$HOME/swaylock.args" ] && ok "desktop lock: a lock already up stays, no second" || bad "lock twice" "rc=$rc"
rm -f "$HOME/locked"
rc=0; out=$(env -u WAYLAND_DISPLAY PATH="$H/lx:$PATH" sh "$SH" desktop lock 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: locks the desktop: run it inside it (Super+Escape)' ] && ok "desktop lock outside the desktop: refused in one line" || bad "lock outside" "rc=$rc $out"
shots=$HOME/pictures/screenshots
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture screen 2>&1) || rc=$?
# shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
[ "$rc" = 0 ] && [ "$out" = '~/pictures/screenshots/2026-10-19-153012.png, and on the clipboard' ] && [ "$(cat "$shots/2026-10-19-153012.png")" = PNG ] \
    && [ "$(tail -1 "$HOME/grim.log")" = "-c -o HDMI-A-1 $shots/2026-10-19-153012.png" ] && [ "$(cat "$HOME/wlcopy.log")" = '--type image/png' ] && [ "$(cat "$HOME/clip")" = PNG ] \
    && ok "desktop capture screen: the screen in use with the pointer in it (#184), a PNG named by the time in ~/pictures/screenshots, and on the clipboard" || bad "capture screen" "rc=$rc $out $(cat "$HOME/grim.log" 2>&1)"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture area 2>&1) || rc=$?
# shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
[ "$rc" = 0 ] && [ "$out" = '~/pictures/screenshots/2026-10-19-153012-2.png, and on the clipboard' ] && [ "$(tail -1 "$HOME/grim.log")" = "-c -g 10,20 300x200 $shots/2026-10-19-153012-2.png" ] \
    && ok "desktop capture area: the area slurp gives; a second picture in the same second gets -2" || bad "capture area" "rc=$rc $out $(tail -1 "$HOME/grim.log")"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture window 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$(tail -1 "$HOME/grim.log")" = "-c -g 10,40 800x600 $shots/2026-10-19-153012-3.png" ] && ok "desktop capture window: the window in front, by its place on the screen" || bad "capture window" "rc=$rc $out $(tail -1 "$HOME/grim.log")"
# the pictures folder the home's file names (#119): a home whose file says ~/Pictures gets no lowercase twin
mkdir -p "$HOME/.config"; printf 'XDG_PICTURES_DIR="$HOME/Pictures"\n' > "$HOME/.config/user-dirs.dirs"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture screen 2>&1) || rc=$?
_shot=$(tail -1 "$HOME/grim.log" | sed 's/^-c -o HDMI-A-1 //')   # a numbered name where the folder holds one already: a Mac's folders are one of any case
[ "$rc" = 0 ] && case $_shot in "$HOME/Pictures/screenshots/2026-10-19-153012"*.png) true ;; *) false ;; esac \
    && ok "desktop capture: the screenshots go to the pictures folder ~/.config/user-dirs.dirs names (#119)" || bad "capture pictures folder" "rc=$rc $out $_shot"
rm -f "$HOME/.config/user-dirs.dirs" "$_shot"
touch "$HOME/slurp-none"; n0=$(ls "$shots" | wc -l)
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture area 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'no area picked: nothing captured' ] && [ "$(ls "$shots" | wc -l)" = "$n0" ] && ok "desktop capture area, Esc in slurp: nothing captured, one line" || bad "capture no area" "rc=$rc $out"
rm -f "$HOME/slurp-none"; touch "$HOME/no-window"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture window 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: no window in front to capture' ] && ok "desktop capture window with no window: refused in one line" || bad "capture no window" "rc=$rc $out"
rm -f "$HOME/no-window"; touch "$HOME/grim-fails"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture screen 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: grim could not take the picture' ] && [ "$(ls "$shots" | wc -l | tr -d ' ')" = 3 ] && ok "desktop capture: grim failing leaves no file, one line" || bad "capture grim fails" "rc=$rc $out $(ls "$shots")"
rm -f "$HOME/grim-fails"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 PATH="$H/lx:$PATH" sh "$SH" desktop capture photo 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: capture takes screen, area or window' ] && ok "desktop capture: a wrong word refused in one line" || bad "capture word" "rc=$rc $out"
# the dialog's window section: three capture rows, as the three keys (#144); a pick closes the dialog and captures a second later
rows=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel window --list 2>&1)
printf '%s\n' "$rows" | grep -q 'capture the screen	window capture screen$' && printf '%s\n' "$rows" | grep -q 'capture an area	window capture area$' \
    && printf '%s\n' "$rows" | grep -q 'capture a window	window capture window$' \
    && ok "the dialog's window section: capture the screen, an area, a window (#144)" || bad "capture rows" "$rows"
# one row a window: the app, then its title, the app's own name off the title's end (#144)
eval "$(sed -n '/^win_rows() {/,/^}/p' "$SRC")"
_wr=$(printf 'firefox: Claude Code \342\200\224 Mozilla Firefox\t12\n~/projects\t13\nmicro: notes.md - micro\t14\nzen: a|b: c\t15\n' | win_rows)
[ "$_wr" = "$(printf 'firefox\t12\tClaude Code\n~/projects\t13\t\nmicro\t14\tnotes.md\nzen\t15\ta/b: c')" ] \
    && ok "window rows: the app, its ID, then the title with the app's name off its end, a bar in a title kept out of the row's fields (#144)" || bad "win_rows" "$_wr"
rm -f "$HOME/swaymsg.log"
rm -f "$HOME/slurp-none"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel window capture area 2>&1) || rc=$?
_aside=$(grep -n 'move scratchpad' "$HOME/swaymsg.log" | cut -d: -f1); _again=$(grep -n 'scratchpad show' "$HOME/swaymsg.log" | cut -d: -f1)
case $out in 2026-10-19-*.png*'on the clipboard') _named=1 ;; *) _named='' ;; esac
[ "$rc" = 0 ] && [ -n "$_named" ] && [ -n "$_aside" ] && [ -n "$_again" ] && [ "$_aside" -lt "$_again" ] \
    && ok "the dialog: a capture steps the dialog aside, takes the picture, brings it back, and says the file's name" || bad "capture from the dialog" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
touch "$HOME/slurp-none"; rm -f "$HOME/swaymsg.log"
rc=0; out=$(WAYLAND_DISPLAY=wayland-1 SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel window capture area 2>&1) || rc=$?
rm -f "$HOME/slurp-none"
[ "$rc" != 0 ] && [ "$out" = 'no area picked: nothing captured' ] && grep -q 'scratchpad show' "$HOME/swaymsg.log" \
    && ok "the dialog: a capture refused comes back too, with its reason on the status row" || bad "capture refused" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
rm -f "$H/lx/swaylock" "$H/lx/pgrep" "$H/lx/grim" "$H/lx/slurp" "$H/lx/wl-copy" "$H/lx/swaymsg" "$H/lx/date"

# the display, the keyboard, the screens and the brightness: the renders
# from the config, the verbs against stubs (swaymsg, pkill, brightnessctl,
# ddcutil), the bar's blocks and the dialog's sections
cat > "$H/lx/swaymsg" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/swaymsg.log"
case "$*" in
    "-t get_version") echo '{"major":1}' ;;
    "-t get_inputs") echo '[{"type":"keyboard","xkb_layout_names":["English (US)","Portuguese (Brazil)"],"xkb_active_layout_index":1}]' ;;
    "-t get_workspaces") [ ! -e "$HOME/ws-styled" ] || { cat "$HOME/ws-styled"; exit 0; }   # the workspaces' style test (#160)
        [ -e "$HOME/ws-test" ] || exit 0   # only the workspace glyphs' test asks
        if [ -e "$HOME/ws-later" ]; then echo '[{"num":1,"name":"1:x"},{"num":5,"name":"5"}]'
        else echo '[{"num":1,"name":"1"},{"num":2,"name":"2:x"},{"num":3,"name":"3 writing"},{"num":10,"name":"10"},{"num":11,"name":"11"}]'; touch "$HOME/ws-later"; fi ;;
    "-r -t subscribe -m [\"workspace\"]") echo '{ "change": "init", "old": null, "current": { "num": 5, "name": "5" } }' ;;   # as sway writes it: spaced
    "-t get_outputs") echo '[{"name":"eDP-1","make":"BOE","model":"0x0BCA","serial":"","active":true,"scale":1.0,"current_mode":{"width":1920,"height":1080},"rect":{"x":0,"y":0,"width":1920,"height":1080},"modes":[{"width":1920,"height":1080},{"width":1280,"height":720}]},{"name":"HDMI-A-1","make":"Lenovo Group Limited","model":"T24i-30","serial":"V30A1","active":true,"scale":1.0,"current_mode":{"width":1920,"height":1080},"rect":{"x":1920,"y":0,"width":1920,"height":1080},"modes":[{"width":1920,"height":1080}]}]' ;;
esac
STUB
printf '#!/bin/sh\necho "pkill $*" >> "$HOME/swaymsg.log"\n' > "$H/lx/pkill"
chmod +x "$H/lx/swaymsg" "$H/lx/pkill"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
L on --yes >/dev/null 2>&1 </dev/null || :
swc=$HOME/.config/sway/config
grep -qx "exec swayidle -w timeout 600 '$REPO/spark-shell desktop idle' resume '$REPO/spark-shell desktop idle off' timeout 900 '$REPO/spark-shell desktop lock || swaylock -f; $REPO/spark-shell desktop idle off' before-sleep '$REPO/spark-shell desktop lock || swaylock -f'" "$swc" \
    && grep -qx "include \"$HOME/.config/spark-shell/screens.conf\"" "$swc" && [ -f "$HOME/.config/spark-shell/screens.conf" ] \
    && grep -qx "# the keyboard: sway's own layout (spark-shell desktop keyboard us br sets some)" "$swc" \
    && grep -qxF 'for_window [app_id="spark-idle"] border none' "$swc" && grep -qx 'workspace idle gaps outer 0' "$swc" \
    && ok "sway render: swayidle brings the idle screen at 10 minutes and the lock at 15 by default, the idle window taken down behind the lock (#66); the idle workspace has no gaps and no border; the screens file included (and there), no keyboard line without KEYBOARD" || bad "display render" "$(grep -n 'swayidle\|include\|keyboard' "$swc")"
# your own sway lines (#170): their folder made and read last; a render changed by hand kept as .bak at the next render, an unchanged one rendered again with none
[ "$(grep -v '^$' "$swc" | tail -1)" = "include $HOME/.config/sway/config.d/*" ] && [ -d "$HOME/.config/sway/config.d" ] && grep -qx 'xwayland enable' "$swc" \
    && ok "sway render: Xwayland on, and the folder for your own lines made and read last (#170)" || bad "sway own lines render" "$(grep -n 'xwayland\|config.d' "$swc")"
echo '# a line of mine' >> "$swc"; rm -f "$swc.bak"
L on --yes >/dev/null 2>&1 </dev/null || :
grep -qx '# a line of mine' "$swc.bak" && ! grep -q 'a line of mine' "$swc" && grep -q 'rendered by spark-shell' "$swc" \
    && ok "render: a file of ours changed by hand is kept as .bak before the new render (#170)" || bad "render by hand" "$(ls "$swc"* 2>&1)"
rm -f "$swc.bak"; L on --yes >/dev/null 2>&1 </dev/null || :
[ ! -e "$swc.bak" ] && ok "render: a render no one changed is rendered again with no .bak (#170)" || bad "render unchanged" "$(ls "$swc"* 2>&1)"
rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop display idle 0 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'idle screen never' ] && grep -qx 'DISPLAY_IDLE=0' "$HOME/.config/spark-shell/config" \
    && grep -qx "exec swayidle -w timeout 900 '$REPO/spark-shell desktop lock || swaylock -f; $REPO/spark-shell desktop idle off' before-sleep '$REPO/spark-shell desktop lock || swaylock -f'" "$swc" \
    && grep '^pkill ' "$HOME/swaymsg.log" | grep -q "^pkill -u $(id -u) -f ^swayidle .*spark-shell desktop lock\$" && grep -q "^-- exec swayidle -w timeout 900 " "$HOME/swaymsg.log" \
    && ok "desktop display idle 0: no idle screen; the render and the running desktop's swayidle (restarted, spark-shell's own alone, #196) follow" || bad "display idle 0" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop display lock 30 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'lock after 30 minutes' ] && grep -q "^exec swayidle -w timeout 1800 " "$swc" && ok "desktop display lock 30: the lock after 30 minutes" || bad "display lock 30" "rc=$rc $out"
rc=0; out=$(PATH="$H/lx:$PATH" sh "$SH" desktop display idle soon 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: display idle takes minutes, 0 to 999 (0: never)' ] && ok "desktop display idle: a wrong word refused in one line" || bad "display idle word" "rc=$rc $out"
rc=0; out=$(PATH="$H/lx:$PATH" sh "$SH" desktop display idle 08 2>&1) || rc=$?
[ "$rc" = 1 ] && ! grep -q 'DISPLAY_IDLE=08' "$HOME/.config/spark-shell/config" && ok "desktop display idle 08: a leading zero refused (sh reads 08 as a bad octal)" || bad "display idle 08" "rc=$rc $out"
printf 'DESKTOP=sway\nDISPLAY_IDLE=ten\n' > "$HOME/.config/spark-shell/config"
rc=0; out=$(PATH="$H/lx:$PATH" sh "$SH" status 2>&1) || rc=$?
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'DISPLAY_IDLE=ten in .*: minutes, 0 to 999 (0: never)$' && ok "config: DISPLAY_IDLE=ten is refused" || bad "display key" "rc=$rc $out"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
# the idle screen's saver (DISPLAY_SAVER, #66): the default reads as it always did, the command, the window, the dialog and the check
dot=$(printf '\302\267'); tb=$(printf '\t')
if [ -n "$py3" ]; then   # a bare container has no python3 (debian, arch, void): the section is a note there
    mkdir -p "$H/svx" "$H/nopy" "$H/pyl" "$H/clk"
    ln -sf "$py3" "$H/svx/python3"                                       # a python3 that runs the savers
    printf '#!/bin/sh\nexit 127\n' > "$H/nopy/python3"                   # one that cannot
    printf '#!/bin/sh\ncase "$2" in --version) exec %s "$@" ;; esac\necho "python3 $*" >> "$HOME/py.log"\nexit 0\n' "$py3" > "$H/pyl/python3"   # logs the saver it was asked to run
    printf '#!/bin/sh\ncase "$2" in --version) exec %s "$@" ;; esac\nexit 3\n' "$py3" > "$H/clk/python3"                                          # a saver that fails
    printf '#!/bin/sh\nexit 1\n' > "$H/clk/sleep"; printf '#!/bin/sh\necho "30 100"\n' > "$H/clk/stty"   # so the clock's loop ends after one drawing
    chmod +x "$H/nopy/python3" "$H/pyl/python3" "$H/clk/python3" "$H/clk/sleep" "$H/clk/stty"
    out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display 2>&1 | sed -n 1p)
    [ "$out" = "idle screen after 10 minutes $dot lock after 15 minutes" ] && ok "desktop display: with no saver chosen the line reads as it always did" || bad "display default line" "$out"
    out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display saver 2>&1)
    [ "$out" = "$(printf '\342\234\223 clock\n  spark\n  starfield\n  drift')" ] && ok "desktop display saver: the savers listed, the one in use ticked, as the keyboard lists its layouts" || bad "saver list" "$out"
    rc=0; out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display saver spark 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ "$out" = 'idle screen shows the spark saver' ] && grep -qx 'DISPLAY_SAVER=spark' "$HOME/.config/spark-shell/config" \
        && ok "desktop display saver spark: said in one line, kept in the config" || bad "saver set" "rc=$rc $out"
    out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display 2>&1 | sed -n 1p)
    [ "$out" = "idle screen after 10 minutes $dot spark saver $dot lock after 15 minutes" ] && ok "desktop display: a chosen saver is named between the idle and the lock" || bad "display with saver" "$out"
    [ "$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display saver 2>&1 | sed -n 2p)" = "$(printf '\342\234\223 spark')" ] && ok "desktop display saver: the tick moves to the one chosen" || bad "saver tick" "$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display saver 2>&1)"
    rc=0; out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display saver nope 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: display saver takes clock, spark, starfield or drift' ] && grep -qx 'DISPLAY_SAVER=spark' "$HOME/.config/spark-shell/config" \
        && ok "desktop display saver: a wrong name refused in one line, the config left as it was" || bad "saver word" "rc=$rc $out"
    rc=0; out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" desktop display saver 'spark drift' 2>&1) || rc=$?
    [ "$rc" = 1 ] && grep -qx 'DISPLAY_SAVER=spark' "$HOME/.config/spark-shell/config" && ok "desktop display saver: two names in one word are no name" || bad "saver two words" "rc=$rc $out"
    rc=0; out=$(PATH="$H/nopy:$H/lx:$PATH" sh "$SH" desktop display saver starfield 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: display saver starfield needs python3, which cannot run it here' ] && grep -qx 'DISPLAY_SAVER=spark' "$HOME/.config/spark-shell/config" \
        && ok "desktop display saver: without a python3 that runs it, a saver is refused, the config left" || bad "saver no python" "rc=$rc $out"
    rc=0; out=$(PATH="$H/nopy:$H/lx:$PATH" sh "$SH" desktop display saver clock 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ "$out" = 'idle screen shows the clock alone' ] && grep -qx 'DISPLAY_SAVER=clock' "$HOME/.config/spark-shell/config" && ok "desktop display saver clock: always possible, python3 or not" || bad "saver clock" "rc=$rc $out"
    # the dialog's rows: one row for the saver in use, the others in a full list, none where no saver can run
    rows=$(SWAYSOCK=$H/sock PATH="$H/svx:$H/lx:$PATH" sh "$SH" bar panel display --list 2>&1)
    printf '%s\n' "$rows" | grep -q "saver clock${tb}display show\$" && printf '%s\n' "$rows" | grep -q "idle screen after 10 minutes${tb}display show\$" && printf '%s\n' "$rows" | grep -q "lock after 15 minutes${tb}display show\$" \
        && ok "the dialog's display section: the saver in use ticked beside the idle and lock rows, which read as they did" || bad "saver rows" "$rows"
    rows=$(SWAYSOCK=$H/sock PATH="$H/svx:$H/lx:$PATH" sh "$SH" bar panel display --list full 2>&1)
    [ "$(printf '%s\n' "$rows" | grep -c "${tb}display saver ")" = 3 ] && printf '%s\n' "$rows" | grep -q "saver spark${tb}display saver spark\$" && ! printf '%s\n' "$rows" | grep -q "saver clock${tb}display saver clock" \
        && ok "the dialog's display section, full: the three other choices one Enter away, never the one in use" || bad "saver rows full" "$rows"
    rows=$(SWAYSOCK=$H/sock PATH="$H/nopy:$H/lx:$PATH" sh "$SH" bar panel display --list full 2>&1)
    ! printf '%s\n' "$rows" | grep -q 'saver' && ok "the dialog's display section: no saver rows where python3 cannot run one" || bad "saver rows no python" "$rows"
    rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/svx:$H/lx:$PATH" sh "$SH" bar panel display saver starfield 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ "$out" = 'idle screen shows the starfield saver' ] && grep -qx 'DISPLAY_SAVER=starfield' "$HOME/.config/spark-shell/config" && ok "the dialog: display saver starfield sets it, and says so" || bad "saver from dialog" "rc=$rc $out"
    rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/svx:$H/lx:$PATH" sh "$SH" bar panel display saver fire 2>&1) || rc=$?
    [ "$rc" = 1 ] && grep -qx 'DISPLAY_SAVER=starfield' "$HOME/.config/spark-shell/config" && ok "the dialog: a saver that is not in the list (fire) is refused, the config left" || bad "saver from dialog bad" "rc=$rc $out"
    # the window: the saver in the clock's place; the clock when it cannot run or fails
    rm -f "$HOME/py.log"
    rc=0; out=$(PATH="$H/pyl:$H/lx:$PATH" sh "$SH" desktop idle --clock 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ "$(grep -v -e ' --version$' "$HOME/py.log")" = "python3 $REPO/lib/saver.py starfield" ] && [ -z "$out" ] \
        && ok "desktop idle --clock: with a saver chosen the window runs it, and draws nothing else" || bad "idle runs saver" "rc=$rc $out $(cat "$HOME/py.log" 2>&1)"
    out=$(PATH="$H/clk:$H/lx:$PATH" sh "$SH" desktop idle --clock 2>&1)
    printf '%s' "$out" | grep -q '38;5;16m' && ok "desktop idle --clock: a saver that fails leaves the clock in its window" || bad "idle saver fails" "$out"
    out=$(PATH="$H/nopy:$H/clk:$H/lx:$PATH" sh "$SH" desktop idle --clock 2>&1)
    printf '%s' "$out" | grep -q '38;5;16m' && ok "desktop idle --clock: with no python3 the clock, as before the savers" || bad "idle no python" "$out"
    # a screen beside the main one (#177): the saver without its clock
    rm -f "$HOME/py.log"
    rc=0; out=$(PATH="$H/pyl:$H/lx:$PATH" sh "$SH" desktop idle --side 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ "$(grep -v -e ' --version$' "$HOME/py.log")" = "python3 $REPO/lib/saver.py starfield --no-clock" ] && [ -z "$out" ] \
        && ok "desktop idle --side: a screen beside the main one runs the saver without its clock (#177)" || bad "idle side saver" "rc=$rc $out $(cat "$HOME/py.log" 2>&1)"
    printf 'DESKTOP=sway\nDISPLAY_SAVER=clock\n' > "$HOME/.config/spark-shell/config"
    rm -f "$HOME/py.log"; out=$(PATH="$H/pyl:$H/clk:$H/lx:$PATH" sh "$SH" desktop idle --clock 2>&1)
    [ ! -s "$HOME/py.log" ] && printf '%s' "$out" | grep -q '38;5;16m' && ok "desktop idle --clock: DISPLAY_SAVER=clock never starts python3" || bad "idle clock default" "$out $(cat "$HOME/py.log" 2>&1)"
    rm -f "$HOME/py.log"; rc=0; out=$(PATH="$H/pyl:$H/clk:$H/lx:$PATH" sh "$SH" desktop idle --side 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ ! -s "$HOME/py.log" ] && ! printf '%s' "$out" | grep -q '38;5;16m' && ok "desktop idle --side: with the clock alone, a screen beside the main one is the dimmed wallpaper, no clock (#177)" || bad "idle side clock" "rc=$rc $out"
    # check: a row for it, a warn with a remedy where a chosen saver cannot run
    out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" check 2>&1) || :
    printf '%s\n' "$out" | grep -q '^ok     saver  *the idle screen shows the clock alone$' && ok "check: the saver row says the idle screen shows the clock alone" || bad "check saver clock" "$(printf '%s\n' "$out" | grep saver)"
    printf 'DESKTOP=sway\nDISPLAY_SAVER=drift\n' > "$HOME/.config/spark-shell/config"
    out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" check 2>&1) || :
    printf '%s\n' "$out" | grep -q '^ok     saver  *the idle screen shows the drift saver$' && ok "check: the saver row names the saver in use" || bad "check saver drift" "$(printf '%s\n' "$out" | grep saver)"
    out=$(PATH="$H/nopy:$H/lx:$PATH" sh "$SH" check 2>&1) || :
    printf '%s\n' "$out" | grep -q '^FAIL   desktop .*cannot render: .config/sway/config' \
        && ok "check: an unavailable binding renderer reports failure and continues diagnostics" || bad "check missing renderer" "$out"
    printf '%s\n' "$out" | grep -q '^warn   saver  *python3 cannot run the drift saver: the idle screen shows the clock -- install python3, or spark-shell desktop display saver clock$' && ok "check: a chosen saver python3 cannot run is a warn with its remedy" || bad "check saver warn" "$(printf '%s\n' "$out" | grep saver)"
    # the key
    printf 'DESKTOP=sway\nDISPLAY_SAVER=mystery\n' > "$HOME/.config/spark-shell/config"
    rc=0; out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" status 2>&1) || rc=$?
    [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'DISPLAY_SAVER=mystery in .*: clock, or one of spark starfield drift$' && ok "config: DISPLAY_SAVER=mystery is refused, with the names" || bad "saver key" "rc=$rc $out"
    printf 'DESKTOP=sway\nDISPLAY_SAVER=spark drift\n' > "$HOME/.config/spark-shell/config"
    rc=0; out=$(PATH="$H/svx:$H/lx:$PATH" sh "$SH" status 2>&1) || rc=$?
    [ "$rc" = 1 ] && ok "config: DISPLAY_SAVER=spark drift (two words) is refused, never read as the first" || bad "saver key two" "rc=$rc $out"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
else
    printf '  note saver: python3 not found; the saver section is skipped\n'
fi
grep -q '^DISPLAY_SAVER=clock$' "$REPO/config.example" && sh "$SH" -h | grep -qF 'spark-shell desktop display saver [NAME]' \
    && ok "docs: config.example shows DISPLAY_SAVER and the help lists the saver command" || bad "saver docs" "$(grep -n SAVER "$REPO/config.example")"
# the keyboard
mkdir -p "$H/xkb"; printf '! model\n  pc105  Generic\n\n! layout\n  us              English (US)\n  br              Portuguese (Brazil)\n\n! variant\n  intl            us: English (US, intl.)\n' > "$H/xkb/evdev.lst"
rc=0; out=$(SPARK_SHELL_XKB_LST=$H/xkb/evdev.lst PATH="$H/lx:$PATH" sh "$SH" desktop keyboard us us+intl br 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'keyboard us us+intl br' ] && grep -qx 'KEYBOARD=us us+intl br' "$HOME/.config/spark-shell/config" \
    && grep -qx 'input type:keyboard xkb_layout "us,us,br"' "$swc" && grep -qx 'input type:keyboard xkb_variant ",intl,"' "$swc" \
    && ok "desktop keyboard us us+intl br: the config, and sway's layouts and variants line for line" || bad "keyboard set" "rc=$rc $out $(grep -n 'input' "$swc")"
rc=0; out=$(SPARK_SHELL_XKB_LST=$H/xkb/evdev.lst PATH="$H/lx:$PATH" sh "$SH" desktop keyboard us zz 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: zz is no keyboard layout xkb knows (the two-letter names: us, br, de, fr, gb)' ] && grep -qx 'KEYBOARD=us us+intl br' "$HOME/.config/spark-shell/config" \
    && ok "desktop keyboard: a layout xkb does not list is refused, the config kept" || bad "keyboard unknown" "rc=$rc $out"
rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop keyboard next 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx -- '-- input type:keyboard xkb_switch_layout next' "$HOME/swaymsg.log" && ok "desktop keyboard next: sway goes to the next layout" || bad "keyboard next" "rc=$rc $out $(cat "$HOME/swaymsg.log")"
# native input preferences: applied, kept, bounded, and reversible
[ "$(grep -c '^input type:touchpad tap enabled$' "$swc")" = 1 ] && grep -qx 'input type:keyboard repeat_rate 25' "$swc" \
    && ok "input defaults: tap to click on touchpads, repeat at 25 per second" || bad "input defaults" "$(grep '^input' "$swc")"
rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop pointer speed 0.5 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'pointer speed 0.5' ] && grep -qx 'POINTER_SPEED=0.5' "$HOME/.config/spark-shell/config" \
    && grep -qx -- '-- input type:pointer pointer_accel 0.5' "$HOME/swaymsg.log" && grep -qx -- '-- input type:touchpad pointer_accel 0.5' "$HOME/swaymsg.log" \
    && grep -qx 'input type:pointer pointer_accel 0.5' "$swc" && ok "pointer speed: mouse and touchpad take it now and at login" || bad "pointer speed" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop pointer tap off 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'POINTER_TAP=off' "$HOME/.config/spark-shell/config" && grep -qx 'input type:touchpad tap disabled' "$swc" \
    && ok "pointer tap: disabled on touchpads, saved for the next login" || bad "pointer tap" "rc=$rc $out"
before=$(cksum < "$HOME/.config/spark-shell/config")
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop pointer speed 2 2>&1) || rc=$?
[ "$rc" != 0 ] && [ "$before" = "$(cksum < "$HOME/.config/spark-shell/config")" ] && ok "pointer speed: an out of range value leaves settings alone" || bad "pointer bounds" "rc=$rc $out"
mkdir -p "$H/inputfail"
printf '#!/bin/sh\ncase "$*" in "-- input type:pointer pointer_accel 1") exit 1 ;; esac\nexec "%s" "$@"\n' "$H/lx/swaymsg" > "$H/inputfail/swaymsg"
chmod +x "$H/inputfail/swaymsg"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/inputfail:$H/lx:$PATH" sh "$SH" desktop pointer speed 1 2>&1) || rc=$?
[ "$rc" != 0 ] && [ "$before" = "$(cksum < "$HOME/.config/spark-shell/config")" ] && printf '%s' "$out" | grep -q 'saved setting is unchanged' \
    && ok "pointer: native refusal leaves the saved preference alone" || bad "pointer native refusal" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop keyboard repeat-delay 400 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'KEY_REPEAT_DELAY=400' "$HOME/.config/spark-shell/config" && grep -qx 'input type:keyboard repeat_delay 400' "$swc" \
    && ok "keyboard delay: applied and saved without changing layouts" || bad "keyboard delay" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop keyboard repeat-rate 0 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'input type:keyboard repeat_rate 0' "$swc" && ok "keyboard repeat: zero disables repeat" || bad "keyboard repeat zero" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop keyboard caps escape 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'input type:keyboard xkb_options caps:escape' "$swc" && grep -qx -- '-- input type:keyboard xkb_options caps:escape' "$HOME/swaymsg.log" \
    && ok "keyboard caps: escape is live and kept" || bad "keyboard caps" "rc=$rc $out"
before=$(cksum < "$HOME/.config/spark-shell/config")
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop keyboard repeat-delay 99 2>&1) || rc=$?
[ "$rc" != 0 ] && [ "$before" = "$(cksum < "$HOME/.config/spark-shell/config")" ] && ok "keyboard delay: refuses too small a delay before a write" || bad "keyboard delay bounds" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel pointer speed -0.5 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'POINTER_SPEED=-0.5' "$HOME/.config/spark-shell/config" && ok "pointer: the dialog uses the same setting" || bad "pointer panel" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel undo all 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qx 'POINTER_SPEED=0.5' "$HOME/.config/spark-shell/config" && ok "pointer: undo restores the prior value" || bad "pointer undo" "rc=$rc $out"
# the screens
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen 2>&1) || rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'HDMI-A-1  Lenovo Group Limited T24i-30 V30A1  1920x1080  scale 1  at 1920,0' && ok "desktop screen: each screen by port, make, model and serial, its mode, scale and place" || bad "screen list" "rc=$rc $out"
rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen t24i scale 1.5 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'HDMI-A-1 scale 1.5' ] && grep -qxF -- '-- output "Lenovo Group Limited T24i-30 V30A1" scale 1.5' "$HOME/swaymsg.log" \
    && grep -qxF 'output "Lenovo Group Limited T24i-30 V30A1" scale 1.5' "$HOME/.config/spark-shell/screens.conf" \
    && ok "desktop screen t24i scale 1.5: found by its model, sway takes it at once, the file keeps it by make, model and serial" || bad "screen scale" "rc=$rc $out $(cat "$HOME/swaymsg.log")"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 left-of edp-1 2>&1) || rc=$?
SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 scale 1 >/dev/null 2>&1 || :
[ "$rc" = 0 ] && [ "$out" = 'HDMI-A-1 left-of eDP-1' ] && grep -qxF 'output "Lenovo Group Limited T24i-30 V30A1" position -1920 0' "$HOME/.config/spark-shell/screens.conf" \
    && [ "$(grep -c 'T24i-30' "$HOME/.config/spark-shell/screens.conf")" = 3 ] && grep -qxF 'output "Lenovo Group Limited T24i-30 V30A1" scale 1' "$HOME/.config/spark-shell/screens.conf" && grep -qxF '# beside "Lenovo Group Limited T24i-30 V30A1" left-of "BOE 0x0BCA Unknown"' "$HOME/.config/spark-shell/screens.conf" \
    && ok "desktop screen left-of: placed by the other's edge; the file keeps one line per kind (the scale replaced, the place kept) and the two screens as a comment, for a turn to place it again (#109)" || bad "screen place" "rc=$rc $out $(cat "$HOME/.config/spark-shell/screens.conf")"
# a placed screen reaches the login screen's own copy at once, when root asks no password (#116)
mkdir -p "$H/root/etc/spark-shell/login"; echo '# a login screen' > "$H/root/etc/spark-shell/login/sway.conf"; printf 'LOGIN=yes\n' >> "$HOME/.config/spark-shell/config"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 left-of edp-1 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qxF 'output "Lenovo Group Limited T24i-30 V30A1" position -1920 0' "$H/root/etc/spark-shell/login/screens.conf" && ! grep -q 'beside' "$H/root/etc/spark-shell/login/screens.conf" \
    && ok "desktop screen: the login screen's screens.conf follows at once (a root with no password), the output lines alone (#116)" || bad "screen login follow" "rc=$rc $out $(cat "$H/root/etc/spark-shell/login/screens.conf" 2>&1)"
# the main screen (#135): workspace 1 and the focus at the start on it, the login screen's form there too; one main at a time
SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen edp-1 main >/dev/null 2>&1 || :
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen t24i main 2>&1) || rc=$?
_mf=$HOME/.config/spark-shell/screens.conf
[ "$rc" = 0 ] && [ "$out" = 'HDMI-A-1 is the main screen: workspace 1 and the login screen go to it from the next start' ] \
    && grep -qxF 'workspace 1 output "Lenovo Group Limited T24i-30 V30A1"' "$_mf" && grep -qxF "exec swaymsg focus output '\"Lenovo Group Limited T24i-30 V30A1\"'" "$_mf" \
    && [ "$(grep -c '^workspace 1 output' "$_mf")" = 1 ] && [ "$(grep -c '^exec swaymsg focus output' "$_mf")" = 1 ] && grep -qxF 'output "Lenovo Group Limited T24i-30 V30A1" position -1920 0' "$_mf" \
    && grep -qxF 'workspace 1 output "Lenovo Group Limited T24i-30 V30A1"' "$H/root/etc/spark-shell/login/screens.conf" && ! grep -q '^exec' "$H/root/etc/spark-shell/login/screens.conf" \
    && grep -qF 'workspace 1 output "Lenovo Group Limited T24i-30 V30A1"' "$HOME/swaymsg.log" \
    && ok "desktop screen main: workspace 1 and the focus at the start on it, the one before gone, the other lines kept; the login screen's copy names it for its form (#135)" || bad "screen main" "rc=$rc $out $(cat "$_mf") | $(cat "$H/root/etc/spark-shell/login/screens.conf" 2>&1)"
# X11's main screen (#173): the main screen named X11's primary once Xwayland runs, by its port; once only; nothing with no X11 or no xrandr
mkdir -p "$H/xr"
printf '#!/bin/sh\necho "$*" >> "$HOME/xrandr.log"\n[ "$1" != --listmonitors ] || cat "$HOME/xrandr.monitors" 2>/dev/null\n' > "$H/xr/xrandr"; chmod +x "$H/xr/xrandr"
rm -f "$HOME/xrandr.log" "$HOME/xrandr.monitors"
DISPLAY=:9 SWAYSOCK=$H/sock PATH="$H/xr:$H/lx:$PATH" sh "$SH" desktop screen --x11-main >/dev/null 2>&1 || :
_x1=$(grep -c -- '--output HDMI-A-1 --primary' "$HOME/xrandr.log" 2>/dev/null || :)
printf ' 0: +*HDMI-A-1 1920/531x1080/299+1920+0  HDMI-A-1\n' > "$HOME/xrandr.monitors"; rm -f "$HOME/xrandr.log"
DISPLAY=:9 SWAYSOCK=$H/sock PATH="$H/xr:$H/lx:$PATH" sh "$SH" desktop screen --x11-main >/dev/null 2>&1 || :
_x2=$(grep -c -- '--primary' "$HOME/xrandr.log" 2>/dev/null || :)
rm -f "$HOME/xrandr.log"; (unset DISPLAY; SWAYSOCK=$H/sock PATH="$H/xr:$H/lx:$PATH" sh "$SH" desktop screen --x11-main >/dev/null 2>&1) || :
[ "$_x1" = 1 ] && [ "$_x2" = 0 ] && [ ! -e "$HOME/xrandr.log" ] && grep -qxF 'for_window [shell="xwayland"] exec @REPO@/spark-shell desktop screen --x11-main' "$REPO/template/.config/sway/config" \
    && ok "desktop screen: the main screen is X11's primary once an X11 window starts, by its port, once; nothing with no X11 (#173)" || bad "screen x11 main" "x1=$_x1 x2=$_x2 $(cat "$HOME/xrandr.log" 2>&1)"
rm -f "$HOME/xrandr.log" "$HOME/xrandr.monitors"
grep -qF 'sed -n '"'"'s/^workspace 1 output "\(.*\)"$/\1/p'"'"' /@LOGIN_ETC@/screens.conf' "$REPO/template/login/window" \
    && ok "login window: its form goes to the main screen screens.conf names, else the one at 0 0 (#135)" || bad "login window main" "$(head -12 "$REPO/template/login/window")"
grep -v '^LOGIN=' "$HOME/.config/spark-shell/config" > "$H/cfg.tmp" && cat "$H/cfg.tmp" > "$HOME/.config/spark-shell/config"; rm -rf "$H/root/etc/spark-shell/login"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen edp-1 off 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'eDP-1 off' ] && grep -qxF -- '-- output "BOE 0x0BCA Unknown" disable' "$HOME/swaymsg.log" && grep -q 'disable' "$HOME/.config/spark-shell/screens.conf" \
    && ok "desktop screen off: applied and saved for the next login" || bad "screen off" "rc=$rc $out $(cat "$HOME/.config/spark-shell/screens.conf")"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen edp-1 mode 800x600 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: eDP-1 has no mode 800x600: 1280x720, 1920x1080' ] && ok "desktop screen mode: a mode the screen lacks refused, naming those it has" || bad "screen mode" "rc=$rc $out"
# The same settings through MCP, including the undo receipt and children.
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://display/rows"}}')
printf '%s' "$j" | jq -e '.result.contents[0].text | fromjson | any(.rows[]; .children == "spark-shell://display/rows/screen/HDMI-A-1")' >/dev/null     && ok "display: each screen opens its choices" || bad "display child" "$j"
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://display/rows/screen/HDMI-A-1"}}')
printf '%s' "$j" | jq -e '.result.contents[0].text | fromjson | any(.rows[]; .tool.name == "display_mode" and .tool.arguments.mode == "1920x1080") and any(.rows[]; .tool.name == "display_place" and .tool.arguments.other == "eDP-1")' >/dev/null     && ok "display: native modes and connected neighbors are offered" || bad "display choices" "$j"
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"display_scale","arguments":{"screen":"HDMI-A-1","scale":"1.5"}}}')
printf '%s' "$j" | jq -e '.result.isError == false and .result.structuredContent.undo == {name:"display_scale",arguments:{screen:"HDMI-A-1",scale:"1"}}' >/dev/null     && ok "display: scale runs through the native action with its prior value as undo" || bad "display scale tool" "$j"
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"display_position","arguments":{"screen":"HDMI-A-1","x":-100,"y":200}}}')
printf '%s' "$j" | jq -e '.result.isError == false and .result.structuredContent.undo.arguments == {screen:"HDMI-A-1",x:1920,y:0}' >/dev/null     && ok "display: absolute placement has typed coordinates and undo" || bad "display position tool" "$j"
before=$(cksum < "$HOME/swaymsg.log")
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"display_position","arguments":{"screen":"HDMI-A-1","x":"0; exec bad","y":0}}}')
printf '%s' "$j" | jq -e '.error.code == -32602' >/dev/null && [ "$before" = "$(cksum < "$HOME/swaymsg.log")" ]     && ok "display: invalid coordinate text is refused before a native call" || bad "display invalid coordinate" "$j"
SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen edp-1 on >/dev/null
! grep -q 'disable' "$HOME/.config/spark-shell/screens.conf" && grep -q 'enable' "$HOME/.config/spark-shell/screens.conf"     && ok "display: on replaces a saved off, with no conflicting power line" || bad "display saved power"
# the orientation (#109): sway's transform, kept like the others; a screen placed beside another is placed again after a turn; the dialog offers the four
rm -f "$HOME/swaymsg.log"; SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 left-of edp-1 >/dev/null 2>&1
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 transform 90 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'HDMI-A-1 turned 90' ] && grep -qxF -- '-- output "Lenovo Group Limited T24i-30 V30A1" transform 90' "$HOME/swaymsg.log" && grep -qxF 'output "Lenovo Group Limited T24i-30 V30A1" transform 90' "$HOME/.config/spark-shell/screens.conf" \
    && grep -qxF '# beside "Lenovo Group Limited T24i-30 V30A1" left-of "BOE 0x0BCA Unknown"' "$HOME/.config/spark-shell/screens.conf" && [ "$(grep -c '^-- output "Lenovo Group Limited T24i-30 V30A1" position' "$HOME/swaymsg.log")" = 2 ] \
    && ok "desktop screen transform 90: sway's own word, kept in screens.conf; the place beside the other screen is a comment there, and the turn places it again" || bad "screen transform" "rc=$rc $out $(cat "$HOME/swaymsg.log") $(cat "$HOME/.config/spark-shell/screens.conf")"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 transform flipped 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: transform takes normal, 90, 180 or 270 (clockwise); no mirrored orientation' ] && ok "desktop screen transform: a mirrored orientation is refused" || bad "screen transform flipped" "rc=$rc $out"
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://display/rows/screen/HDMI-A-1"}}')
printf '%s' "$j" | jq -e '.result.contents[0].text | fromjson | [.rows[] | select(.group == "orientation") | .text + ":" + .tool.name + ":" + .tool.arguments.transform] == ["upright:display_transform:normal", "turned 90:display_transform:90", "turned 180:display_transform:180", "turned 270:display_transform:270"]' >/dev/null \
    && ok "display: a screen's rows offer the orientation, upright and three turns, through one typed tool" || bad "display orientation rows" "$j"
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"display_transform","arguments":{"screen":"HDMI-A-1","transform":"180"}}}')
printf '%s' "$j" | jq -e '.result.isError == false and .result.structuredContent.receipt == "HDMI-A-1 turned 180" and .result.structuredContent.undo == {name:"display_transform",arguments:{screen:"HDMI-A-1",transform:"normal"}}' >/dev/null \
    && ok "display: the orientation tool turns the screen, its undo the orientation it had (sway says none: upright)" || bad "display transform tool" "$j"
j=$(screen_mcp '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"display_transform","arguments":{"screen":"HDMI-A-1","transform":"flipped-90"}}}')
[ "$(printf '%s' "$j" | jq -r '.error.code')" = -32602 ] && ok "display: a mirrored orientation never reaches sway" || bad "display transform refused" "$j"
# A single active screen stays on; a login with none recovers one.
mkdir -p "$H/screens-one"
cat > "$H/screens-one/swaymsg" <<'SCREEN_STUB'
#!/bin/sh
case "$*" in
    '-t get_version') echo '{}' ;;
    '-t get_outputs') printf '[{"name":"HDMI-A-1","make":"Test","model":"Screen","serial":"1","active":%s,"scale":1,"rect":{"x":0,"y":0,"width":1920,"height":1080},"current_mode":{"width":1920,"height":1080},"modes":[]}]\n' "${SCREEN_ACTIVE:-true}" ;;
    *) echo "$*" >> "$HOME/one-screen.log" ;;
esac
SCREEN_STUB
chmod +x "$H/screens-one/swaymsg"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/screens-one:$H/lx:$PATH" sh "$SH" desktop screen HDMI-A-1 off 2>&1) || rc=$?
[ "$rc" = 1 ] && [ ! -e "$H/one-screen.log" ] && ok "display: the last active screen cannot be disabled" || bad "display last screen" "$out"
SCREEN_ACTIVE=false SWAYSOCK=$H/sock PATH="$H/screens-one:$H/lx:$PATH" sh "$SH" desktop screen --ensure-visible >/dev/null
grep -q 'enable' "$H/one-screen.log" && ok "display: login recovers an all-off set of connected screens" || bad "display recovery"
# the layout's left and top edges at 0 (#171): a screen left of 0 moves with every other by the same amount
mkdir -p "$H/screens-left"
cat > "$H/screens-left/swaymsg" <<'LEFT_STUB'
#!/bin/sh
case "$*" in
    '-t get_version') echo '{}' ;;
    '-t get_outputs') echo '[{"name":"DP-3","make":"Test","model":"Tall","serial":"2","active":true,"scale":1,"rect":{"x":-1200,"y":0,"width":1200,"height":1920},"current_mode":{"width":1920,"height":1200},"modes":[]},{"name":"HDMI-A-1","make":"Test","model":"Screen","serial":"1","active":true,"scale":1,"rect":{"x":0,"y":0,"width":1920,"height":1080},"current_mode":{"width":1920,"height":1080},"modes":[]}]' ;;
    *) echo "$*" >> "$HOME/left-screen.log" ;;
esac
LEFT_STUB
chmod +x "$H/screens-left/swaymsg"
cp "$HOME/.config/spark-shell/screens.conf" "$H/screens.keep" 2>/dev/null || :
printf '%s\n' '# rendered by spark-shell: the screens' 'output "Test Tall 2" transform 270' 'output "Test Tall 2" position -1200 0' '# beside "Test Tall 2" left-of "Test Screen 1"' > "$HOME/.config/spark-shell/screens.conf"
rm -f "$HOME/left-screen.log"
SWAYSOCK=$H/sock PATH="$H/screens-left:$H/lx:$PATH" sh "$SH" desktop screen --ensure-visible >/dev/null 2>&1 || :
_sl=$HOME/.config/spark-shell/screens.conf
grep -qxF -- '-- output "Test Tall 2" position 0 0' "$HOME/left-screen.log" && grep -qxF -- '-- output "Test Screen 1" position 1200 0' "$HOME/left-screen.log" \
    && grep -qxF 'output "Test Tall 2" position 0 0' "$_sl" && grep -qxF 'output "Test Screen 1" position 1200 0' "$_sl" && ! grep -q 'position -' "$_sl" \
    && grep -qxF 'output "Test Tall 2" transform 270' "$_sl" && grep -qxF '# beside "Test Tall 2" left-of "Test Screen 1"' "$_sl" \
    && ok "desktop screen: at the start a screen left of 0 moves with every other by the same amount, its turn and beside line kept (#171)" || bad "screen origin" "$(cat "$HOME/left-screen.log" 2>&1) | $(cat "$_sl")"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/screens-left:$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 scale 1 2>&1) || rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -qx 'every screen moved by the same amount, so none sits left of or above 0 (X11 apps take clicks there)' \
    && ok "desktop screen: a change that leaves a screen left of 0 moves them all and says so (#171)" || bad "screen origin said" "rc=$rc $out"
rm -f "$HOME/left-screen.log"; SWAYSOCK=$H/sock PATH="$H/screens-one:$H/lx:$PATH" sh "$SH" desktop screen --ensure-visible >/dev/null 2>&1 || :
[ ! -e "$HOME/left-screen.log" ] && ! grep -q 'position' "$H/one-screen.log" && ok "desktop screen: a layout already at 0 is left as it is (#171)" || bad "screen origin none" "$(cat "$H/one-screen.log")"
[ ! -f "$H/screens.keep" ] || cp "$H/screens.keep" "$_sl"
# the window keys (#182): a snap is one sway command to the focused window, its half of the workspace's area; float toggles at two thirds, centered
mkdir -p "$H/win"
cat > "$H/win/swaymsg" <<'WIN_STUB'
#!/bin/sh
case "$*" in
    '-t get_version') echo '{}' ;;
    '-t get_tree') echo tree >> "$HOME/win.trees"; cat "$HOME/win-tree.json" ;;
    *) echo "$*" >> "$HOME/win.log" ;;
esac
WIN_STUB
chmod +x "$H/win/swaymsg"
win_tree() { printf '{"type":"root","nodes":[{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","id":3,"num":1,"rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[{"type":"%s","id":7,"focused":%s,"fullscreen_mode":%s,"nodes":[]}],"floating_nodes":[]}]}]}\n' "$1" "$2" "$3" > "$HOME/win-tree.json"; }
win_run() { rm -f "$HOME/win.log" "$HOME/win.trees"; rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/win:$H/lx:$PATH" sh "$SH" desktop window "$@" 2>&1) || rc=$?; }
win_tree con true 0
win_run left; _wl=$(cat "$HOME/win.log" 2>/dev/null)
win_run right; _wr=$(cat "$HOME/win.log" 2>/dev/null)
win_run up; _wu=$(cat "$HOME/win.log" 2>/dev/null)
win_run down; _wd=$(cat "$HOME/win.log" 2>/dev/null)
[ "$_wl" = '-- [con_id=7] mark --add _spark-shell.tiled.7, floating enable, resize set width 944 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.LF.7, mark --add _spark-shell.area.1216.42.1888.1022.7' ] \
    && [ "$_wr" = '-- [con_id=7] mark --add _spark-shell.tiled.7, floating enable, resize set width 944 px height 1022 px, move absolute position 2160 42, mark --add _spark-shell.place.RF.7, mark --add _spark-shell.area.1216.42.1888.1022.7' ] \
    && [ "$_wu" = '-- [con_id=7] mark --add _spark-shell.tiled.7, floating enable, resize set width 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.tiled.7' ] \
    && [ "$_wd" = '-- [con_id=7] mark --add _spark-shell.min.tiled.7, move scratchpad' ] && [ "$out" = 'the window is on the pad: a click or Super+minus brings it back' ] \
    && ok "desktop window left, right: the focused window floats at that half of its workspace's area, one command by its con_id (#182), marked as one the keys took from the tiling (v0.133); up fills the area and down minimizes, in one press (v0.140)" || bad "window snap" "$_wl | $_wr | $_wu | $_wd | $out"
win_run float
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=7] floating enable, resize set width 1258 px height 681 px, move position center' ] && [ "$out" = 'the window is floating' ] \
    && ok "desktop window float: a tiled window floats at two thirds of its workspace, centered (#182)" || bad "window float" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_tree floating_con true 0; win_run float
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=7] floating disable, mark --add _spark-shell.yours.7' ] && [ "$out" = 'the window is tiled' ] && ok "desktop window float: a floating window tiles again (#182), the person's choice, so a new window's rule leaves it tiled (#262)" || bad "window tile" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_tree con true 1; win_run left
[ "$(cat "$HOME/win.log")" = '-- [con_id=7] fullscreen disable, mark --add _spark-shell.tiled.7, floating enable, resize set width 944 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.LF.7, mark --add _spark-shell.area.1216.42.1888.1022.7' ] && ok "desktop window: a full screen window leaves full screen before its snap (#182)" || bad "window full" "$(cat "$HOME/win.log" 2>&1)"
win_tree con false 0; win_run left
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: no window has the focus' ] && [ ! -e "$HOME/win.log" ] && ok "desktop window: no window with the focus, refused in one line, nothing sent (#182)" || bad "window none" "rc=$rc $out"
win_run sideways
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: window takes float, left, right, up, down, max, min, toggle, restore, move, back or refit' ] && ok "desktop window: a wrong word refused in one line (#182)" || bad "window word" "rc=$rc $out"
win_run restore x7
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: window takes a window's ID, its digits, after the word" ] && [ ! -e "$HOME/win.log" ] && ok "desktop window: an ID that is not digits refused in one line, nothing sent (v0.133)" || bad "window id word" "rc=$rc $out"
# the window states: each key reads the place the floating window sits at (its rect on the area's two by two grid);
# Up and Down step it a row, past the top it is maximized, past the bottom minimized; Super+minus brings it back
win_at() { printf '{"type":"root","nodes":[{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","id":3,"num":1,"rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[],"floating_nodes":[{"type":"floating_con","id":7,"focused":true,"fullscreen_mode":0,"rect":{"x":%s,"y":%s,"width":%s,"height":%s},"nodes":[]}]}]}]}\n' "$1" "$2" "$3" "$4" > "$HOME/win-tree.json"; }
_wq='-- [con_id=7] floating enable, resize set width'
win_at 2160 42 944 1022; win_run down
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$_wq 944 px height 511 px, move absolute position 2160 553, mark --add _spark-shell.place.RB.7, mark --add _spark-shell.area.1216.42.1888.1022.7" ] && [ "$out" = 'the window is in the bottom right quarter' ] \
    && ok "desktop window: Super+Down on the right half takes it to the bottom right quarter" || bad "window right down" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_at 2160 553 944 511; win_run down
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=7] mark --add _spark-shell.min.RB.7, move scratchpad' ] && [ "$out" = 'the window is on the pad: a click or Super+minus brings it back' ] \
    && ok "desktop window: Super+Down on a bottom quarter minimizes it to the pad, marked with the place it left" || bad "window quarter down" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_at 2161 554 943 510; win_run up
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$_wq 944 px height 1022 px, move absolute position 2160 42, mark --add _spark-shell.place.RF.7, mark --add _spark-shell.area.1216.42.1888.1022.7" ] && [ "$out" = 'the window is on the right half' ] \
    && ok "desktop window: Super+Up on a bottom quarter, a pixel off, goes back to its half" || bad "window quarter up" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_at 1216 42 1886 504; win_run up
[ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.FT.7" ] && [ "$out" = 'the window is maximized' ] \
    && ok "desktop window: a terminal a few cells short of the top half is on it: Super+Up maximizes it, and keeps where it came from" || bad "window cells up" "$out $(cat "$HOME/win.log" 2>&1)"
win_at 1216 42 1888 440; win_run up
[ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.1216.42.1888.440.7" ] && ok "desktop window: a window much shorter than the top half is free: Super+Up fills the area, its rect kept (v0.140)" || bad "window short up" "$(cat "$HOME/win.log" 2>&1)"
win_at 1216 42 1888 511; win_run up
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.FT.7" ] && [ "$out" = 'the window is maximized' ] \
    && ok "desktop window: Super+Up on the top half maximizes it: Super+Up twice" || bad "window top up" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_at 1216 42 1888 1022; win_run down
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 511 px, move absolute position 1216 553, mark --add _spark-shell.place.FB.7, mark --add _spark-shell.area.1216.42.1888.1022.7" ] && [ "$out" = 'the window is on the bottom half' ] \
    && ok "desktop window: Super+Down on a maximized window takes it to the bottom half" || bad "window max down" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_at 1216 553 1888 511; win_run down
[ "$(cat "$HOME/win.log")" = '-- [con_id=7] mark --add _spark-shell.min.FB.7, move scratchpad' ] && ok "desktop window: Super+Down on the bottom half minimizes it: Super+Down twice" || bad "window bottom down" "$(cat "$HOME/win.log" 2>&1)"
win_at 2160 42 944 511; win_run left
[ "$(cat "$HOME/win.log")" = "$_wq 944 px height 511 px, move absolute position 1216 42, mark --add _spark-shell.place.LT.7, mark --add _spark-shell.area.1216.42.1888.1022.7" ] && [ "$out" = 'the window is in the top left quarter' ] \
    && ok "desktop window: Super+Left on the top right quarter keeps its row" || bad "window quarter left" "$out $(cat "$HOME/win.log" 2>&1)"
win_at 1400 200 800 600; win_run up
[ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.1400.200.800.600.7" ] && ok "desktop window: a floating window at no place is free: Super+Up fills the area (v0.140)" || bad "window free up" "$(cat "$HOME/win.log" 2>&1)"
win_at 2160 42 944 1022; win_run up 7
[ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 511 px, move absolute position 1216 42, mark --add _spark-shell.place.FT.7, mark --add _spark-shell.area.1216.42.1888.1022.7" ] && ok "desktop window: a window named by its ID gets the half it asks for (the dialog's place rows)" || bad "window id up" "$(cat "$HOME/win.log" 2>&1)"
win_at 2160 42 944 1022; win_run max
[ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.RF.7" ] && ok "desktop window max: the window fills the area, its place kept for the way back" || bad "window max" "$(cat "$HOME/win.log" 2>&1)"
win_tree con true 0; win_run min
[ "$(cat "$HOME/win.log")" = '-- [con_id=7] mark --add _spark-shell.min.tiled.7, move scratchpad' ] && ok "desktop window min: a tiled window is minimized, marked tiled" || bad "window min" "$(cat "$HOME/win.log" 2>&1)"
printf '{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","rect":{"x":0,"y":0,"width":0,"height":0},"nodes":[],"floating_nodes":[{"type":"floating_con","id":5,"marks":["_spark-shell.min.tiled.5"],"nodes":[]},{"type":"floating_con","id":8,"marks":[],"nodes":[]},{"type":"floating_con","id":9,"marks":["_spark-shell.min.RB.9"],"nodes":[]}]}]},{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","name":"1","focused":true,"rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[],"floating_nodes":[]}]}]}\n' > "$HOME/win-tree.json"
win_run restore
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.min.RB.9, scratchpad show, floating disable, floating enable, resize set width 944 px height 511 px, move absolute position 2160 553, mark --add _spark-shell.place.RB.9, mark --add _spark-shell.area.1216.42.1888.1022.9' ] \
    && [ "$out" = 'the window is back, in the bottom right quarter' ] && ok "desktop window restore: the window minimized last comes back at the place it left" || bad "window restore" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
printf '{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","nodes":[],"floating_nodes":[{"type":"floating_con","id":5,"marks":["_spark-shell.min.tiled.5"],"nodes":[]}]}]}]}\n' > "$HOME/win-tree.json"
win_run restore
[ "$(cat "$HOME/win.log")" = '-- [con_id=5] unmark _spark-shell.min.tiled.5, scratchpad show, floating disable' ] && [ "$out" = 'the window is back, tiled' ] && ok "desktop window restore: a window minimized from the tiling tiles again" || bad "window restore tiled" "$out $(cat "$HOME/win.log" 2>&1)"
printf '{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","nodes":[],"floating_nodes":[{"type":"floating_con","id":8,"marks":[],"nodes":[]}]}]}]}\n' > "$HOME/win-tree.json"
win_run restore
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: no window is on the pad' ] && [ ! -e "$HOME/win.log" ] && ok "desktop window restore: a scratchpad window spark-shell did not minimize stays, refused in one line" || bad "window restore none" "rc=$rc $out"
# the tiled fix (v0.133): Super+Down twice on a tiled window floated it to the bottom half, then minimized it from
# there, and it came back floating on that half; the keys now mark a window they take from the tiling, and the pad
# tiles it again
win_atm() { printf '{"type":"root","nodes":[{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","id":3,"num":1,"rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[],"floating_nodes":[{"type":"floating_con","id":7,"focused":true,"fullscreen_mode":0,"marks":[%s],"rect":{"x":%s,"y":%s,"width":%s,"height":%s},"nodes":[]}]}]}]}\n' "$5" "$1" "$2" "$3" "$4" > "$HOME/win-tree.json"; }
win_atm 1216 553 1888 511 '"_spark-shell.tiled.7"'; win_run down
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=7] unmark _spark-shell.tiled.7, mark --add _spark-shell.min.tiled.7, move scratchpad' ] && [ "$out" = 'the window is on the pad: a click or Super+minus brings it back' ] \
    && ok "desktop window: a window the keys took from the tiling goes to the pad marked tiled, from the bottom half too: Super+Down twice on a tiled window brings it back tiled (v0.133)" || bad "window tiled min" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_atm 2160 42 944 1022 '"_spark-shell.tiled.7"'; win_run down
[ "$(cat "$HOME/win.log")" = "-- [con_id=7] unmark _spark-shell.tiled.7, floating enable, resize set width 944 px height 511 px, move absolute position 2160 553, mark --add _spark-shell.place.RB.7, mark --add _spark-shell.area.1216.42.1888.1022.7" ] && ok "desktop window: a second place a key gives ends the tiling's mark, so that place is the one that comes back from the pad (v0.133)" || bad "window tiled step" "$(cat "$HOME/win.log" 2>&1)"
win_atm 1216 553 1888 511 '"_spark-shell.tiled.7"'; win_run float
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=7] unmark _spark-shell.tiled.7, floating disable, mark --add _spark-shell.yours.7' ] && [ "$out" = 'the window is tiled' ] \
    && ok "desktop window float: a window tiled again by the float key leaves its tiling mark behind (v0.133)" || bad "window tiled float" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_atm 1216 553 1888 511 ''; win_run down
[ "$(cat "$HOME/win.log")" = '-- [con_id=7] mark --add _spark-shell.min.FB.7, move scratchpad' ] && ok "desktop window: a window floating by itself still comes back at the place it left (v0.133)" || bad "window floating min" "$(cat "$HOME/win.log" 2>&1)"
# the fill glyph (v0.140): toggle fills the area, and from the whole area goes back where the window came from
win_atm 1216 42 1888 1022 '"_spark-shell.place.FF.7","_spark-shell.area.1216.42.1888.1022.7","_spark-shell.from.RF.7"'; win_run toggle
[ "$(cat "$HOME/win.log")" = '-- [con_id=7] unmark _spark-shell.place.FF.7, unmark _spark-shell.area.1216.42.1888.1022.7, unmark _spark-shell.from.RF.7, floating enable, resize set width 944 px height 1022 px, move absolute position 2160 42, mark --add _spark-shell.place.RF.7, mark --add _spark-shell.area.1216.42.1888.1022.7' ] && [ "$out" = 'the window is on the right half' ] \
    && ok "desktop window toggle: a window that fills the area goes back where it came from (v0.140)" || bad "window toggle back" "$out $(cat "$HOME/win.log" 2>&1)"
win_atm 1216 42 1888 1022 '"_spark-shell.place.FF.7","_spark-shell.area.1216.42.1888.1022.7","_spark-shell.from.tiled.7","_spark-shell.tiled.7"'; win_run toggle
[ "$(cat "$HOME/win.log")" = '-- [con_id=7] unmark _spark-shell.tiled.7, unmark _spark-shell.place.FF.7, unmark _spark-shell.area.1216.42.1888.1022.7, unmark _spark-shell.from.tiled.7, floating disable' ] && [ "$out" = 'the window is tiled' ] \
    && ok "desktop window toggle: a window the keys took from the tiling tiles again" || bad "window toggle tiled" "$out $(cat "$HOME/win.log" 2>&1)"
win_atm 1400 200 800 600 ''; win_run toggle
[ "$(cat "$HOME/win.log")" = "$_wq 1888 px height 1022 px, move absolute position 1216 42, mark --add _spark-shell.place.FF.7, mark --add _spark-shell.area.1216.42.1888.1022.7, mark --add _spark-shell.from.1400.200.800.600.7" ] && [ "$out" = 'the window is maximized' ] \
    && ok "desktop window toggle: a free window fills the area, its rect kept" || bad "window toggle fill" "$out $(cat "$HOME/win.log" 2>&1)"
# a window by its ID (the pad's click): that one, from among those on the pad; one the pad does not hold is refused
pad_tree() { printf '{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","nodes":[],"floating_nodes":[{"type":"floating_con","id":5,"app_id":"foot","name":"~/notes","marks":["_spark-shell.min.tiled.5"],"nodes":[]},{"type":"floating_con","id":8,"app_id":"spark-dialog","marks":[],"nodes":[]},{"type":"floating_con","id":9,"window_properties":{"class":"firefox"},"name":"Pull requests","marks":["_spark-shell.min.RB.9"],"nodes":[]}]}]},{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","name":"1","focused":true,"rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[],"floating_nodes":[]}]}]}\n' > "$HOME/win-tree.json"; }
pad_tree; win_run restore 5
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=5] unmark _spark-shell.min.tiled.5, scratchpad show, floating disable' ] && [ "$out" = 'the window is back, tiled' ] \
    && ok "desktop window restore ID: the window named, not the last one, comes back as it left (v0.133)" || bad "window restore id" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
win_run restore 8
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: window 8 is not on the pad' ] && [ ! -e "$HOME/win.log" ] && ok "desktop window restore ID: a window the pad does not hold is refused, nothing sent (v0.133)" || bad "window restore not on pad" "rc=$rc $out"
# the places the keys give (#264): each key replaces the place and the area a window wears; the pad and the float key
# end them; refit puts every window in sight that wears a place at that place on the area as it is now, one command a
# window, and a window that left its place (tiled again, dragged, resized) loses it and stays
rf_win() { printf '{"type":"%s","id":%s,"pid":%s,"app_id":"foot","fullscreen_mode":%s,"marks":[%s],"rect":{"x":%s,"y":%s,"width":%s,"height":%s},"nodes":[]}' "$2" "$1" "$1" "$3" "$8" "$4" "$5" "$6" "$7"; }   # rf_win ID TYPE FULL X Y W H MARKS -> a window
pa() { printf '"_spark-shell.place.%s.%s","_spark-shell.area.%s.%s"' "$1" "$2" "$3" "$2"; }   # pa PLACE ID AREA -> the two a key gives, AREA X.Y.W.H
_A=1216.42.1888.1022; _A2=1276.42.1828.1022   # the area of the tests, and the same with a strip 60 pixels wide at the left
win_atm 2160 42 944 1022 "$(pa LF 7 "$_A"),\"_spark-shell.tiled.7\""; win_run down
[ "$(cat "$HOME/win.log")" = "-- [con_id=7] unmark _spark-shell.tiled.7, unmark _spark-shell.place.LF.7, unmark _spark-shell.area.$_A.7, floating enable, resize set width 944 px height 511 px, move absolute position 2160 553, mark --add _spark-shell.place.RB.7, mark --add _spark-shell.area.$_A.7" ] \
    && ok "desktop window: a key takes the place a window wore and gives it the new one, with the area it was placed on (#264)" || bad "place replaced" "$(cat "$HOME/win.log" 2>&1)"
win_atm 1216 553 1888 511 "$(pa FB 7 "$_A")"; win_run down
[ "$(cat "$HOME/win.log")" = "-- [con_id=7] unmark _spark-shell.place.FB.7, unmark _spark-shell.area.$_A.7, mark --add _spark-shell.min.FB.7, move scratchpad" ] \
    && ok "desktop window: a window minimized leaves its place behind, the pad keeps where it was (#264)" || bad "place min" "$(cat "$HOME/win.log" 2>&1)"
win_atm 1216 553 1888 511 "$(pa FB 7 "$_A")"; win_run float
[ "$(cat "$HOME/win.log")" = "-- [con_id=7] unmark _spark-shell.place.FB.7, unmark _spark-shell.area.$_A.7, floating disable, mark --add _spark-shell.yours.7" ] && [ "$out" = 'the window is tiled' ] \
    && ok "desktop window float: a window tiled again leaves its place (#264)" || bad "place float" "$(cat "$HOME/win.log" 2>&1)"
rf_tree() {   # rf_tree AX AY AW AH TILED FLOATING DP1FLOATING -> workspace 1 in sight on HDMI-A-1 at that area, workspace 2 behind it with a placed window, and DP-1's workspace 5 in sight at a strip 30 pixels high at its bottom
    printf '{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","rect":{"x":0,"y":0,"width":0,"height":0},"nodes":[],"floating_nodes":[]}]},{"type":"output","name":"HDMI-A-1","current_workspace":"1","nodes":[{"type":"workspace","id":3,"name":"1","rect":{"x":%s,"y":%s,"width":%s,"height":%s},"nodes":[%s],"floating_nodes":[%s]},{"type":"workspace","id":4,"name":"2","rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[],"floating_nodes":[%s]}]},{"type":"output","name":"DP-1","current_workspace":"5","nodes":[{"type":"workspace","id":5,"name":"5","rect":{"x":0,"y":42,"width":1200,"height":1000},"nodes":[],"floating_nodes":[%s]}]}]}\n' \
        "$1" "$2" "$3" "$4" "$5" "$6" "$(rf_win 20 floating_con 0 2160 42 944 1022 "$(pa LF 20 "$_A")")" "$7" > "$HOME/win-tree.json"
}
rf_tree 1276 42 1828 1022 "$(rf_win 10 con 0 1216 42 944 1022 "$(pa LB 10 "$_A")")" \
    "$(rf_win 7 floating_con 0 1261 42 944 1022 "$(pa LF 7 "$_A")"),$(rf_win 8 floating_con 0 2160 42 944 1022 "$(pa RF 8 "$_A")"),$(rf_win 9 floating_con 0 1600 400 944 511 "$(pa LT 9 "$_A")"),$(rf_win 11 floating_con 0 2160 553 600 511 "$(pa RB 11 "$_A")"),$(rf_win 12 floating_con 1 0 0 1920 1080 "$(pa RF 12 "$_A")"),$(rf_win 13 floating_con 0 1400 200 800 600 '')" \
    "$(rf_win 30 floating_con 0 600 42 600 1030 "$(pa RF 30 0.42.1200.1030)")"
win_run refit
_rf=$(printf '%s\n' \
    "-- [con_id=10] unmark _spark-shell.place.LB.10, unmark _spark-shell.area.$_A.10" \
    "-- [con_id=7] resize set width 914 px height 1022 px, move absolute position 1276 42, unmark _spark-shell.area.$_A.7, mark --add _spark-shell.area.$_A2.7" \
    "-- [con_id=8] resize set width 914 px height 1022 px, move absolute position 2190 42, unmark _spark-shell.area.$_A.8, mark --add _spark-shell.area.$_A2.8" \
    "-- [con_id=9] unmark _spark-shell.place.LT.9, unmark _spark-shell.area.$_A.9" \
    "-- [con_id=11] unmark _spark-shell.place.RB.11, unmark _spark-shell.area.$_A.11" \
    "-- [con_id=30] resize set width 600 px height 1000 px, move absolute position 600 42, unmark _spark-shell.area.0.42.1200.1030.30, mark --add _spark-shell.area.0.42.1200.1000.30")
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$_rf" ] && [ "$out" = '3 windows are at their places again; 3 windows that left their places stay where they are' ] && [ "$(grep -c '' "$HOME/win.trees")" = 1 ] \
    && ok "desktop window refit: a strip at the left, the halves move right of it, one command a window, on every screen in sight; one sway moved itself still counts; dragged, resized or tiled again it loses its place; full screen, free, and behind another workspace, nothing (#264)" || bad "refit" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
rf_tree 1216 42 1888 1022 '' "$(rf_win 7 floating_con 0 1276 42 914 1022 "$(pa LF 7 "$_A2")"),$(rf_win 8 floating_con 0 2190 42 910 1015 "$(pa RF 8 "$_A2")")" ''
win_run refit
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$(printf '%s\n' "-- [con_id=7] resize set width 944 px height 1022 px, move absolute position 1216 42, unmark _spark-shell.area.$_A2.7, mark --add _spark-shell.area.$_A.7" "-- [con_id=8] resize set width 944 px height 1022 px, move absolute position 2160 42, unmark _spark-shell.area.$_A2.8, mark --add _spark-shell.area.$_A.8")" ] \
    && [ "$out" = '2 windows are at their places again' ] && ok "desktop window refit: the strip gone, the halves take the room back; a terminal a few pixels short of its place is still on it (#264)" || bad "refit back" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
rf_tree 1216 42 1888 1022 '' "$(rf_win 7 floating_con 0 1216 42 944 1022 "$(pa LF 7 "$_A")"),$(rf_win 8 floating_con 0 2400 300 944 1022 "$(pa RF 8 "$_A")")" ''
win_run refit
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "-- [con_id=8] unmark _spark-shell.place.RF.8, unmark _spark-shell.area.$_A.8" ] && [ "$out" = '1 window that left its place stays where it is' ] \
    && ok "desktop window refit: the area as it was, a window at its place is left as it is and one dragged by hand loses its place (#264)" || bad "refit same" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
rf_tree 1216 42 1888 1022 '' "$(rf_win 7 floating_con 0 1208 41 944 1022 "$(pa LF 7 "$_A")"),$(rf_win 8 floating_con 0 2168 41 944 1022 "$(pa RF 8 "$_A")")" ''
win_run refit
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "$(printf '%s\n' "-- [con_id=7] resize set width 944 px height 1022 px, move absolute position 1216 42, unmark _spark-shell.area.$_A.7, mark --add _spark-shell.area.$_A.7" "-- [con_id=8] resize set width 944 px height 1022 px, move absolute position 2160 42, unmark _spark-shell.area.$_A.8, mark --add _spark-shell.area.$_A.8")" ] \
    && [ "$out" = '2 windows are at their places again' ] && ok "desktop window refit: the area as it was, two halves sway moved 8 pixels by itself as a strip came and went take their places again, neither lost (#273)" || bad "refit nudged" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
rf_tree 1216 42 1888 1022 '' "$(rf_win 7 floating_con 0 1216 42 944 1022 "$(pa LF 7 "$_A")")" ''
win_run refit
[ "$rc" = 0 ] && [ ! -e "$HOME/win.log" ] && [ "$out" = 'the windows the keys placed are at their places' ] && ok "desktop window refit: nothing to move, nothing sent (#264)" || bad "refit none to move" "rc=$rc $out"
rf_tree 1216 42 1888 1022 '' "$(rf_win 13 floating_con 0 1400 200 800 600 '')" ''
win_run refit
[ "$rc" = 0 ] && [ ! -e "$HOME/win.log" ] && [ "$out" = 'no window in sight has a place the keys gave it' ] && ok "desktop window refit: no window wears a place, said in one line (#264)" || bad "refit no place" "rc=$rc $out"
printf '{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","nodes":[],"floating_nodes":[{"type":"floating_con","id":9,"marks":["_spark-shell.min.RB.9"],"nodes":[]}]}]},{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","name":"1","focused":true,"rect":{"x":1276,"y":42,"width":1828,"height":1022},"nodes":[],"floating_nodes":[]}]}]}\n' > "$HOME/win-tree.json"
win_run restore
[ "$(cat "$HOME/win.log")" = "-- [con_id=9] unmark _spark-shell.min.RB.9, scratchpad show, floating disable, floating enable, resize set width 914 px height 511 px, move absolute position 2190 553, mark --add _spark-shell.place.RB.9, mark --add _spark-shell.area.$_A2.9" ] \
    && ok "desktop window restore: back at its place on the area as it is now, wearing it again (#264)" || bad "restore place" "$(cat "$HOME/win.log" 2>&1)"
# a new window (#262): the sway rule's mark, then one decision from one read of the tree
nw='{"type":"con","id":9,"pid":9,"app_id":"foot","fullscreen_mode":0,"marks":["_spark-shell.new"],"rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[]}'
nw_tree() { printf '{"type":"root","nodes":[{"type":"output","name":"HDMI-A-1","current_workspace":"1","nodes":[{"type":"workspace","id":3,"name":"1","rect":{"x":1216,"y":42,"width":1888,"height":1022},"nodes":[%s],"floating_nodes":[%s]}]}]}\n' "$1" "$2" > "$HOME/win-tree.json"; }   # nw_tree TILED FLOATING
_lt=$(rf_win 7 floating_con 0 1216 42 944 511 "$(pa LT 7 "$_A")"); _rt=$(rf_win 8 floating_con 0 2160 42 944 511 "$(pa RT 8 "$_A")")
_lb=$(rf_win 10 floating_con 0 1216 553 944 511 "$(pa LB 10 "$_A")"); _rb=$(rf_win 11 floating_con 0 2160 553 944 511 "$(pa RB 11 "$_A")")
nw_tree "$nw" "$_lt,$_rt"; win_run new
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = "-- [con_id=9] unmark _spark-shell.new, floating enable, resize set width 1888 px height 511 px, move absolute position 1216 553, mark --add _spark-shell.place.FB.9, mark --add _spark-shell.area.$_A.9" ] \
    && [ "$out" = 'the new window is on the bottom half' ] && ok "desktop window new: two windows the keys placed in the top quarters, the new one floats in the bottom half, wearing it (#262)" || bad "new bottom half" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
nw_tree "$nw" "$_lt,$_rt,$_lb,$_rb"; win_run new
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new, floating enable, resize set width 1258 px height 681 px, move position center' ] \
    && [ "$out" = 'the new window floats at two thirds of the screen, centered: no place is free' ] && ok "desktop window new: every place taken, the new one floats at two thirds, centered, on top (#262)" || bad "new center" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
nw_tree "$nw,$(rf_win 5 con 0 1216 42 944 1022 '')" "$_lt"; win_run new
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new' ] && [ "$out" = 'the new window tiles' ] && ok "desktop window new: a workspace with a tiled window tiles the new one (#262)" || bad "new tiled" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
nw_tree "$nw" ''; win_run new
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new' ] && [ "$out" = 'the new window tiles' ] && ok "desktop window new: alone on its workspace, it tiles (#262)" || bad "new alone" "rc=$rc $out"
nw_tree "$nw" "$(rf_win 7 floating_con 0 1216 42 944 1022 '')"; win_run new
[ "$(cat "$HOME/win.log")" = "-- [con_id=9] unmark _spark-shell.new, floating enable, resize set width 944 px height 1022 px, move absolute position 2160 42, mark --add _spark-shell.place.RF.9, mark --add _spark-shell.area.$_A.9" ] && [ "$out" = 'the new window is on the right half' ] \
    && ok "desktop window new: a window at the left half (placed before v0.134.1, by its rect), the new one takes the right half: a half first (#262)" || bad "new right half" "$out | $(cat "$HOME/win.log" 2>&1)"
nw_tree "$nw" "$_lt,$_rb"; win_run new
[ "$(cat "$HOME/win.log")" = "-- [con_id=9] unmark _spark-shell.new, floating enable, resize set width 944 px height 511 px, move absolute position 2160 42, mark --add _spark-shell.place.RT.9, mark --add _spark-shell.area.$_A.9" ] && [ "$out" = 'the new window is in the top right quarter' ] \
    && ok "desktop window new: no half free, the first quarter free in reading order (#262)" || bad "new quarter" "$out | $(cat "$HOME/win.log" 2>&1)"
nw_tree "$nw" "$(rf_win 13 floating_con 0 1400 200 800 600 '')"; win_run new
[ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new' ] && [ "$out" = 'the new window tiles' ] && ok "desktop window new: a window floating at no place is none the keys placed: the new one tiles (#262)" || bad "new free" "$out | $(cat "$HOME/win.log" 2>&1)"
nw_tree '' "$_lt,$(printf '%s' "$nw" | sed 's/"type":"con"/"type":"floating_con"/; s/"app_id":"foot"/"app_id":"spark-dialog"/')"; win_run new
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new' ] && [ "$out" = 'the new window stays as it opened' ] && ok "desktop window new: the dialog, floated by its own rule, stays as it opened (#262)" || bad "new dialog" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
nw_tree "$(printf '%s' "$nw" | sed 's/"fullscreen_mode":0/"fullscreen_mode":1/')" "$_lt"; win_run new
[ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new' ] && [ "$out" = 'the new window stays as it opened' ] && ok "desktop window new: a full screen window stays as it opened (#262)" || bad "new full" "$out"
nw_tree "$(printf '%s' "$nw" | sed 's/"_spark-shell.new"/"_spark-shell.new","_spark-shell.yours.9"/')" "$_lt"; win_run new
[ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.new' ] && [ "$out" = 'the new window stays as it opened' ] && ok "desktop window new: a window the float key tiled is the person's choice and stays (#262)" || bad "new yours" "$out"
nw_tree "$(rf_win 5 con 0 1216 42 944 1022 '')" "$_lt"; win_run new
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: no window opened just now' ] && [ ! -e "$HOME/win.log" ] && ok "desktop window new: no window wears the rule's mark, refused in one line, nothing sent (#262)" || bad "new none" "rc=$rc $out"
# the pad (v0.133): spark-winpad's stand-in records how it was started and the signals it takes, holds its lock as the
# real one does, and turns hidden on SIGUSR2
mkdir -p "$H/padbin" "$H/run"
cat > "$H/padbin/spark-winpad" <<'WINPAD_STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/pad.log"
env | grep -E '^(SPARK_SHELL|WINPAD_[A-Z_]+)=' | sort > "$HOME/winpad.env"
trap 'echo usr1 >> "$HOME/pad.sig"' USR1
trap 'echo usr2 >> "$HOME/pad.sig"; if grep -qx "hidden 1" "$WINPAD_STATE"; then printf "hidden 0\n" > "$WINPAD_STATE"; else printf "hidden 1\n" > "$WINPAD_STATE"; fi' USR2
trap 'rm -f "$WINPAD_LOCK"; exit 0' TERM
printf 'hidden 0\ncount 2\n' > "$WINPAD_STATE"
echo $$ > "$WINPAD_LOCK"   # last, as the real pad takes its lock once its signals are set
while :; do sleep 0.1; done
WINPAD_STUB
chmod +x "$H/padbin/spark-winpad"
padr() { rm -f "$HOME/win.log"; rc=0; out=$(XDG_RUNTIME_DIR=$H/run SPARK_SHELL_WINPAD=$H/padbin/spark-winpad SWAYSOCK=$H/sock PATH="$H/win:$H/lx:$PATH" sh "$SH" desktop pad "$@" 2>&1) || rc=$?; }
pad_up() { _pu=0; while [ "$_pu" -lt 40 ] && [ ! -s "$H/run/spark-shell-winpad.pid" ]; do sleep 0.1; _pu=$((_pu + 1)); done; }
pad_sig() { _ps=0; while [ "$_ps" -lt 20 ]; do _pc=$(grep -c "^$1$" "$HOME/pad.sig" 2>/dev/null) || :; [ "${_pc:-0}" -lt "$2" ] || break; sleep 0.1; _ps=$((_ps + 1)); done; }   # the stand-in takes a signal after its sleep: wait for it, 2 s at most
pad_hidden_is() { _ph=0; while [ "$_ph" -lt 50 ]; do grep -qx "hidden $1" "$H/run/spark-shell-winpad.state" 2>/dev/null && return 0; sleep 0.1; _ph=$((_ph + 1)); done; return 1; }   # the stand-in writes its state after it logs the signal: wait for the state, 5 s at most
pad_down() { [ ! -s "$H/run/spark-shell-winpad.pid" ] || kill "$(cat "$H/run/spark-shell-winpad.pid")" 2>/dev/null || :; _pd=0; while [ "$_pd" -lt 20 ] && [ -e "$H/run/spark-shell-winpad.pid" ]; do sleep 0.1; _pd=$((_pd + 1)); done; rm -f "$H/run/spark-shell-winpad.pid" "$H/run/spark-shell-winpad.state" "$HOME/pad.log" "$HOME/pad.sig" "$HOME/winpad.env"; }
win_at 2160 42 944 1022; padr
[ "$rc" = 0 ] && [ "$out" = 'no window is on the pad' ] && ok "desktop pad: none waits, said in one line (v0.133)" || bad "pad none" "rc=$rc $out"
padr keys
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: no window is on the pad' ] && [ ! -e "$HOME/pad.log" ] && ok "desktop pad keys: nothing on the pad, refused, no pad started (v0.133)" || bad "pad keys none" "rc=$rc $out"
pad_tree; padr
[ "$rc" = 0 ] && [ "$out" = 'the pad has 2 windows: foot, firefox' ] && ok "desktop pad: the windows on the pad by their apps, oldest first; a scratchpad window not put there is none of them (v0.133)" || bad "pad list" "rc=$rc $out"
padr keys; pad_up
_pe=$(cat "$HOME/winpad.env" 2>/dev/null)
[ "$rc" = 0 ] && [ "$out" = 'the pad has the keys: Enter brings the window back, Esc leaves' ] && [ "$(cat "$HOME/pad.log" 2>/dev/null)" = '--keys' ] \
    && printf '%s\n' "$_pe" | grep -qx "SPARK_SHELL=$SH" && printf '%s\n' "$_pe" | grep -qx 'WINPAD_PLACE=bottom center' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_WIDTH=0' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_SIDE_WIDTH=36' \
    && printf '%s\n' "$_pe" | grep -qx 'WINPAD_BAR=top' && printf '%s\n' "$_pe" | grep -qx "WINPAD_LOCK=$H/run/spark-shell-winpad.pid" && printf '%s\n' "$_pe" | grep -qx "WINPAD_STATE=$H/run/spark-shell-winpad.state" \
    && printf '%s\n' "$_pe" | grep -qx 'WINPAD_ACCENT=ff5555' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_FG=aaaaaa' && [ "$(printf '%s\n' "$_pe" | grep -cE '^WINPAD_(SURFACE|LIT|BAND_HEX|MUTED)=[0-9a-f]{6}$')" = 4 ] \
    && printf '%s\n' "$_pe" | grep -qx 'WINPAD_BAND=off' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_GAP=8' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_VIEW=icons' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_HEIGHT=0' \
    && printf '%s\n' "$_pe" | grep -qE '^WINPAD_FONT=.+ [0-9]+(px)?$' && printf '%s\n' "$_pe" | grep -qE '^WINPAD_ALPHA=[0-9.]+$' && printf '%s\n' "$_pe" | grep -q '^WINPAD_BAR_PID=' \
    && ok "desktop pad keys (Super+minus): no pad running, spark-winpad starts with --keys, the look, the place, the bar's place and its files in its environment (v0.133); the band's setting, its color apart, and the outer gap as its margin (#265, #266); the view, icons by default, and the height, 0 by default (#269)" || bad "pad keys start" "rc=$rc $out $(cat "$HOME/pad.log" 2>&1) | $_pe"
padr keys; pad_sig usr1 1
[ "$rc" = 0 ] && [ "$(grep -c '' "$HOME/pad.log")" = 1 ] && [ "$(grep -c '^usr1$' "$HOME/pad.sig" 2>/dev/null)" = 1 ] && ok "desktop pad keys: a pad running takes SIGUSR1, none other starts (v0.133)" || bad "pad keys signal" "rc=$rc $out $(cat "$HOME/pad.log" "$HOME/pad.sig" 2>&1)"
_pdl() { XDG_RUNTIME_DIR=$H/run SPARK_SHELL_WINPAD=$H/padbin/spark-winpad SWAYSOCK=$H/sock PATH="$H/win:$H/lx:$PATH" sh "$SH" bar status --once 2>/dev/null; }
padsign=$(printf '\342\212\237')
line=$(_pdl)
[ "$(printf '%s' "$line" | jq -r '.[0].name')" = pad ] && [ "$(printf '%s' "$line" | jq -r '.[0].full_text')" = "<span foreground='#555555'>$padsign</span> 2" ] \
    && ok "bar: the pad's block first while windows wait on it, its sign muted while the pad is in sight, and how many (v0.133)" || bad "bar pad shown" "$line"
padr toggle; pad_sig usr2 1
[ "$rc" = 0 ] && [ "$out" = 'the pad is hidden' ] && pad_hidden_is 1 && ok "desktop pad toggle (the bar's click): the pad takes SIGUSR2 and hides (v0.133)" || bad "pad toggle hide" "rc=$rc $out $(cat "$H/run/spark-shell-winpad.state" 2>&1)"
line=$(_pdl)
[ "$(printf '%s' "$line" | jq -r '.[0].full_text')" = "<span foreground='#ff5555'>$padsign</span> 2" ] && ok "bar: the pad's sign in the accent while the pad is hidden (v0.133)" || bad "bar pad hidden" "$line"
padr toggle; pad_sig usr2 2
[ "$rc" = 0 ] && [ "$out" = 'the pad is back in sight' ] && pad_hidden_is 0 && ok "desktop pad toggle: a hidden pad comes back in sight (v0.133)" || bad "pad toggle show" "rc=$rc $out"
pad_down
line=$(_pdl)
[ "$(printf '%s' "$line" | jq -r '.[0].full_text')" = "<span foreground='#ff5555'>$padsign</span> 2" ] && ok "bar: windows on the pad and no pad running: the sign in the accent (v0.133)" || bad "bar pad none running" "$line"
padr toggle; pad_up
[ "$rc" = 0 ] && [ "$out" = 'the pad is back in sight' ] && [ "$(cat "$HOME/pad.log" 2>/dev/null)" = '' ] && [ -s "$H/run/spark-shell-winpad.pid" ] && ok "desktop pad toggle: no pad running, one starts, in sight (v0.133)" || bad "pad toggle start" "rc=$rc $out $(cat "$HOME/pad.log" 2>&1)"
pad_down
win_at 2160 42 944 1022
line=$(_pdl)
[ "$(printf '%s' "$line" | jq -r '[.[] | select(.name == "pad")] | length')" = 0 ] && ok "bar: no window on the pad, no block for it (v0.133)" || bad "bar pad gone" "$line"
pad_tree; rm -f "$HOME/win.log"; rc=0; out=$(XDG_RUNTIME_DIR=$H/run env -u SPARK_SHELL_WINPAD SWAYSOCK=$H/sock PATH="$H/win:$H/lx:$PATH" sh "$SH" desktop pad keys 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$(cat "$HOME/win.log")" = '-- [con_id=9] unmark _spark-shell.min.RB.9, scratchpad show, floating disable, floating enable, resize set width 944 px height 511 px, move absolute position 2160 553, mark --add _spark-shell.place.RB.9, mark --add _spark-shell.area.1216.42.1888.1022.9' ] && [ "$out" = 'the window is back, in the bottom right quarter' ] \
    && ok "desktop pad keys: no spark-winpad here, Super+minus brings back the window minimized last, as before the pad (v0.133)" || bad "pad keys fallback" "rc=$rc $out $(cat "$HOME/win.log" 2>&1)"
# the window keys put a window on the pad: the pad starts, never waited for
win_at 2160 553 944 511; rm -f "$HOME/win.log"; rc=0; out=$(XDG_RUNTIME_DIR=$H/run SPARK_SHELL_WINPAD=$H/padbin/spark-winpad SWAYSOCK=$H/sock PATH="$H/win:$H/lx:$PATH" sh "$SH" desktop window down 2>&1) || rc=$?; pad_up
[ "$rc" = 0 ] && [ -s "$H/run/spark-shell-winpad.pid" ] && [ "$(cat "$HOME/pad.log" 2>/dev/null)" = '' ] && ok "desktop window: a window put on the pad starts the pad, in sight (v0.133)" || bad "pad wake" "rc=$rc $out $(cat "$HOME/pad.log" 2>&1)"
pad_down
# where it sits: the keys the pad writes after a drag, each checked; a pad of v0.134.1 sends three, one of v0.134.2 the height too (#269)
cfg=$HOME/.config/spark-shell/config; cp "$cfg" "$H/cfg.pad"
padr place 'left center' 0 72
[ "$rc" = 0 ] && [ "$out" = 'the pad sits at the left edge, in the middle' ] && grep -qx 'WINPAD_PLACE=left center' "$cfg" && grep -qx 'WINPAD_WIDTH=0' "$cfg" && grep -qx 'WINPAD_SIDE_WIDTH=72' "$cfg" && ! grep -q '^WINPAD_HEIGHT=' "$cfg" \
    && ok "desktop pad place: an edge and where along it, the widths, in the config (v0.133); three words, as a pad of v0.134.1 sends them, write no height (#269)" || bad "pad place" "rc=$rc $out $(grep WINPAD_ "$cfg")"
padr place 'bottom start' 480 36 76
[ "$rc" = 0 ] && [ "$out" = 'the pad sits at the bottom edge, at its left end' ] && grep -qx 'WINPAD_PLACE=bottom start' "$cfg" && grep -qx 'WINPAD_WIDTH=480' "$cfg" && grep -qx 'WINPAD_SIDE_WIDTH=36' "$cfg" && grep -qx 'WINPAD_HEIGHT=76' "$cfg" \
    && ok "desktop pad place: the height fourth, in the config as WINPAD_HEIGHT, the place and the widths with it (#269)" || bad "pad place height" "rc=$rc $out $(grep WINPAD_ "$cfg")"
padr place 'top center' 0 36
[ "$rc" = 0 ] && [ "$out" = 'the pad sits at the top edge, in the middle' ] && grep -qx 'WINPAD_PLACE=top center' "$cfg" && grep -qx 'WINPAD_HEIGHT=76' "$cfg" \
    && ok "desktop pad place: three words after a height leave the height as it was (#269)" || bad "pad place height kept" "rc=$rc $out $(grep WINPAD_ "$cfg")"
padr place 'bottom center' 0 36 tall
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: pad place: the height is pixels, 0 to 9999 (0: as many rows as needed)' ] && grep -qx 'WINPAD_PLACE=top center' "$cfg" && grep -qx 'WINPAD_HEIGHT=76' "$cfg" \
    && ok "desktop pad place: a height that is not whole pixels is refused, the config as it was (#269)" || bad "pad place height bad" "rc=$rc $out $(grep WINPAD_ "$cfg")"
padr place 'bottom center' 0 36 0 9
_pp1=$rc$out; padr place 'bottom center' 0
[ "$_pp1" = '1spark-shell desktop: pad place takes PLACE WIDTH SIDE [HEIGHT]: "bottom center" 0 36 0' ] && [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: pad place takes PLACE WIDTH SIDE [HEIGHT]: "bottom center" 0 36 0' ] && grep -qx 'WINPAD_PLACE=top center' "$cfg" \
    && ok "desktop pad place: five words or two are refused in one line, the config as it was (#269)" || bad "pad place count" "$_pp1 | rc=$rc $out"
padr place 'free 300 200' 600 36
[ "$rc" = 0 ] && [ "$out" = 'the pad sits where you left it' ] && grep -qx 'WINPAD_PLACE=free 300 200' "$cfg" && grep -qx 'WINPAD_WIDTH=600' "$cfg" && ok "desktop pad place: free, where it was left (v0.133)" || bad "pad place free" "rc=$rc $out"
padr place middle 0 36
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: pad place: top, bottom, left or right and center, start, end or pixels along that edge, or free X Y' ] && grep -qx 'WINPAD_PLACE=free 300 200' "$cfg" \
    && ok "desktop pad place: a place it cannot be is refused, the config as it was (v0.133)" || bad "pad place bad" "rc=$rc $out"
padr place 'bottom end' 0 20
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: pad place: the width at a side is pixels, 36 to 9999' ] && ok "desktop pad place: a side narrower than one icon is refused (v0.133)" || bad "pad place side" "rc=$rc $out"
printf 'WINPAD_PLACE=sideways\n' >> "$cfg"; padr
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'WINPAD_PLACE=sideways in .*: top, bottom, left or right' && ok "config: WINPAD_PLACE out of its shapes refused in one line (v0.133)" || bad "pad config" "rc=$rc $out"
cp "$H/cfg.pad" "$cfg"
# the pad's settings as a config from v0.142 or before names them: read as they are until on writes the new names (v0.143)
pad_down; printf 'PAD_PLACE=left center\nPAD_SIDE_WIDTH=72\nPAD_VIEW=titles\n' >> "$cfg"; pad_tree; padr keys; pad_up
_pe=$(cat "$HOME/winpad.env" 2>/dev/null)
printf '%s\n' "$_pe" | grep -qx 'WINPAD_PLACE=left center' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_SIDE_WIDTH=72' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_VIEW=titles' \
    && ok "config: the pad's settings under their names through v0.142 (PAD_PLACE, PAD_SIDE_WIDTH, PAD_VIEW) are read as they are (v0.143)" || bad "pad old names" "rc=$rc $out $_pe"
pad_down; cp "$H/cfg.pad" "$cfg"
# the pad's band (#266): off by default, a switch of its own in the config; a running pad starts again to take it
padr band
[ "$rc" = 0 ] && [ "$out" = "pad band off $dot the handle alone across its top" ] && ok "desktop pad band: off by default, the handle alone, said in one line (#266, #269)" || bad "pad band bare" "rc=$rc $out"
padr band on
[ "$rc" = 0 ] && [ "$out" = "pad band on $dot the band under its handle says pad and how many wait" ] && grep -qx 'WINPAD_BAND=on' "$cfg" && ok "desktop pad band on: in the config, with its receipt (#266)" || bad "pad band on" "rc=$rc $out $(grep WINPAD_ "$cfg")"
padr band on
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: the pad's band is on already" ] && ok "desktop pad band on: on already, refused in one line (#266)" || bad "pad band again" "rc=$rc $out"
padr band maybe
[ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: pad band takes on or off' ] && grep -qx 'WINPAD_BAND=on' "$cfg" && ok "desktop pad band: a word that is neither refused, the config as it was (#266)" || bad "pad band word" "rc=$rc $out"
pad_tree; padr keys; pad_up
_pi=0; while [ "$_pi" -lt 20 ] && ! grep -qx 'WINPAD_BAND=on' "$HOME/winpad.env" 2>/dev/null; do sleep 0.1; _pi=$((_pi + 1)); done
padr band off
_pi=0; while [ "$_pi" -lt 40 ] && [ "$(grep -c '' "$HOME/pad.log" 2>/dev/null)" -lt 2 ]; do sleep 0.1; _pi=$((_pi + 1)); done
_pi=0; while [ "$_pi" -lt 20 ] && ! grep -qx 'WINPAD_BAND=off' "$HOME/winpad.env" 2>/dev/null; do sleep 0.1; _pi=$((_pi + 1)); done
[ "$rc" = 0 ] && [ "$out" = "pad band off $dot the handle alone across its top" ] && grep -qx 'WINPAD_BAND=off' "$cfg" && [ "$(grep -c '' "$HOME/pad.log")" = 2 ] && grep -qx 'WINPAD_BAND=off' "$HOME/winpad.env" && grep -qE '^WINPAD_BAND_HEX=[0-9a-f]{6}$' "$HOME/winpad.env" \
    && ok "desktop pad band off: a running pad starts again without its band, its color still handed apart (#266)" || bad "pad band again pad" "rc=$rc $out $(cat "$HOME/pad.log" "$HOME/winpad.env" 2>&1)"
pad_down
printf 'WINPAD_BAND=maybe\n' >> "$cfg"; padr band
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'WINPAD_BAND=maybe in .*: on or off' && ok "config: WINPAD_BAND other than on or off refused in one line (#266)" || bad "pad band config" "rc=$rc $out"
sed -i.bak '/^WINPAD_BAND=/d' "$cfg"; rm -f "$cfg.bak"
rm -f "$HOME/win.log"; rc=0; out=$(WINPAD_BAND=c3d0ee XDG_RUNTIME_DIR=$H/run SWAYSOCK=$H/sock PATH="$H/win:$H/lx:$PATH" sh "$SH" desktop pad band 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = "pad band off $dot the handle alone across its top" ] && ok "config: a band's color a pad of v0.134 hands down as WINPAD_BAND, in no config file, leaves the default (#266)" || bad "pad band old pad env" "rc=$rc $out"
# the pad's view (#269): icons by default, titles a switch of its own in the config; a running pad starts again to take it
padr view
[ "$rc" = 0 ] && [ "$out" = "pad view icons $dot one icon a window, its title beside it on hover" ] && ! grep -q '^WINPAD_VIEW=' "$cfg" && ok "desktop pad view: icons by default, said in one line, nothing written (#269)" || bad "pad view bare" "rc=$rc $out"
padr view titles
[ "$rc" = 0 ] && [ "$out" = "pad view titles $dot a slot a window, its icon, its app and its title" ] && grep -qx 'WINPAD_VIEW=titles' "$cfg" && ok "desktop pad view titles: in the config, with its receipt (#269)" || bad "pad view titles" "rc=$rc $out $(grep WINPAD_ "$cfg")"
padr view
[ "$rc" = 0 ] && [ "$out" = "pad view titles $dot a slot a window, its icon, its app and its title" ] && ok "desktop pad view: the view the config holds, said in one line (#269)" || bad "pad view bare titles" "rc=$rc $out"
padr view titles
[ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: the pad's view is titles already" ] && ok "desktop pad view titles: titles already, refused in one line (#269)" || bad "pad view again" "rc=$rc $out"
padr view grid
_pv1=$rc$out; padr view icons titles
[ "$_pv1" = '1spark-shell desktop: pad view takes icons or titles' ] && [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: pad view takes icons or titles' ] && grep -qx 'WINPAD_VIEW=titles' "$cfg" \
    && ok "desktop pad view: another word, or two, refused in one line, the config as it was (#269)" || bad "pad view word" "$_pv1 | rc=$rc $out"
padr place 'bottom center' 0 36 76
pad_tree; padr keys; pad_up
_pi=0; while [ "$_pi" -lt 20 ] && ! grep -qx 'WINPAD_VIEW=titles' "$HOME/winpad.env" 2>/dev/null; do sleep 0.1; _pi=$((_pi + 1)); done
_pe=$(cat "$HOME/winpad.env" 2>/dev/null)
padr view icons
_pi=0; while [ "$_pi" -lt 40 ] && [ "$(grep -c '' "$HOME/pad.log" 2>/dev/null)" -lt 2 ]; do sleep 0.1; _pi=$((_pi + 1)); done
_pi=0; while [ "$_pi" -lt 20 ] && ! grep -qx 'WINPAD_VIEW=icons' "$HOME/winpad.env" 2>/dev/null; do sleep 0.1; _pi=$((_pi + 1)); done
[ "$rc" = 0 ] && [ "$out" = "pad view icons $dot one icon a window, its title beside it on hover" ] && grep -qx 'WINPAD_VIEW=icons' "$cfg" && printf '%s\n' "$_pe" | grep -qx 'WINPAD_VIEW=titles' && printf '%s\n' "$_pe" | grep -qx 'WINPAD_HEIGHT=76' \
    && [ "$(grep -c '' "$HOME/pad.log")" = 2 ] && grep -qx 'WINPAD_VIEW=icons' "$HOME/winpad.env" && grep -qx 'WINPAD_HEIGHT=76' "$HOME/winpad.env" && grep -qx 'WINPAD_BAND=off' "$HOME/winpad.env" && grep -qE '^WINPAD_BAND_HEX=[0-9a-f]{6}$' "$HOME/winpad.env" && grep -qx 'WINPAD_GAP=8' "$HOME/winpad.env" \
    && ok "desktop pad view icons: a running pad in titles, its height in its environment, starts again in icons, the band and the gap as they were (#269)" || bad "pad view again pad" "rc=$rc $out $(cat "$HOME/pad.log" "$HOME/winpad.env" 2>&1) | $_pe"
pad_down
for _pk in WINPAD_VIEW=grid WINPAD_VIEW=Icons 'WINPAD_VIEW=icons titles'; do
    printf '%s\n' "$_pk" >> "$cfg"; padr view
    [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qF "${_pk} in " && printf '%s\n' "$out" | grep -q ': icons or titles$' || bad "pad view config $_pk" "rc=$rc $out"
    sed -i.bak '$d' "$cfg"; rm -f "$cfg.bak"
done
ok "config: WINPAD_VIEW other than icons or titles refused in one line (#269)"
for _pk in WINPAD_HEIGHT=-1 WINPAD_HEIGHT=76px WINPAD_HEIGHT=076 WINPAD_HEIGHT=10000 'WINPAD_HEIGHT=7 6'; do
    printf '%s\n' "$_pk" >> "$cfg"; padr view
    [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qF "${_pk} in " && printf '%s\n' "$out" | grep -qF ': pixels, 0 to 9999 (0: as many rows as needed)' || bad "pad height config $_pk" "rc=$rc $out"
    sed -i.bak '$d' "$cfg"; rm -f "$cfg.bak"
done
ok "config: WINPAD_HEIGHT other than whole pixels, 0 to 9999, refused in one line (#269)"
for _pk in WINPAD_HEIGHT=0 WINPAD_HEIGHT=9999; do
    printf '%s\n' "$_pk" >> "$cfg"; padr view
    [ "$rc" = 0 ] || bad "pad height config $_pk taken" "rc=$rc $out"
    sed -i.bak '$d' "$cfg"; rm -f "$cfg.bak"
done
ok "config: WINPAD_HEIGHT 0, as many rows as needed, and 9999 taken (#269)"
# voice (v0.144): the ear's words into the terminal's line, a stand-in engine speaking the contract; the
# compositor types (wtype), the terminal says whether its shell is at the prompt (a fixture /proc)
mkdir -p "$H/vx" "$H/proc/4242"
cat > "$H/vx/ear-stub" <<'EAR_STUB'
#!/bin/sh
echo 'level 2'; echo 'type hey'; echo 'level 5'; echo 'type  can'; echo 'erase 3'; echo 'type cat'; echo 'level 1'
[ -z "${EAR_STUB_WAIT:-}" ] || cat > /dev/null   # held open: the leash's end ends it
echo 'level 0'
EAR_STUB
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$HOME/wtype.log"\n' > "$H/vx/wtype"
printf '#!/bin/sh\n[ "$1" = -P ] && echo 4242\n' > "$H/vx/pgrep"
printf '#!/bin/sh\nprintf "%%s|" "$@" >> "$HOME/notify.log"; echo >> "$HOME/notify.log"\n' > "$H/vx/notify-send"
printf '#!/bin/sh\necho "home $*" >> "$HOME/home.log"\n' > "$H/vx/python3"
chmod +x "$H/vx/ear-stub" "$H/vx/wtype" "$H/vx/pgrep" "$H/vx/notify-send" "$H/vx/python3"
printf '4242 (bash) S 4000 4242 4242 34816 4242 4194560 0 0\n' > "$H/proc/4242/stat"   # pgrp 4242 = tpgid 4242: the shell is at its prompt
[ ! -f "$HOME/win-tree.json" ] || cp "$HOME/win-tree.json" "$H/tree.voice"   # the tree the tests around share, put back at the end
voice_tree() { printf '{"type":"root","nodes":[{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","id":3,"num":1,"nodes":[{"type":"con","id":7,"app_id":"%s","pid":4000,"focused":true,"nodes":[]}],"floating_nodes":[]}]}]}' "$1" > "$HOME/win-tree.json"; }
vrun() { rc=0; out=$(XDG_RUNTIME_DIR=$H/run SPARK_SHELL_PROC=$H/proc WAYLAND_DISPLAY=wayland-9 SWAYSOCK=$H/sock PATH="$H/vx:$H/win:$H/lx:$PATH" sh "$SH" desktop voice "$@" 2>&1) || rc=$?; }
vclean() { rm -f "$HOME/wtype.log" "$HOME/notify.log" "$HOME/home.log" "$H/run/spark-shell-voice/want" "$H/run/spark-shell-voice.state"; }
vstate=$H/run/spark-shell-voice.state
cp "$cfg" "$H/cfg.voice"
vclean; vrun status
[ "$rc" = 0 ] && [ "$out" = 'voice: nothing can hear here (spark-shell on desktop)' ] && ok "desktop voice status: nothing hears here, said in one line (v0.144)" || bad "voice status none" "rc=$rc $out"
printf 'VOICE_ENGINE=%s\n' "$H/vx/ear-stub" >> "$cfg"
vrun status
[ "$rc" = 0 ] && [ "$out" = 'voice: ready (hold Super+Space, or click the mic on a terminal)' ] && ok "desktop voice status: your engine named, ready (v0.144)" || bad "voice status ready" "rc=$rc $out"
voice_tree firefox; vclean; vrun --listen now
[ "$rc" = 0 ] && grep -q 'Voice: focus a terminal at its prompt' "$HOME/notify.log" && [ ! -e "$HOME/wtype.log" ] && [ ! -e "$H/run/spark-shell-voice/want" ] \
    && ok "desktop voice: the focus on another window, nothing typed, one notification (v0.144)" || bad "voice not terminal" "rc=$rc $out $(cat "$HOME/notify.log" 2>&1)"
printf '4242 (bash) S 4000 4242 4242 34816 4300 4194560 0 0\n' > "$H/proc/4242/stat"   # a program in front of the shell
voice_tree foot; vclean; vrun --listen now
[ "$rc" = 0 ] && grep -q 'Voice: focus a terminal at its prompt' "$HOME/notify.log" && [ ! -e "$HOME/wtype.log" ] \
    && ok "desktop voice: a terminal with a program running, nothing typed (v0.144)" || bad "voice not at prompt" "rc=$rc $out $(cat "$HOME/notify.log" 2>&1)"
printf '4242 (sleep) S 4000 4242 4242 34816 4242 4194560 0 0\n' > "$H/proc/4242/stat"   # a program the terminal runs itself, no shell
voice_tree foot; vclean; vrun --listen now
[ "$rc" = 0 ] && grep -q 'Voice: focus a terminal at its prompt' "$HOME/notify.log" && [ ! -e "$HOME/wtype.log" ] \
    && ok "desktop voice: a terminal running a program of its own, no shell, nothing typed (v0.144)" || bad "voice no shell" "rc=$rc $out $(cat "$HOME/notify.log" 2>&1)"
printf '4242 (bash) S 4000 4242 4242 34816 4242 4194560 0 0\n' > "$H/proc/4242/stat"
vclean; vrun --listen now
[ "$rc" = 0 ] && [ "$(cat "$HOME/wtype.log")" = "$(printf -- '-s 20 -- hey\n-s 20 --  can\n-s 20 -k BackSpace -k BackSpace -k BackSpace\n-s 20 -- cat')" ] && grep -qx 'listening 0' "$vstate" && [ ! -e "$HOME/notify.log" ] && [ ! -e "$H/run/spark-shell-voice/pid" ] \
    && ok "desktop voice: the engine's words typed into the terminal's line as they come, an erase as backspaces; at rest after (v0.144)" || bad "voice typed" "rc=$rc $out $(cat "$HOME/wtype.log" "$vstate" 2>&1)"
vclean; vrun --listen hold
[ "$rc" = 0 ] && [ ! -e "$HOME/wtype.log" ] && [ ! -e "$HOME/notify.log" ] && ok "desktop voice: a tap, the key up within 0.3 s, hears nothing (v0.144)" || bad "voice tap" "rc=$rc $out"
vclean; vrun press; vrun release; sleep 0.5
[ "$rc" = 0 ] && grep -q '^home ' "$HOME/home.log" && [ ! -e "$HOME/wtype.log" ] && ok "desktop voice press then release at once: home opens, as Super+Space did (v0.144)" || bad "voice press tap" "rc=$rc $out $(cat "$HOME/home.log" 2>&1)"
vclean; vrun press; sleep 0.7; vrun release; sleep 0.5
[ "$rc" = 0 ] && [ ! -e "$HOME/home.log" ] && grep -qx -- '-s 20 -- hey' "$HOME/wtype.log" && ok "desktop voice press held past 0.3 s: it listens, the release ends it, no home (v0.144)" || bad "voice press hold" "rc=$rc $out $(cat "$HOME/wtype.log" "$HOME/home.log" 2>&1)"
# an engine that holds its leash: the mic stays open until it is clicked again
cat > "$H/vx/ear-hold" <<'EAR_HOLD'
#!/bin/sh
echo 'level 2'; echo 'type hey'; echo 'level 1'
cat > /dev/null   # the leash's end ends it
EAR_HOLD
chmod +x "$H/vx/ear-hold"
sed -i.bak '/^VOICE_ENGINE=/d' "$cfg"; rm -f "$cfg.bak"; printf 'VOICE_ENGINE=%s\n' "$H/vx/ear-hold" >> "$cfg"
vclean; vrun toggle; _vt1=$out; sleep 0.6
_vt2=$(tr '\n' ' ' < "$vstate" 2>/dev/null); _vt3=$(cat "$H/run/spark-shell-voice/pid" 2>/dev/null)
kill -0 "${_vt3:-0}" 2>/dev/null && _vt5=alive || _vt5=gone
vrun toggle; _vt4=$out; sleep 0.8
kill -0 "${_vt3:-0}" 2>/dev/null && _vt6=alive || _vt6=gone
[ "$_vt1" = 'voice: listening' ] && [ "$_vt2" = 'listening 1 level 1 ' ] && [ "$_vt5" = alive ] && [ "$_vt4" = 'voice: off' ] && [ "$_vt6" = gone ] \
    && grep -qx 'listening 0' "$vstate" && [ "$(sed -n 1p "$HOME/wtype.log")" = '-s 20 -- hey' ] \
    && ok "desktop voice toggle (the mic clicked): it listens, the state carries the level for the band; clicked again, it stops (v0.144)" \
    || bad "voice toggle" "$_vt1 | $_vt2 | $_vt3 $_vt5 | $_vt4 $_vt6 | $(cat "$HOME/wtype.log" 2>&1)"
sed -i.bak '/^VOICE_ENGINE=/d' "$cfg"; rm -f "$cfg.bak"; printf 'VOICE_ENGINE=%s\n' "$H/vx/ear-stub" >> "$cfg"
printf 'VOICE=maybe\n' >> "$cfg"; vrun status
[ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'VOICE=maybe in .*: yes or no' && ok "config: VOICE other than yes or no refused in one line (v0.144)" || bad "voice config" "rc=$rc $out"
cp "$H/cfg.voice" "$cfg"; vclean
rm -rf "$H/vx" "$H/proc/4242"
[ ! -f "$H/tree.voice" ] || cp "$H/tree.voice" "$HOME/win-tree.json"
# a change of the area under a real sway (its socket): the bar's text, the bar moved, a screen; refit soon after
_rsk=$H/rs.sock; "$py3" -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$_rsk" 2>/dev/null || :
if [ -S "$_rsk" ]; then
    rf_tree 1276 42 1828 1022 '' "$(rf_win 7 floating_con 0 1216 42 944 1022 "$(pa LF 7 "$_A")")" ''
    _rfl="-- [con_id=7] resize set width 914 px height 1022 px, move absolute position 1276 42, unmark _spark-shell.area.$_A.7, mark --add _spark-shell.area.$_A2.7"
    rm -f "$HOME/win.log"; rc=0; out=$(XDG_RUNTIME_DIR=$H/run SWAYSOCK=$_rsk PATH="$H/win:$H/lx:$PATH" sh "$SH" bar text 14 2>&1) || rc=$?
    _pi=0; while [ "$_pi" -lt 40 ] && ! grep -qxF -- "$_rfl" "$HOME/win.log" 2>/dev/null; do sleep 0.1; _pi=$((_pi + 1)); done
    [ "$rc" = 0 ] && grep -qxF -- "$_rfl" "$HOME/win.log" && ok "bar text: the bar's new height, then a refit of the windows the keys placed (#264)" || bad "bar text refit" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
    sleep 2   # the second refit of the first, before the next
    rm -f "$HOME/win.log"; rc=0; out=$(XDG_RUNTIME_DIR=$H/run SWAYSOCK=$_rsk PATH="$H/win:$H/lx:$PATH" sh "$SH" bar bottom 2>&1) || rc=$?
    _pi=0; while [ "$_pi" -lt 40 ] && ! grep -qxF -- "$_rfl" "$HOME/win.log" 2>/dev/null; do sleep 0.1; _pi=$((_pi + 1)); done
    [ "$rc" = 0 ] && grep -qx 'reload' "$HOME/win.log" && grep -qx 'gaps outer all set 8' "$HOME/win.log" && grep -qx '\[tiling\] border normal 1' "$HOME/win.log" && grep -qxF -- "$_rfl" "$HOME/win.log" \
        && ok "bar bottom: sway reloaded, the open workspaces take the gaps of 8 and the title band at once (#265), then a refit of the windows the keys placed (#264)" || bad "bar bottom refit" "rc=$rc $out | $(cat "$HOME/win.log" 2>&1)"
    sleep 2
    sh "$SH" bar top >/dev/null 2>&1 || :
else
    ok "bar text, bar bottom: no unix socket can be made here, the refit after them is proven in test/window_desktop_proof.py"
fi
cp "$H/cfg.pad" "$cfg"
# the moving wallpaper (#180, #187): a drawing's loop made in the background from its frames, played by spark-wallpaper on
# every screen; a second start finds it playing; off stops it; on again plays the loop from the cache, made once
mkdir -p "$H/mo" "$H/motmp" "$H/run"
cat > "$H/mo/swaymsg" <<'MO_SWAY'
#!/bin/sh
case "$*" in
    "-t get_version") echo "{}" ;;
    "-t get_outputs") echo '[{"name":"DP-3","active":true,"scale":1,"rect":{"x":0,"y":0,"width":1200,"height":1920}},{"name":"HDMI-A-1","active":true,"scale":1,"rect":{"x":1200,"y":0,"width":1920,"height":1080}}]' ;;
    *) echo "$*" >> "$HOME/mosway.log" ;;
esac
MO_SWAY
cat > "$H/mo/python3" <<'MO_PY'
#!/bin/sh
case "$*" in
    *"-c import numpy"*) exit 0 ;;
    *--info*) size=''; while [ $# -gt 0 ]; do [ "$1" != --size ] || size=$2; shift; done
        w=${size%x*}; h=${size#*x}; if [ "$h" -gt "$w" ]; then g=270x480; else g=480x270; fi
        echo "{\"scene\":\"watch\",\"fps\":12,\"kind\":\"pixel\",\"grid\":\"$g\"}" ;;
    *--raw*) echo "$*" >> "$HOME/scene.log"; printf 'frames' ;;
    *--still*) echo "$*" >> "$HOME/scene.log"; out=''; while [ $# -gt 0 ]; do [ "$1" != --png ] || out=$2; shift; done; echo png > "$out" ;;
    *) for a; do d=$a; done; echo "<svg/>" > "$d/f0000.svg"; echo "<svg/>" > "$d/f0001.svg" ;;
esac
MO_PY
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" != -o ] || { shift; cat > "$1"; }; shift; done\n' > "$H/mo/rsvg-convert"
printf '#!/bin/sh\necho "$*" >> "$HOME/mpv.log"; case " $* " in *" - "*) cat >/dev/null ;; esac   # frames on its input: read them all, as mpv does\nfor a; do case $a in --o=*) echo loop > "${a#--o=}" ;; esac; done\n' > "$H/mo/mpv"
printf '#!/bin/sh\necho "$*" >> "$HOME/player.log"\nwhile :; do sleep 1; done\n' > "$H/mo/spark-wallpaper"
chmod +x "$H/mo/swaymsg" "$H/mo/python3" "$H/mo/rsvg-convert" "$H/mo/mpv" "$H/mo/spark-wallpaper"
cp "$HOME/.config/spark-shell/config" "$H/cfg.mo"; printf 'DESKTOP=sway\nTHEME=dracula\nWALLPAPER=orbit\nWALLPAPER_MOTION=on\n' > "$HOME/.config/spark-shell/config"
rm -f "$HOME/mpv.log" "$HOME/player.log"; _mdir=${XDG_CACHE_HOME:-$HOME/.cache}/spark-shell/motion
mo() { TMPDIR=$H/motmp XDG_RUNTIME_DIR=$H/run SWAYSOCK=$H/sock SPARK_SHELL_WALLPAPER=$H/mo/spark-wallpaper PATH="$H/mo:$H/lx:$PATH" sh "$SH" "$@"; }
mo_wait() { _i=0; while [ "$_i" -lt 50 ] && [ "$(grep -c '' "$HOME/player.log" 2>/dev/null || :)" != "$1" ]; do sleep 0.2; _i=$((_i + 1)); done; }
mo_stop() { for _mp in $(pgrep -u "$(id -u)" -f "$H/mo/spark-wallpaper" 2>/dev/null || :); do kill "$_mp" 2>/dev/null || :; done; }
mo desktop --motion >/dev/null 2>&1; mo_wait 1
_ml=$(sed -n 1p "$HOME/player.log" 2>/dev/null || :)
case $_ml in "--all $_mdir/orbit-"*.mp4) _mok=1 ;; *) _mok='' ;; esac
[ -n "$_mok" ] && [ -f "${_ml##* }" ] && [ "$(grep -c '' "$HOME/mpv.log")" = 1 ] && grep -q 'mf://.* --mf-fps=30 .*--ovc=libx264' "$HOME/mpv.log" && [ -z "$(ls "$H/motmp")" ] \
    && ok "desktop --motion: a drawing's frames made into a loop by mpv in the background, kept in the cache, played by spark-wallpaper on every screen, the frames gone (#180, #187)" || bad "motion start" "$_ml | $(cat "$HOME/mpv.log" 2>&1) | $(ls "$H/motmp")"
mo desktop --motion >/dev/null 2>&1; sleep 0.5
[ "$(grep -c '' "$HOME/player.log")" = 1 ] && ok "desktop --motion: a loop already playing is left as it is (#180)" || bad "motion twice" "$(cat "$HOME/player.log")"
rc=0; out=$(mo theme motion off 2>&1) || rc=$?; sleep 0.5
[ "$rc" = 0 ] && [ "$out" = 'moving wallpaper off' ] && grep -qx 'WALLPAPER_MOTION=off' "$HOME/.config/spark-shell/config" && [ -z "$(pgrep -u "$(id -u)" -f "spark-wallpaper .*$_mdir/" || :)" ] && [ ! -e "$H/run/spark-shell-motion.want" ] \
    && ok "theme motion off: the loop's player stopped, the still shows (#180)" || bad "motion off" "rc=$rc $out $(pgrep -u "$(id -u)" -f "spark-wallpaper .*$_mdir/" || :)"
rc=0; out=$(mo theme motion on 2>&1) || rc=$?; mo_wait 2
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^moving wallpaper on .* orbit moves$' && [ "$(grep -c '' "$HOME/player.log")" = 2 ] && [ "$(grep -c '' "$HOME/mpv.log")" = 1 ] \
    && ok "theme motion on: the loop in the cache plays again, never made twice (#180)" || bad "motion cache" "rc=$rc $out $(cat "$HOME/player.log" "$HOME/mpv.log" 2>&1)"
mo_stop
# a scene (#188): a loop a screen, each at its shape (a pixel scene at its own grid, the player scaling it with square pixels),
# made from make.py's raw frames by mpv; the portrait screen's still drawn in its own shape and given to that screen alone
rm -f "$HOME/player.log" "$HOME/mpv.log" "$HOME/scene.log" "$HOME/mosway.log" "$H/run/spark-shell-motion.want"
printf 'DESKTOP=sway\nTHEME=dracula\nWALLPAPER=watch\nWALLPAPER_MOTION=on\n' > "$HOME/.config/spark-shell/config"
mo desktop --motion >/dev/null 2>&1; mo_wait 1; sleep 0.3
_ml=$(sed -n 1p "$HOME/player.log" 2>/dev/null || :)
case $_ml in "--scale nearest --screen DP-3=$_mdir/watch-"*"-270x480.mp4 --screen HDMI-A-1=$_mdir/watch-"*"-480x270.mp4") _mok=1 ;; *) _mok='' ;; esac
[ -n "$_mok" ] && [ "$(grep -c -- '--demuxer=rawvideo' "$HOME/mpv.log")" = 2 ] && grep -q -- '--demuxer-rawvideo-w=270 --demuxer-rawvideo-h=480 .*--vf=format=yuv444p' "$HOME/mpv.log" \
    && grep -q -- '--raw --scene watch --size 480x270 ' "$HOME/scene.log" && [ -z "$(ls "$H/motmp")" ] \
    && ok "desktop --motion, a scene: a loop a screen at its shape (a pixel scene at its grid, lossless), played with square pixels (#187, #188)" || bad "scene loops" "$_ml | $(cat "$HOME/mpv.log" "$HOME/scene.log" 2>&1)"
grep -q -- "--still poster --size 1200x1920 " "$HOME/scene.log" && grep -q '^-- output "DP-3" bg ".*/watch-dracula-1200x1920.png" fill$' "$HOME/mosway.log" && ! grep -q 'HDMI-A-1" bg' "$HOME/mosway.log" \
    && ok "desktop --motion, a scene: the portrait screen's still in its own shape, on that screen alone (#188)" || bad "scene portrait still" "$(cat "$HOME/scene.log" "$HOME/mosway.log" 2>&1)"
mo_stop
cp "$H/cfg.mo" "$HOME/.config/spark-shell/config"
# two screens with one name (no serial, the same model): each by its port, never both at once
sed -i.bak 's/"make":"BOE","model":"0x0BCA","serial":""/"make":"Lenovo Group Limited","model":"T24i-30","serial":"V30A1"/' "$H/lx/swaymsg"; rm -f "$H/lx/swaymsg.bak" "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" desktop screen hdmi-a-1 scale 2 2>&1) || rc=$?
[ "$rc" = 0 ] && grep -qxF -- '-- output "HDMI-A-1" scale 2' "$HOME/swaymsg.log" && grep -qxF 'output "HDMI-A-1" scale 2' "$HOME/.config/spark-shell/screens.conf" \
    && ok "desktop screen: two screens sharing make, model and serial go by their ports" || bad "screen twins" "rc=$rc $out $(cat "$HOME/swaymsg.log")"
# the brightness: a laptop's backlight
mkdir -p "$H/sysb/class/backlight/amdgpu_bl1"
printf '#!/bin/sh\necho "$*" >> "$HOME/bctl.log"\ncase "$*" in "-m -c backlight info") echo "amdgpu_bl1,backlight,120,47%%,255" ;; esac\n' > "$H/lx/brightnessctl"; chmod +x "$H/lx/brightnessctl"
rc=0; out=$(SPARK_SHELL_SYS=$H/sysb PATH="$H/lx:$PATH" sh "$SH" desktop display brightness up 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'brightness at 52%' ] && grep -qx -- '-q -c backlight set 52%' "$HOME/bctl.log" && ok "desktop display brightness up: the backlight 5 up, through brightnessctl" || bad "brightness backlight" "rc=$rc $out $(cat "$HOME/bctl.log" 2>&1)"
line=$(SPARK_SHELL_SYS=$H/sysb SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status --once 2>/dev/null)
pip=$(printf '\342\226\260'); pipoff=$(printf '\342\226\261'); g=$(printf '%s' "$line" | jq -r '.[] | select(.name == "light" and .instance == "gauge") | .full_text'); k=$(printf '%s' "$line" | jq -r '.[] | select(.name == "kb") | .full_text')
[ "$(printf '%s' "$g" | LC_ALL=C grep -o "$pip" | wc -l | tr -d ' ')" = 2 ] && [ "$(printf '%s' "$g" | LC_ALL=C grep -o "$pipoff" | wc -l | tr -d ' ')" = 3 ] && [ "$(printf '%s' "$line" | jq -r '.[] | select(.name == "light" and .instance == "name") | .full_text')" = "<span foreground='#ff5555'>$(printf '\342\230\274')</span>" ] && [ "$k" = "<span foreground='#555555'>$(printf '\342\214\227')</span> us+intl" ] \
    && ok "bar: light, a sun in the accent with its gauge (47: two of five cells), and kb, a key grid muted with the layout in use (sway's second, us+intl)" || bad "bar light kb" "$line"
# the workspaces' names (#248): a workspace named by its number, or a layout's "3 writing", takes its label in the glyph
# family, stone's number in angle brackets by default; one the user named is left, and so is one past the end of nothing
WSO=${XDG_RUNTIME_DIR:+$XDG_RUNTIME_DIR/spark-shell}; WSO=${WSO:-$HOME/.local/state/spark-shell}/ws-order   # the order the bar drew before the families, in the runtime dir when a login has one
la=$(printf '\342\237\250'); ra=$(printf '\342\237\251'); ls_=$(printf '\342\227\202'); rs_=$(printf '\342\226\270')
rm -f "$HOME/swaymsg.log" "$HOME/ws-later" "$WSO"; touch "$HOME/ws-test"
SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status </dev/null >/dev/null 2>&1 & bp=$!
i=0; while [ "$i" -lt 50 ] && [ "$(cat "$HOME/swaymsg.log" 2>/dev/null | grep -c '^-- rename')" -lt 5 ]; do sleep 0.1; i=$((i + 1)); done; kill "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
[ "$(grep '^-- rename' "$HOME/swaymsg.log" 2>/dev/null)" = "$(printf '%s\n' "-- rename workspace \"1\" to \"1:${la}1$ra\"" "-- rename workspace \"3 writing\" to \"3:${la}3$ra writing\"" "-- rename workspace \"10\" to \"10:${la}10$ra\"" "-- rename workspace \"11\" to \"11:${la}11$ra\"" "-- rename workspace \"5\" to \"5:${la}5$ra\"")" ] && [ ! -e "$WSO" ] \
    && ok "bar status: each workspace takes its number in stone's angle brackets at the bar's start, a new one (5) at once; a layout's 3 writing keeps its words, 2:x the user's own is left, 11 past the tenth is named too (#248)" || bad "workspace labels" "$(cat "$HOME/swaymsg.log" 2>&1)"
# theme family (#248): the open workspaces renamed at once in the new family, every name of ours (another family's label, its
# number, a symbol of the order before the families) and a bare one; a name the user gave is left; the same family again refused
mkdir -p "$(dirname "$WSO")"; printf '%s\n' '\342\215\237' '\342\215\252' '\342\215\234' '\342\214\254' '\342\215\266' '\342\215\234' > "$WSO"
old6=$(printf '\342\215\234')
printf '[{"num":1,"name":"1:%s1%s"},{"num":2,"name":"2:x"},{"num":3,"name":"3:%s3%s writing"},{"num":4,"name":"4"},{"num":5,"name":"5:5"},{"num":6,"name":"6:%s"},{"num":7,"name":"7:%s7%s"}]\n' "$la" "$ra" "$la" "$ra" "$old6" "$ls_" "$rs_" > "$HOME/ws-styled"; rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" theme family banner 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'glyph family banner' ] && [ "$(grep '^-- rename' "$HOME/swaymsg.log" 2>/dev/null)" = "$(printf '%s\n' "-- rename workspace \"1:${la}1$ra\" to \"1:I\"" "-- rename workspace \"3:${la}3$ra writing\" to \"3:III writing\"" "-- rename workspace \"4\" to \"4:IV\"" "-- rename workspace \"5:5\" to \"5:V\"" "-- rename workspace \"6:$old6\" to \"6:VI\"" "-- rename workspace \"7:${ls_}7$rs_\" to \"7:VII\"")" ] \
    && ok "theme family banner (#248): the workspaces renamed at once in Roman numbers, from stone's and star's labels, a number and an old symbol; a layout's words kept, a name the user gave left" || bad "family banner" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" theme family banner 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'the glyph family is banner already' ] && ok "theme family: the family in use again is refused" || bad "family again" "rc=$rc $out"
printf '[{"num":4,"name":"4:IV"},{"num":12,"name":"12 news"}]\n' > "$HOME/ws-styled"; rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" theme family star 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$(grep '^-- rename' "$HOME/swaymsg.log" 2>/dev/null)" = "$(printf '%s\n' "-- rename workspace \"4:IV\" to \"4:${ls_}4$rs_\"" "-- rename workspace \"12 news\" to \"12:${ls_}12$rs_ news\"")" ] \
    && ok "theme family star: the number between star's small triangles, from banner's Roman number too" || bad "family star" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
line=$(SPARK_SHELL_SYS=$H/sysb SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status --once 2>/dev/null)
on=$(printf '\342\224\201'); off=$(printf '\342\224\200'); g=$(printf '%s' "$line" | jq -r '.[] | select(.name == "light" and .instance == "gauge") | .full_text')
[ "$(printf '%s' "$g" | LC_ALL=C grep -o "$on" | wc -l | tr -d ' ')" = 2 ] && [ "$(printf '%s' "$g" | LC_ALL=C grep -o "$off" | wc -l | tr -d ' ')" = 3 ] && ! printf '%s' "$g" | LC_ALL=C grep -q "$pip" \
    && ok "bar: the gauges wear the family's pair, star's heavy and light lines (47: two of five lit)" || bad "star gauge" "$g"
SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" theme family stone >/dev/null 2>&1; rm -f "$HOME/ws-styled" "$WSO"
rm -f "$HOME/ws-test" "$HOME/ws-later"
SPARK_SHELL_SYS=$H/sysb PATH="$H/lx:$PATH" sh "$SH" bar light down; grep -qx -- '-q -c backlight set 42%' "$HOME/bctl.log" && ok "bar light down: the brightness keys, 5 down" || bad "bar light down" "$(cat "$HOME/bctl.log")"
rm -f "$HOME/bctl.log"; rc=0; out=$(SPARK_SHELL_SYS=$H/sysb SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel display brightness down 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'brightness at 42%' ] && grep -qx -- '-q -c backlight set 42%' "$HOME/bctl.log" \
    && ok "panel display brightness down, the step a want plans: 5 down from the level now (47 to 42), never straight to 1 (#31)" || bad "panel brightness down" "rc=$rc $out $(cat "$HOME/bctl.log" 2>&1)"
# a screen over DDC/CI: no backlight, ddcutil on the screen's bus
cat > "$H/lx/ddcutil" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/ddc.log"
case "$*" in
    "detect --terse") printf 'Invalid display\n   I2C bus:  /dev/i2c-3\n\nDisplay 1\n   I2C bus:          /dev/i2c-5\n   Monitor:          LEN:T24i-30:V30A1\n' ;;
    "--bus 5 getvcp 10 --terse") echo 'VCP 10 C 30 50' ;;
esac
STUB
chmod +x "$H/lx/ddcutil"; export XDG_RUNTIME_DIR=$H/rt; mkdir -p "$H/rt"; rm -f "$H/rt/spark-shell/ddc.bus" "$HOME/.local/state/spark-shell/light"
rc=0; out=$(SPARK_SHELL_DEV=$H/dev SPARK_SHELL_SYS=$H/sysnone PATH="$H/lx:$PATH" sh "$SH" desktop display brightness 80 2>&1) || rc=$?
[ "$rc" = 1 ] && [ ! -e "$HOME/ddc.log" ] && [ ! -e "$H/rt/spark-shell/ddc.bus" ] && ok "brightness with no i2c device open to you: ddcutil never asked, nothing kept (the group comes at the next login)" || bad "ddc no device" "rc=$rc $out"
mkdir -p "$H/dev"; : > "$H/dev/i2c-5"
rc=0; out=$(SPARK_SHELL_DEV=$H/dev SPARK_SHELL_SYS=$H/sysnone PATH="$H/lx:$PATH" sh "$SH" desktop display brightness 80 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'brightness at 80%' ] && grep -qx -- '--bus 5 setvcp 10 80 --noverify' "$HOME/ddc.log" && ok "desktop display brightness 80: the screen's DDC/CI on its own bus (5, the first display that answers), no read back" || bad "brightness ddc" "rc=$rc $out $(cat "$HOME/ddc.log")"
rm -f "$HOME/.local/state/spark-shell/light"
out=$(SPARK_SHELL_DEV=$H/dev SPARK_SHELL_SYS=$H/sysnone PATH="$H/lx:$PATH" sh "$SH" desktop display 2>&1)
[ "$(printf '%s\n' "$out" | sed -n 2p)" = 'brightness 60%' ] && [ "$(grep -c '^detect' "$HOME/ddc.log")" = 1 ] && ok "desktop display: the brightness read from the screen (30 of 50, 60%); which screen answers is kept, asked once" || bad "display show" "$out $(cat "$HOME/ddc.log")"
# a screen asleep (DPMS) is asked again within a minute, never kept as none; the answer lives in the runtime directory a reboot clears
printf '#!/bin/sh\necho "$*" >> "$HOME/ddc.log"\nprintf "Invalid display\\n   I2C bus:  /dev/i2c-5\\n   DRM reports the monitor is in a DPMS sleep state\\n"\n' > "$H/lx/ddcutil"; rm -f "$H/rt/spark-shell/ddc.bus"
SPARK_SHELL_DEV=$H/dev SPARK_SHELL_SYS=$H/sysnone PATH="$H/lx:$PATH" sh "$SH" desktop display >/dev/null 2>&1 || :
[ "$(cat "$H/rt/spark-shell/ddc.bus" 2>/dev/null)" = asleep ] && ok "brightness: a screen asleep is kept as asleep (asked again in a minute), in the runtime directory" || bad "ddc asleep" "$(cat "$H/rt/spark-shell/ddc.bus" 2>&1)"
# the dialog's display and keyboard sections
rows=$(SPARK_SHELL_SYS=$H/sysb SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel display --list 2>&1)
printf '%s\n' "$rows" | grep -q 'idle screen after 10 minutes	display show$' && printf '%s\n' "$rows" | grep -q 'lock after 15 minutes	display show$' && printf '%s\n' "$rows" | grep -q 'brighter	display brightness up$' && printf '%s\n' "$rows" | grep -qF "screen HDMI-A-1 $(printf '\302\267') T24i-30 $(printf '\302\267') 1920x1080 $(printf '\302\267') scale 1	display show" \
    && ok "the dialog's display section: the minutes now, brighter and dimmer, a row per screen" || bad "display rows" "$rows"
rows=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel keyboard --list 2>&1)
printf '%s\n' "$rows" | grep -q 'br	keyboard use br$' && printf '%s\n' "$rows" | grep -q 'the next layout	keyboard next$' && ok "the dialog's keyboard section: the layouts, the one in use ticked, the others one Enter away, and the next" || bad "keyboard rows" "$rows"
rm -f "$HOME/swaymsg.log"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel keyboard use br 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'the keyboard is br' ] && grep -qx -- '-- input type:keyboard xkb_switch_layout 2' "$HOME/swaymsg.log" && ok "the dialog: keyboard use br switches to its index (2)" || bad "keyboard use" "rc=$rc $out $(cat "$HOME/swaymsg.log")"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel display idle 5 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'idle screen after 5 minutes' ] && grep -qx 'DISPLAY_IDLE=5' "$HOME/.config/spark-shell/config" && ok "the dialog: display idle 5 sets it, and says the idle screen, as the command does (#68)" || bad "display idle from dialog" "rc=$rc $out"
rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar panel display lock 20 2>&1) || rc=$?
[ "$rc" = 0 ] && [ "$out" = 'lock after 20 minutes' ] && grep -qx 'DISPLAY_LOCK=20' "$HOME/.config/spark-shell/config" && ok "the dialog: display lock 20 says the lock (#68)" || bad "display lock from dialog" "rc=$rc $out"
# notes: one Markdown file a note in ~/notes, the first line its name
[ "$(NL notes add 'groceries for the weekend')" = 'new note: groceries for the weekend' ] && [ "$(cat "$HOME/notes/groceries-for-the-weekend.md")" = '# groceries for the weekend' ] \
    && ok "notes add: a new note, its words the first line, a file named from them in ~/notes" || bad "notes add" "$(ls "$HOME/notes" 2>&1)"
[ "$(ls -ld "$HOME/notes" | cut -c1-10)" = drwx------ ] && [ "$(ls -l "$HOME/notes/groceries-for-the-weekend.md" | cut -c1-10)" = -rw------- ] \
    && ok "notes: ~/notes and a note spark-shell writes are yours alone, 0700 and 0600 (#63)" || bad "notes modes" "$(ls -ld "$HOME/notes" "$HOME/notes/groceries-for-the-weekend.md")"
[ "$(NL notes add 'groceries for the weekend: buy oat milk')" = 'added to groceries for the weekend: buy oat milk' ] && [ "$(sed -n 2p "$HOME/notes/groceries-for-the-weekend.md")" = '- buy oat milk' ] \
    && ok "notes add NAME: TEXT: a line added to the note NAME" || bad "notes add to" "$(cat "$HOME/notes/groceries-for-the-weekend.md")"
printf '# the jabra mic levels\ncapture at 60%%, an arm'"'"'s length away\n' > "$HOME/notes/jabra.md"; touch -t 202601010900 "$HOME/notes/jabra.md"
[ "$(NL notes find 'arm')" = "1 note says arm $(printf '\302\267') the jabra mic levels: capture at 60%, an arm's length away" ] && ok "notes find: which note says the words, and the line" || bad "notes find" "$(NL notes find arm)"
rows=$(NL notes --list)
[ "$(printf '%s\n' "$rows" | grep -n 'notes open' | head -1 | cut -d: -f2-)" = "$(printf '%s\n' "$rows" | grep 'notes open groceries' )" ] && printf '%s\n' "$rows" | grep -q 'new note	notes new$' \
    && ok "notes: new note, then the notes newest first" || bad "notes list" "$rows"
rm -f "$HOME/swaymsg.log"; out=$(NL notes open the jabra mic levels)
[ "$out" = 'opened the jabra mic levels' ] && grep -qxF -- "-- exec foot -e true '$HOME/notes/jabra.md'" "$HOME/swaymsg.log" && ok "notes open: the note in your editor, in a terminal window" || bad "notes open" "$out $(cat "$HOME/swaymsg.log" 2>&1)"
j=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://notes/rows"}}' | SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" provide notes 2>/dev/null | jq -r 'select(.id == 2) | .result.contents[0].text')
printf '%s' "$j" | jq -e '[.rows[] | select(.text == "the jabra mic levels")][0] | .group == "recent" and .columns == ["Jan 1"] and .tool.name == "notes_open"' >/dev/null \
    && ok "provide notes: a note's row, its date a column, in the group recent, Enter opens it" || bad "provide notes" "$j"
# the reminders read today and tomorrow off the clock: in a zone where it is about noon now, a run that crosses
# midnight (CI's clock is UTC) never turns tomorrow into today halfway through
_ntz=$(noon_tz); [ -z "$_ntz" ] || { TZ=$_ntz; export TZ; }
# reminders: one iCalendar event a reminder in ~/calendar, its alarm at its time
vd=$(LC_ALL=C date -d 2030-01-02 '+%a %d %b' 2>/dev/null || LC_ALL=C date -j -f %Y%m%d 20300102 '+%a %d %b'); vd=$(printf '%s' "$vd" | sed 's/ 0/ /')
[ "$(NL reminders add '2030-01-02 10:00 the vet, Luna'"'"'s shots')" = "reminder $vd 10:00 the vet, Luna's shots" ] \
    && f=$(ls "$HOME"/calendar/*.ics) && tr -d '\r' < "$f" | grep -qx 'DTSTART:20300102T100000' && tr -d '\r' < "$f" | grep -qxF "SUMMARY:the vet\\, Luna's shots" && tr -d '\r' < "$f" | grep -qx 'TRIGGER:PT0M' && [ "$(grep -c "$(printf '\r')$" "$f")" = "$(wc -l < "$f" | tr -d ' ')" ] \
    && ok "reminders add: an iCalendar event in ~/calendar, its local time, its alarm at that time, the comma escaped, every line CRLF" || bad "reminders add" "$(cat "$HOME"/calendar/*.ics 2>&1)"
[ "$(NL reminders add 'tomorrow 9am standup with the team')" = 'reminder tomorrow 09:00 standup with the team' ] && ok "reminders add: tomorrow, 9am read as 09:00, the words as said" || bad "reminders tomorrow" "$(NL reminders --list)"
for w in 'gym in 10 minutes' 'in 10 minutes swim' 'gym in an hour'; do out=$(NL reminders add "$w"); printf '%s\n' "$out" | grep -Eq '^reminder (today|tomorrow) [0-2][0-9]:[0-5][0-9] (gym|swim)$' || bad "reminders add $w" "$out"; done   # three titles: the same words at the same minute would be one (#111)
ok "reminders add: a while from now, before the words or after them (gym in 10 minutes, in an hour), the time from now"
[ "$(NL reminders add '23:59 a late one')" = 'reminder today 23:59 a late one' ] && [ "$(NL reminders add '00:00 an early one')" = 'reminder tomorrow 00:00 an early one' ] && [ "$(NL reminders add 'walk the dog at 23:59')" = 'reminder today 23:59 walk the dog' ] \
    && ok "reminders add: a time alone is today, or tomorrow once today's has passed (23:59 a late one, 00:00 an early one, walk the dog at 23:59)" || bad "reminders time alone" "$(NL reminders add '00:00 an early one' 2>&1) | $(NL reminders add 'walk the dog at 23:59' 2>&1)"
for f in "$HOME"/calendar/*.ics; do grep -q 'SUMMARY:\(a late one\|an early one\|walk the dog\)' "$f" 2>/dev/null && rm -f "$f"; done; rm -f "$HOME/.local/state/spark-shell/reminders.list"   # the three go: the rows tests below count the fixture's own
NL reminders add 'call the bank 2030-01-03 at 9' | grep -Eq '^reminder [A-Za-z]+ 3 [A-Za-z]+ 09:00 call the bank$' \
    && [ "$(NL reminders add 'pay rent on 2030-01-04 at 10:30' | sed 's/^reminder [A-Za-z]* [0-9]* [A-Za-z]* //')" = '10:30 pay rent' ] && ! NL reminders add 'buy 2 apples' >/dev/null \
    && ok "reminders add: the day and the time last, as spoken (call the bank 2030-01-03 at 9, on ... at 10:30); a bare number is a time only after at" || bad "reminders spoken order" "$(NL reminders add 'call the bank 2030-01-03 at 9')"
grep -l '^SUMMARY:\(gym\|swim\)' "$HOME"/calendar/*.ics 2>/dev/null | while IFS= read -r f; do rm -f "$f"; done   # the later checks read the next one ahead
out=$(NL reminders add 'yesterday call the bank' || :); [ "$out" = 'a reminder takes a day and a time, then the words (tomorrow 09:00 call the dentist), a time alone for today or else tomorrow (5pm gym), or a while from now (gym in 10 minutes)' ] && ok "reminders add: no day and time, refused with an example" || bad "reminders refuse" "$out"
# a reminder due: the bar's due block, one chime, done and a snooze in the section; another tool's events read, never changed
printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:spark-shell-test-1@box\r\nDTSTART:%s\r\nSUMMARY:water the plants\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(ago 60)" > "$HOME/calendar/ours.ics"
printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:khal-1\r\nDTSTART:%s\r\nSUMMARY:a long title from another calendar\\, folded\r\n  across two lines\; done\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:khal-old\r\nDTSTART:20200101T080000Z\r\nSUMMARY:an old meeting\r\nEND:VEVENT\r\nBEGIN:VEVENT\r\nUID:khal-weekly\r\nDTSTART:%s\r\nRRULE:FREQ=WEEKLY\r\nSUMMARY:a weekly one\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(ago_utc 30)" "$(ago 10)" > "$HOME/calendar/other.ics"
printf '#!/bin/sh\necho "$*" >> "$HOME/chime.log"\n' > "$H/lx/pw-play"; chmod +x "$H/lx/pw-play"; rm -f "$HOME/chime.log"
line=$(SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status --once 2>/dev/null); SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status --once >/dev/null 2>&1; sleep 1
[ "$(printf '%s' "$line" | jq -r '.[] | select(.name == "due") | .full_text')" = "<span foreground='#ff5555'>$(printf '\342\247\227')</span> a long title from another ca" ] && [ "$(grep -c . "$HOME/chime.log" 2>/dev/null)" = 1 ] \
    && ok "bar: the latest reminder due (another tool's, in UTC, its folded title joined), cut at 28 characters, and one chime for the two due, not at every line" || bad "due block" "$(printf '%s' "$line" | jq -c '.[] | select(.name == "due")') chimes=$(cat "$HOME/chime.log" 2>&1)"
rows=$(NL reminders --list)
printf '%s\n' "$rows" | grep -q "a long title from another calendar, folded across two lines; done	reminders show" && ! printf '%s\n' "$rows" | grep -q 'an old meeting\|a weekly one' \
    && printf '%s\n' "$rows" | grep -q 'again in 10 minutes	reminders snooze ' \
    && ok "reminders: a folded title joined and unescaped; old and repeating events left out; external events read only and owned events have done and snooze" || bad "due rows" "$rows"
out=$(NL reminders snooze a long title from another calendar, folded across two lines\; 'done' || :); [ "$out" = "a long title from another calendar, folded across two lines; done is an event another calendar wrote: change it there" ] && grep -q 'UID:khal-old' "$HOME/calendar/other.ics" \
    && ok "reminders snooze on another calendar's event: refused, its file untouched" || bad "foreign snooze" "$out"
out=$(NL reminders snooze water the plants); printf '%s' "$out" | grep -q '^water the plants again at [0-9][0-9]:[0-9][0-9]$' \
    && ok "reminders snooze: our event moved 10 minutes on" || bad "snooze" "$out $(cat "$HOME/calendar/ours.ics")"
out=$(NL reminders 'done' water the plants); [ "$out" = 'done: water the plants' ] && [ ! -e "$HOME/calendar/ours.ics" ] && [ -f "$HOME/calendar/done/ours.ics" ] && ! NL reminders --list | grep -q "water the plants$(printf '\t')reminders" && NL --list | grep -q "reminder water the plants$(printf '\t')undo all" \
    && ok "reminders done: our event put aside in ~/calendar/done, out of the list, and undo offered" || bad "done" "$out $(ls -R "$HOME/calendar")"
out=$(NL reminders restore water the plants); [ "$out" = 'water the plants is back' ] && [ -f "$HOME/calendar/ours.ics" ] && [ ! -e "$HOME/calendar/done/ours.ics" ] \
    && ok "reminders restore: the one put aside is back where it was" || bad "restore" "$out $(ls -R "$HOME/calendar")"
printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:spark-shell-test-3@box\r\nDTSTART:%s\r\nSUMMARY:check the oven\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(ago 5)" > "$HOME/calendar/oven.ics"
j=$(mcp_rem reminders_done 'check the oven'); u=$(printf '%s' "$j" | jq -c '.structuredContent.undo'); j2=$(mcp_rem reminders_restore spark-shell-test-3@box)
[ "$u" = '{"name":"reminders_restore","arguments":{"name":"spark-shell-test-3@box"}}' ] && printf '%s' "$j2" | jq -e '.isError == false' >/dev/null && [ -f "$HOME/calendar/oven.ics" ] && [ ! -e "$HOME/calendar/done/oven.ics" ] \
    && ok "provide reminders: done is put aside, its undo names that one by its uid, and the undo brings it back: a real undo" || bad "done undo" "$j | $j2"
rm -f "$HOME/calendar/oven.ics"
out=$(NL reminders 'done' water the plants) && touch -t 202001010000 "$HOME/calendar/done/ours.ics" && NL reminders add 'tomorrow 08:00 a later one' >/dev/null && NL reminders 'done' a later one >/dev/null && [ ! -e "$HOME/calendar/done/ours.ics" ] \
    && ok "reminders done: one put aside more than 30 days ago is gone at the next done" || bad "done prune" "$out $(ls -l "$HOME/calendar/done")"
out=$(NL reminders restore nothing like it || :); [ "$out" = 'no unique reminder done named nothing like it; use its UID' ] && ok "reminders restore: no such one, said" || bad "restore none" "$out"
[ "$(NL reminders add 'tomorrow 09:00 semi; colon, comma' | tail -1)" != '' ] && f=$(grep -l 'semi' "$HOME"/calendar/*.ics 2>/dev/null | head -1) && tr -d '\r' < "${f:-/dev/null}" | grep -qxF 'SUMMARY:semi\; colon\, comma' \
    && ok "reminders add: a semicolon and a comma escaped as iCalendar text" || bad "ics escape" "$(cat "${f:-/dev/null}" 2>&1) $(ls "$HOME/calendar")"
out=$(NL reminders add '2026-19-39 10:00 nothing' || :); [ "$out" = 'a reminder takes a day and a time, then the words (tomorrow 09:00 call the dentist), a time alone for today or else tomorrow (5pm gym), or a while from now (gym in 10 minutes)' ] && ok "reminders add: a day the calendar lacks is refused" || bad "bad date" "$out"
rm -f "$HOME/calendar/other.ics"
j=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://reminders/rows"}}' | SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" provide reminders 2>/dev/null | jq -r 'select(.id == 2) | .result.contents[0].text')
printf '%s' "$j" | jq -e '[.rows[] | select(.text | startswith("the vet"))][0] | .date == "2030-01-02" and .group == "later" and (.columns[0] | endswith("10:00"))' >/dev/null \
    && ok "provide reminders: a reminder's row carries its day for the Calendar, its group and its time" || bad "provide reminders" "$j"
printf '%s' "$j" | jq -e '(.rows[0] | .id == "reminders:add" and .text == "new reminder" and .tool.ask == ["words"]) and ([.rows[] | select(.id == "reminders:more")][0] | .children == "spark-shell://reminders/rows" and (.columns[0] | startswith("tomorrow 09:00"))) and ([.rows[] | select(.text | startswith("say it"))] | length == 0)' >/dev/null \
    && ok "provide reminders: new reminder first, asking for its words; the next one ahead, its day and time, opens the rest; no hint posing as a row" || bad "provide reminders rows" "$j"
j=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" provide reminders 2>/dev/null | jq -c 'select(.id == 2) | .result.tools')
printf '%s' "$j" | jq -e '.[] | select(.name == "reminders_add") | .inputSchema.properties.words.description == "when and what: fri 9am call the vet"' >/dev/null \
    && ok "provide reminders: the words of reminders_add say what they are, for the dialog's hint when it asks" || bad "reminders_add description" "$j"
# a reminder ahead (#111): its steps reachable, a delete at the prompt, the UID shown when a name repeats, a double add refused
NL reminders add '2099-03-01 09:00 test the garden hose' >/dev/null; NL reminders add '2099-03-02 09:00 test the garden hose' >/dev/null
out=$(NL reminders add '2099-03-01 09:00 Test the Garden Hose' || :); [ "$out" = 'Sun 1 Mar 09:00 test the garden hose is a reminder already' ] && [ "$(grep -l 'garden hose' "$HOME"/calendar/*.ics | wc -l | tr -d ' ')" = 2 ] \
    && ok "reminders add: the same words at the same minute, whatever the case, is refused with the one that exists; two at different times are two" || bad "reminders double add" "$out"
u1=$(grep -l '20990301T090000' "$HOME"/calendar/*.ics | head -1 | xargs grep '^UID:' | cut -c5- | tr -d '\r'); u2=$(grep -l '20990302T090000' "$HOME"/calendar/*.ics | head -1 | xargs grep '^UID:' | cut -c5- | tr -d '\r')
out=$(sh "$SH" reminders 2>&1); printf '%s\n' "$out" | grep -q "^  Sun 1 Mar 09:00  test the garden hose  $u1\$" && printf '%s\n' "$out" | grep -q "^  Mon 2 Mar 09:00  test the garden hose  $u2\$" && ! printf '%s\n' "$out" | grep -q "feed the cat  spark-shell" \
    && ok "spark-shell reminders: a name two reminders share carries each one's UID, a name alone does not" || bad "reminders uid column" "$out"
rc=0; out=$(sh "$SH" reminders delete test the garden hose 2>&1) || rc=$?; [ "$rc" = 1 ] && [ "$out" = 'spark-shell reminders: no unique reminder named test the garden hose; select it in Calendar' ] \
    && [ "$(sh "$SH" reminders delete "$u1" 2>&1)" = 'deleted: test the garden hose' ] && [ "$(grep -l 'garden hose' "$HOME"/calendar/*.ics | wc -l | tr -d ' ')" = 1 ] && ! grep -rq "$u1" "$HOME/calendar" \
    && ok "spark-shell reminders delete: a name two share is refused, the UID names one, and its file goes" || bad "reminders delete" "rc=$rc $out $(ls "$HOME/calendar")"
j=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://reminders/rows"}}' "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"reminders_delete\",\"arguments\":{\"name\":\"$u2\"}}}" "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"reminders_restore\",\"arguments\":{\"name\":\"$u2\"}}}" | SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" provide reminders 2>/dev/null)
printf '%s\n' "$j" | jq -r 'select(.id == 2) | .result.contents[0].text' | jq -e --arg u "$u2" '.rows[] | select(.text == "test the garden hose") | .sign == "ring" and .tool == {name: "reminders_done", arguments: {name: $u}} and ([.more[] | .name + ":" + .said] == ["reminders_done:done", "reminders_snooze:again in 10 minutes", "reminders_delete:delete"])' >/dev/null \
    && [ "$(printf '%s\n' "$j" | jq -c --arg u "$u2" 'select(.id == 3) | .result.structuredContent | [.receipt, .undo, .effect.operation]')" = "[\"deleted: test the garden hose\",{\"name\":\"reminders_restore\",\"arguments\":{\"name\":\"$u2\"}},\"deleted\"]" ] \
    && [ "$(printf '%s\n' "$j" | jq -r 'select(.id == 4) | .result.structuredContent.receipt')" = 'test the garden hose is back' ] && grep -rq "$u2" "$HOME/calendar" \
    && ok "provide reminders: one ahead is a row with done on Enter and done, again in 10 minutes and delete as its steps, each in a person's words; delete says its undo, and restore brings the deleted one back while the provider lives" || bad "provide reminders ahead" "$(printf '%s\n' "$j" | head -c 1200)"
sh "$SH" reminders delete "$u2" >/dev/null 2>&1; rm -f "$HOME/.local/state/spark-shell/reminders.list"
rows=$(NL --list)
printf '%s\n' "$rows" | grep -q 'new reminder	reminders add$' && printf '%s\n' "$rows" | grep -q 'reminders  [a-z].*	reminders more$' \
    && ok "the home list: new reminder, and the next reminder ahead, which opens the rest" || bad "home reminders" "$rows"
# a look at the bar (check, status) rings no chime and spends none
printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:spark-shell-test-look@box\r\nDTSTART:%s\r\nSUMMARY:look only\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(ago 2)" > "$HOME/calendar/look.ics"
rm -f "$HOME/chime.log"; SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" check >/dev/null 2>&1 || :; SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar >/dev/null 2>&1 || :; sleep 1
c0=$(grep -c . "$HOME/chime.log" 2>/dev/null || :); SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status --once >/dev/null 2>&1; sleep 1; c1=$(grep -c . "$HOME/chime.log" 2>/dev/null || :)
[ "${c0:-0}" = 0 ] && [ "${c1:-0}" = 1 ] && ok "a reminder due: check and bar look without ringing; the bar's own pass rings it once" || bad "look rings" "check/bar=$c0 then bar status=$c1"
rm -f "$HOME/calendar/look.ics"
# notes and reminders as commands of their own; the notes list in the machine's zone, as the note's Jan 1 was set in
out=$(unset TZ; SWAYSOCK=$H/sock EDITOR=true PATH="$H/lx:$PATH" sh "$SH" notes 2>&1); printf '%s\n' "$out" | grep -q '^  [a-zA-Z].* *groceries for the weekend$' && printf '%s\n' "$out" | grep -q '^  Jan 1  *the jabra mic levels$' \
    && ok "spark-shell notes: each note with its date, the newest first" || bad "notes command" "$out"
[ "$(sh "$SH" notes add 'groceries for the weekend: eggs' 2>&1)" = 'added to groceries for the weekend: eggs' ] && [ "$(sh "$SH" notes find eggs 2>&1)" = "1 note says eggs $(printf '\302\267') groceries for the weekend: eggs" ] \
    && ok "spark-shell notes add and find" || bad "notes add/find command" "$(sh "$SH" notes find eggs 2>&1)"
rm -f "$HOME/swaymsg.log"; out=$(SWAYSOCK=$H/sock EDITOR=true PATH="$H/lx:$PATH" sh "$SH" notes the jabra mic levels </dev/null 2>&1)
[ "$out" = 'opened the jabra mic levels' ] && grep -qxF -- "-- exec foot -e true '$HOME/notes/jabra.md'" "$HOME/swaymsg.log" && ok "spark-shell notes NAME: away from a terminal, the note opens in the desktop's" || bad "notes open command" "$out"
rc=0; out=$(sh "$SH" notes nothing like it 2>&1) || rc=$?; [ "$rc" = 1 ] && [ "$out" = 'spark-shell notes: no unique note named nothing like it; use its filename (spark-shell notes lists them)' ] && ok "spark-shell notes NAME: no such note, refused" || bad "notes refuse" "rc=$rc $out"
out=$(sh "$SH" reminders add tomorrow 7:30pm feed the cat 2>&1); [ "$out" = 'reminder tomorrow 19:30 feed the cat' ] && ok "spark-shell reminders add: the day, the time, the words" || bad "reminders add command" "$out"
out=$(sh "$SH" reminders 2>&1); printf '%s\n' "$out" | grep -q '^tomorrow$' && printf '%s\n' "$out" | grep -q '^  19:30  *feed the cat$' && printf '%s\n' "$out" | grep -q '^later$' \
    && ok "spark-shell reminders: the ones ahead under their groups, each its time" || bad "reminders command" "$out"
[ "$(sh "$SH" reminders 'done' feed the cat 2>&1)" = 'done: feed the cat' ] && ok "spark-shell reminders done NAME" || bad "reminders done command" "$(sh "$SH" reminders 2>&1)"
[ "$(sh "$SH" reminders restore feed the cat 2>&1)" = 'feed the cat is back' ] && sh "$SH" reminders 2>&1 | grep -q 'feed the cat$' && sh "$SH" reminders 'done' feed the cat >/dev/null 2>&1 && ok "spark-shell reminders restore NAME" || bad "reminders restore command" "$(sh "$SH" reminders 2>&1)"
rc=0; out=$(sh "$SH" reminders snooze 2>&1) || rc=$?; [ "$rc" = 1 ] && [ "$out" = "spark-shell reminders: snooze takes the reminder's name (spark-shell reminders lists them)" ] && ok "spark-shell reminders snooze with no name: refused" || bad "snooze refuse" "rc=$rc $out"
# a reminder due on tmux's status line: the words, and the chime once though the bar asks too
printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:spark-shell-test-2@box\r\nDTSTART:%s\r\nSUMMARY:#take the bread out of the oven now\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(ago 1)" > "$HOME/calendar/bread.ics"
rm -f "$HOME/chime.log"; out=$(PATH="$H/lx:$PATH" sh "$SH" bar due 2>&1); PATH="$H/lx:$PATH" sh "$SH" bar due >/dev/null 2>&1; SWAYSOCK=$H/sock PATH="$H/lx:$PATH" sh "$SH" bar status --once >/dev/null 2>&1; sleep 1
[ "$out" = 'due: take the bread out of the ov  ' ] && [ "$(grep -c . "$HOME/chime.log" 2>/dev/null)" = 1 ] \
    && ok "bar due: tmux's line says the reminder due (no #, cut at 28), and the chime plays once across the line and the bar" || bad "bar due" "[$out] chimes=$(cat "$HOME/chime.log" 2>&1)"
rm -f "$HOME/calendar/bread.ics"; [ -z "$(PATH="$H/lx:$PATH" sh "$SH" bar due 2>&1)" ] && ok "bar due: nothing due, nothing on the line" || bad "bar due empty"
rm -rf "$HOME/notes" "$HOME/calendar" "$H/lx/pw-play"
rm -rf "$H/lx/swaymsg" "$H/lx/pkill" "$H/lx/brightnessctl" "$H/lx/ddcutil" "$H/sysb" "$H/xkb"
unset TZ   # the reminders' noon ends here
# the folders that hold what is yours (#63): on makes the ones already there private, with a row; a link is left as it is
mkdir -p "$HOME/.local/state/spark-shell" "$HOME/.config/spark-shell/themes" "$H/shared"; chmod 755 "$HOME/.local/state/spark-shell" "$HOME/.config/spark-shell/themes" "$H/shared"; ln -s "$H/shared" "$HOME/notes"
out=$(L on --dry-run 2>&1)
printf '%s\n' "$out" | grep -qx 'would  private      .local/state/spark-shell yours alone (0700)' && printf '%s\n' "$out" | grep -qx 'would  private      .config/spark-shell/themes yours alone (0700)' && [ "$(ls -ld "$HOME/.local/state/spark-shell" | cut -c1-10)" = drwxr-xr-x ] \
    && ok "on --dry-run: a state or themes folder open to others is a would row, nothing changed (#63)" || bad "private dry" "$(printf '%s\n' "$out" | grep private)"
out=$(L on --yes 2>&1)
printf '%s\n' "$out" | grep -qx 'ok     private      yours alone now (0700): .local/state/spark-shell .config/spark-shell/themes' && [ "$(ls -ld "$HOME/.local/state/spark-shell" | cut -c1-10)" = drwx------ ] && [ "$(ls -ld "$HOME/.config/spark-shell/themes" | cut -c1-10)" = drwx------ ] && [ "$(ls -ld "$H/shared" | cut -c1-10)" = drwxr-xr-x ] \
    && ok "on: the two made yours alone in one row; ~/notes as a link to a shared folder left as it is (#63)" || bad "private on" "$(printf '%s\n' "$out" | grep private; ls -ld "$HOME/.local/state/spark-shell" "$HOME/.config/spark-shell/themes" "$H/shared")"
out=$(L on --yes 2>&1); ! printf '%s\n' "$out" | grep -q 'private' && ok "on again: nothing to say about them" || bad "private again" "$(printf '%s\n' "$out" | grep private)"
rm -f "$HOME/notes"; rm -rf "$H/shared"

# macOS: the palette and the font are Terminal.app's profile, through the helper
fresh
console_stubs Darwin
palette_fixture test '#fe8019'
L theme test >/dev/null
grep -qx "python3 $REPO/lib/terminal.py apply $HOME/.config/spark/theme.env Menlo-Regular 13" "$H/log" && [ ! -e "$H/root/etc" ] \
    && ok "macOS: theme test runs the helper with theme.env, Menlo-Regular 13, no root file" || bad "mac theme" "$(cat "$H/log")"
: > "$H/log"; L theme test >/dev/null
[ "$(cat "$H/log")" = "python3 $REPO/lib/terminal.py has-profile" ] && ok "macOS: theme test again asks the helper, and leaves the profile alone" || bad "mac idempotent" "$(cat "$H/log")"
: > "$H/gone"; : > "$H/log"
ck=$(L check || true)
printf '%s\n' "$ck" | grep -q "^warn   theme        test: Terminal.app has no spark-shell profile -- spark-shell on$" && ok "macOS: check warns when the profile is gone, the stamp alone is not enough" || bad "mac check gone" "$(printf '%s\n' "$ck" | grep theme)"
L theme test >/dev/null
grep -qx "python3 $REPO/lib/terminal.py apply $HOME/.config/spark/theme.env Menlo-Regular 13" "$H/log" && ok "macOS: theme test imports the profile again when it is gone" || bad "mac reimport" "$(cat "$H/log")"
rm -f "$H/gone"
rc=0; out=$(SPARK_SHELL_MAC_FONTS="Menlo-Regular Monaco" L font VGA 14 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell font: no font named VGA is installed here (spark-shell font list shows them)" ] && ok "macOS: a face this Mac lacks is refused" || bad "mac font refused" "rc=$rc $out"
SPARK_SHELL_MAC_FONTS="Menlo-Regular Monaco" L font Monaco 14 >/dev/null
grep -qx "python3 $REPO/lib/terminal.py apply $HOME/.config/spark/theme.env Monaco 14" "$H/log" && ok "macOS: font Monaco 14 rewrites the profile" || bad "mac font" "$(cat "$H/log")"
rc=0; out=$(L quiet login on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet: macOS has no login notice or boot menu to quiet." ] && ok "macOS: quiet login on is one sentence" || bad "mac quiet" "rc=$rc $out"
: > "$H/stuck"; out=$(L theme none)
printf '%s\n' "$out" | grep -q '^todo   terminal     Terminal.app kept the profile' && [ -f "$HOME/.local/state/spark-shell/terminal.seen" ] \
    && ok "macOS: a remove that failed is a todo, and the stamp stays" || bad "mac remove stuck" "$out"
rm -f "$H/stuck"; : > "$H/log"; L theme none >/dev/null
grep -qx "python3 $REPO/lib/terminal.py remove" "$H/log" && [ ! -e "$HOME/.config/spark/theme.env" ] && [ ! -e "$HOME/.local/state/spark-shell/terminal.seen" ] \
    && ok "macOS: theme none removes the profile and theme.env" || bad "mac none" "$(cat "$H/log")"
rc=0; out=$(L theme -h 2>&1) || rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^  spark-shell theme NAME|none  ' && ok "theme -h: the help answers first" || bad "theme -h" "rc=$rc $out"

# --- the warning: on, on desktop and quiet boot on ask first -------------
# The question is asked at a terminal only; the suite has none, so it
# drives the answer through stdin with SPARK_SHELL_TEST_TTY set. A
# sudo stub logs every call: a refused or stopped run makes none.
fresh
console_stubs Linux
printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\n' "$H" > "$H/lx/sudo"; chmod +x "$H/lx/sudo"
warn_on='spark-shell replaces your shell files, installs packages
and changes the console colors. spark-shell on --dry-run
shows every change.

Continue? [y/N] spark-shell: nothing was changed.'
snap_a=$(mktemp); snap_b=$(mktemp)
snap > "$snap_a"
rc=0; out=$(L on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: no terminal and no --yes, one line, exit 1" || bad "warning no terminal" "rc=$rc $out"
rc=0; out=$(L apply </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: apply is on, the same line" || bad "warning apply" "rc=$rc $out"
printf 'ID=arch\n' > "$H/os-release"
rc=0; out=$(L on desktop </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: on desktop with no terminal, the same line" || bad "warning desktop no terminal" "rc=$rc $out"
rc=0; out=$(L desktop on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && ok "warning: desktop on is on desktop, the same line" || bad "warning desktop on" "rc=$rc $out"
printf 'ID=fixture\n' > "$H/os-release"
rc=0; out=$(printf 'n\n' | A on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "$warn_on" ] && ok "warning: on says what it changes and asks; n stops it (exit 1)" || bad "warning text" "rc=$rc $out"
rc=0; out=$(printf '\n' | A on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "$warn_on" ] && ok "warning: Enter alone is No" || bad "warning enter" "rc=$rc $out"
rc=0; out=$(A on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$(printf '%s\n' "$out" | tail -1)" = "spark-shell: nothing was changed." ] && ok "warning: no answer at all is No" || bad "warning eof" "rc=$rc $out"
snap > "$snap_b"
cmp -s "$snap_a" "$snap_b" && ok "warning: a refused or stopped on leaves HOME byte for byte as it was" || bad "warning HOME changed" "$(diff "$snap_a" "$snap_b" | head -5)"
rm -f "$snap_a" "$snap_b"
[ ! -e "$H/sudo.log" ] && ok "warning: a refused or stopped on asks sudo nothing" || bad "warning sudo" "$(cat "$H/sudo.log")"
# the desktop: the distro's PKG_DESKTOP, the login, Void's two lines
printf 'ID=arch\n' > "$H/os-release"
rc=0; out=$(printf 'n\n' | A on desktop 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell replaces your shell files, installs packages
and changes the console colors.
spark-shell on desktop --dry-run shows every change.

spark-shell changes how this machine works:

  packages     sway swaybg foot foot-terminfo ttf-dejavu curl openssh swayidle
               swaylock grim slurp wl-clipboard brightnessctl ddcutil librsvg
               poppler otf-monaspace mako libnotify udisks2 xdg-desktop-portal
               xdg-desktop-portal-wlr xdg-desktop-portal-gtk
               gsettings-desktop-schemas bluez bluez-utils python-dbus
               python-gobject xorg-xwayland xorg-xrandr mpv mesa python-numpy
               pipewire wireplumber pipewire-pulse pipewire-alsa (sudo)
  login        logging in on tty1 starts the desktop
               Alt+F2 is a plain shell

spark-shell off desktop puts the login back.
Packages stay.

On Arch, missing packages require a full system upgrade; pacman asks first.

Continue? [y/N] spark-shell: nothing was changed." ] && ok "warning: on desktop names the packages (the desktop's with Arch's font, then the sound's), the login and the way back" || bad "warning desktop" "rc=$rc $out"
[ ! -e "$HOME/.config/spark-shell/config" ] && [ ! -e "$H/sudo.log" ] && ok "warning: a stopped on desktop writes nothing, no sudo" || bad "warning desktop wrote" "$(cat "$HOME/.config/spark-shell/config" 2>&1)"
printf 'ID=void\n' > "$H/os-release"
rc=0; out=$(printf 'n\n' | A on desktop 2>&1) || rc=$?
printf '%s\n' "$out" | grep -qx '  groups       adds you to _seatd and audio (sudo)' && printf '%s\n' "$out" | grep -qx '  services     turns on seatd at boot (sudo)' \
    && printf '%s\n' "$out" | grep -qx '  sound        PipeWire starts with the desktop, and ALSA programs play through' && printf '%s\n' "$out" | grep -qx '               it (sudo)' \
    && printf '%s\n' "$out" | grep -qx '  power        lets you suspend, restart and shut down, nothing else (sudo)' && printf '%s\n' "$out" | grep -qx '  drives       lets you mount and eject USB drives (polkit, sudo)' \
    && ok "warning: on desktop on Void adds the _seatd and audio groups, the seatd service, says PipeWire starts with the desktop, and names the power and the drives' rules" || bad "warning void" "rc=$rc $out"
mkdir -p "$HOME/.config/spark/sv"
rc=0; out2=$(printf 'n\n' | A on desktop 2>&1) || rc=$?
printf '%s\n' "$out2" | grep -qxF "  sound        PipeWire runs from boot, under spark's supervisor, and ALSA" && printf '%s\n' "$out2" | grep -qxF '               programs play through it (sudo)' \
    && ok "warning: on desktop on Void with spark's supervisor says PipeWire runs from boot" || bad "warning void boot" "rc=$rc $out2"
rm -rf "$HOME/.config/spark/sv"
pk=$(sed -n 's/^PKG_DESKTOP=//p' "$REPO/distro/void.env")
if [ -n "$pk" ]; then printf '%s\n' "$out" | grep -q "^  packages     ${pk%% *} " && ok "warning: Void's PKG_DESKTOP named" || bad "warning void packages" "$out"
else printf '%s\n' "$out" | grep -q '^  packages' && bad "warning: a packages row with no PKG_DESKTOP" "$out" || ok "warning: no PKG_DESKTOP, no packages row"; fi
rc=0; out=$(printf 'n\n' | PKG_DESKTOP="$(printf 'pkg%s ' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17)" PKG_SOUND=pkg18 SPARK_SHELL_TEST_TTY=1 PATH=$H/lx:$PATH sh "$SH" on desktop 2>&1) || rc=$?
[ "$(printf '%s\n' "$out" | awk 'length > 79' | wc -l | tr -d ' ')" = 0 ] && [ "$(printf '%s\n' "$out" | grep -c '^               pkg')" -ge 1 ] && printf '%s\n' "$out" | grep -q 'pkg18 (sudo)$' \
    && ok "warning: a long package list wraps under its column, within 80" || bad "warning wrap" "$out"
# y and --yes go ahead; --dry-run never asks
printf 'ID=fixture\n' > "$H/os-release"
rc=0; out=$(printf 'y\n' | A on 2>&1) || rc=$?
[ "$rc" = 0 ] && [ -L "$HOME/.bashrc" ] && printf '%s\n' "$out" | grep -q '^Continue? \[y/N\] ' && ok "warning: y goes ahead" || bad "warning y" "rc=$rc $out"
rm -f "$H/sudo.log"
fresh
console_stubs Linux
rc=0; out=$(L on --yes </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && [ -L "$HOME/.bashrc" ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: --yes goes ahead with no terminal, no question" || bad "warning --yes" "rc=$rc $out"
rc=0; out=$(L on --dry-run </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: on --dry-run never asks" || bad "warning dry-run" "rc=$rc $out"
printf 'ID=arch\n' > "$H/os-release"
rc=0; out=$(L on desktop --dry-run </dev/null 2>&1) || rc=$?
printf 'ID=fixture\n' > "$H/os-release"
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: on desktop --dry-run never asks" || bad "warning desktop dry-run" "rc=$rc $out"
# off, follow, theme and quiet login never ask
rc=0; out=$(L off </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: off never asks" || bad "warning off" "rc=$rc $out"
rc=0; out=$(L off desktop </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: off desktop never asks" || bad "warning off desktop" "rc=$rc $out"
L on --yes >/dev/null
theme_fixture '#55ff55'
rc=0; out=$(printf 'n\n' | A follow 2>&1) || rc=$?
[ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^spark-shell: [0-9]* files updated for the new palette\.$' && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' \
    && ok "warning: follow (the login profile) never asks, even at a terminal" || bad "warning follow" "rc=$rc $out"
rc=0; out=$(L theme none </dev/null 2>&1) || rc=$?
! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: theme never asks" || bad "warning theme" "rc=$rc $out"
printf 'ID=debian\n' > "$H/os-release"
rc=0; out=$(L quiet login on </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: quiet login on never asks" || bad "warning quiet login" "rc=$rc $out"
# quiet boot on asks; quiet boot off does not
mkdir -p "$H/root/etc/default"; printf 'GRUB_TIMEOUT=5\n' > "$H/root/etc/default/grub"
rc=0; out=$(L quiet boot on </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell: no terminal to ask on -- add --yes to go ahead" ] && [ ! -e "$H/root/etc/default/grub.d" ] && ok "warning: quiet boot on with no terminal, one line, nothing written" || bad "warning boot no terminal" "rc=$rc $out"
rc=0; out=$(printf 'n\n' | A quiet boot on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell quiet boot on changes how this machine starts:
the boot menu is hidden, and the kernel and init are silent.
It adds a GRUB settings file and runs update-grub (sudo).
spark-shell quiet boot off puts it back.

Continue? [y/N] spark-shell: nothing was changed." ] && [ ! -e "$H/root/etc/default/grub.d" ] && ! grep -q 'QUIET_BOOT=yes' "$HOME/.config/spark-shell/config" \
    && ok "warning: quiet boot on names what it changes and asks; n stops it" || bad "warning boot text" "rc=$rc $out"
rc=0; out=$(L quiet boot on --dry-run </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: quiet boot on --dry-run never asks" || bad "warning boot dry-run" "rc=$rc $out"
rc=0; out=$(printf 'yes\n' | A quiet boot on 2>&1) || rc=$?
[ "$rc" = 0 ] && [ -e "$H/root/etc/default/grub.d/zz-spark-shell-quiet.cfg" ] && ok "warning: quiet boot on, yes goes ahead" || bad "warning boot yes" "rc=$rc $out"
rc=0; out=$(L quiet boot off </dev/null 2>&1) || rc=$?
[ "$rc" = 0 ] && ! printf '%s\n' "$out" | grep -q 'Continue?\|no terminal' && ok "warning: quiet boot off never asks" || bad "warning boot off" "rc=$rc $out"
# macOS: the Terminal.app colors, and the font
fresh
console_stubs Darwin
rc=0; out=$(printf 'n\n' | A on 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell replaces your shell files, installs packages and
a font, and changes the Terminal.app colors and font.
spark-shell on --dry-run shows every change.

Continue? [y/N] spark-shell: nothing was changed." ] && ok "warning (macOS): the font, the Terminal.app colors and font" || bad "warning mac" "rc=$rc $out"

fi

# --- 20. the bar at the top of the screen --------------------------------
if want 20; then
# a fixture tree in place of /sys and /proc (SPARK_SHELL_SYS, SPARK_SHELL_PROC),
# stubs for ip, bluetoothctl and amixer (wpctl and pactl stubs that fail, so
# plain ALSA is the audio system), jq the real one. The theme fixture's
# accent is #ff5555, its muted #555555, its red #aa0000. The Linux half is
# guarded by uname like 14.
full=$(printf '\342\226\210')
fresh
desktop_stubs
layout_stubs
bar_fixture
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
sh "$SH" on --yes >/dev/null
sway=$HOME/.config/sway/config; amlog=$H/.local/state/amixer.log
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" bar status --once 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: not on macOS, which has its own desktop' ] && ok "macOS: bar status refuses, na, one line, exit 1" || bad "macOS bar status" "st=$st $out"
    st=0; out=$(sh "$SH" bar --desktop 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: no desktop here (spark-shell on desktop)' ] && ok "macOS: bar --desktop refuses, one line" || bad "macOS bar --desktop" "st=$st $out"
    st=0; out=$(sh "$SH" bar 2>&1) || st=$?
    [ "$st" -eq 0 ] && ok "macOS: bare bar exits 0 (the status line's state, or that tmux is not running)" || bad "macOS bar" "st=$st $out"
else
    # the render: the bar block from the config, the palette's hex, the font in pango's words
    grep -q '^bar {$' "$sway" && grep -q '^    position top$' "$sway" && grep -q "^    status_command $REPO/spark-shell bar status\$" "$sway" && grep -q '^    mode dock$' "$sway" \
        && ok "sway: a bar at the top, dock mode, drawn by the clone's spark-shell bar status" || bad "sway bar render" "$(grep -n 'bar {\|position\|status_command\|mode ' "$sway")"
    grep -q '^    font pango:DejaVu Sans Mono 12$' "$sway" && ok "sway: the bar's font is FONT in pango's words (DejaVu Sans Mono 12)" || bad "bar font" "$(grep -n 'font' "$sway")"
    grep -q '^        background #000000f2$' "$sway" && grep -q '^        focused_workspace #ff5555 #ff5555 #000000$' "$sway" && grep -q '^        inactive_workspace #000000f2 #000000f2 #555555$' "$sway" \
        && ok "sway: the bar's colors are the palette's, the background with the picture's alpha (f2 = 0.95)" || bad "bar colors" "$(grep -n 'background\|_workspace' "$sway")"
    grep -q "^bindsym XF86AudioRaiseVolume exec $REPO/spark-shell bar volume up\$" "$sway" && grep -q "^bindsym XF86AudioMicMute exec $REPO/spark-shell bar volume mic\$" "$sway" \
        && ok "sway: the volume keys and the mic mute key run spark-shell bar volume" || bad "volume keys" "$(grep -n XF86 "$sway")"
    ! grep -q 'mod+p ' "$sway" && grep -q '^for_window \[app_id="spark-dialog"\] floating enable, border none, move position center, opacity 0$' "$sway" \
        && ok "sway: no Super+p any more; the dialog's window floats in the middle, unseen until its opening is drawn (#167)" || bad "panel key" "$(grep -n 'spark-dialog\|mod+p' "$sway")"
    printf 'DESKTOP=sway\nFONT=Test Mono:pixelsize=14\nWALLPAPER=none\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    grep -q '^    font pango:Test Mono 14px$' "$sway" && grep -q '^        background #000000f2$' "$sway" && ok "sway: a pixelsize font is Npx in pango; none is the ground, the bar as translucent as over any wallpaper" || bad "bar font px" "$(grep -n 'font\|background' "$sway")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" on --yes >/dev/null
    # one line: every block present, in its group, groups parted by air
    st=0; line=$(sh "$SH" bar status --once 2>&1) || st=$?
    names=$(printf '%s' "$line" | jq -r '[.[] | .name + ":" + .instance] | join(" ")' 2>/dev/null || :)
    [ "$st" -eq 0 ] && [ "$names" = 'lan: bt: wifi:name wifi:gauge out:name out:gauge mic:name mic:gauge bat: clock: logo:' ] \
        && ok "bar status --once: lan, bt, wifi (sign, gauge) | out (sign, gauge), mic (sign, gauge) | bat | clock, one JSON array; no theme block (the palette is the panel's)" || bad "bar line" "st=$st $names $line"
    printf '%s' "$line" | jq -e 'all(.[]; .markup == "pango" and .separator == false)' >/dev/null 2>&1 && ok "bar: every block is pango markup with swaybar's own separator off" || bad "bar markup" "$line"
    t() { printf '%s' "$line" | jq -r --arg n "$1" --arg i "${2:-}" '.[] | select(.name == $n and .instance == $i) | .full_text'; }   # t NAME [INSTANCE] -> its text
    pip=$(printf '\342\226\260'); pipoff=$(printf '\342\226\261')
    cur() { sh "$SH" bar panel "$1" --list 2>&1 | sed -n 1p | tr 'A-Z' 'a-z'; }   # cur out|mic -> the panel's title, the device in use: the bar shows its sign alone
    [ "$(t lan)" = "<span foreground='#ff5555'>$(printf '\342\207\205')</span>" ] && ok "lan: the arrows alone, in the accent, when the wire is up (no address on screen)" || bad "lan block" "$(t lan)"
    [ "$(t wifi name)" = "<span foreground='#ff5555'>$(printf '\342\227\240')</span>" ] && g=$(t wifi gauge) && [ "$(count "$g" "$pip")" = 4 ] && [ "$(count "$g" "$pipoff")" = 1 ] && printf '%s' "$g" | grep -q "^<span foreground='#ff5555'>" && ! printf '%s' "$line" | grep -q '192\.' \
        && ok "wifi joined: the half circle in the accent, then a gauge as sound's, 4 of 5 cells in the accent at 49/70 (70%); no address" || bad "wifi block" "$(t wifi name) $(t wifi gauge)"
    [ "$(t bt)" = "<span foreground='#ff5555'>$(printf '\342\234\246')</span>" ] && ok "bt: a device connected, the star in the accent; its name is the panel's" || bad "bt block" "$(t bt)"
    [ "$(t out name)" = "<span foreground='#ff5555'>$(printf '\342\227\200')</span>" ] && ok "out: the speaker's triangle, filled and in the accent while it plays" || bad "out name" "$(t out name)"
    g=$(t out gauge); [ "$(count "$g" "$pip")" = 2 ] && [ "$(count "$g" "$pipoff")" = 3 ] && printf '%s' "$g" | grep -q "^<span foreground='#ff5555'>" \
        && ok "out: the gauge is 5 cells, 2 lit in the accent at 40%, 3 unlit muted" || bad "out gauge" "$g"
    [ "$(t mic name)" = "<span foreground='#ff5555'>$(printf '\342\227\211')</span>" ] && ok "mic: the fisheye in the accent while it is open" || bad "mic block" "$(t mic name)"
    g=$(t mic gauge); [ "$(count "$g" "$pip")" = 3 ] && [ "$(count "$g" "$pipoff")" = 2 ] && printf '%s' "$g" | grep -q "^<span foreground='#ff5555'>" \
        && ok "mic: its own gauge, 3 of 5 cells in the accent at 50% (the Capture level)" || bad "mic gauge" "$g"
    [ "$(t bat)" = "<span foreground='#aaaaaa'>$pip$pip$pip</span><span foreground='#555555'>$pipoff</span> <span foreground='#aaaaaa'>80</span>" ] && ok "bat: four cells, three lit, and the number in the text color" || bad "bat block" "$(t bat)"
    printf '%s' "$(t clock)" | grep -Eq "^<span foreground='#555555'>[A-Za-z]+ [0-9]{2} [A-Za-z]+</span> [0-9]{2}:[0-9]{2}$" && ok "clock: the date muted, the time in the text color" || bad "clock block" "$(t clock)"
    printf '%s' "$(t logo)" | grep -Eq "^<span foreground='#[0-9a-f]{6}'>$(printf '\342\235\257')</span>$" && ok "logo: spark-shell's sign, the prompt sign in the palette's yellow, one cell" || bad "logo block" "$(t logo)"
    [ "$(printf '%s' "$line" | jq -r '[.[] | select(.separator_block_width == 28) | .name + ":" + .instance] | join(" ")')" = 'wifi:gauge mic:gauge bat: logo:' ] && [ "$(printf '%s' "$line" | jq -r '[.[] | select(.name == "div")] | length')" = 0 ] && [ "$(printf '%s' "$line" | jq -r '.[-1].name')" = logo ] \
        && ok "bar: no dividers, each group's last block takes 28 px of air, the sign last" || bad "group air" "$line"
    LC_ALL=C grep -q "[^ -~${tab}]" "$SRC" && bad "the script holds a byte outside ASCII (the glyphs must be built from their bytes)" || ok "the script stays ASCII: the glyphs are built from their bytes"
    # the states: mute, a recording mic, a low battery, a charging one, sound on another card
    touch "$H/muted"; line=$(sh "$SH" bar status --once)
    g=$(t out gauge); [ "$(count "$g" "'#ff5555'")" = 0 ] && [ "$(count "$g" "$pip")" = 2 ] && [ "$(t out name)" = "<span foreground='#555555'>$(printf '\342\227\201')</span>" ] && ok "out muted: the triangle turns hollow, the level stays, the whole gauge turns muted" || bad "muted gauge" "$(t out name) $g"
    rm -f "$H/muted"
    touch "$H/cmuted"; line=$(sh "$SH" bar status --once)
    g=$(t mic gauge); [ "$(t mic name)" = "<span foreground='#555555'>$(printf '\342\227\213')</span>" ] && [ "$(count "$g" "'#ff5555'")" = 0 ] && ok "mic muted: the ring turns hollow and muted, its gauge muted" || bad "mic muted" "$(t mic name) $g"
    rm -f "$H/cmuted"
    echo 'state: RUNNING' > "$P/asound/card0/pcm0c/sub0/status"; line=$(sh "$SH" bar status --once)
    [ "$(t mic name)" = "<span foreground='#aa0000'>$(printf '\342\227\217')</span>" ] && ok "mic recording: a red dot" || bad "mic live" "$(t mic name)"
    echo closed > "$P/asound/card0/pcm0c/sub0/status"
    echo 10 > "$S/class/power_supply/BAT0/capacity"; line=$(sh "$SH" bar status --once)
    [ "$(t bat)" = "<span foreground='#aa0000'>$pip</span><span foreground='#555555'>$pipoff$pipoff$pipoff</span> <span foreground='#aa0000'>10</span>" ] && ok "bat under 15: one cell and the number, red" || bad "bat low" "$(t bat)"
    echo Charging > "$S/class/power_supply/BAT0/status"; line=$(sh "$SH" bar status --once)
    [ "$(t bat)" = "<span foreground='#aaaaaa'>$pip</span><span foreground='#555555'>$pipoff$pipoff$pipoff</span> <span foreground='#aaaaaa'>10</span><span foreground='#ff5555'>+</span>" ] && ok "bat charging: a plus in the accent, and no red while it charges" || bad "bat charging" "$(t bat)"
    echo 80 > "$S/class/power_supply/BAT0/capacity"; echo Discharging > "$S/class/power_supply/BAT0/status"
    echo 'state: RUNNING' > "$P/asound/card1/pcm0p/sub0/status"; line=$(sh "$SH" bar status --once)
    [ "$(t out name)" = "<span foreground='#ff5555'>$(printf '\342\227\200')</span>" ] && [ -z "$(t out gauge)" ] && ok "sound playing on the HDMI card: out follows it; no volume control there, so no gauge" || bad "out follows" "$(t out name) / $(t out gauge)"
    echo closed > "$P/asound/card1/pcm0p/sub0/status"
    touch "$H/bt-none"; line=$(sh "$SH" bar status --once)
    [ "$(t bt)" = "<span foreground='#555555'>$(printf '\342\234\246')</span>" ] && ok "bt with nothing connected: the star alone, muted" || bad "bt idle" "$(t bt)"
    rm -f "$H/bt-none"
    echo 0 > "$S/class/net/eth0/carrier"; line=$(sh "$SH" bar status --once)
    [ "$(t lan)" = "<span foreground='#aa0000'>$(printf '\342\207\205') $(printf '\342\232\240')</span>" ] && ok "lan with no carrier: the arrows and a warning sign, in red" || bad "lan down" "$(t lan)"
    echo 1 > "$S/class/net/eth0/carrier"
    echo down > "$S/class/net/wlan0/operstate"; line=$(sh "$SH" bar status --once)
    [ "$(t wifi name)" = "<span foreground='#555555'>$(printf '\342\227\240')</span>" ] && [ -z "$(t wifi gauge)" ] && ok "wifi off: the half circle alone, muted, no gauge" || bad "wifi off" "$(t wifi name) / $(t wifi gauge)"
    echo up > "$S/class/net/wlan0/operstate"
    # the words set (#160): the kind words where the signs were, in the colors the signs take (the accent for what is on and
    # connected), the gauges as they were, the battery its word and its number
    printf 'BAR_GLYPHS=words\n' >> "$HOME/.config/spark-shell/config"; line=$(sh "$SH" bar status --once)
    [ "$(t lan)" = "<span foreground='#ff5555'>lan</span>" ] && [ "$(t bt)" = "<span foreground='#ff5555'>bt</span>" ] && [ "$(t wifi name)" = "<span foreground='#ff5555'>wifi</span>" ] \
        && [ "$(t out name)" = "<span foreground='#ff5555'>out</span>" ] && [ "$(t mic name)" = "<span foreground='#ff5555'>mic</span>" ] && [ -n "$(t out gauge)" ] && [ -n "$(t wifi gauge)" ] \
        && [ "$(t bat)" = "<span foreground='#555555'>bat</span> <span foreground='#aaaaaa'>80</span>" ] \
        && ok "bar in words (#160): lan, bt, wifi, out and mic as words, each in the accent while on and connected; the gauges as before; the battery its word and number" || bad "bar words" "$line"
    sed -i.bak '/^BAR_GLYPHS=/d' "$HOME/.config/spark-shell/config"; rm -f "$HOME/.config/spark-shell/config.bak"
    # present-only: a machine with none of it shows the clock alone, and no divider
    mv "$S" "$S.full"; mv "$P" "$P.full"; mkdir -p "$S" "$P"
    line=$(sh "$SH" bar status --once)
    [ "$(printf '%s' "$line" | jq -r '[.[] | .name] | join(" ")')" = 'clock logo' ] && ok "present-only: no hardware, no block for it and no divider; the clock and the sign alone" || bad "bare machine" "$line"
    rm -rf "$S" "$P"; mv "$S.full" "$S"; mv "$P.full" "$P"
    # clicks: swaybar's stream on stdin; the gauges set the levels, any other block opens the panel; each redraws the bar at once
    rm -f "$amlog" "$H/.local/state/foot.log"
    printf '[\n,{"name":"out","instance":"gauge","button":1,"relative_x":60,"width":100}\n,{"name":"out","instance":"gauge","button":4}\n,{"name":"out","instance":"gauge","button":3}\n,{"name":"mic","instance":"gauge","button":3}\n,{"name":"mic","instance":"gauge","button":1,"relative_x":30,"width":100}\n,{"name":"out","instance":"name","button":1,"x":1500,"relative_x":12,"width":90}\n,{"name":"lan","instance":"","button":1,"x":1200,"relative_x":5,"width":40}\n' > "$H/clicks"
    # Send clicks after the initial frame. Feeding a completed file at startup
    # can coalesce every signal into that first frame on a busy CI runner.
    mkfifo "$H/bar-clicks"
    sh "$SH" bar status < "$H/bar-clicks" > "$H/bar.out" 2> "$H/bar.err" & bp=$!
    exec 8> "$H/bar-clicks"
    for _i in $(seq 1 100); do
        [ "$(grep -c '^\[{' "$H/bar.out")" -ge 1 ] && break
        sleep .1
    done
    cat "$H/clicks" >&8
    exec 8>&-
    for _i in $(seq 1 100); do
        [ "$(grep -c '^\[{' "$H/bar.out")" -ge 2 ] && [ "$(wc -l < "$amlog" 2>/dev/null || echo 0)" -ge 5 ] && [ "$(wc -l < "$H/.local/state/foot.log" 2>/dev/null || echo 0)" -ge 2 ] && break
        sleep .1
    done
    kill "$bp" 2>/dev/null || :; wait "$bp" 2>/dev/null || :
    head -1 "$H/bar.out" | grep -q '^{"version":1,"click_events":true}$' && [ "$(sed -n 2p "$H/bar.out")" = '[' ] && ok "bar status: the i3bar header asks for clicks, then the array opens" || bad "bar header" "$(head -2 "$H/bar.out")"
    [ "$(grep -c '^\[{' "$H/bar.out")" -ge 2 ] && ok "bar status: one line at start, and the bar drawn again after the clicks (quick clicks share one redraw)" || bad "bar redraws" "$(grep -c '^\[{' "$H/bar.out") lines; $(cat "$H/bar.err")"
    [ "$(cat "$amlog" 2>/dev/null)" = "$(printf '%s\n' '-c 0 sset Master 60%' '-c 0 sset Master 5%+' '-c 0 sset Master toggle' '-c 0 sset Capture toggle' '-c 0 sset Capture 30%')" ] \
        && ok "clicks: a click at 60% of the gauge sets 60%, the wheel up adds 5, a right click mutes; the mic gauge mutes on a right click and sets 30% on a click" || bad "click actions" "$(cat "$amlog" 2>&1)"
    for _i in 1 2 3 4 5 6; do [ "$(wc -l < "$H/.local/state/foot.log" 2>/dev/null || echo 0)" -ge 2 ] && break; sleep 1; done   # two detached openers write the log
    [ "$(sort "$H/.local/state/foot.log" 2>/dev/null | grep -v '^--version')" = "$(printf '%s\n' "--config $HOME/.config/foot/dialog.ini --app-id spark-dialog -e $REPO/spark-shell dialog lan | " "--config $HOME/.config/foot/dialog.ini --app-id spark-dialog -e $REPO/spark-shell dialog out | ")" ] \
        && ok "a click on out or lan opens the panel with that block first, in a foot window; no placement passed" || bad "panel open" "$(cat "$H/.local/state/foot.log" 2>&1); $(cat "$H/bar.err")"
    ! tail -1 "$H/bar.out" | grep -q '192\.0\.2\.' && ok "a click never puts an address in the bar" || bad "address in the bar" "$(tail -1 "$H/bar.out")"
    [ ! -e "$H/.local/state/spark-shell/bar.pid" ] && ok "bar status ended: its pid file is gone" || bad "bar pid file stays"
    # the volume keys reach the running bar (the default card back to the first: the asoundrc the click wrote is gone)
    rm -f "$amlog" "$H/.config/alsa/asoundrc"
    sh "$SH" bar status < /dev/null > "$H/bar.out" 2> "$H/bar.err" & bp=$!
    sleep 1
    sh "$SH" bar volume up; sleep 1; sh "$SH" bar volume mute; sleep 1; sh "$SH" bar volume mic
    sleep 1
    kill "$bp" 2>/dev/null || :; wait "$bp" 2>/dev/null || :
    [ "$(cat "$amlog" 2>/dev/null)" = "$(printf '%s\n' '-c 0 sset Master 5%+' '-c 0 sset Master toggle' '-c 0 sset Capture toggle')" ] && [ "$(grep -c '^\[{' "$H/bar.out")" -ge 3 ] \
        && ok "bar volume up|mute|mic: the key's change, and the running bar redrawn after each" || bad "volume keys" "$(cat "$amlog" 2>&1); $(grep -c '^\[{' "$H/bar.out") lines"
    st=0; out=$(sh "$SH" bar volume louder 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: volume takes up, down, mute or mic' ] && ok "bar volume: a wrong word is refused in one line" || bad "volume refuse" "st=$st $out"
    rm -f "$HOME/level" "$HOME/clevel"   # restore this fixture's baseline after the volume-key tests
    # the out page switches the card: ALSA's default for new programs, in spark-shell's own marked file, the ! form alsa.conf takes for a name
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'out HDMI for programs started from now' ] && [ "$(sed -n '2,3p' "$H/.config/alsa/asoundrc" 2>/dev/null | paste -sd ' ' -)" = 'defaults.pcm.!card HDMI defaults.ctl.!card HDMI' ] && head -1 "$H/.config/alsa/asoundrc" | grep -q '^# rendered by spark-shell' \
        && ok "bar panel out use hdmi: the HDMI card becomes ALSA's default for new programs, in spark-shell's own marked file, the ! form" || bad "asoundrc" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    rm -f "$H/.config/alsa/asoundrc"
    # a file of yours is never written over
    printf 'pcm.!default { type hw card 1 }\n' > "$H/.config/alsa/asoundrc"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'asoundrc is yours' ] && [ "$(cat "$H/.config/alsa/asoundrc")" = 'pcm.!default { type hw card 1 }' ] \
        && ok "out use with an asoundrc of yours: the file stays, one line says so" || bad "asoundrc yours" "st=$st $out; $(cat "$H/.config/alsa/asoundrc")"
    rm -f "$H/.config/alsa/asoundrc"
    # a file ALSA refuses would take every program's sound with it: taken back at once, one line says so
    touch "$H/amixer-refuse"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'ALSA refused the file' ] && [ ! -e "$H/.config/alsa/asoundrc" ] \
        && ok "out use when ALSA refuses the file: the file is taken back, one line says so" || bad "asoundrc refused" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    rm -f "$H/amixer-refuse"
    # the file v0.45 wrote (the card by name without !) is mended when the bar starts, and read
    printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.card HDMI\ndefaults.ctl.card HDMI\n' > "$H/.config/alsa/asoundrc"
    line=$(sh "$SH" bar status --once)
    [ "$(sed -n '2,3p' "$H/.config/alsa/asoundrc" | paste -sd ' ' -)" = 'defaults.pcm.!card HDMI defaults.ctl.!card HDMI' ] && head -1 "$H/.config/alsa/asoundrc" | grep -q '^# rendered by spark-shell' && cur out | grep -q hdmi \
        && ok "bar status: a file v0.45 wrote is mended to the ! form at the start, and out reads it (hdmi)" || bad "asoundrc mend" "$(cat "$H/.config/alsa/asoundrc"); $(cur out)"
    rm -f "$H/.config/alsa/asoundrc"
    # Bluetooth on plain ALSA (issue 6): bluez-alsa's devices beside the cards, a pick routed through spark-shell's file, its level bluez-alsa's mixer
    touch "$HOME/bt-audio"; rm -f "$amlog"
    out=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://out/rows"}}' | sh "$SH" provide out 2>/dev/null)
    printf '%s\n' "$out" | jq -r 'select(.id == 2) | .result.contents[0].text' | jq -e '[.rows[] | .text] | index("MAJOR V") != null and index("Crafted") == null' >/dev/null \
        && ok "out on plain ALSA: a headset bluez-alsa offers is a row beside the cards; a device whose address is no address is not" || bad "bt out row" "$(printf '%s\n' "$out" | tail -2 | cut -c1-400)"
    st=0; out=$(sh "$SH" bar panel out use major v 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'out MAJOR V for programs started from now' ] && grep -qxF '    playback.pcm { type plug slave.pcm "bluealsa:DEV=00:25:D1:4A:C2:AA,PROFILE=a2dp" }' "$H/.config/alsa/asoundrc" \
        && grep -qxF '    capture.pcm "sysdefault"' "$H/.config/alsa/asoundrc" && grep -qx '# bluetooth out: MAJOR V' "$H/.config/alsa/asoundrc" && head -1 "$H/.config/alsa/asoundrc" | grep -q '^# rendered by spark-shell' \
        && ok "out use a headset: playing goes through bluez-alsa's A2DP for programs started from now, listening stays the card's, in spark-shell's own file" || bad "bt out use" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    line=$(sh "$SH" bar status --once)
    [ "$(t out name)" = "<span foreground='#ff5555'>$(printf '\342\227\200')</span>" ] && cur out | grep -q 'major v' && sh "$SH" bar panel out level 35 >/dev/null && sh "$SH" bar panel out mute >/dev/null \
        && [ "$(cat "$amlog")" = "$(printf '%s\n' '-D bluealsa sset MAJOR V - A2DP 35%' '-D bluealsa sset MAJOR V - A2DP mute')" ] \
        && ok "out on a headset: the panel names it, and the level and mute are bluez-alsa's mixer" || bad "bt out level" "$(t out name) $(cur out); $(cat "$amlog" 2>&1)"
    rm -f "$amlog" "$HOME/bmuted"
    st=0; out=$(sh "$SH" bar panel mic use major v 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qxF '    capture.pcm { type plug slave.pcm "bluealsa:DEV=00:25:D1:4A:C2:AA,PROFILE=sco" }' "$H/.config/alsa/asoundrc" && grep -q 'PROFILE=a2dp' "$H/.config/alsa/asoundrc" \
        && sh "$SH" bar panel mic mute >/dev/null && [ "$(cat "$amlog")" = '-D bluealsa sset MAJOR V - SCO nocap' ] \
        && ok "mic use a headset: listening on its hands-free link, playing kept; the mute is the SCO capture switch" || bad "bt mic" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1); $(cat "$amlog" 2>&1)"
    rm -f "$HOME/bcmuted"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    [ "$st" -eq 0 ] && ! grep -q 'PROFILE=a2dp' "$H/.config/alsa/asoundrc" && grep -q 'PROFILE=sco' "$H/.config/alsa/asoundrc" && grep -qx 'defaults.pcm.!card HDMI' "$H/.config/alsa/asoundrc" \
        && ok "out use a card after a headset: playing back on the card, the headset's mic kept" || bad "bt back to card" "st=$st $out; $(cat "$H/.config/alsa/asoundrc" 2>&1)"
    rm -f "$HOME/bt-audio"
    cur mic | grep -q 'major v' \
        && ok "a headset gone: the panel still names the device the file sends listening to" || bad "bt gone" "$(cur mic)"
    rm -f "$H/.config/alsa/asoundrc"
    # your own ~/.asoundrc setting the default (here through a file it includes): spark-shell says so and writes nothing
    mkdir -p "$HOME/.config/box"; printf 'pcm.!default { type hw card 1 }\n' > "$HOME/.config/box/box.conf"; printf '<~/.config/box/box.conf>\n' > "$HOME/.asoundrc"
    st=0; out=$(sh "$SH" bar panel out use hdmi 2>&1) || st=$?
    # shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: ~/.config/box/box.conf picks the sound device, read by your ~/.asoundrc: spark-shell leaves it to that file' ] && [ ! -e "$H/.config/alsa/asoundrc" ] \
        && ok "out use when your own ~/.asoundrc sets the default, through a file it includes: one line names that file, nothing written" || bad "asoundrc theirs" "st=$st $out"
    rows=$(sh "$SH" bar panel out --list 2>&1 | cut -f3 | sed -n '/^out /p')
    # shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
    ! printf '%s\n' "$rows" | grep -q '^out use ' && sh "$SH" bar panel out --list 2>&1 | grep -q '~/.config/box/box.conf picks the sound device, read by your ~/.asoundrc' \
        && ok "out rows when your own file picks the device: the devices shown with no pick that could only be refused, and one row names the file" || bad "asoundrc theirs rows" "$rows"
    rm -rf "$HOME/.asoundrc" "$HOME/.config/box"
    # PipeWire: the same bar through wpctl (the stub answers as WirePlumber 0.5 does), the volume keys and a pick of output
    wplog=$H/.local/state/wpctl.log; rm -f "$wplog"
    cat > "$H/.local/bin/wpctl" <<'STUB'
#!/bin/sh
log=${XDG_STATE_HOME:-$HOME/.local/state}/wpctl.log; mkdir -p "$(dirname "$log")"
[ ! -e "$HOME/wp-down" ] || { echo 'Could not connect to PipeWire' >&2; exit 1; }
sink=$(cat "$HOME/wp-sink" 2>/dev/null || echo 50)
V=$(printf '\342\224\202'); T=$(printf '\342\224\234\342\224\200'); E=$(printf '\342\224\224\342\224\200')   # the tree wpctl draws, built from its bytes
s50=' '; s51=' '; [ "$sink" = 50 ] && s50='*' || s51='*'
case "$1" in
    status) printf '%s\n' "PipeWire 'pipewire-0' [1.6.8, ada@box, cookie:1]" " $E Clients:" '        33. WirePlumber                         [1.6.8, ada@box, pid:900]' '' 'Audio' " $T Devices:" "  $V      46. Jabra SPEAK 410 USB                 [alsa]" "  $V      47. Built-in Audio                      [alsa]" "  $V  " \
            " $T Sinks:" " $V  $s50   50. Jabra SPEAK 410 USB Analog Stereo   [vol: 0.40]" " $V  $s51   51. Built-in Audio Digital Stereo (HDMI) [vol: 1.00]" " $V  " " $T Sources:" " $V  *   52. Jabra SPEAK 410 USB Mono            [vol: 0.50]" " $V  " " $T Filters:" " $V  " " $E Streams:" '' 'Video' " $T Devices:" " $V  " " $T Sinks:" " $V  " " $E Sources:" ;;
    get-volume) case $2 in *SINK*) v=0.40; f=$HOME/wp-muted ;; *) v=0.50; f=$HOME/wp-cmuted ;; esac
        if [ -e "$f" ]; then echo "Volume: $v [MUTED]"; else echo "Volume: $v"; fi ;;
    set-default) echo "$*" >> "$log"; echo "$2" > "$HOME/wp-sink" ;;
    set-mute) echo "$*" >> "$log"; f=$HOME/wp-muted; case $2 in *SOURCE*) f=$HOME/wp-cmuted ;; esac
        case $3 in 1) touch "$f" ;; 0) rm -f "$f" ;; toggle) if [ -e "$f" ]; then rm -f "$f"; else touch "$f"; fi ;; esac ;;
    *) echo "$*" >> "$log" ;;
esac
STUB
    printf '#!/bin/sh\n[ -e "$HOME/wp-rec" ] && echo %s || echo %s\n' "'[{\"info\":{\"state\":\"running\",\"props\":{\"media.class\":\"Stream/Input/Audio\"}}}]'" "'[]'" > "$H/.local/bin/pw-dump"
    printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/pipewire"
    printf '#!/bin/sh\n[ "$*" = "-x bluealsa" ] && [ -e "$HOME/bluealsa-runs" ]\n' > "$H/.local/bin/pgrep"
    chmod +x "$H/.local/bin/wpctl" "$H/.local/bin/pw-dump" "$H/.local/bin/pipewire" "$H/.local/bin/pgrep"
    line=$(sh "$SH" bar status --once)
    [ "$(t out name)" = "<span foreground='#ff5555'>$(printf '\342\227\200')</span>" ] && [ "$(t mic name)" = "<span foreground='#ff5555'>$(printf '\342\227\211')</span>" ] && cur out | grep -q 'jabra speak' && cur mic | grep -q 'jabra speak' \
        && ok "PipeWire: out and mic are WirePlumber's defaults (the panel names them)" || bad "wp names" "$(t out name) / $(t mic name) / $(cur out) / $(cur mic)"
    g=$(t out gauge); m=$(t mic gauge); [ "$(count "$g" "$pip")" = 2 ] && [ "$(count "$m" "$pip")" = 3 ] && ok "PipeWire: the gauges are wpctl's volumes (40, 50: 2 and 3 of 5)" || bad "wp gauges" "$g / $m"
    touch "$H/wp-rec"; line=$(sh "$SH" bar status --once)
    [ "$(t mic name)" = "<span foreground='#aa0000'>$(printf '\342\227\217')</span>" ] && ok "PipeWire: a running capture stream turns the mic a red dot" || bad "wp mic live" "$(t mic name)"
    rm -f "$H/wp-rec"
    sh "$SH" bar volume up; sh "$SH" bar volume down; sh "$SH" bar volume mute; sh "$SH" bar volume mic
    [ "$(cat "$wplog" 2>/dev/null)" = "$(printf '%s\n' 'set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+' 'set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%-' 'set-mute @DEFAULT_AUDIO_SINK@ toggle' 'set-mute @DEFAULT_AUDIO_SOURCE@ toggle')" ] \
        && ok "PipeWire: the volume keys are wpctl's, capped at 100 (-l 1.0); mute and the mic key toggle" || bad "wp keys" "$(cat "$wplog" 2>&1)"
    line=$(sh "$SH" bar status --once); g=$(t out gauge)
    [ "$(count "$g" "'#ff5555'")" = 0 ] && ok "PipeWire: a muted output turns its gauge muted" || bad "wp muted" "$g"
    rm -f "$wplog" "$H/wp-muted" "$H/wp-cmuted"
    st=0; out=$(sh "$SH" bar panel out use built-in audio digital stereo '(hdmi)' 2>&1) || st=$?
    line=$(sh "$SH" bar status --once)
    [ "$st" -eq 0 ] && [ "$(cat "$wplog")" = 'set-default 51' ] && cur out | grep -q 'built-in' && [ ! -e "$H/.config/alsa/asoundrc" ] \
        && ok "PipeWire: out use moves sound at once (wpctl set-default), no ALSA file written" || bad "wp out use" "st=$st $out; $(cat "$wplog" 2>&1); $(cur out)"
    out=$(sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     sound        PipeWire runs from the desktop: out Built-in Audio Digital Stereo (HDMI), mic Jabra SPEAK 410 USB Mono$' \
        && [ "$(printf '%s\n' "$out" | grep -c '^[a-zA-Z]* *sound ')" = 1 ] \
        && ok "check: one sound row, PipeWire answers, where it runs from (no systemd, no service: the desktop), the output and the mic" || bad "check wp" "$(printf '%s\n' "$out" | grep sound)"
    # what keeps sound from PipeWire, each a warn of its own: bluez-alsa beside it, your own ALSA default
    touch "$H/bluealsa-runs"; printf 'pcm.!default { type hw card 1 }\n' > "$HOME/.asoundrc"
    out=$(sh "$SH" check || true)
    # shellcheck disable=SC2088   # the line as the user reads it, a tilde and all
    printf '%s\n' "$out" | grep -q '^warn   sound        bluez-alsa runs beside PipeWire, and only one of them can offer Bluetooth sound -- turn one of them off$' \
        && printf '%s\n' "$out" | grep -q '^warn   sound        your ~/.asoundrc picks the sound device, so ALSA programs that use it skip PipeWire -- take the default out of it$' \
        && ok "check: bluez-alsa running and an ~/.asoundrc of yours with a default are said, each with its remedy" || bad "check wp warns" "$(printf '%s\n' "$out" | grep sound)"
    rm -f "$H/bluealsa-runs" "$HOME/.asoundrc" "$H/.local/bin/pgrep"
    printf '# a file with no default\npcm.mine { type hw card 1 }\n' > "$HOME/.asoundrc"
    out=$(sh "$SH" check || true)
    ! printf '%s\n' "$out" | grep -q 'asoundrc' && ok "check: an ~/.asoundrc that sets no default is not said (no empty name)" || bad "asoundrc no default" "$(printf '%s\n' "$out" | grep sound)"
    rm -f "$HOME/.asoundrc"
    # PipeWire installed and silent: outside a desktop it starts with the next one (no systemd); inside, a warn
    touch "$H/wp-down"
    out=$(env -u WAYLAND_DISPLAY sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     sound        PipeWire starts with the desktop$' && ok "check: PipeWire silent outside a desktop, no systemd: it starts with the desktop, ok" || bad "check wp later" "$(printf '%s\n' "$out" | grep sound)"
    out=$(WAYLAND_DISPLAY=wayland-1 sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^warn   sound        PipeWire does not answer -- leave the desktop and log in again$' && ok "check: PipeWire silent inside a desktop: a warn, log in again" || bad "check wp silent" "$(printf '%s\n' "$out" | grep sound)"
    rm -f "$H/wp-down"
    rm -f "$wplog" "$H/wp-sink"
    # a login outside the desktop (ssh, a service, spark's MCP host) has no XDG_RUNTIME_DIR, and PipeWire's socket is in
    # the private directory the desktop made (#31): taken when it is a real directory of yours at 0700, never made here
    mv "$H/.local/bin/wpctl" "$H/wpctl.real"
    printf '#!/bin/sh\n[ -e "${XDG_RUNTIME_DIR:-/nonexistent}/pipewire-0" ] || { echo "Could not connect to PipeWire" >&2; exit 1; }\nexec "$HOME/wpctl.real" "$@"\n' > "$H/.local/bin/wpctl"; chmod +x "$H/.local/bin/wpctl"
    rd=$H/rt/$(id -u)-runtime-dir; mkdir -p "$H/rt"; mkdir -m 0700 "$rd"; : > "$rd/pipewire-0"
    out=$(env -u XDG_RUNTIME_DIR TMPDIR="$H/rt" sh "$SH" bar panel out --list 2>&1)
    printf '%s\n' "$out" | grep -q "^$(printf '\342\227\217') out        Jabra SPEAK 410 USB Analog Stereo	out show$" && printf '%s\n' "$out" | grep -q "^  out        mute	out mute$" \
        && ok "no XDG_RUNTIME_DIR (ssh, a service): the desktop's private one is taken, so the sound is PipeWire's and mute is offered" || bad "runtime adopt" "$out"
    chmod 0755 "$rd"; out=$(env -u XDG_RUNTIME_DIR TMPDIR="$H/rt" sh "$SH" bar panel out --list 2>&1); chmod 0700 "$rd"
    rm -rf "$rd"; mkdir -p "$H/rt-elsewhere"; : > "$H/rt-elsewhere/pipewire-0"; ln -s "$H/rt-elsewhere" "$rd"
    out2=$(env -u XDG_RUNTIME_DIR TMPDIR="$H/rt" sh "$SH" bar panel out --list 2>&1)
    ! printf '%s\n' "$out" | grep -q 'Analog Stereo	out show$' && ! printf '%s\n' "$out2" | grep -q 'Analog Stereo	out show$' && [ "$(ls -ld "$H/rt-elsewhere" | cut -c1-10)" != drwx------ ] \
        && ok "no XDG_RUNTIME_DIR: a directory others can read, or a symlink in its place, is not taken, and nothing is changed" || bad "runtime adopt refused" "$out | $out2"
    rm -rf "$H/rt" "$H/rt-elsewhere"; mv "$H/wpctl.real" "$H/.local/bin/wpctl"
    printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/wpctl"; rm -f "$H/.local/bin/pw-dump" "$H/.local/bin/pipewire"; chmod +x "$H/.local/bin/wpctl"
    # the verb: both halves, one of them, the config key, the render, a running sway
    export SWAYSOCK=$H/sway.sock
    st=0; out=$(sh "$SH" bar 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q '^status line: tmux is not running (it shows inside tmux)$' && printf '%s\n' "$out" | grep -q '^bar: shown at the top of the screen -- bat, bt, clock, lan, mic, out, wifi (spark-shell bar off --desktop hides it)$' \
        && ok "bar: both halves said -- tmux not running, the bar shown with its blocks" || bad "bar bare" "st=$st $out"
    st=0; out=$(sh "$SH" bar --terminal 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell bar: tmux is not running -- start tmux first' ] && ok "bar --terminal with no tmux: refused in one line" || bad "bar --terminal" "st=$st $out"
    st=0; out=$(sh "$SH" bar off --desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP_BAR=no$' "$HOME/.config/spark-shell/config" && grep -q '^    mode invisible$' "$sway" && printf '%s\n' "$out" | grep -q '^ok     sway         reloaded' && printf '%s\n' "$out" | grep -q '^bar: hidden (spark-shell bar on --desktop shows it)$' \
        && ok "bar off --desktop: DESKTOP_BAR=no, the bar block in invisible mode, sway reloaded, one closing line" || bad "bar off" "st=$st $out $(grep -n 'mode ' "$sway")"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  bar   hidden' && ok "status: the bar row says hidden" || bad "status bar hidden" "$(printf '%s\n' "$st" | grep '^  bar')"
    out=$(sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     top          hidden (spark-shell bar on --desktop shows it)' && ok "check: the top row says hidden, ok" || bad "check top hidden" "$out"
    st=0; out=$(sh "$SH" bar on --desktop 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^DESKTOP_BAR=yes$' "$HOME/.config/spark-shell/config" && grep -q '^    mode dock$' "$sway" && ok "bar on --desktop: DESKTOP_BAR=yes, dock mode again" || bad "bar on" "st=$st $out"
    st=$(sh "$SH" status); printf '%s\n' "$st" | grep -q '^  bar   shown .*at the top of the screen: bat, bt, clock, lan, mic, out, wifi' && ok "status: the bar row names the blocks present" || bad "status bar shown" "$(printf '%s\n' "$st" | grep '^  bar')"
    without_tools "$H/no-pipewire" pipewire wireplumber pipewire-pulse
    out=$(PATH=$H/.local/bin:$H/no-pipewire sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^ok     top          the bar draws bat, bt, clock, lan, mic, out, wifi$' \
        && [ "$(printf '%s\n' "$out" | grep '^[a-zA-Z]* *sound ')" = 'warn   sound        PipeWire is not installed: the bar reads plain ALSA -- spark-shell on desktop' ] \
        && ok "check: the top row names the blocks; on plain ALSA one sound warn, PipeWire missing, the remedy on desktop" || bad "check top" "$out"
    # the panel as text (no terminal): the title line restates what opened it, then ONE list in sections -- the first section's rows, then what every other section can do; each row wears a sign, names its section and carries its action
    DOT=$(printf '\342\227\217'); RING=$(printf '\342\227\213'); TICK=$(printf '\342\234\223'); CROSS=$(printf '\342\234\227'); GO=$(printf '\342\226\270'); SEP=$(printf '\302\267')
    journal=$H/.local/state/spark-shell/panel; rm -f "$journal/undo" "$journal/recent"   # the lists below in their plain order: nothing picked yet
    out=$(sh "$SH" bar panel lan --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "lan        up $SEP 192.0.2.10" ] && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "  lan        address 192.0.2.10	lan show" ] && printf '%s\n' "$out" | grep -q "^  lan        speed 1000 Mb/s	lan show$" && printf '%s\n' "$out" | grep -q "^  lan        gateway 192.0.2.1	lan show$" \
        && ok "panel lan: the address, the speed and the gateway, a look only, first (the old bar panel spelling)" || bad "panel lan" "$out"
    printf '%s\n' "$out" | awk 'NR > 1 && index($0, " lan ") == 0 { bad = 1 } END { exit bad }' \
        && ok "panel lan: the lan section alone, never every other section after it: building them asked CUPS for a theme's list (#186)" || bad "panel lan rest" "$out"
    _d0=$(date '+%A %d %B'); out=$(sh "$SH" panel --list); _d1=$(date '+%A %d %B')   # the day before and after: a run across midnight has either
    printf '%s\n' "$out" | sed -n 1p | grep -q -e "^$_d0 $SEP [0-9][0-9]:[0-9][0-9]$" -e "^$_d1 $SEP [0-9][0-9]:[0-9][0-9]$" && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "wifi home $SEP bt $DOT MAJOR V $SEP out 40% $SEP mic 50% $SEP bat 80% $SEP theme none" ] && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "$GO spark      chat	spark chat" ] && printf '%s\n' "$out" | grep -q "^$DOT wifi       home	wifi disconnect$" && ! printf '%s\n' "$out" | grep -q "	[a-z]* show$" \
        && ok "panel with nothing first (Super+d): the glance (the date and time, the bar's facts; a wire that is up says nothing), the chat row first, then everything it can do" || bad "panel bar" "$out"
    out=$(sh "$SH" panel spark --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "spark      a conversation, in this window" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$GO spark      chat	spark chat" ] && ok "panel spark --list: the one row that opens the conversation" || bad "panel spark" "$out"
    # the cache: a probe's last answer is kept with its age; a long section shows what matters and a `more` row
    cache=$H/.local/state/spark-shell/panel; mkdir -p "$cache"
    { echo "$(date +%s)"; printf 'a1\t4\t1\nb2\t3\t1\nc3\t3\t1\nd4\t2\t1\ne5\t1\t1\nopen\t2\t0\nold\t1\t1\n'; } > "$cache/wifi.scan"
    out=$(sh "$SH" panel --list)
    [ "$(printf '%s\n' "$out" | grep -c "^$RING wifi       ")" = 4 ] && printf '%s\n' "$out" | grep -q "^$RING wifi       old .* $TICK saved	wifi connect old$" && printf '%s\n' "$out" | grep -q "^  wifi       3 more	wifi more$" \
        && ok "panel: a fresh scan is read from the cache; wifi shows the saved ones, the strongest three and a more row" || bad "wifi more" "$out"
    [ "$(sh "$SH" panel wifi --list | grep -c "^$RING wifi       ")" = 7 ] && ! sh "$SH" panel wifi --list | grep -q "	wifi more$" && ok "panel wifi: the section that opened the panel shows every network, no more row" || bad "wifi full" "$(sh "$SH" panel wifi --list)"
    # a network's name is anyone's words: one made like an option stays a name (grep took -c for its own, then read the rest of the list as its input)
    { echo "$(date +%s)"; printf -- '-c\t4\t1\ncafe-two\t3\t1\n'; } > "$cache/wifi.scan"
    _wo=$(sh "$SH" panel wifi --list 2>&1)
    printf '%s\n' "$_wo" | grep -q 'connect -c$' && printf '%s\n' "$_wo" | grep -q 'connect cafe-two$' && ok "panel wifi: a network named like an option is a row, and the rows after it stay" || bad "wifi option name" "$_wo"
    { echo "$(( $(date +%s) - 120 ))"; printf 'stale\t4\t1\n'; } > "$cache/wifi.scan"
    sh "$SH" panel --list | grep -q "^$RING wifi       cafe" && ! sh "$SH" panel --list | grep -q stale && grep -q "^cafe" "$cache/wifi.scan" && [ $(( $(date +%s) - $(sed -n 1p "$cache/wifi.scan") )) -lt 60 ] \
        && ok "panel: a scan older than a minute is made again and kept, with its time" || bad "wifi stale" "cache: $(tr '\n' '|' < "$cache/wifi.scan"); list: $(sh "$SH" panel --list 2>&1 | grep wifi | tr '\n' '|')"
    { echo "$(( $(date +%s) - 120 ))"; printf 'stale\t4\t1\n'; } > "$cache/wifi.scan"; printf '#!/bin/sh\n[ "$3" = scan_results ] && printf "bssid\\tfreq\\tsignal\\tflags\\tssid\\n00\\t2412\\t-50\\t[WPA2]\\thome\\n"; [ "$3" = status ] && echo ssid=home; exit 0\n' > "$H/.local/bin/wpa_cli.thin"
    mv "$H/.local/bin/wpa_cli" "$H/wpa_cli.full"; mv "$H/.local/bin/wpa_cli.thin" "$H/.local/bin/wpa_cli"; chmod +x "$H/.local/bin/wpa_cli"
    sh "$SH" panel --list >/dev/null; _age=$(( $(date +%s) - $(sed -n 1p "$cache/wifi.scan") ))
    mv "$H/wpa_cli.full" "$H/.local/bin/wpa_cli"
    [ "$_age" -ge 50 ] && [ "$_age" -lt 60 ] && ok "panel: a scan that found one network at most (the radio was busy) is kept for ten seconds, not a minute" || bad "wifi thin" "age $_age: $(tr '\n' '|' < "$cache/wifi.scan")"
    rm -f "$cache/wifi.scan"
    printf '%s\n' "$out" | grep -q "^  theme      none $SEP more	theme more$" && [ "$(printf '%s\n' "$out" | grep -c "^. theme      ")" = 1 ] && sh "$SH" panel theme --list > "$H/theme.list" && grep -q "^  theme      Wallpaper	theme wallpaper$" "$H/theme.list" && grep -q "^  theme      dracula	theme dracula$" "$H/theme.list" && grep -q "^  theme      Text size	theme show$" "$H/theme.list" && grep -q "^  theme      Transparency	theme show$" "$H/theme.list" \
        && ok "panel: theme is one row in the list, the palette and a more; opened on theme, the wallpaper row, the text size and the transparency rows, the palettes" || bad "theme more" "$(printf '%s\n' "$out" | grep theme; grep theme "$H/theme.list" | head -3)"
    out=$(sh "$SH" panel apps --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "apps       every app allowed $SEP Enter opens one" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$GO apps       terminal	apps terminal" ] && [ "$(printf '%s\n' "$out" | sed -n 3p)" = "$GO apps       tmux	apps open tmux" ] && [ "$(printf '%s\n' "$out" | sed -n 4p)" = "$GO apps       firefox	apps open firefox" ] && printf '%s\n' "$out" | grep -q "^$GO apps       gimp-3.0	apps open gimp-3.0$" && [ "$(printf '%s\n' "$out" | grep "^$GO apps       " | tail -1)" = "$GO apps       choose the allowed apps	apps pick" ] \
        && ok "panel apps --list: the title says what is allowed, a terminal first, a row per app that opens it in the order of its group (tmux is system, before the others, #169), the picker last" || bad "panel apps" "$out"
    mcp apps "$(rq 1 resources/read '{"uri":"spark-shell://apps/rows"}')" "$(rq 2 resources/read "{\"uri\":\"spark-shell://apps/page/$(b64u 'apps:open tmux')\"}")"
    ans 1 | jq -r '.result.contents[0].text' | jq -e '([.rows[] | select(.text == "tmux")][0] | .group == "system" and (.page | startswith("spark-shell://apps/page/"))) and ([.rows[] | select(.text == "firefox")][0].group == "others") and (.rows[0].text == "terminal" and .rows[0].group == null)' >/dev/null \
        && ans 2 | jq -r '.result.contents[0].text' | jq -e '.lines[0:2] == ["tmux", "A shell with panes, sessions and the status line"] and (.lines | index("group       system")) and (.lines | index("runs in     a terminal")) and (.lines | index("command     tmux"))' >/dev/null \
        && ok "provide apps: each app under the group its desktop entry names (tmux system, one with none others), the terminal first; Space shows an app: its group, where it runs, its command, how it came (#169)" || bad "apps groups" "$(head -c 900 "$H/mcp.out")"
    rm -f "$H/.local/state/swaymsg.log" "$H/.local/state/swaymsg.trees"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps terminal 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'opened a terminal' ] && grep -qx 'exec foot' "$H/.local/state/swaymsg.log" && ok "panel apps terminal: a terminal window, as Super+Return" || bad "apps terminal" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps open GIMP-3.0 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'opened gimp-3.0' ] && grep -q '^exec gimp-3.0' "$H/.local/state/swaymsg.log" && ok "panel apps open NAME: the app opens on the current workspace the way its entry says (any case)" || bad "apps open" "st=$st $out $(tail -2 "$H/.local/state/swaymsg.log" 2>&1)"
    [ ! -e "$H/.local/state/swaymsg.trees" ] && ok "panel apps open and terminal: each ends at sway's event for the new window; no window count is polled (#196)" || bad "apps open poll" "$(wc -l < "$H/.local/state/swaymsg.trees")"
    [ "$(sh "$SH" panel --list | sed -n 3p)" = "$GO apps       gimp-3.0	apps open gimp-3.0" ] && [ "$(sed -n 1p "$journal/recent")" = "apps	open gimp-3.0" ] \
        && ok "recent: the app just opened is the first row of the next list, and the journal's first line" || bad "recent" "$(sh "$SH" panel --list | sed -n 2,4p) | $(cat "$journal/recent")"
    touch "$HOME/no-new-window"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps open firefox 2>&1) || st=$?; rm -f "$HOME/no-new-window"
    [ "$st" -eq 0 ] && [ "$out" = 'asked firefox to open; no new window came' ] && ok "panel apps open: an app that maps no window (one open took it as a tab) is said, not refused (#196)" || bad "apps open no window" "st=$st $out"
    ( export SWAYSOCK=/tmp/x; mcp apps "$(rq 1 resources/read '{"uri":"spark-shell://apps/rows"}')" "$(call 2 apps_open '{"name":"micro"}')" )
    [ "$(ans 2 | jq -c '.result.structuredContent')" = '{"opened":true}' ] && grep -qx 'exec foot -e micro' "$H/.local/state/swaymsg.log" \
        && ok "provide apps_open: the app its row names opens, a terminal app inside foot, from the list the gate read; the answer says opened, so the dialog closes (#196)" || bad "provide apps_open" "$(ans 2) $(tail -2 "$H/.local/state/swaymsg.log")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps open nowhere 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: apps: no app named nowhere here' ] && ok "panel apps open: an app that is not here is refused in one line" || bad "apps open gate" "st=$st $out"
    # undo: a step's inverse is read before the act, kept in the journal, played back newest first
    rm -f "$amlog" "$journal/recent"; sh "$SH" panel out use hdmi >/dev/null
    [ "$(sh "$SH" panel undo --list | sed -n 2p)" = "  undo       out Jabra	undo all" ] && [ "$(sh "$SH" panel --list | sed -n 3p)" = "  undo       out Jabra	undo all" ] && [ "$(cat "$journal/undo")" = "out	use Jabra	out Jabra" ] \
        && ok "undo: after out use hdmi the undo row says out Jabra, first in the list; the journal holds the inverse step" || bad "undo row" "$(sh "$SH" panel --list | sed -n 2,5p) | $(cat "$journal/undo" 2>&1)"
    st=0; out=$(sh "$SH" panel undo all 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$TICK out Jabra for programs started from now" ] && [ "$(sh "$SH" panel out --list | sed -n 1p)" = "out        Jabra $SEP 40%" ] && ! sh "$SH" panel --list | grep -q "^  undo       " \
        && ok "undo all: the inverse played (out is Jabra again), then nothing to undo" || bad "undo all" "st=$st $out $(sh "$SH" panel out --list | sed -n 1p)"
    rm -f "$journal/undo" "$journal/recent"
    mkdir -p "$HOME/.config/spark-shell/layouts"; printf '{"words": "news and music", "why": "the feeds and a player", "main": {"app": "newsboat"}}\n' > "$HOME/.config/spark-shell/layouts/news"
    out=$(sh "$SH" panel --list)
    _ln=$(printf '%s\n' "$out" | grep -nxF "$GO layout     news	layout open news" | cut -d: -f1); _an=$(printf '%s\n' "$out" | grep -n "^$GO apps " | tail -1 | cut -d: -f1)
    [ -n "$_ln" ] && [ -n "$_an" ] && [ "$_ln" -gt "$_an" ] && [ "$(sh "$SH" panel layout --list | sed -n 1p)" = "layout     1 saved" ] \
        && ok "panel: a saved layout comes after the apps, by the name it was saved under (#51), opening it by name; the layout title counts it" || bad "panel layout row" "$out"
    rm -rf "$HOME/.config/spark-shell/layouts"
    [ ! -e "$H/.local/bin/spark" ] || mv "$H/.local/bin/spark" "$H/spark.away"   # no spark for a moment: the want is refused, not asked
    st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" panel sideways --list 2>&1) || st=$?
    [ ! -e "$H/spark.away" ] || mv "$H/spark.away" "$H/.local/bin/spark"
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)' ] && ok "panel WORDS: a word that is no section is a want (here without spark: refused in one line)" || bad "panel no block" "st=$st $out"
    out=$(sh "$SH" bar panel wifi --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "wifi       $(printf '\342\226\202\342\226\204\342\226\206\342\226\221') home $SEP 192.0.2.20" ] && [ "$(printf '%s\n' "$out" | sed -n 4p)" = "$DOT wifi       home	wifi disconnect" ] && printf '%s\n' "$out" | sed -n 5p | grep -q "^$RING wifi       cafe .*	wifi connect cafe$" && printf '%s\n' "$out" | sed -n 6p | grep -q "^$RING wifi       open .*	wifi connect open$" && [ "$(printf '%s\n' "$out" | sed -n 7p)" = "  wifi       forget old	wifi forget old" ] \
        && ok "panel wifi (wpa_cli): the network in use first, the ones around strongest first, then forget for a saved one" || bad "panel wifi" "$out"
    st=0; out=$(sh "$SH" bar panel wifi connect cafe 2>&1 </dev/null) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'no password given, so not connected' ] && ok "panel wifi connect, a secured network that is new: asks for the password; with none, nothing is done" || bad "wifi connect secured" "st=$st $out"
    wlog=$H/.local/state/wpa.log; rm -f "$wlog"
    st=0; out=$(sh "$SH" bar panel wifi connect open 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'connected to open' ] && grep -qx 'set_network 2 ssid 6f70656e' "$wlog" && grep -qx 'set_network 2 key_mgmt NONE' "$wlog" && grep -qx 'enable_network 2' "$wlog" && grep -qx save_config "$wlog" && grep -qx 'select_network 2' "$wlog" \
        && ok "panel wifi connect, an open network: added, saved, selected, connected" || bad "wifi connect open" "st=$st $out; $(cat "$wlog" 2>&1)"
    rm -f "$wlog"
    st=0; out=$(sh "$SH" bar panel wifi disconnect 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'disconnected from open' ] && grep -qx disconnect "$wlog" && ok "panel wifi disconnect: one line, the tool told" || bad "wifi disconnect" "st=$st $out"
    echo 0 > "$H/wpa.sel"; rm -f "$H/wpa.down" "$wlog"
    st=0; out=$(sh "$SH" bar panel wifi forget old 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'forgot old' ] && grep -qx 'remove_network 1' "$wlog" && grep -qx save_config "$wlog" && ok "panel wifi forget: the saved network removed, the config saved" || bad "wifi forget" "st=$st $out; $(cat "$wlog" 2>&1)"
    # a new network's password reaches the tool on its stdin, never as an argument (#62)
    rm -f "$wlog" "${wlog%.log}.argv" "$H/wpa.nohome" "$cache/wifi.scan"; echo cafe > "$H/wpa.name2"
    st=0; out=$(PANEL_PASS='s3cret "pass" word' sh "$SH" bar panel wifi connect cafe 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'connected to cafe' ] && grep -qxF 'set_network 2 psk aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$wlog" && ! grep -q s3cret "${wlog%.log}.argv" && [ -e "$H/wpa.nohome" ] && [ ! -e "$H/.wpa_cli_history" ] \
        && ok "panel wifi connect, wpa_cli: the password goes in as a command on stdin, with HOME unset (no history file), in no call's arguments (#62)" || bad "wpa psk stdin" "st=$st $out; $(cat "$wlog" "${wlog%.log}.argv" 2>&1)"
    rm -f "$wlog" "$H/wpa.name2"; echo 0 > "$H/wpa.sel"
    st=0; out=$(PANEL_PASS="$(printf 'two\nlines')" sh "$SH" bar panel wifi connect cafe 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'a password holds no control character, so not connected' ] && [ ! -s "$wlog" ] \
        && ok "panel wifi connect: a password with a new line is refused before any tool hears it (it would be a second command)" || bad "wifi psk newline" "st=$st $out; $(cat "$wlog" 2>&1)"
    touch "$H/nm.on"; nlog=$H/.local/state/nmcli.log; rm -f "$nlog" "$nlog.argv" "$cache/wifi.scan"
    st=0; out=$(PANEL_PASS='s3cret "pass" word' sh "$SH" bar panel wifi connect cafe 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'connected to cafe' ] && grep -qxF 's3cret "pass" word' "$nlog" && grep -qx -- '--ask dev wifi connect cafe ifname wlan0 hidden no' "$nlog.argv" && ! grep -q s3cret "$nlog.argv" \
        && ok "panel wifi connect, nmcli: --ask, the password at nmcli's own prompt on stdin, in no argument (#62)" || bad "nmcli stdin" "st=$st $out; $(cat "$nlog" "$nlog.argv" 2>&1)"
    rm -f "$cache/wifi.scan"; st=0; out=$(PANEL_PASS=wrong sh "$SH" bar panel wifi connect cafe 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'could not connect to cafe: Error: Connection activation failed: Secrets were required, but not provided.' ] \
        && ok "panel wifi connect, nmcli refuses: its error line, never its prompt" || bad "nmcli refused" "st=$st $out"
    st=0; out=$(PANEL_PASS='hidden-pass' sh "$SH" bar panel wifi hidden cafe 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx -- '--ask dev wifi connect cafe ifname wlan0 hidden yes' "$nlog.argv" && ! grep -q hidden-pass "$nlog.argv" \
        && ok "hidden wifi: NetworkManager receives the chosen interface and hidden flag, password on stdin" || bad "nmcli hidden" "$out"
    rm -f "$H/nm.on"; touch "$H/iw.on"; ilog=$H/.local/state/iwctl.log; rm -f "$ilog" "$ilog.argv" "$cache/wifi.scan"
    st=0; out=$(PANEL_PASS='s3cret "pass" word' sh "$SH" bar panel wifi connect cafe 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'connected to cafe' ] && grep -qxF 's3cret "pass" word' "$ilog" && grep -qx 'station wlan0 connect cafe' "$ilog.argv" && ! grep -q -e s3cret -e passphrase "$ilog.argv" \
        && ok "panel wifi connect, iwctl: the passphrase at its agent's prompt on stdin, no --passphrase (#62)" || bad "iwctl stdin" "st=$st $out; $(cat "$ilog" "$ilog.argv" 2>&1)"
    st=0; out=$(PANEL_PASS='hidden-pass' sh "$SH" bar panel wifi hidden cafe 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx 'station wlan0 connect-hidden cafe' "$ilog.argv" && ! grep -q hidden-pass "$ilog.argv" \
        && ok "hidden wifi: iwd connects by hidden name, password on stdin" || bad "iwctl hidden" "$out"
    rm -f "$H/iw.on" "$cache/wifi.scan"
    echo cafe > "$H/wpa.name2"
    st=0; out=$(PANEL_PASS='hidden-pass' sh "$SH" bar panel wifi hidden cafe 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx 'set_network 2 scan_ssid 1' "$wlog" && ! grep -q hidden-pass "${wlog%.log}.argv" \
        && ok "hidden wifi: wpa_supplicant saves active scanning for the hidden name" || bad "wpa hidden" "$out"
    rm -f "$H/wpa.name2"; echo 0 > "$H/wpa.sel"
    st=0; out=$(sh "$SH" bar panel wifi connect nowhere 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: nowhere is not in the list now' ] && ok "panel: an action the section does not offer is refused in one line" || bad "panel gate" "st=$st $out"
    out=$(sh "$SH" bar panel bt --list); blog=$H/.local/state/bt.log
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "bt         $DOT MAJOR V" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT bt         MAJOR V	bt disconnect MAJOR V" ] && printf '%s\n' "$out" | grep -q "^$RING bt         Buds $SEP new	bt pair Buds$" && printf '%s\n' "$out" | grep -q "^  bt         find new devices	bt scan$" && printf '%s\n' "$out" | grep -q "^  bt         turn off	bt power off$" \
        && ok "panel bt: the connected device, a new one to pair, a row that scans, and off" || bad "panel bt" "$out"
    mcp bt "$(rq 1 resources/read '{"uri":"spark-shell://bt/rows"}')" "$(rq 2 resources/read "{\"uri\":\"spark-shell://bt/page/$(b64u 'bt:disconnect MAJOR V')\"}")"
    ans 1 | jq -r '.result.contents[0].text' | jq -e '([.rows[] | select(.tool.name == "bt_remove")] == []) and ([.rows[] | select(.text == "MAJOR V")][0] | .more == [{name: "bt_remove", arguments: {name: "MAJOR V"}, said: "remove"}] and .page != null)' >/dev/null \
        && ans 2 | jq -r '.result.contents[0].text' | jq -e '.lines[0] == "MAJOR V" and (.lines | index("connected   yes")) and (.lines | index("address     00:25:D1:4A:C2:AA"))' >/dev/null \
        && ok "provide bt: remove is behind a paired device, no row of its own; Space shows a device, connected, paired, its address (#169)" || bad "bt remove behind" "$(head -c 1200 "$H/mcp.out")"
    rm -f "$blog"; st=0; out=$(sh "$SH" bar panel bt disconnect MAJOR V 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'disconnected MAJOR V' ] && grep -qx 'disconnect 00:25:D1:4A:C2:AA' "$blog" && ok "panel bt disconnect NAME: the device's address told to bluetoothctl" || bad "bt disconnect" "st=$st $out; $(cat "$blog" 2>&1)"
    out=$(sh "$SH" bar panel out --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "out        Jabra $SEP 40%" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT out        Jabra	out show" ] && printf '%s\n' "$out" | grep -q "^$RING out        HDMI	out use HDMI$" && printf '%s\n' "$out" | grep -q "^  out        mute	out mute$" && ! printf '%s\n' "$out" | grep -q " mic  " \
        && ok "panel out: the cards that play, the one in use named, and mute; the out section alone (#186)" || bad "panel out" "$out"
    printf ' 0 [USB            ]: USB-Audio - Jabra SPEAK 410 USB\n                      Jabra SPEAK 410 USB at usb-0000:00:14.0-2, full speed\n 1 [HDMI           ]: HDA-Intel - HD-Audio Generic\n' > "$P/asound/cards"
    [ "$(sh "$SH" bar panel out --list | sed -n 1p)" = "out        Jabra SPEAK 410 USB $SEP 40%" ] && ok "ALSA: a card with the generic id USB is named by its long name, read past the driver's own hyphen (USB-Audio)" || bad "alsa usb name" "$(sh "$SH" bar panel out --list | sed -n 1p)"
    printf ' 0 [Jabra          ]: USB-Audio - Jabra SPEAK 410 USB\n                      Jabra SPEAK 410 USB at usb-0000:00:14.0-2, full speed\n 1 [HDMI           ]: HDA-Intel - HD-Audio Generic\n                      HD-Audio Generic at 0xdc5c8000 irq 104\n' > "$P/asound/cards"
    out=$(sh "$SH" bar panel mic --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "mic        Jabra $SEP 50%" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "$DOT mic        Jabra	mic show" ] && ! printf '%s\n' "$out" | grep -q "mic        HDMI" && printf '%s\n' "$out" | grep -q "^  mic        mute	mic mute$" \
        && ok "panel mic: the cards that capture only, with the level" || bad "panel mic" "$out"
    rm -f "$amlog"; sh "$SH" bar panel mic mute >/dev/null && sh "$SH" bar panel out level 35 >/dev/null
    [ "$(cat "$amlog")" = "$(printf '%s\n' '-c 0 sset Capture nocap' '-c 0 sset Master 35%')" ] && ok "panel mic mute, out level 35: set, not toggled; the mic's capture switch by amixer's own word" || bad "panel sound actions" "$(cat "$amlog")"
    m1=$(sh "$SH" bar panel mic --list | sed -n 1p); un=$(sh "$SH" bar panel mic unmute); m2=$(sh "$SH" bar panel mic --list | sed -n 1p)
    [ "$m1" = "mic        Jabra $SEP 50% $SEP muted" ] && [ "$un" = 'mic unmuted' ] && [ "$m2" = "mic        Jabra $SEP 50%" ] \
        && ok "panel mic mute then unmute: the state read back from amixer, the title says muted in between" || bad "panel mic read back" "$m1 | $un | $m2"
    sh "$SH" bar panel out level 35 >/dev/null; u1=$(cat "$journal/undo" 2>/dev/null)
    touch "$H/muted"; st=0; out=$(sh "$SH" bar panel out mute 2>&1) || st=$?; u2=$(cat "$journal/undo" 2>/dev/null)
    rm -f "$H/muted"; st3=0; out3=$(sh "$SH" bar panel out unmute 2>&1) || st3=$?; u3=$(cat "$journal/undo" 2>/dev/null); rm -f "$amlog"
    [ "$st" -eq 0 ] && [ "$out" = 'out muted' ] && [ "$st3" -eq 0 ] && [ "$out3" = 'out unmuted' ] && [ -n "$u1" ] && [ "$u2" = "$u1" ] && [ "$u3" = "$u1" ] \
        && ok "panel out mute when muted already, unmute when not: a receipt, never 'not on the panel now', and the undo before it stays (#31)" || bad "mute again" "st=$st $out | st3=$st3 $out3 | $u1 | $u2 | $u3"
    sh "$SH" bar panel out use HDMI >/dev/null
    st=0; out=$(sh "$SH" bar panel out mute 2>&1) || st=$?; st2=0; out2=$(sh "$SH" bar panel out level 50 2>&1) || st2=$?
    sh "$SH" bar panel out use Jabra >/dev/null; rm -f "$amlog" "$HOME/level"
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: out: HDMI has no volume control here, so it cannot be muted or set' ] && [ "$st2" -eq 1 ] && [ "$out2" = "$out" ] \
        && ok "panel out mute and level on an output with no volume control (HDMI): why, in one line; never 'not on the panel now', never a level said that nothing took (#31)" || bad "no mixer" "st=$st $out | st2=$st2 $out2"
    out=$(sh "$SH" bar panel bat --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "bat        80% $SEP discharging $SEP 2:00 left" ] && printf '%s\n' "$out" | grep -q "^  bat        health 83% of new	bat show$" && printf '%s\n' "$out" | grep -q "^  bat        cycles 123	bat show$" && printf '%s\n' "$out" | grep -q "^  bat        power 20.0 W	bat show$" \
        && ok "panel bat: the charge, the time left from the kernel's numbers, the health, the cycles" || bad "panel bat" "$out"
    out=$(sh "$SH" bar panel clock --list)
    B=$(printf '\342\226\210')   # the full block: three bytes, so the patterns below never count characters (the CI containers run in the C locale)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "$(date '+%A %d %B %Y')" ] && [ -z "$(printf '%s\n' "$out" | sed -n 2p)" ] && printf '%s\n' "$out" | sed -n 3p | grep -q "^ \{40\} *$(date '+%B %Y')$" && printf '%s\n' "$out" | sed -n 4p | grep -q " Su  Mo  Tu  We  Th  Fr  Sa$" && [ "$(printf '%s\n' "$out" | sed -n '4,8p' | grep -c "^[$B ]*${B}[$B ]*      ")" = 5 ] && printf '%s\n' "$out" | sed -n '4,8p' | grep -q "$B$B  *$B" && printf '%s\n' "$out" | grep -q "	clock format 12$" && printf '%s\n' "$out" | grep -q "	clock week monday$" \
        && ok "panel clock: the date alone on top, then the time five rows tall in strokes two cells wide on the left and this month on the right, 34 cells apart; time settings follow" || bad "panel clock" "$out"
    out=$(sh "$SH" bar panel look --list)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "theme      none" ] && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "  theme      catppuccin-mocha	theme catppuccin-mocha" ] && printf '%s\n' "$out" | grep -q "^  theme      Wallpaper	theme wallpaper$" && printf '%s\n' "$out" | grep -q "^$TICK theme      terminal default colors	theme show$" && printf '%s\n' "$out" | grep -q "^  theme      dracula	theme dracula$" && printf '%s\n' "$out" | grep -q "^  theme      save this look as	theme save$" && printf '%s\n' "$out" | grep -q "^  theme      Text size	theme show$" && printf '%s\n' "$out" | grep -q "^  theme      Transparency	theme show$" \
        && ok "panel theme (look, the old word, still opens it): the palettes first, each its own step (#183), then the wallpaper, the text size and the transparency, the palettes by name, none as terminal default colors, save this look as" || bad "panel look" "$out"
    st=0; out=$(sh "$SH" panel theme text bigger 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "text at 13 $SEP new windows and the bar take it; the pointer 24 pixels" ] && grep -q '^FONT=DejaVu Sans Mono:size=13$' "$HOME/.config/spark-shell/config" && grep -q '^    font pango:DejaVu Sans Mono 13$' "$sway" \
        && ok "panel theme text bigger: FONT in the config, the bar's font rendered, the receipt names the pointer's size" || bad "look text" "st=$st $out $(grep -n 'FONT\|font' "$HOME/.config/spark-shell/config" "$sway")"
    st=0; out=$(sh "$SH" panel theme alpha 0.5 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^ALPHA=0.5$' "$HOME/.config/spark-shell/config" && grep -q '^        background #00000080$' "$sway" && ok "panel look alpha 0.5: ALPHA in the config, the bar's background rendered with it (80)" || bad "look alpha" "st=$st $out $(grep -n 'background' "$sway")"
    st=0; out=$(sh "$SH" panel theme see-through more 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'transparency stops at 50%' ] && grep -q '^ALPHA=0.5$' "$HOME/.config/spark-shell/config" && ok "panel theme see-through more (the word before v0.71) at 50%: transparency refused in one line, nothing written" || bad "transparency floor" "st=$st $out"
    st=0; out=$(sh "$SH" panel theme transparency less 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "transparency at 40%" ] && grep -q '^ALPHA=0.6$' "$HOME/.config/spark-shell/config" \
        && ok "panel theme transparency less: a tenth less, said as a percent (the open windows take it at once, #35)" || bad "transparency less" "st=$st $out $(grep ALPHA "$HOME/.config/spark-shell/config")"
    sh "$SH" panel --list | grep -q "^  undo       transparency 50%	undo all$" && ok "undo: the transparency step's inverse names the percent it was" || bad "transparency undo" "$(sh "$SH" panel --list | grep undo)"
    # the bar: hide and show from the panel, remembered in the config and the render
    rm -f "$journal/undo"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar off 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "bar hidden $SEP Super+space opens the dialog" ] && grep -q '^DESKTOP_BAR=no$' "$HOME/.config/spark-shell/config" && grep -q '^    mode invisible$' "$sway" && [ "$(sh "$SH" panel bar --list | sed -n 2,4p)" = "$(printf '  bar        at the top of the screen\tbar top\n  bar        at the bottom of the screen\tbar bottom\n%s bar        hidden\tbar show' "$TICK")" ] && sh "$SH" panel --list | grep -q "^  undo       bar shown	undo all$" \
        && ok "panel bar off (the hidden row): DESKTOP_BAR=no, the bar invisible in the render, hidden the place checked, the undo says shown" || bad "bar off" "st=$st $out $(grep -n 'mode ' "$sway"; sh "$SH" panel bar --list)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar on 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'bar shown' ] && grep -q '^DESKTOP_BAR=yes$' "$HOME/.config/spark-shell/config" && grep -q '^    mode dock$' "$sway" && [ "$(sh "$SH" panel bar --list | sed -n 2p)" = "$TICK bar        at the top of the screen	bar show" ] && [ "$(sh "$SH" panel bar --list | sed -n 4p)" = "  bar        hidden	bar off" ] \
        && ok "panel bar on: back where it was, the top checked and hidden a step again" || bad "bar on" "st=$st $out $(sh "$SH" panel bar --list)"
    # the bar's place (top or bottom), its text size and the tray, from the panel
    rm -f "$journal/undo"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar bottom 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'bar at the bottom of the screen' ] && grep -q '^BAR_POSITION=bottom$' "$HOME/.config/spark-shell/config" && grep -q '^    position bottom$' "$sway" && grep -qx 'anchor=bottom-right' "$HOME/.config/mako/config" \
        && [ "$(sh "$SH" panel bar --list | sed -n 3p)" = "$TICK bar        at the bottom of the screen	bar show" ] && [ "$(sh "$SH" panel bar --list | sed -n 1p)" = "bar        shown at the bottom of the screen" ] && sh "$SH" panel --list | grep -q "^  undo       bar at the top of the screen	undo all$" \
        && ok "panel bar bottom: BAR_POSITION=bottom, the bar at the bottom in the render and the notifications in the bottom corner, the row checked, the undo names the top" || bad "bar bottom" "st=$st $out $(grep -n 'position' "$sway"; sh "$SH" panel bar --list)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar off 2>&1 && SWAYSOCK=/tmp/x sh "$SH" panel bar on 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^    position bottom$' "$sway" && grep -q '^    mode dock$' "$sway" && ok "panel bar off, then on: back at the bottom, where it was" || bad "bar on bottom" "st=$st $out $(grep -n 'position\|mode' "$sway")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar top 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'bar at the top of the screen' ] && grep -q '^    position top$' "$sway" && grep -qx 'anchor=top-right' "$HOME/.config/mako/config" && ok "panel bar top: the top again, the notifications in the top corner" || bad "bar top" "st=$st $out"
    grep -q '^    tray_output none$' "$sway" && ok "sway: the tray off by default, the bar in its own glyphs (BAR_TRAY=no)" || bad "tray default" "$(grep -n tray "$sway")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel bar tray on 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "tray on $SEP the apps' icons show at the bar's end" ] && grep -q '^BAR_TRAY=yes$' "$HOME/.config/spark-shell/config" && grep -q '^    tray_output \*$' "$sway" && sh "$SH" panel --list | grep -q "^  undo       tray off	undo all$" \
        && ok "panel bar tray on: BAR_TRAY=yes, the tray on every screen's bar in the render, the undo turns it off" || bad "bar tray on" "st=$st $out $(grep -n tray "$sway")"
    SWAYSOCK=/tmp/x sh "$SH" panel bar tray off >/dev/null 2>&1 || :
    st=0; out=$(sh "$SH" panel bar text 15 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'bar text 15' ] && grep -q '^BAR_TEXT=15$' "$HOME/.config/spark-shell/config" && grep -q '^    font pango:DejaVu Sans Mono 15$' "$sway" && grep -qx 'font=DejaVu Sans Mono 13' "$HOME/.config/mako/config" \
        && ok "panel bar text 15: BAR_TEXT=15, the bar's font at 15, the text and the notifications at the text size" || bad "bar text" "st=$st $out $(grep -n font "$sway" "$HOME/.config/mako/config")"
    st=0; out=$(sh "$SH" panel bar text 41 2>&1) || st=$?
    [ "$st" -eq 1 ] && grep -q '^BAR_TEXT=15$' "$HOME/.config/spark-shell/config" && ok "panel bar text 41: refused, nothing written" || bad "bar text 41" "st=$st $out"
    st=0; out=$(sh "$SH" panel bar text auto 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "bar text auto, 13 now $SEP it follows the screen" ] && grep -q '^    font pango:DejaVu Sans Mono 13$' "$sway" \
        && ok "panel bar text auto: with no sway to ask, the text size (13)" || bad "bar text auto" "st=$st $out $(grep -n font "$sway")"
    # the windows: how new ones sit, this workspace now and the default for new ones
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window tabs 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'windows in tabs' ] && grep -q '^WINDOWS=tabs$' "$HOME/.config/spark-shell/config" && grep -q '^workspace_layout tabbed$' "$sway" && grep -qxF '[workspace=__focused__ tiling] layout tabbed' "$H/.local/state/swaymsg.log" \
        && [ "$(sh "$SH" panel window --list | sed -n 1p)" = "window     tabs" ] && sh "$SH" panel window --list | grep -q "^$TICK window     tabs	window show$" && sh "$SH" panel window --list | grep -q "^  window     side by side	window split$" && sh "$SH" panel --list | grep -q "^  undo       windows side by side	undo all$" \
        && ok "panel window tabs: WINDOWS=tabs, workspace_layout tabbed rendered, this workspace's tiling windows in tabs now, the rows and the undo say it" || bad "window tabs" "st=$st $out $(grep -n 'workspace_layout' "$sway"; cat "$H/.local/state/swaymsg.log"; sh "$SH" panel window --list)"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window split 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'windows side by side' ] && grep -q '^WINDOWS=split$' "$HOME/.config/spark-shell/config" && grep -q '^workspace_layout default$' "$sway" && grep -qxF '[workspace=__focused__ tiling] layout splith' "$H/.local/state/swaymsg.log" \
        && ok "panel window split: side by side again, workspace_layout default" || bad "window split" "st=$st $out"
    # one line of the config: sway's file alone is rendered again, and the look is not sent to sway again (#196)
    mv "$HOME/.config/foot/foot.ini" "$H/foot.ini.keep" 2>/dev/null || :; rm -f "$H/.local/state/swaymsg.log"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window tabs 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^workspace_layout tabbed$' "$sway" && [ ! -e "$HOME/.config/foot/foot.ini" ] && ! grep -q 'client.focused' "$H/.local/state/swaymsg.log" \
        && ok "panel window tabs: sway's file alone rendered again (foot's not written), nothing of the look sent to sway (#196)" || bad "window tabs one file" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    [ ! -e "$H/foot.ini.keep" ] || mv "$H/foot.ini.keep" "$HOME/.config/foot/foot.ini"; SWAYSOCK=/tmp/x sh "$SH" panel window split >/dev/null 2>&1 || :
    st=0; out=$(sh "$SH" panel window sideways 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: sideways is not in the list now' ] && ok "panel window WORD: a way that is not a row is refused" || bad "window refuse" "st=$st $out"
    # the windows open now: a row that puts one in front, a close row, the steps by name; the tree shows a firefox window while $HOME/fullscreen is there
    touch "$HOME/fullscreen" "$HOME/aerc"; rm -f "$H/.local/state/swaymsg.log"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window close firefox 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'firefox closed' ] && grep -qxF '[con_id=77] kill' "$H/.local/state/swaymsg.log" && ! grep -q 'app_id=firefox\] kill' "$H/.local/state/swaymsg.log" && ! sh "$SH" panel --list | grep -q 'undo.*firefox' \
        && ok "panel window close firefox: that one window, by its id, is told to close; no undo row for it" || bad "window close" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window close aerc 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'foot closed' ] && grep -qxF '[con_id=79] kill' "$H/.local/state/swaymsg.log" && ! grep -q 'foot' "$H/.local/state/swaymsg.log" \
        && ok "panel window close aerc: a terminal window goes by what runs in it, and only that terminal is told to close" || bad "window close aerc" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    touch "$HOME/aerc"; rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel apps close aerc 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = 'foot closed' ] && grep -qxF '[con_id=79] kill' "$H/.local/state/swaymsg.log" && ok "panel apps close NAME: read as window close, the way spark tends to say it" || bad "apps close" "st=$st $out"
    touch "$HOME/fullscreen" "$HOME/aerc"; SWAYSOCK=/tmp/x sh "$SH" panel window --list > "$H/win.list"
    grep -q "^$(printf '\342\226\270') window     firefox	window focus 77$" "$H/win.list" && grep -q "^  window     close firefox	window close 77$" "$H/win.list" && grep -q "^$(printf '\342\226\270') window     foot	window focus 79$" "$H/win.list" && ! grep -q 'spark-dialog' "$H/win.list" \
        && ok "panel window --list: each open window by its name is a row that puts it in front, and a close row; a terminal as foot; the panel's own window not listed" || bad "window rows" "$(cat "$H/win.list")"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel window close nothing 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: window: no unique window named nothing is open; select it in Workspace' ] && ok "panel window close NAME: a window that is not open is refused" || bad "window close refuse" "st=$st $out"
    # a close as the dialog makes it, the rows read first: the windows read once for the call (its check, its name, the
    # step's), once to see the window gone, then the rows after it as a read reads them (#196)
    touch "$HOME/fullscreen"; rm -f "$H/.local/state/swaymsg.trees"
    ( export SWAYSOCK=/tmp/x; mcp window "$(rq 1 resources/read '{"uri":"spark-shell://window/rows"}')" ); _rr=$(grep -c '' "$H/.local/state/swaymsg.trees" 2>/dev/null || :)
    rm -f "$H/.local/state/swaymsg.log" "$H/.local/state/swaymsg.trees"
    ( export SWAYSOCK=/tmp/x; mcp window "$(rq 1 resources/read '{"uri":"spark-shell://window/rows"}')" "$(call 2 window_close '{"name":"77"}')" ); _rt=$(grep -c '' "$H/.local/state/swaymsg.trees" 2>/dev/null || :)
    [ "$(ans 2 | jq -c '.result.structuredContent.effect')" = '{"kind":"window","id":"77","title":"firefox","operation":"close"}' ] && [ ! -e "$HOME/fullscreen" ] \
        && [ "$_rt" = $((2 * _rr + 2)) ] && grep -qxF '[con_id=77] kill' "$H/.local/state/swaymsg.log" \
        && ok "provide window_close: the windows read once for the call's check, name and step, once to see the window gone, then the rows (#196)" || bad "provide window_close" "trees=$_rt read=$_rr $(ans 2) $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    rm -f "$HOME/fullscreen" "$HOME/aerc" "$H/win.list"
    printf 'DESKTOP=sway\nTHEME=dracula\n' > "$HOME/.config/spark-shell/config"
    line=$(sh "$SH" bar status --once)
    printf '%s' "$line" | jq -e '[.[] | select(.name == "theme")] | length == 0' >/dev/null && ok "bar: no theme block even with a palette set (the panel's theme section has it)" || bad "theme block" "$line"
    [ "$(sh "$SH" bar panel look --list | grep -c "^$TICK theme      dracula	theme dracula$")" = 1 ] && ok "panel look: the current palette named" || bad "look current" "$(sh "$SH" bar panel look --list | head -4)"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    # a want: spark turns the words into steps from what this machine offers; the gate refuses the rest
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/spark.argv"
printf '{"why": "quiet: no sound out, no mic, no bluetooth", "steps": [{"page": "out", "action": "mute"}, {"page": "mic", "action": "mute"}, {"page": "bt", "action": "power", "arg": "off"}, {"page": "bt", "action": "dance", "arg": "x"}, {"page": "theme", "action": "alpha", "arg": "7"}, {"page": "desktop", "action": "lights", "arg": "low"}]}\n'
EOF
    chmod +x "$H/.local/bin/spark"; rm -f "$amlog" "$blog"
    st=0; out=$(sh "$SH" bar quiet please 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$(printf '%s\n' 'panel> quiet please' "  $TICK out muted" "  $TICK mic muted" "  $TICK bluetooth off" "  $CROSS x is not in the list now" "  $CROSS theme: alpha takes 0 to 1" "  $CROSS no desktop here")" ] \
        && ok "bar WORDS: one line per step with its sign and no why line; a step the panel does not offer, or a section it does not have, is refused in a few words, the rest played" || bad "bar want" "st=$st $out"
    [ "$(cat "$amlog")" = "$(printf '%s\n' '-c 0 sset Master mute' '-c 0 sset Capture nocap')" ] && grep -qx 'power off' "$blog" && ok "bar WORDS: the steps reached amixer and bluetoothctl" || bad "want steps" "$(cat "$amlog" "$blog" 2>&1)"
    grep -q '^do this on the desktop: quiet please$' "$H/spark.argv" && grep -q 'bt: disconnect MAJOR V, remove MAJOR V, pair Buds, scan, power off' "$H/spark.argv" && grep -q 'out: use HDMI, mute, level N' "$H/spark.argv" && grep -q 'layout: new TASK' "$H/spark.argv" && grep -q 'theme: .*dracula, .*text bigger' "$H/spark.argv" && grep -q "What the bar shows now: lan up $SEP 192.0.2.10; wifi .* home $SEP 192.0.2.20; bt $DOT MAJOR V; out Jabra $SEP 40%" "$H/spark.argv" \
        && ok "bar WORDS: spark gets the words, what the bar shows now (a question has its facts) and what each section offers, a new layout among them" || bad "want brief" "$(cat "$H/spark.argv")"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/spark.argv"; printf "{\\"why\\": \\"a question\\", \\"answer\\": \\"192.0.2.10 on the wire, 192.0.2.20 on wifi.\\", \\"steps\\": []}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel Firefox please 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$(printf '%s\n' 'panel> Firefox please' "  $TICK opened firefox")" ] && [ ! -e "$H/spark.argv" ] && grep -q '^exec firefox' "$H/.local/state/swaymsg.log" \
        && ok "panel WORDS, one or two, that name an app this machine declares (Firefox): the app opens at once, spark is not asked" || bad "want program" "st=$st $out $(cat "$H/spark.argv" 2>&1)"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel Firefox fullscreen please now 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  layout> Firefox fullscreen please now$' && grep -q 'write the layout for this need' "$H/spark.argv" && ! grep -q 'do this on the desktop' "$H/spark.argv" \
        && ok "panel WORDS, more of them, that name an app: a layout for the task, and that is the whole answer (spark is not asked for steps after)" || bad "want layout" "st=$st $out $(head -2 "$H/spark.argv")"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel what is my address 2>&1) || st=$?
    grep -q 'do this on the desktop: what is my address' "$H/spark.argv" && ok "panel WORDS with no app named go to spark, even where a word is a command (what, on a Mac)" || bad "want not an app" "st=$st $out $(head -3 "$H/spark.argv" 2>&1)"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel Firefox fullscreen 2>&1) || st=$?
    grep -q 'write the layout for this need: Firefox fullscreen' "$H/spark.argv" && ok "panel WORDS, two, naming an app with a layout word (fullscreen): a layout, not a bare open" || bad "want app layout word" "st=$st $out $(head -2 "$H/spark.argv")"
    rm -f "$journal/undo" "$journal/recent"
    st=0; out=$(sh "$SH" panel what is my address 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$out" = "$(printf '%s\n' 'panel> what is my address' '  192.0.2.10 on the wire, 192.0.2.20 on wifi.')" ] && ok "panel WORDS that ask: the answer in place, no steps" || bad "want answer" "st=$st $out"
    rm -f "$H/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel writing with vi and the prompt shell 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^  layout> writing with vi and the prompt shell$' && ! printf '%s\n' "$out" | grep -q '192.0.2.10' \
        && ok "panel WORDS that are no question and get no step: a layout for the task, never the model's shrug or a facts dump" || bad "want task fallback" "st=$st $out"
    # words about closing an app never open it or a layout: they go to the list, where spark picks window close
    cat > "$H/.local/bin/spark" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/spark.argv"
printf '{"why": "close it", "steps": [{"page": "window", "action": "close", "arg": "firefox"}]}\n'
EOF
    chmod +x "$H/.local/bin/spark"; touch "$HOME/fullscreen"; rm -f "$H/.local/state/swaymsg.log" "$HOME/spark.argv"
    st=0; out0=$(SWAYSOCK=/tmp/x sh "$SH" panel close the window with firefox </dev/null 2>&1) || st=$?
    printf '%s\n' "$out0" | grep -q "window close firefox: kept, not done (it takes a typed yes)$" && [ ! -s "$H/.local/state/swaymsg.log" ] || bad "want close no yes" "$out0"
    st=0; out=$(echo yes | SPARK_SHELL_TEST_TTY=1 SWAYSOCK=/tmp/x sh "$SH" panel close the window with firefox 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "type yes to window close firefox: $TICK firefox closed$" && grep -qxF '[con_id=77] kill' "$H/.local/state/swaymsg.log" && ! grep -q '^exec firefox' "$H/.local/state/swaymsg.log" && grep -q 'close 77' "$HOME/spark.argv" \
        && ok "panel WORDS about closing an app: never the app opened or a layout; spark picks window close firefox from the list; with no yes it is kept, and after a typed yes the window is told to close" || bad "want close" "st=$st $out $(cat "$H/.local/state/swaymsg.log" 2>&1)"
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/spark.argv"\nprintf "{\\"why\\": \\"no\\", \\"steps\\": []}\\n"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"; rm -f "$H/.local/state/swaymsg.log"
    st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel quit firefox 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^  $CROSS no step on the panel does that$" && ! grep -q '^exec firefox' "$H/.local/state/swaymsg.log" 2>/dev/null \
        && ok "panel WORDS about closing with no step from spark: one honest line, never a layout" || bad "want close no step" "st=$st $out"
    rm -f "$HOME/spark.argv"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel zebra stripes 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^  $CROSS no step on the panel does that$" && ! printf '%s\n' "$out" | grep -q 'layout>' && ! grep -q 'write the layout' "$HOME/spark.argv" 2>/dev/null \
        && ok "panel WORDS, a word or two with no step from spark: one honest line, never a layout (about once opened aerc)" || bad "want short no step" "st=$st $out"
    rm -f "$HOME/fullscreen"
    # the window itself, driven by an fzf of the test's: a pick runs through panel_run and panel_step, the next list carries the undo row
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  out        mute\tout mute\n'; exit 0; else exit 130; fi
STUB
    # unmuted first: the want above muted the output, and a mute when muted is a receipt that keeps no undo (#31)
    chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$amlog" "$journal/undo" "$journal/recent" "$H/muted"
    st=0; out=$(SPARK_SHELL_TEST_TTY=1 sh "$SH" panel 2>&1 </dev/null) || st=$?
    [ "$st" -eq 0 ] && [ "$(cat "$H/fzf.calls")" = 2 ] && sed "s/$(printf '\033')\[[0-9;]*m//g" "$H/fzf.in.2" | grep -q "^  $TICK out muted$" && printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*m//g" | grep -q "^    $(date '+%A %d %B') *$(printf '\342\235\257')$" && ! printf '%s\n' "$out" | grep -q 'not found' && grep -q "undo.*out unmute	undo all$" "$H/fzf.in.2" && grep -q -- "--highlight-line --pointer  --marker  --padding 1,0,0,2 --header-lines=[0-9]* --bind change:reload(cat .*/head; if \[ -n {q} \]; then cat .*/rows.full; else cat .*/rows.short; fi) --bind resize:reload(cat .*/head; " "$H/fzf.args.2" && grep -q -- 'click-header:transform(if \[ "$FZF_CLICK_HEADER_LINE" = 1 \] && \[ "$FZF_CLICK_HEADER_COLUMN" -ge [0-9]* \]; then echo abort; fi)' "$H/fzf.args.2" && grep -qx -- '-c 0 sset Master mute' "$amlog" \
        && ok "the window: Enter on out mute plays the step, the receipt rides in fzf's first lines with a check, the next list opens with the undo row, fzf holds the glance (header lines, a reload with the head on a change and on a resize, the corner's click told by line and column); Esc ends it" || bad "window pick" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) out=$(printf '%s' "$out" | tr -d '\033' | tr '\n' '|' | tail -c 400) in2=$(grep undo "$H/fzf.in.2" 2>&1)"
    plain=$(sed "s/$(printf '\033')\[[0-9;]*m//g" "$H/fzf.in.1")
    printf '%s\n' "$plain" | grep -q "^  $(date '+%A %d %B') *$(printf '\342\235\257')$" && printf '%s\n' "$plain" | grep -q "$B$B.*      .* Su  Mo  Tu  We  Th  Fr  Sa$" && [ "$(printf '%s\n' "$plain" | grep -c "$B$B")" -ge 5 ] && [ "$(grep -c "$B$B" "$H/fzf.in.2")" -ge 5 ] && ! printf '%s\n' "$plain" | grep -q "wifi home $SEP" && ! printf '%s\n' "$plain" | grep -q "out        Jabra" && grep -q "	about open$" "$H/fzf.in.1" && grep -q "pick an option, or say what you would like .* Esc .*closes" "$H/fzf.args.1" \
        && ok "the window: one view behind every door as fzf's first lines -- the date with the close glyph in the last cell, the time in strokes beside this month, no facts line and no title line; the about row last; the hint names the keys; drawn again after the pick" || bad "window view" "$(printf '%s' "$plain" | tr '\n' '|' | head -c 600)"
    rm -f "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent"
    # a pick that puts a window on the screen closes the panel: fzf runs once, the receipt is the last thing printed, the app was sent to sway
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  apps       firefox\tapps open firefox\n'; exit 0; else exit 130; fi
STUB
    swlog=$H/.local/state/swaymsg.log; chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    st=0; out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 sh "$SH" panel 2>&1 </dev/null) || st=$?
    plain=$(printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*m//g" | tr -d '\033' | sed 's/\[2J\[H//')
    [ "$st" -eq 0 ] && [ "$(cat "$H/fzf.calls")" = 1 ] && [ "$(printf '%s\n' "$plain" | grep -v '^ *$' | tail -1)" = "    $TICK opened firefox" ] && grep -q '^exec firefox' "$swlog" \
        && ok "the window: Enter on an app opens it and the panel closes at once, the receipt its last line (the window is the receipt)" || bad "window app closes" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) out=$(printf '%s' "$plain" | tr '\n' '|' | tail -c 300) sway=$(grep exec "$swlog" 2>&1)"
    rm -f "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    # a palette picked inside the panel: the next list is drawn with the new palette's shades (the settings read anew), not the ones the panel opened with
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  theme      nord\ttheme nord\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent"
    st=0; out=$(SPARK_SHELL_TEST_TTY=1 sh "$SH" panel 2>&1 </dev/null) || st=$?
    plain=$(printf '%s\n' "$out" | sed "s/$(printf '\033')\[[0-9;]*m//g")
    [ "$st" -eq 0 ] && [ "$(cat "$H/fzf.calls")" = 2 ] && sed "s/$(printf '\033')\[[0-9;]*m//g" "$H/fzf.in.2" | grep -q "$TICK nord is on" && grep -q '^THEME=nord$' "$HOME/.config/spark-shell/config" && grep -q 'bg+:#4c525e,hl:#88c0d0' "$H/fzf.args.2" && ! grep -q 'bg+:#4c525e' "$H/fzf.args.1" && grep -q "undo.*theme none	undo all$" "$H/fzf.in.2" \
        && ok "the window: a palette picked is read anew -- the next list is lit and marked in nord's shades (bg+ a fifth of the way to the text, hl the accent), the undo row goes back to none" || bad "window theme reload" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) a1=$(grep -o 'color=[^ ]*' "$H/fzf.args.1" 2>&1) a2=$(grep -o 'color=[^ ]*' "$H/fzf.args.2" 2>&1) out=$(printf '%s' "$plain" | tr '\n' '|' | tail -c 200)"
    sh "$SH" theme none >/dev/null 2>&1 || true; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"   # as before the pick
    rm -f "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent"
    # a window fullscreen on the workspace steps aside for the panel, which is focused over it; Esc puts it back. The panel's parent pid is written for the stub's tree
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  out        mute\tout mute\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; : > "$H/fullscreen"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog" "$amlog"
    mkdir -p "$H/ft"; ln -sf "$(command -v sh)" "$H/ft/foot"   # the panel's parent must be a foot: a shell by that name stands in, and writes its pid for the stub's tree
    out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 "$H/ft/foot" -c 'echo $$ > "$HOME/panel.ppid"; sh "$1" panel 2>&1 </dev/null; echo "exit $?"' foot "$SH"); st=${out##*exit }
    [ "$st" = 0 ] && [ "$(cat "$H/fzf.calls")" = 2 ] && [ "$(grep 'fullscreen\|focus' "$swlog" | tr '\n' '|')" = '[con_id=77] fullscreen disable|[app_id=spark-dialog] focus|[con_id=77] fullscreen enable|' ] && grep -qx -- '-c 0 sset Master mute' "$amlog" \
        && ok "the window under a fullscreen one: the window steps aside and the panel is focused over it; after the pick and Esc it is fullscreen again" || bad "window fullscreen" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) sway=$(tr '\n' '|' < "$swlog" 2>&1) out=$(printf '%s' "$out" | tr -d '\033' | tr '\n' '|' | tail -c 200)"
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
: > "$SPARK_SHELL_ASIDE"; exit 130
STUB
    rm -f "$swlog"
    out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 "$H/ft/foot" -c 'echo $$ > "$HOME/panel.ppid"; sh "$1" panel 2>&1 </dev/null; echo "exit $?"' foot "$SH"); st=${out##*exit }
    [ "$st" = 0 ] && [ "$(grep 'fullscreen' "$swlog" | tr '\n' '|')" = '[con_id=77] fullscreen disable|' ] \
        && ok "the window under a fullscreen one: placed otherwise while the panel is up, it stays as placed" || bad "window aside placed" "st=$st sway=$(tr '\n' '|' < "$swlog" 2>&1) out=$out"
    cat > "$H/.local/bin/fzf" <<'STUB'
#!/bin/sh
case $1 in --version) echo 0.60.3; exit 0 ;; esac
n=$(cat "$HOME/fzf.calls" 2>/dev/null || echo 0); n=$((n + 1)); echo "$n" > "$HOME/fzf.calls"
cat > "$HOME/fzf.in.$n"; printf '%s\n' "$*" > "$HOME/fzf.args.$n"
if [ "$n" -eq 1 ]; then printf '\n  apps       firefox\tapps open firefox\n'; exit 0; else exit 130; fi
STUB
    chmod +x "$H/.local/bin/fzf"; rm -f "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    out=$(SWAYSOCK=/tmp/x SPARK_SHELL_TEST_TTY=1 "$H/ft/foot" -c 'echo $$ > "$HOME/panel.ppid"; sh "$1" panel 2>&1 </dev/null; echo "exit $?"' foot "$SH"); st=${out##*exit }
    [ "$st" = 0 ] && [ "$(cat "$H/fzf.calls")" = 1 ] && grep -q '^\[con_id=77\] fullscreen disable$' "$swlog" && grep -q '^exec firefox' "$swlog" && ! grep -q 'fullscreen enable' "$swlog" \
        && ok "the window under a fullscreen one, an app picked: the panel closes and the window stays as it is, the app has the screen" || bad "window fullscreen app" "st=$st calls=$(cat "$H/fzf.calls" 2>&1) sway=$(tr '\n' '|' < "$swlog" 2>&1)"
    rm -rf "$H/fullscreen" "$H/panel.ppid" "$H/ft" "$H/.local/bin/fzf" "$H/fzf.calls" "$H/fzf.in."* "$H/fzf.args."* "$journal/undo" "$journal/recent" "$swlog"
    rm -f "$H/.local/bin/spark"
    rm -f "$H/.local/bin/amixer" "$P/asound/cards"
    out=$(PATH=$H/.local/bin:$H/no-pipewire sh "$SH" check || true); printf '%s\n' "$out" | grep -q '^warn   sound        no audio system found, so no out or mic block -- spark-shell on desktop$' \
        && ok "check: no audio system is a warn with the package to install, never a FAIL" || bad "check sound warn" "$out"
    printf 'DESKTOP_BAR=maybe\n' > "$HOME/.config/spark-shell/config"
    sh "$SH" status >/dev/null 2>&1 && bad "DESKTOP_BAR=maybe accepted" || ok "config: DESKTOP_BAR=maybe is refused"
    _br=''; for _bk in BAR_POSITION=left BAR_TEXT=5 BAR_TEXT=big BAR_TRAY=maybe; do printf '%s\n' "$_bk" > "$HOME/.config/spark-shell/config"; ! sh "$SH" status >/dev/null 2>&1 || _br="$_br $_bk"; done
    [ -z "$_br" ] && ok "config: BAR_POSITION=left, BAR_TEXT=5 and big, BAR_TRAY=maybe are refused" || bad "bar keys accepted" "$_br"
    # the bar's text, auto: the text size on 1080 rows, by the square root of the rows over 1080 on a taller screen, the shortest side of the shortest screen on deciding
    printf 'DESKTOP=sway\nFONT=DejaVu Sans Mono:size=11\n' > "$HOME/.config/spark-shell/config"
    if command -v python3 >/dev/null 2>&1; then
        mkdir -p "$H/bt-sway"; rm -f "$H/bt.sock"; python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$H/bt.sock"
        printf '#!/bin/sh\ncase "$*" in "-t get_outputs") printf %%s "$BT_OUTPUTS" ;; esac\n' > "$H/bt-sway/swaymsg"; chmod +x "$H/bt-sway/swaymsg"
        _bto() { BT_OUTPUTS=$1 SWAYSOCK=$H/bt.sock PATH=$H/bt-sway:$PATH sh "$SH" bar text 2>&1; }
        _b1=$(_bto '[{"active":true,"rect":{"width":1920,"height":1080}}]'); _b2=$(_bto '[{"active":true,"rect":{"width":2560,"height":1440}}]')
        _b3=$(_bto '[{"active":true,"rect":{"width":3840,"height":2160}}]'); _b4=$(_bto '[{"active":true,"rect":{"width":3840,"height":2160}},{"active":true,"rect":{"width":1920,"height":1080}},{"active":false,"rect":{"width":800,"height":600}}]')
        _b5=$(_bto '[{"active":true,"rect":{"width":1080,"height":1920}}]'); _b6=$(_bto '[{"active":true,"rect":{"width":1920,"height":1080}}]' | head -1)
        _bw="$SEP the text size, larger on a screen of many pixels"
        [ "$_b1" = "bar text auto, 11 now $_bw" ] && [ "$_b2" = "bar text auto, 13 now $_bw" ] && [ "$_b3" = "bar text auto, 16 now $_bw" ] && [ "$_b4" = "bar text auto, 11 now $_bw" ] && [ "$_b5" = "bar text auto, 11 now $_bw" ] \
            && ok "bar text auto: 11 on 1080 rows, 13 on 1440, 16 on 2160; beside a 1080 screen and an inactive one, 11; a screen on its side counts its shorter side" || bad "bar text auto" "$_b1 | $_b2 | $_b3 | $_b4 | $_b5"
        rm -rf "$H/bt-sway" "$H/bt.sock"
    fi
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    st=0; out=$(PATH=$H/.local/bin:$sys sh "$SH" bar sideways 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell panel: spark is not installed -- spark reads what you want (github.com/forgewright-ai/spark)' ] && ok "bar WORDS without spark: refused in one line" || bad "bar want no spark" "st=$st $out"
    # off takes the ALSA file spark-shell wrote, never one of yours
    printf '# rendered by spark-shell (bar): the sound card for programs started from now -- spark-shell off removes it\ndefaults.pcm.!card HDMI\ndefaults.ctl.!card HDMI\n' > "$H/.config/alsa/asoundrc"
    sh "$SH" off >/dev/null
    [ ! -e "$H/.config/alsa/asoundrc" ] && ok "off: the asoundrc spark-shell wrote is removed" || bad "off asoundrc"
    mkdir -p "$H/.config/alsa"; printf 'pcm.!default { type hw card 1 }\n' > "$H/.config/alsa/asoundrc"
    sh "$SH" off >/dev/null
    [ "$(cat "$H/.config/alsa/asoundrc")" = 'pcm.!default { type hw card 1 }' ] && ok "off: an asoundrc of yours stays" || bad "off asoundrc yours"
fi
unset SPARK_SHELL_SYS SPARK_SHELL_PROC SWAYSOCK

fi

# --- 21. the providers: a section as an MCP server, the want verb, the dialog's keys
if want 21; then
# `spark-shell provide SECTION` driven on a pipe by a scripted client:
# each request a jq line, every line out parsed. The Linux half reads
# the bar's fixture (wpa_cli, bluetoothctl, amixer stubs).
fresh
desktop_stubs
layout_stubs
bar_fixture
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
init=$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{"elicitation":{}},"clientInfo":{"name":"test","version":"0"}}')
mcp theme "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 2 tools/list)" "$(rq 3 ping)"
st=$?; [ "$st" -eq 0 ] && [ "$(ans 1 | jq -r '.result.protocolVersion + " " + .result.serverInfo.name')" = '2025-06-18 theme' ] && ans 1 | jq -e '.result.capabilities == {tools: {listChanged: true}, resources: {subscribe: true, listChanged: true}, logging: {}}' >/dev/null \
    && [ "$(grep -c '' "$H/mcp.out")" = 3 ] && [ "$(ans 3 | jq -c .result)" = '{}' ] \
    && ok "provide: initialize answers 2025-06-18, the section as the server's name, tools, resources with subscribe, logging; a notification gets no answer; ping is {}" || bad "provide initialize" "st=$st $(cat "$H/mcp.out" "$H/mcp.err")"
ans 1 | jq -e '.result.serverInfo.title | test("^none")' >/dev/null && ok "provide: the server's title is the context title, the panel's title line (the palette in use)" || bad "provide title" "$(ans 1)"
jq -e -s 'all(.[]; .jsonrpc == "2.0")' "$H/mcp.out" >/dev/null && ok "provide: every line on stdout is a JSON-RPC 2.0 message, nothing else" || bad "provide stdout" "$(cat "$H/mcp.out")"
long=$(awk 'BEGIN { s = "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"ping\",\"params\":{\"x\":\""; while (length(s) < 70000) s = s "aaaaaaaaaa"; print s "\"}}" }')
mcp theme 'not json' '[1,2]' '{"jsonrpc":"2.0","id":null,"method":"ping"}' '{"jsonrpc":"1.0","id":4,"method":"ping"}' "$(rq 5 prompts/list)" "$long" "$(rq 6 ping)"
[ "$(jq -r -s 'map(.error.code // "ok") | map(tostring) | join(" ")' "$H/mcp.out")" = '-32700 -32600 -32600 -32600 -32601 -32600 ok' ] && [ "$(ans 6 | jq -c .result)" = '{}' ] \
    && ok "provide: bad JSON -32700, an array, a null id, the wrong jsonrpc and a line over 64 kB -32600, a method it lacks -32601; the server goes on" || bad "provide errors" "$(cat "$H/mcp.out")"
# the shipped wallpapers: each name in WALL_SHIPPED has its SVG source and a PNG of 3840 by 2160 in gallery/wallpaper/, and nothing else is there
_wb=''
for n in $(sed -n 's/^WALL_SHIPPED="\(.*\)"$/\1/p' "$SRC" | tr ' ' '\n' | cut -d: -f1); do
    [ -f "$REPO/gallery/wallpaper/$n.svg" ] && [ -f "$REPO/gallery/wallpaper/$n.png" ] && [ "$(od -An -tu1 -j16 -N8 "$REPO/gallery/wallpaper/$n.png" | tr -s ' \n' ' ' | sed 's/^ //; s/ $//')" = '0 0 15 0 0 0 8 112' ] || _wb="$_wb $n"
done
for _mf in "$REPO"/lib/motion_*.py; do _mn=${_mf##*/motion_}; wall_n=${_mn%.py}; grep -q "[ \"]$wall_n:" "$SRC" || _wb="$_wb motion_$_mn"; done
[ -f "$REPO/lib/wallpaper.py" ] || _wb="$_wb wallpaper.py"
[ -z "$_wb" ] && [ "$(ls "$REPO/gallery/wallpaper" | wc -l | tr -d ' ')" = 36 ] && ok "gallery/wallpaper/: the 18 drawings, each its SVG and a 3840 by 2160 PNG; lib/motion_NAME.py a script of a shipped one alone, lib/wallpaper.py the scenes'" || bad "wallpaper files" "$_wb $(ls "$REPO/gallery/wallpaper")"
# every tool of every section: one name shape, one title shape, the hints spelled out, the destructive and read-only ones named
: > "$H/tools.all"
for s in lan wifi bt printers out mic bat clock theme window display keyboard pointer notifications storage power notes reminders bar layout apps tools about undo files; do mcp "$s" "$(rq 1 tools/list)"; ans 1 | jq -c '.result.tools[]' >> "$H/tools.all"; done
[ "$(grep -c '' "$H/tools.all")" = 158 ] && [ "$(jq -r .name "$H/tools.all" | sort | paste -sd ' ' -)" = "$(sed -n 's/^PROVIDE_TOOLS="\(.*\)"$/\1/p' "$SRC" | tr ' ' '\n' | sort | paste -sd ' ' -)" ] \
    && ok "provide: the twenty-five sections hold the 158 tools of PROVIDE_TOOLS, each once" || bad "provide tool count" "$(jq -r .name "$H/tools.all" | paste -sd ' ' -)"
jq -e -s 'any(.name == "pointer_speed" and .inputSchema.properties.value.type == "number" and .inputSchema.properties.value.minimum == -1 and .inputSchema.properties.value.maximum == 1) and any(.name == "keyboard_repeat_delay" and .inputSchema.properties.value.minimum == 100)' "$H/tools.all" >/dev/null \
    && ok "input tools: numeric bounds reach the decision model" || bad "input schemas"
mcp pointer "$(call 1 pointer_speed '{"value":2}')"
[ "$(ans 1 | jq -r .error.code)" = -32602 ] && ok "pointer MCP: an invalid speed is refused before native execution" || bad "pointer MCP bounds" "$(cat "$H/mcp.out")"
mcp notes "$(call 1 notes_add '{"text":"AX result fixture"}')" "$(call 2 notes_add '{"text":"AX result fixture: one more line"}')" "$(call 3 notes_find '{"words":"AX result fixture"}')"
ans 1 | jq -e '.result.isError == false and .result.structuredContent.effect == {kind:"note",operation:"created",id:"ax-result-fixture.md",title:"AX result fixture"}' >/dev/null \
    && ans 2 | jq -e '.result.structuredContent.effect.operation == "appended" and .result.structuredContent.effect.id == "ax-result-fixture.md"' >/dev/null \
    && ans 3 | jq -e '.result.structuredContent | has("effect") | not' >/dev/null \
    && grep -qx -- '- one more line' "$H/notes/ax-result-fixture.md" \
    && ok "provide notes: results identify the actual created or appended file, with no stale effect on the next call" || bad "note result" "$(ans 1) $(ans 2) $(ans 3)"
# the words given are the words kept: dash's echo read a backslash in them as an escape, and \c cut the rest
mcp notes "$(call 1 notes_add "$(jq -cn --arg t 'the folder C:\new\temp and \cut this part' '{text: $t}')")"
_nf=$(ans 1 | jq -r '.result.structuredContent.effect.id')
[ "$(sed -n 1p "$H/notes/$_nf")" = '# the folder C:\new\temp and \cut this part' ] && ok "provide notes: a backslash in the words stays a backslash, and nothing after it is cut" || bad "note backslash" "$(ans 1) $(cat "$H/notes/$_nf" 2>&1)"
# a call's answer carries the section's rows as the step left them, and no note that they changed follows it: the host
# shows them and reads nothing again (#196); a host's step writes neither the panel's recent picks nor its undo journal
rm -f "$H/.local/state/spark-shell/panel/recent" "$H/.local/state/spark-shell/panel/undo"
mcp notes "$(rq 1 resources/subscribe '{"uri":"spark-shell://notes/rows"}')" "$(call 2 notes_add '{"text":"rows in the answer"}')"
ans 2 | jq -e '.result.isError == false and .result.structuredContent.rows.title == "notes" and any(.result.structuredContent.rows.rows[]; .id == "notes:open rows-in-the-answer.md")
        and (.result.content[0].text | fromjson | has("rows") | not)' >/dev/null \
    && ! grep -q 'notifications/resources/updated' "$H/mcp.out" \
    && [ ! -e "$H/.local/state/spark-shell/panel/recent" ] && [ ! -e "$H/.local/state/spark-shell/panel/undo" ] \
    && ok "provide: a call answers with the section's rows as the step left them, no rows-changed note after it, and no entry in the panel's recent picks or undo journal (#196)" || bad "call answers with rows" "$(head -c 600 "$H/mcp.out")"
if command -v strace >/dev/null 2>&1; then   # the processes a call starts, over the provider's own start: a budget (#196)
    spawns() { printf '%s\n' "$@" | strace -f -e trace=execve -o "$H/execve" sh "$SH" provide notes >/dev/null 2>&1; grep -c 'execve(' "$H/execve"; }
    mv "$H/notes" "$H/notes.kept"; mkdir "$H/notes"   # an empty notes folder: a read's cost grows with the notes, a call's should not
    _base=$(spawns "$(rq 1 ping)")
    _calln=$(( $(spawns "$(call 1 notes_add '{"text":"a budget"}')") - _base ))
    _refn=$(( $(spawns "$(rq 1 resources/read '{"uri":"spark-shell://notes/rows"}')" "$(call 2 notes_open '{"name":"no-such.md"}')") - _base ))
    rm -rf "$H/notes"; mv "$H/notes.kept" "$H/notes"
    [ "$_calln" -lt 100 ] && [ "$_refn" -lt 60 ] \
        && ok "provide: a note added, its rows in the answer, starts $_calln processes past the provider's start (under 100); a read and a refused call $_refn (under 60) (#196)" \
        || bad "call spawn budget" "call $_calln, read and refusal $_refn: $(grep -o 'execve("[^"]*"' "$H/execve" | sort | uniq -c | sort -rn | head -8 | tr '\n' ' ')"
else
    printf '  NOTICE: strace is not installed -- the call'"'"'s process budget not counted\n'
fi
# the reads (#196): the palettes, their chips and the desktop entries are read again only when their folders change;
# a palette added is in the next read; a section the desktop does not change behind the dialog has no watcher
if command -v strace >/dev/null 2>&1; then
    readn() { printf '%s\n' "$(rq 1 resources/read "{\"uri\":\"spark-shell://$1/rows\"}")" | strace -f -e trace=execve -o "$H/execve" sh "$SH" provide "$1" >/dev/null 2>&1; grep -c 'execve(' "$H/execve"; }
    pingn() { printf '%s\n' "$(rq 1 ping)" | strace -f -e trace=execve -o "$H/execve" sh "$SH" provide "$1" >/dev/null 2>&1; grep -c 'execve(' "$H/execve"; }
    readn theme >/dev/null; readn apps >/dev/null   # the caches made
    _th=$(( $(readn theme) - $(pingn theme) )); _ap=$(( $(readn apps) - $(pingn apps) ))
    [ "$_th" -lt 60 ] && [ "$_ap" -lt 60 ] \
        && ok "provide: a rows read on a warm cache starts $_th processes for theme and $_ap for apps past the provider's start, each under 60 (#196)" \
        || bad "read spawn budget" "theme $_th, apps $_ap: $(grep -o 'execve("[^"]*"' "$H/execve" | sort | uniq -c | sort -rn | head -8 | tr '\n' ' ')"
fi
# one probe per rows read (#196): the title, the short form and the full form share each device's answer, and the next
# read asks again. A stub of each tool counts its calls: two reads in one provider, less a provider that only pings,
# ask each probe twice (each note's time and the calendar's files too)
if [ "$(uname -s)" != Darwin ]; then
    mkdir -p "$H/once" "$H/sys/class/backlight/panel" "$HOME/calendar"; rm -f "$H/.local/state/spark-shell/panel/bt.list"
    cp "$HOME/.config/spark-shell/config" "$H/config.once"; printf 'DESKTOP=sway\nKEYBOARD=us br\n' > "$HOME/.config/spark-shell/config"
    printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:spark-shell-once-196\r\nDTSTART:%s\r\nSUMMARY:the probe test\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(date -d '+2 days' +%Y%m%dT090000)" > "$HOME/calendar/once-196.ics"
    cat > "$H/once/stub" <<'STUB'
#!/bin/sh
t=${0##*/}; printf '%s %s\n' "$t" "$*" >> "$HOME/once.log"
case $t in stat) PATH=$ONCE_PATH; export PATH; exec stat "$@" ;; esac
case "$t $*" in
    'wpctl status') printf 'Audio\n |- Sinks:\n |  *   50. Studio Speakers [vol: 0.40]\n |      51. HDMI Output [vol: 1.00]\n |\n |- Sources:\n |  *   52. Studio Mic [vol: 0.50]\n |\n' ;;
    'wpctl get-volume '*) echo 'Volume: 0.40' ;;
    pw-dump*) echo '[]' ;;
    dbus-send*) echo 'boolean true' ;;
    'bluetoothctl show') printf 'Controller 00:11:22:33:44:55 (public)\n\tPowered: yes\n' ;;
    'bluetoothctl devices'*) echo 'Device 00:25:D1:4A:C2:AA MAJOR V' ;;
    lsblk*) echo '{"blockdevices": [{"name":"sdb","path":"/dev/sdb","type":"disk","rm":true,"hotplug":true,"size":31004295168,"model":"Ultra","vendor":"SanDisk","label":null,"fstype":null,"mountpoint":null,
        "children":[{"name":"sdb1","path":"/dev/sdb1","type":"part","rm":true,"hotplug":true,"size":31003246592,"label":"STICK","fstype":"exfat","mountpoint":"/run/media/ada/STICK"}]}]}' ;;
    df*) printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/x 30000000 27000000 3000000 90%% /\n' ;;
    'makoctl mode') echo default ;;
    'makoctl list') printf 'Notification 9: Download complete\n  App name: firefox\n' ;;
    'makoctl history') printf 'Notification 5: Build passed\n  App name: aerc\n' ;;
    'swaymsg -t get_inputs') echo '[{"type":"keyboard","xkb_layout_names":["English (US)","Portuguese (Brazil)"],"xkb_active_layout_index":1}]' ;;
    'swaymsg -t get_outputs') echo '[{"name":"DP-1","active":true,"make":"Fake","model":"Screen","serial":"1","scale":1,"rect":{"x":0,"y":0,"width":2560,"height":1440},"current_mode":{"width":2560,"height":1440,"refresh":60000}}]' ;;
    'brightnessctl -m -c backlight info') echo 'panel,backlight,750,75%,1000' ;;
esac
STUB
    chmod +x "$H/once/stub"
    for t in wpctl pw-dump dbus-send bluetoothctl lsblk df makoctl mako swaymsg brightnessctl stat; do ln -sf stub "$H/once/$t"; done
    ONCE_PATH=$PATH; export ONCE_PATH   # the stub's stat runs the real one
    asks() {   # asks SECTION PATTERN -> the calls PATTERN matches in two rows reads, less a provider that only pings; the second read's rows in $H/once.json
        rm -f "$HOME/once.log"; rq 1 ping | SWAYSOCK=$H/sock PATH="$H/once:$PATH" sh "$SH" provide "$1" >/dev/null 2>&1
        _ab=$(grep -c -- "$2" "$HOME/once.log" 2>/dev/null || :)
        rm -f "$HOME/once.log"; printf '%s\n' "$(rq 1 resources/read "{\"uri\":\"spark-shell://$1/rows\"}")" "$(rq 2 resources/read "{\"uri\":\"spark-shell://$1/rows\"}")" \
            | SWAYSOCK=$H/sock PATH="$H/once:$PATH" sh "$SH" provide "$1" 2>/dev/null | jq -r 'select(.id == 2) | .result.contents[0].text' > "$H/once.json"
        echo $(( $(grep -c -- "$2" "$HOME/once.log" 2>/dev/null || :) - ${_ab:-0} ))
    }
    _ob=''; _os=''
    for c in 'out:wpctl status' 'out:wpctl get-volume @DEFAULT_AUDIO_SINK@' 'mic:wpctl get-volume @DEFAULT_AUDIO_SOURCE@' 'mic:pw-dump' \
        'bt:dbus-send' 'bt:bluetoothctl show' 'bt:bluetoothctl devices Connected' 'storage:lsblk' 'storage:df -Pk /$' 'storage:df -Pk /run/media/ada/STICK' \
        'notifications:makoctl mode$' 'notifications:makoctl list' 'notifications:makoctl history' 'keyboard:swaymsg -t get_inputs' \
        'display:swaymsg -t get_outputs' 'display:brightnessctl' 'reminders:stat -c %n %s %Y'; do
        _n=$(asks "${c%%:*}" "${c#*:}"); [ "$_n" = 2 ] || _ob="$_ob [$c] $_n"
        _os="$_os$(jq -r '.state' "$H/once.json" 2>/dev/null)|"
    done
    _nn=$(ls "$HOME/notes"/*.md 2>/dev/null | wc -l | tr -d ' '); _n=$(asks notes "stat -c %Y $HOME/notes/"); [ "$_n" = $((2 * _nn)) ] || _ob="$_ob [notes] $_n of $((2 * _nn))"
    _sp=" $(printf '\302\267') "; _dt=$(printf '\342\227\217')   # the panel's middle dot and its dot for in use
    [ -z "$_ob" ] && [ "$_nn" -gt 0 ] && [ "$_os" = "Studio Speakers${_sp}40%|Studio Speakers${_sp}40%|Studio Mic${_sp}40%|Studio Mic${_sp}40%|$_dt MAJOR V|$_dt MAJOR V|$_dt MAJOR V|1 drive|1 drive|1 drive|1 on the screen|1 on the screen|1 on the screen|br${_sp}2 layouts|brightness 75%|brightness 75%|0 today, 1 after|" ] \
        && ok "provide: one rows read asks each device, list and file once, its title, short form and full form sharing the answer, and the next read asks again: sound, bluetooth, drives, notifications, keyboard, screens, brightness, notes and reminders (#196)" \
        || bad "one probe per read" "asked otherwise:$_ob; states: $_os"
    cp "$H/config.once" "$HOME/.config/spark-shell/config"; rm -rf "$H/once" "$H/sys/class/backlight" "$HOME/calendar/once-196.ics" "$H/.local/state/spark-shell/panel/bt.list" "$HOME/once.log" "$H/once.json" "$H/config.once"; unset ONCE_PATH
fi
mkdir -p "$H/.config/spark-shell/themes"; cp "$REPO/gallery/theme/nord.env" "$H/.config/spark-shell/themes/cache-196.env"
mcp theme "$(rq 1 resources/read '{"uri":"spark-shell://theme/rows"}')"
ans 1 | jq -r '.result.contents[0].text' | jq -e 'any(.rows[]; .text == "cache-196" and .group == "dark" and (.chip | length) == 9)' >/dev/null \
    && ok "provide: a palette added is a row of the next read, dark and with its chip: the cache saw its folder change (#196)" || bad "palette cache" "$(head -c 400 "$H/mcp.out")"
rm -f "$H/.config/spark-shell/themes/cache-196.env"
: > "$H/mcp.out"
{ rq 1 resources/subscribe '{"uri":"spark-shell://notes/rows"}'; sleep 1; printf 'made behind its back\n' > "$H/notes/behind-196.md"; sleep 2.5
  rq 2 resources/unsubscribe '{"uri":"spark-shell://notes/rows"}'; } | SPARK_SHELL_PROVIDE_POLL=1 sh "$SH" provide notes > "$H/mcp.out" 2> "$H/mcp.err"
! grep -q 'notifications/resources/updated' "$H/mcp.out" && [ "$(jq -s 'length' "$H/mcp.out")" = 2 ] \
    && ok "provide: notes, which only a step changes, has no watcher: a subscribed host is sent no rows-changed note (#196)" || bad "notes unwatched" "$(cat "$H/mcp.out")"
rm -f "$H/notes/behind-196.md"
printf '# Shopping list\n- oat milk\n' > "$H/notes/shop-169.md"; printf 'plain first line\nthe vet on friday\n' > "$H/notes/vet-169.md"
mcp notes "$(rq 1 resources/read '{"uri":"spark-shell://notes/rows"}')" "$(rq 2 resources/read "{\"uri\":\"spark-shell://notes/page/$(b64u 'notes:open shop-169.md')\"}")" "$(rq 3 resources/read "{\"uri\":\"spark-shell://notes/rows/find/$(b64u 'vet friday')\"}")"
ans 1 | jq -r '.result.contents[0].text' | jq -e '([.rows[] | select(.id == "notes:open shop-169.md")][0] | ([.more[].name] == ["notes_append", "notes_rename", "notes_trash"]) and (.page | startswith("spark-shell://notes/page/"))) and ([.rows[] | select(.text | startswith("append to"))] == [])' >/dev/null \
    && ans 2 | jq -r '.result.contents[0].text' | jq -e '.lines == ["Shopping list", "- oat milk"]' >/dev/null \
    && ans 3 | jq -r '.result.contents[0].text' | jq -e '[.rows[].id] == ["notes:open vet-169.md"]' >/dev/null \
    && ok "provide notes: append, rename and trash behind a note's row, no row of its own for append; Space shows the note; the notes that say every word, for a search from Home (#169)" || bad "notes steps" "$(head -c 900 "$H/mcp.out")"
export SPARK_SHELL_NO_GIO=1   # the trash by the spec here: a Mac's Homebrew gio would put the note in this Mac's own Trash
mcp notes "$(call 1 notes_rename '{"name":"shop-169.md","to":"Groceries"}')" "$(call 2 notes_rename '{"name":"vet-169.md","to":"Luna at the vet"}')" "$(call 3 notes_trash '{"name":"vet-169.md"}')" "$(call 4 notes_rename '{"name":"../x.md","to":"no"}')"
[ "$(sed -n 1p "$H/notes/shop-169.md")" = '# Groceries' ] && ans 1 | jq -e '.result.structuredContent == {receipt: "Shopping list renamed to Groceries", undo: {name: "notes_rename", arguments: {name: "shop-169.md", to: "Shopping list"}}}' >/dev/null \
    && ans 2 | jq -e '.result.structuredContent.undo.arguments.to == "plain first line"' >/dev/null \
    && [ ! -e "$H/notes/vet-169.md" ] && ans 3 | jq -e '.result.structuredContent.undo == {name: "notes_restore", arguments: {name: "vet-169.md"}}' >/dev/null && [ "$(ans 4 | jq -r .error.code)" = -32602 ] \
    && ok "notes rename: the first line takes the new title, its hashes kept, a plain line stays plain, undo the old title; trash: the note in the trash, undo restores it; a path is refused (#169)" || bad "notes rename trash" "$(cat "$H/mcp.out")"
mcp notes "$(call 1 notes_restore '{"name":"vet-169.md"}')"
[ "$(sed -n 1p "$H/notes/vet-169.md" 2>&1)" = 'Luna at the vet' ] && ans 1 | jq -e '.result.structuredContent.undo.name == "notes_trash"' >/dev/null && ok "notes restore: the note back from the trash as it was (#169)" || bad "notes restore" "$(cat "$H/mcp.out") $(ls "$H/notes")"
rm -f "$H/notes/shop-169.md" "$H/notes/vet-169.md"; unset SPARK_SHELL_NO_GIO
printf '#!/bin/sh\ncase "$1" in +%%s) echo 1234567890 ;; *) exec %s "$@" ;; esac\n' "$(command -v date)" > "$H/.local/bin/date"
chmod +x "$H/.local/bin/date"
mcp reminders "$(call 1 reminders_add '{"words":"2099-01-01 10:00 AX result fixture"}')" "$(call 2 reminders_add '{"words":"2099-01-02 10:00 AX second fixture"}')"
rm -f "$H/.local/bin/date"
_effect_id=$(ans 1 | jq -r '.result.structuredContent.effect.id')
_effect_id2=$(ans 2 | jq -r '.result.structuredContent.effect.id')
ans 1 | jq -e '.result.isError == false and (.result.structuredContent.effect | .kind == "reminder" and .operation == "created" and .title == "AX result fixture" and .localTime == "2099-01-01 10:00")' >/dev/null \
    && grep -lF "UID:$_effect_id" "$H/calendar/"*.ics >/dev/null \
    && ok "provide reminders: the result carries the saved event identity and local time" || bad "reminder result" "$(ans 1)"
[ "$_effect_id" != "$_effect_id2" ] && grep -lF "UID:$_effect_id2" "$H/calendar/"*.ics >/dev/null \
    && ok "provide reminders: two additions in the same second keep both events with distinct identities" || bad "reminder identity" "$(ans 1) $(ans 2)"
rm -f "$H/notes/ax-result-fixture.md"
for _effect_file in "$H/calendar/"*.ics; do
    if grep -qF "UID:$_effect_id" "$_effect_file" || grep -qF "UID:$_effect_id2" "$_effect_file"; then rm -f "$_effect_file"; fi
done
# the brightness takes the gate's own words, up, down or 1 to 100: a planner told 0 to 100 and no step sent a 0 the gate
# refused, and the dialog's brighter and dimmer rows send up and down (#31). spark's grammar types an argument one
# way, so a string enum holds both, the tens first: a brief names an enum's first twelve
mcp display "$init" "$(call 2 display_brightness '{"level":0}')" "$(call 3 display_brightness '{"level":"down"}')" "$(call 4 display_brightness '{"level":"30"}')"
jq -e -s '(map(select(.name == "display_brightness"))[0].inputSchema.properties.level | .type == "string" and .enum[0:12] == ["up", "down", "10", "20", "30", "40", "50", "60", "70", "80", "90", "100"] and (.enum | length) == 102 and (.enum | index("1") != null and index("99") != null and index("0") == null))
    and (map(select(.name == "out_level"))[0].inputSchema.properties.level | [.minimum, .maximum]) == [0, 100]' "$H/tools.all" >/dev/null \
    && [ "$(ans 2 | jq -r .error.message)" = 'display_brightness: level is up, down or a whole number, 1 to 100' ] && [ "$(ans 3 | jq -c .error)" = null ] && [ "$(ans 4 | jq -c .error)" = null ] \
    && ok "provide: display_brightness takes up, down or 1 to 100, in its schema and its arguments' check, as its gate does; out_level 0 to 100 (#31)" || bad "brightness schema" "$(jq -c 'select(.name == "display_brightness") | .inputSchema' "$H/tools.all" | cut -c1-200) $(ans 2) $(ans 3) $(ans 4)"
# the rows carry the section's state, the dialog's subtitle, read again with every rows read
mcp theme "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}')" "$(rq 2 resources/read '{"uri":"spark-shell://theme/rows"}')"
ans 2 | jq -r '.result.contents[0].text' | jq -e '.title == "theme" and (.state | type == "string" and length > 0)' >/dev/null \
    && ok "provide: a rows read carries the section's state beside its title, so a subtitle follows each step" || bad "rows state" "$(ans 2 | head -c 300)"
# the wallpaper's picture: a path, no row of it (the dialog's pick), so its own gate: under home, no link, nothing hidden, a picture's type
mkdir -p "$H/Pictures" "$H/.hid"; printf 'x' > "$H/Pictures/sea.png"; printf 'x' > "$H/.hid/sea.png"; printf 'x' > "$H/Pictures/sea.txt"; PH=$(realpath "$H")
mcp theme "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}')" \
    "$(call 2 theme_wallpaper_picture "$(jq -cn --arg p "$PH/.hid/sea.png" '{path: $p}')")" "$(call 3 theme_wallpaper_picture "$(jq -cn --arg p "$PH/Pictures/sea.txt" '{path: $p}')")" "$(call 4 theme_wallpaper_picture '{"path":"/etc/hosts"}')"
[ "$(ans 2 | jq -r '.result.content[0].text')" = 'wallpaper: a hidden file is not offered' ] && [ "$(ans 3 | jq -r '.result.content[0].text')" = 'wallpaper: a picture is jpg jpeg png webp' ] && [ "$(ans 4 | jq -r '.result.content[0].text')" = 'wallpaper: a picture comes from under your home' ] \
    && ok "provide theme_wallpaper_picture: a path no row holds, held to its own gate: a hidden file, a type that is no picture, a path outside home refused" || bad "wallpaper picture gate" "$(cat "$H/mcp.out")"
jq -e -s 'all(.[]; (.name | test("^[a-z][a-z0-9_]{0,63}$")) and (.title | test("^[a-z][a-z-]*( [a-z-]+| [A-Z]+)*$")) and (.title | length) <= 60)' "$H/tools.all" >/dev/null \
    && ok "provide: every tool name is lower case with underscores, every title a sentence of plain words with its argument in capitals, 60 at most" || bad "tool shapes" "$(jq -r '.name + " | " + .title' "$H/tools.all")"
jq -e -s 'all(.[]; .annotations | (.readOnlyHint | type) == "boolean" and (.destructiveHint | type) == "boolean" and (.idempotentHint | type) == "boolean" and .openWorldHint == false)' "$H/tools.all" >/dev/null \
    && [ "$(jq -r 'select(.annotations.destructiveHint) | .name' "$H/tools.all" | sort | paste -sd ' ' -)" = 'bt_remove files_empty files_purge power_logout power_restart power_shutdown printers_cancel theme_delete tools_end wifi_forget wifi_setup window_close' ] \
    && [ "$(jq -r 'select(.annotations.readOnlyHint) | .name' "$H/tools.all" | paste -sd ' ' -)" = 'notes_find tools_check tools_measure about_open files_show files_attach files_find files_say' ] \
    && ok "provide: every hint spelled out (the spec's default is destructive); destructive only where something is lost (#112): forget, close, remove, delete, delete for good and empty the trash (#130), the power steps, a print job cancelled, the network manager installed, a program ended (v0.129); the network, clock and printer settings carry undo instead; read only: notes find, the check and the measure of tools, about, files show, attach, find and say" || bad "tool hints" "$(jq -c '[.name, .annotations]' "$H/tools.all")"
[ "$(jq -r 'select(._meta["spark-shell/opens"] == true) | .name' "$H/tools.all" | sort | paste -sd ' ' -)" = 'about_site apps_open apps_terminal files_app files_browse files_open files_reveal notes_open power_lock storage_open tools_clean_packages tools_fix tools_front tools_update tools_update_system window_focus' ] \
    && [ "$(jq -s '[.[] | select(._meta != null and ._meta != {"spark-shell/opens": true} and ._meta != {"spark-shell/opens": true, "spark-shell/person": true})] | length' "$H/tools.all")" = 0 ] \
    && [ "$(jq -r 'select(._meta["spark-shell/person"] == true) | .name' "$H/tools.all" | sort | paste -sd ' ' -)" = 'tools_clean_packages tools_fix tools_update tools_update_system' ] \
    && ok "provide: the tools that put a window in front say so (_meta spark-shell/opens), so the dialog steps aside at the click (#196); a person's step says so too (spark-shell/person: a terminal, or sudo, v0.129.2); no other _meta" || bad "tool opens" "$(jq -c 'select(._meta) | [.name, ._meta]' "$H/tools.all")"
# a person's step to the dialog alone (v0.129.2): another client that names itself (spark's MCP list, the prompt line, spark
# do) neither sees it nor calls it; the suite's raw requests, which name no client, see every tool
pinit() { rq 0 initialize "$(jq -cn --arg n "$1" '{protocolVersion: "2025-06-18", capabilities: {}, clientInfo: {name: $n, version: "1"}}')"; }
mcp tools "$(pinit spark-dialog)" "$(rq 1 tools/list)"; _pd=$(ans 1 | jq -r '[.result.tools[].name] | join(" ")')
mcp tools "$(pinit spark)" "$(rq 1 tools/list)" "$(call 2 tools_update)"; _ps=$(ans 1 | jq -r '[.result.tools[].name] | join(" ")')
[ "$_pd" = 'tools_check tools_fix tools_copy_details tools_update tools_update_system tools_export tools_front tools_end tools_measure tools_clean_packages' ] \
    && [ "$_ps" = 'tools_check tools_copy_details tools_export tools_front tools_end tools_measure' ] \
    && [ "$(ans 2 | jq -r .error.message)" = 'tools_update runs from its row in the dialog, never from a plan' ] \
    && ok "provide tools: a person's step to the dialog alone; spark sees the rest, and a call of one is refused in one line (v0.129.2)" || bad "person steps" "dialog: $_pd | spark: $_ps | $(ans 2)"
# tools (v0.129): six utilities, a page each; the check kept, a fake /proc, a measured home; every step that ends or runs
# something held to its gate. Linux alone: macOS has no /proc and no tools place
if [ "$(uname -s)" != Darwin ]; then
    SEP=$(printf '\302\267'); _ts=$H/.local/state/spark-shell; mkdir -p "$_ts"
    { date +%s; printf '%s\n' 'ok     rc           sourced from .zshrc' 'warn   tools        missing: fzf zoxide -- spark-shell on' 'FAIL   look         out of date: .tmux.conf -- spark-shell on' \
        'ok     font         na (CONSOLE_FONT unset: the console keeps its font)' 'warn   saver        no screen saver -- spark-shell desktop'; } > "$_ts/check.last"
    # a fake /proc: the desktop, the dialog, another user's program, a kernel thread, a browser of two processes, a script; pids past
    # any pid_max, so nothing here is ever a real process
    TP=$H/tproc; mkdir -p "$TP"; printf 'cpu  100 0 100 800 0 0 0 0 0 0\nbtime 1793990000\n' > "$TP/stat"
    _ou=0; [ "$(id -u)" != 0 ] || _ou=1
    _onn=$(awk -F: -v u="$_ou" '$3 == u { print $1; exit }' /etc/passwd)   # Void and openSUSE have no user 1: the row says the id, the refusal "user 1"
    _on=${_onn:-user $_ou}; _onl=${_onn:-$_ou}
    tproc() {   # tproc PID UID UTIME COMMAND...
        _tp=$TP/$1; _tu=$2; _tt=$3; shift 3; mkdir -p "$_tp"
        printf '%s (%s) S 1 1 1 0 -1 0 0 0 0 0 %s 0 0 0 20 0 1 0 500 1000 0 0 0 0\n' "${_tp##*/}" "${1:-kthread}" "$_tt" > "$_tp/stat"
        printf '1000 500 100 0 0 0 0\n' > "$_tp/statm"; printf 'Name:\tx\nUid:\t%s\t%s\t%s\t%s\n' "$_tu" "$_tu" "$_tu" "$_tu" > "$_tp/status"
        if [ $# -gt 0 ]; then printf '%s\0' "$@" > "$_tp/cmdline"; else : > "$_tp/cmdline"; fi
    }
    tproc 4194401 "$(id -u)" 50 /usr/bin/sway; tproc 4194402 "$(id -u)" 10 /usr/bin/spark-dialog --home; tproc 4194403 "$_ou" 5 /usr/sbin/udevd
    tproc 4194404 0 0; tproc 4194405 "$(id -u)" 300 /usr/lib/firefox/firefox; tproc 4194406 "$(id -u)" 200 /usr/lib/firefox/firefox -contentproc
    tproc 4194407 "$(id -u)" 1 python3 /opt/notes-sync.py; tproc 4194408 "$(id -u)" 0 /usr/bin/swaybar -b bar-0
    (SPARK_SHELL_PROC=$TP; export SPARK_SHELL_PROC; mcp tools "$(rq 1 resources/read '{"uri":"spark-shell://tools/rows"}')" "$(rq 2 resources/read '{"uri":"spark-shell://tools/rows/check"}')" \
        "$(rq 3 resources/read '{"uri":"spark-shell://tools/rows/check/passed"}')" "$(rq 4 resources/read '{"uri":"spark-shell://tools/rows/running"}')" \
        "$(rq 5 resources/read "$(jq -cn --arg u "spark-shell://tools/page/$(b64u tools:program:firefox)" '{uri: $u}')")" \
        "$(call 6 tools_end '{"name":"sway"}')" "$(call 7 tools_end '{"name":"spark-dialog"}')" "$(call 8 tools_end '{"name":"udevd"}')" "$(call 9 tools_end '{"name":"nosuch"}')" \
        "$(call 10 tools_front '{"name":"firefox"}')" "$(call 11 tools_fix '{"command":"rm -rf /"}')" "$(call 12 tools_fix '{"command":"spark-shell on"}')" \
        "$(call 13 tools_clean_packages)" "$(rq 14 resources/read '{"uri":"spark-shell://tools/rows/system"}')" "$(rq 15 resources/read '{"uri":"spark-shell://tools/rows/updates"}')" \
        "$(call 16 tools_end '{"name":"swaybar"}')")   # a subshell: sh keeps a variable set before a function after it
    rows() { ans "$1" | jq -c '.result.contents[0].text | fromjson'; }
    said() { ans "$1" | jq -r '.result.content[0].text'; }
    [ "$(rows 1 | jq -c '[.rows[] | [.id, .text, .children]]')" = '[["tools:check","check","spark-shell://tools/rows/check"],["tools:space","space","spark-shell://tools/rows/space"],["tools:running","running","spark-shell://tools/rows/running"],["tools:system","system","spark-shell://tools/rows/system"],["tools:updates","updates","spark-shell://tools/rows/updates"],["tools:software","software","spark-shell://tools/rows/software"]]' ] \
        && [ "$(rows 1 | jq -r '.rows[0].columns[0], .rows[2].columns[0], .rows[0].line')" = "$(printf '3 problems\n8 processes\ncheck %s test the setup and fix problems' "$SEP")" ] \
        && rows 1 | jq -e 'all(.rows[]; (.columns[0] | length) > 0)' >/dev/null \
        && ok "provide tools: six rows, one word each, each its state (the last check, the processes) and its page as children" || bad "tools rows" "$(rows 1)"
    [ "$(rows 2 | jq -c '[.rows[] | select(.text != "") | [.text, .group, (.columns[0] // ""), (.tool.arguments.command // "")]]')" = '[["programs","problems","missing: fzf zoxide",""],["config files","problems","out of date: .tmux.conf",""],["screen saver","problems","no screen saver",""],["fix",null,"spark-shell on","spark-shell on"],["fix",null,"spark-shell desktop","spark-shell desktop"],["1 passed",null,"",""],["1 not applicable",null,"",""],["check again",null,"checked at '"$(date -d "@$(sed -n 1p "$_ts/check.last")" +%H:%M)"'",""]]' ] \
        && [ "$(rows 2 | jq -r .state)" = '3 problems' ] && [ "$(rows 3 | jq -c '[.rows[] | [.text, .columns[0]]]')" = '[["shell startup","sourced from .zshrc"]]' ] \
        && ok "tools check: the problems by plain name, one fix for the two that share it, the passed and the not applicable counted apart, check again with its time" || bad "tools check" "$(rows 2)"
    [ "$(rows 4 | jq -c '[.rows[] | [.text, .columns, ([.more[].name] | join(" ")), .line]]')" = "$(jq -cn --arg s "$SEP" --arg o "$_onl" '[["firefox", ["0%", "3.1 MB"], "tools_end", "firefox \($s) 0% cpu \($s) 3.1 MB \($s) 2 processes"],
            ["notes-sync.py", ["0%", "1.6 MB"], "tools_end", "notes-sync.py \($s) 0% cpu \($s) 1.6 MB \($s) 1 process"], ["spark-dialog", ["0%", "1.6 MB"], "", "spark-dialog \($s) 0% cpu \($s) 1.6 MB \($s) 1 process"],
            ["sway", ["0%", "1.6 MB"], "", "sway \($s) 0% cpu \($s) 1.6 MB \($s) 1 process"], ["swaybar", ["0%", "1.6 MB"], "", "swaybar \($s) 0% cpu \($s) 1.6 MB \($s) 1 process"],
            ["udevd", ["0%", "1.6 MB"], "", "udevd \($s) 0% cpu \($s) 1.6 MB \($s) 1 process \($s) user \($o)"]]')" ] \
        && [ "$(rows 4 | jq -r .state)" = '8 processes' ] && [ "$(ans 5 | jq -r '.result.contents[0].text | fromjson | .lines[2:5] | join("|")')" = 'processes   2|ids         4194405, 4194406|user        you' ] \
        && ok "tools running: a program its command's name (a script by its script), its processes one row, a kernel thread left out; end on the person's own alone, not the desktop's parts or the dialog; its view" || bad "tools running" "$(rows 4) $(ans 5)"
    [ "$(said 6)" = 'sway is the desktop: use logout in power' ] && [ "$(said 7)" = 'the dialog closes with Esc' ] && [ "$(said 8)" = "udevd belongs to $_on and cannot be ended here" ] \
        && [ "$(said 9)" = 'nosuch is not running' ] && [ "$(said 10)" = 'firefox has no window' ] && [ "$(said 11)" = 'rm -rf / is not a fix the last check gave' ] \
        && [ "$(said 12)" = 'a terminal window needs the desktop' ] && [ "$(said 13)" = 'no supported package manager here' ] \
        && [ "$(said 16)" = 'swaybar is part of the desktop: use logout in power' ] \
        && ans 8 | jq -e '.result.isError' >/dev/null && ok "tools: end refuses the desktop and its parts, the dialog, another user's program and one not running; front one with no window; a fix the check did not give; a terminal with no desktop; a clean with no package manager" \
        || bad "tools refusals" "$(for i in 6 7 8 9 10 11 12 13; do said $i; done | paste -sd '|' -)"
    [ "$(rows 14 | jq -c '[.rows[] | .group] | unique')" != '[null]' ] && rows 14 | jq -e 'any(.rows[]; .id == "tools:copy-details" and .tool.name == "tools_copy_details") and all(.rows[]; .group == null or .group == "hardware" or .group == "operating system" or .group == "desktop")' >/dev/null \
        && rows 15 | jq -e '[.rows[] | .id] | index("tools:update") != null' >/dev/null \
        && ok "tools system and updates: the facts under hardware, operating system and desktop, copy details; update spark-shell" || bad "tools system" "$(rows 14) $(rows 15)"
    # a fix runs in a terminal, and the check runs again after it in the same window, so the record is the fix's
    # result and not the one from before it; an update runs alone
    cat > "$H/fix.want" <<EOF
printf '%s\n\n' 'spark-shell on'
$REPO/spark-shell on
printf '\n%s\n\n' 'spark-shell check'
$REPO/spark-shell check
printf '\npress Enter to close\n'
read _
EOF
    rm -f "$H/.local/state/swaymsg.log"; st=0; out=$(SWAYSOCK=/tmp/x sh "$SH" panel tools fix 'spark-shell on' 2>&1) || st=$?
    _tfs=$(sed -n 's/^exec foot sh //p' "$H/.local/state/swaymsg.log" 2>/dev/null | tail -1)
    rm -f "$H/.local/state/swaymsg.log"; st2=0; out2=$(SWAYSOCK=/tmp/x sh "$SH" panel tools update 2>&1) || st2=$?
    _tus=$(sed -n 's/^exec foot sh //p' "$H/.local/state/swaymsg.log" 2>/dev/null | tail -1)
    [ "$st" -eq 0 ] && [ "$out" = 'opened a terminal: spark-shell on' ] && [ -f "$_tfs" ] && [ "$(sed 1,2d "$_tfs")" = "$(cat "$H/fix.want")" ] \
        && [ "$st2" -eq 0 ] && [ -f "$_tus" ] && ! grep -q 'spark-shell check' "$_tus" \
        && ok "tools fix: the fix in a terminal, then the check again in the same window, before Enter closes it; update with no check" \
        || bad "tools fix check" "st=$st $out | $(cat "$_tfs" 2>&1) | st2=$st2 $out2"
    rm -f "$_tfs" "$_tus" "$H/fix.want"
    # tools' menu on screen: a check that ran outside the dialog (the fix's terminal above) says the rows changed,
    # once, and a record left as it is says nothing more, though the running count moves. The record as it was is
    # read before the subscribe's answer, so a check that ends at once is not missed
    cp "$_ts/check.last" "$H/check.keep"; : > "$H/mcp.out"
    { rq 1 resources/subscribe '{"uri":"spark-shell://tools/rows"}'
      tries=0
      until jq -e -s 'any(.id == 1)' "$H/mcp.out" >/dev/null 2>&1; do
          tries=$((tries + 1)); [ "$tries" -lt 300 ] || break; sleep 0.1
      done
      { date +%s; printf '%s\n' 'ok     rc           sourced from .zshrc'; } > "$_ts/check.last"
      tries=0
      until jq -e -s 'any(.method == "notifications/resources/updated")' "$H/mcp.out" >/dev/null 2>&1; do
          tries=$((tries + 1)); [ "$tries" -lt 300 ] || break; sleep 0.1
      done
      sleep 2.5
      rq 2 resources/unsubscribe '{"uri":"spark-shell://tools/rows"}'; } \
        | SPARK_SHELL_PROVIDE_POLL=1 sh "$SH" provide tools > "$H/mcp.out" 2> "$H/mcp.err"
    order=$(jq -r 'if .id then "r" + (.id | tostring) else .method end' "$H/mcp.out" | uniq | paste -sd ' ' -)
    [ "$order" = 'r1 notifications/resources/updated r2' ] && [ "$(jq -s '[.[] | select(.method == "notifications/resources/updated")] | length' "$H/mcp.out")" -eq 1 ] \
        && ok "provide tools: a check that ran outside the dialog says the menu changed, once; nothing more while the record stays" \
        || bad "tools check watch" "$order $(cat "$H/mcp.err")"
    mv "$H/check.keep" "$_ts/check.last"
    # running for real: a program of its own name, ended, and the provider that ends it untouched
    # a script, named by its own name as an interpreter's script is; a copy of sleep is a uutils multicall on
    # Ubuntu 26.04, which knows no such name and exits at once; it sleeps in itself, so no child is left behind
    printf '#!/usr/bin/env python3\nimport time\ntime.sleep(600)\n' > "$H/spark-test-sleeper"; chmod +x "$H/spark-test-sleeper"
    "$H/spark-test-sleeper" & _tsl=$!; sleep 0.5
    (SPARK_SHELL_PROC=/proc; export SPARK_SHELL_PROC; mcp tools "$(call 1 tools_end '{"name":"spark-test-sleeper"}')")   # the real one: the section's bar fixture set a fake
    # its death is read from wait, not kill -0: until this shell reaps it, a child that ended is a zombie, and dash reaps
    # it only here; never a wait on one still running (600 seconds)
    _tsr=$(ans 1 | jq -r .result.structuredContent.receipt)
    if [ "$_tsr" = 'spark-test-sleeper ended' ]; then _tsw=0; wait "$_tsl" 2>/dev/null || _tsw=$?; else kill "$_tsl" 2>/dev/null || :; wait "$_tsl" 2>/dev/null || :; _tsw=none; fi
    [ "$_tsr" = 'spark-test-sleeper ended' ] && [ "$_tsw" = 143 ] && ok "tools end: every process of the program stopped (TERM), said in the past tense; one ended and not yet reaped counts as ended" \
        || bad "tools end" "$(ans 1) wait=$_tsw"
    # space: home measured, the app caches left out, the trash taken out of its folder, a hidden folder viewed, not opened
    mkdir -p "$H/spacebig" "$H/.spacehid" "$H/.cache/mozilla" "$H/.local/share/Trash/files"
    head -c 8000000 /dev/zero > "$H/spacebig/a"; head -c 7000000 /dev/zero > "$H/.spacehid/a"; head -c 300000 /dev/zero > "$H/.cache/mozilla/c"
    mcp tools "$(rq 1 resources/read '{"uri":"spark-shell://tools/rows/space"}')" "$(rq 2 resources/read "$(jq -cn --arg u "spark-shell://tools/page/$(b64u tools:space:caches)" '{uri: $u}')")" \
        "$(rq 3 resources/read "$(jq -cn --arg u "spark-shell://tools/page/$(b64u tools:folder:../etc)" '{uri: $u}')")" "$(call 4 tools_measure)"
    _tbig=$(b64u "$(realpath "$H/spacebig")")
    rows 1 | jq -e --arg big "spark-shell://files/rows/$_tbig" --arg s "$SEP" '(.rows | map(.id)) as $ids
        | ($ids | index("tools:fact:system disk") == 0) and ($ids | index("tools:folder:.cache") == null) and ($ids | index("tools:clean-packages") == null)
        and any(.rows[]; .id == "tools:trash" and .children == "spark-shell://files/rows/trash" and .group == "cleanup")
        and any(.rows[]; .id == "tools:caches" and (.page | startswith("spark-shell://tools/page/")) and .children == null)
        and any(.rows[]; .id == "tools:folder:spacebig" and .children == $big and .group == "home" and (.line | endswith($s + " folder")))
        and any(.rows[]; .id == "tools:folder:.spacehid" and .children == null and .page != null and (.line | endswith("hidden folder")))
        and any(.rows[]; .id == "tools:measure" and .tool.name == "tools_measure" and (.columns[0] | startswith("measured at ")))' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.contents[0].text | fromjson | .lines[0], .lines[3]' | cut -c1-7)" = "$(printf 'app cac\nmozilla')" ] \
        && [ "$(ans 3 | jq -r .error.code)" = -32002 ] && ans 4 | jq -r .result.structuredContent.receipt | grep -q '^measured: ' \
        && ok "tools space: the system disk, cleanup (the trash in files, the app caches' view), home's folders as objects that open in files, a hidden one viewed; a folder outside home refused; measure again" || bad "tools space" "$(rows 1 | head -c 1500) $(ans 2) $(ans 3)"
    rm -rf "$H/spacebig" "$H/.spacehid" "$H/spark-test-sleeper" "$TP"
fi
jq -e -s 'all(.[]; .inputSchema.type == "object" and .inputSchema.additionalProperties == false and .outputSchema.type == "object")' "$H/tools.all" >/dev/null \
    && [ "$(jq -c 'select(.name == "wifi_connect") | .inputSchema.properties.password' "$H/tools.all")" = '{"type":"string","format":"password","maxLength":256}' ] \
    && [ "$(jq -c 'select(.name == "bt_power") | .inputSchema.properties.state.enum' "$H/tools.all")" = '["on","off"]' ] && [ "$(jq -c 'select(.name == "out_level") | .inputSchema.properties.level' "$H/tools.all")" = '{"type":"integer","minimum":0,"maximum":100}' ] \
    && ok "provide: every input schema closed (no other argument), a password a masked string, a closed set an enum, a level 0 to 100" || bad "tool schemas" "$(jq -c '[.name, .inputSchema]' "$H/tools.all" | head -5)"
# the rows resource, a call, its undo, the refusals
mcp theme "$(rq 1 resources/list)" "$(rq 2 resources/read '{"uri":"spark-shell://theme/rows"}')" "$(rq 3 resources/read '{"uri":"spark-shell://wifi/rows"}')"
ans 2 | jq -r '.result.contents[0].text' > "$H/rows.json"
[ "$(ans 1 | jq -c '.result.resources[0] | [.uri, .mimeType]')" = '["spark-shell://theme/rows","application/json"]' ] && [ "$(ans 3 | jq -r .error.code)" = -32002 ] \
    && jq -e '.title == "theme" and (.rows[] | select(.text == "terminal default colors") | .sign == "check" and .tool == null and .group == "custom") and (.rows[] | select(.id == "theme:dracula") | .tool == {name: "theme_palette", arguments: {name: "dracula"}} and .group == "dark" and (.chip | length) == 9)' "$H/rows.json" >/dev/null \
    && jq -e '.short == ["theme:more"] and (.rows[] | select(.id == "theme:more") | .children == "spark-shell://theme/rows" and .tool == null)' "$H/rows.json" >/dev/null \
    && ok "provide: the rows resource: the palette in use (none, terminal default colors) a check with no tool, every other a row whose tool takes it by name, with its chip; the short form the one row that opens the section" || bad "provide rows" "$(cat "$H/rows.json" | head -c 600)"
mcp theme "$(call 1 theme_palette '{"name":"nord"}')" "$(call 2 theme_palette '{"name":"nowhere"}')" "$(call 3 theme_text '{"size":"huge"}')" "$(call 4 theme_alpha '{"value":0.9,"x":1}')" "$(call 5 wifi_connect '{"name":"home"}')" "$(call 6 'Theme_Font')" "$(call 7 theme_alpha '{"value":2}')"
[ "$(ans 1 | jq -c '.result.structuredContent | del(.palette, .transitions, .rows)')" = '{"receipt":"nord is on","undo":{"name":"theme_palette","arguments":{"name":"none"}}}' ] && [ "$(ans 1 | jq -r '.result.structuredContent.transitions')" = "$REPO/gallery/animation/tide/nord" ] && ans 1 | jq -e '.result.isError == false and (.result.content[0].text | fromjson) == (.result.structuredContent | del(.rows)) and .result.structuredContent.rows.title == "theme"' >/dev/null && grep -q '^THEME=nord$' "$HOME/.config/spark-shell/config" \
    && ok "provide tools/call: the palette set, the receipt in the present tense, the undo the step that takes it back, the same JSON in a text block; the animation it brings, for an open dialog to read again (#126)" || bad "provide call" "$(ans 1) $(cat "$H/mcp.err")"
nfg=$(sed -n 's/^THEME_FG=#//p' "$REPO/gallery/theme/nord.env"); nbg=$(sed -n 's/^THEME_BG=#//p' "$REPO/gallery/theme/nord.env")
ans 1 | jq -e --arg f "$nfg" --arg b "$nbg" '.result.structuredContent.palette | (.HEX_FG | ascii_downcase) == ($f | ascii_downcase) and (.PANEL_BG | test("^[0-9a-fA-F]{6}$")) and (.PANEL_BG | ascii_downcase) != ($b | ascii_downcase) and (keys == (["GLYPH_FAMILY", "HEX_ACCENT", "HEX_FG", "PANEL_BG", "PANEL_HI", "PANEL_MUTED"] + [range(16) | "HEX_ANSI_\(.)"] | sort)) and .GLYPH_FAMILY == "stone" and all(to_entries[] | select(.key | startswith("HEX_ANSI_")); .value | test("^[0-9a-fA-F]{6}$"))' >/dev/null \
    && ok "provide theme: a step's result carries the palette as it is now, the dialog's surface a shade off the background, so the dialog repaints itself; the glyph family with it (#248), and the 16 colors a drawn piece takes (#247)" || bad "theme palette in result" "$(ans 1 | jq -c .result.structuredContent.palette) fg=$nfg bg=$nbg"
[ "$(ans 2 | jq -r .error.code)" = -32602 ] && ans 2 | jq -e '.error.message | startswith("theme_palette: name is one of ") and contains("nord") and contains("none")' >/dev/null && [ "$(ans 3 | jq -r .error.message)" = "theme_text: size is one of bigger, smaller, $(awk 'BEGIN { for (i = 6; i <= 40; i++) printf "%s%d", (i > 6 ? ", " : ""), i }')" ] && [ "$(ans 4 | jq -r .error.message)" = 'theme_alpha: no argument x' ] \
    && [ "$(ans 5 | jq -r .error.message)" = 'no tool wifi_connect in theme' ] && [ "$(ans 6 | jq -r .error.code)" = -32602 ] && [ "$(ans 7 | jq -r .error.message)" = 'theme_alpha: value is a number, 0 to 1' ] \
    && ok "provide: a palette no row offers is outside the schema's enum, -32602 with the names; an argument outside its schema, an argument it lacks, another section's tool and a name of another shape are -32602" || bad "provide refusals" "$(cat "$H/mcp.out")"
mcp theme "$(call 1 theme_palette '{"name":"none"}')"; grep -q '^THEME=none$' "$HOME/.config/spark-shell/config" && ok "provide: the undo, called as a tool, puts the palette back" || bad "provide undo" "$(cat "$H/mcp.out")"
mcp theme "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 2 tools/list)"
ans 2 | jq -e '.result.tools[] | select(.name == "theme_palette") | .inputSchema.properties.name.enum | index("nord") != null and index("none") != null and length > 10 and (map(select(test("^[A-Za-z0-9._-]+$"))) | length) == length' >/dev/null \
    && ok "provide theme: theme NAME takes an enum of every palette, every saved theme and none, so a model under the grammar writes a real name only (#95)" || bad "theme enum" "$(ans 2 | jq -c '.result.tools[] | select(.name == "theme_palette") | .inputSchema')"
# a reminder with no day and time: one question over the wire (elicitation), the answer in front of the words; cancelled, not done
mcp reminders "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(call 2 reminders_add '{"words":"test the network later today"}')" '{"jsonrpc":"2.0","id":"ask-2","result":{"action":"accept","content":{"when":"tomorrow 9:00"}}}' "$(call 3 reminders_add '{"words":"water the plants"}')" '{"jsonrpc":"2.0","id":"ask-3","result":{"action":"cancel"}}' "$(call 4 reminders_add '{"words":"tomorrow 10:00 no question here"}')"
q=$(jq -c 'select(.method == "elicitation/create")' "$H/mcp.out" | head -1)
[ "$(printf '%s' "$q" | jq -r '.id')" = ask-2 ] && [ "$(printf '%s' "$q" | jq -r '.params.message')" = When ] && [ "$(printf '%s' "$q" | jq -c '.params.requestedSchema.required')" = '["when"]' ] \
    && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'reminder tomorrow 09:00 test the network later today' ] && [ "$(ans 3 | jq -c '.result')" = '{"content":[{"type":"text","text":"not done: no time given"}],"isError":true}' ] \
    && [ "$(ans 4 | jq -r '.result.structuredContent.receipt')" = 'reminder tomorrow 10:00 no question here' ] && [ "$(jq -c 'select(.method == "elicitation/create")' "$H/mcp.out" | wc -l | tr -d ' ')" = 2 ] \
    && ok "provide reminders_add: words with no day and time get one question over the wire (elicitation, the field when); the answer goes in front of the words and the reminder is saved; cancelled is not done, no time given; words with a time ask nothing (#95)" || bad "reminders ask" "$(cat "$H/mcp.out" "$H/mcp.err")"
# a layout save: no yes, a new name saved with its undo, a name in use refused
mkdir -p "$H/ls"; cat > "$H/ls/swaymsg" <<'EOF'
#!/bin/sh
case "$*" in "-t get_version") echo '{"human_readable":"sway-stub"}' ;; "-t get_tree") echo '{"type":"root","nodes":[{"type":"workspace","num":1,"focused":true,"nodes":[{"type":"con","id":79,"pid":1,"app_id":"firefox","focused":true}]}]}' ;; *) : ;; esac
EOF
chmod +x "$H/ls/swaymsg"; _lp=$PATH; PATH="$H/ls:$PATH"; export SWAYSOCK=/nowhere/sway.sock   # a sway with one window open on the focused workspace
mcp layout "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 9 tools/list)" "$(call 2 layout_save '{"name":"webdev"}')" "$(call 3 layout_save '{"name":"webdev"}')"
ans 9 | jq -e '.result.tools[] | select(.name == "layout_save") | .annotations.destructiveHint == false' >/dev/null \
    && [ "$(ans 2 | jq -c '.result.structuredContent.undo')" = '{"name":"layout_delete","arguments":{"name":"webdev"}}' ] && [ -f "$HOME/.config/spark-shell/layouts/webdev" ] \
    && [ "$(ans 3 | jq -r '.result.content[0].text')" = 'webdev is a layout already: rename it, or delete it first' ] && [ "$(ans 3 | jq -r '.result.isError')" = true ] \
    && ok "provide layout_save: not destructive, so no yes; a new name is saved with its undo (layout delete); a name in use is refused, nothing written over (#96)" || bad "layout save" "$(cat "$H/mcp.out" "$H/mcp.err")"
# several windows: the dialog left out, a terminal by the program inside it (a shell when none runs), each app by the
# name a layout knows it; the apps and the processes read once for them all (#196)
printf '#!/bin/sh\n[ "$*" = "-eo pid=,ppid=,comm=" ] || exit 1\nprintf "    1     0 init\\n 4242     1 foot\\n 4243  4242 /usr/bin/sleep\\n 4244  4242 sh\\n"\n' > "$H/ls/ps"; chmod +x "$H/ls/ps"   # the processes: a terminal (4242) with a program inside it
cat > "$H/ls/swaymsg" <<'EOF'
#!/bin/sh
case "$*" in "-t get_version") echo '{"human_readable":"sway-stub"}' ;; "-t get_tree") cat "$HOME/ls.tree" ;; *) : ;; esac
EOF
printf '{"type":"root","nodes":[{"type":"workspace","num":1,"nodes":[{"type":"con","id":80,"pid":1,"app_id":"Firefox","focused":true},{"type":"con","id":81,"pid":4242,"app_id":"foot"},{"type":"con","id":82,"pid":4245,"app_id":"foot"}],"floating_nodes":[{"type":"floating_con","id":83,"pid":4242,"app_id":"spark-dialog"}]}]}\n' > "$HOME/ls.tree"
mcp layout "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(call 2 layout_save '{"name":"three"}')"
[ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'saved three: firefox, sleep, shell' ] \
    && [ "$(jq -c 'del(.why)' "$HOME/.config/spark-shell/layouts/three")" = '{"words":"three","main":{"app":"firefox"},"side":[{"app":"sleep"},{"app":"shell"}]}' ] \
    && ok "provide layout_save: three windows saved as a layout knows them (Firefox is firefox, a terminal by the program in it, a shell when none), the dialog left out (#196)" || bad "layout save windows" "$(ans 2) $(cat "$HOME/.config/spark-shell/layouts/three" 2>&1)"
rm -f "$HOME/.config/spark-shell/layouts/three"
# the workspace place: four windows on two workspaces and two screens, one in the scratchpad, the dialog over them
cat > "$HOME/ls.tree" <<'EOF'
{"type":"root","nodes":[{"type":"output","name":"__i3","nodes":[{"type":"workspace","name":"__i3_scratch","num":-1,"nodes":[],"floating_nodes":[{"id":99,"type":"floating_con","pid":9,"app_id":"xterm","name":"hidden"}]}]},
{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","id":10,"name":"1:s","num":1,"layout":"splith","focus":[11,12],"nodes":[{"id":11,"type":"con","pid":1,"app_id":"org.mozilla.firefox","name":"Claude Code \u2014 Mozilla Firefox","nodes":[],"floating_nodes":[]},{"id":12,"type":"con","pid":2,"app_id":"foot","name":"~/projects","nodes":[],"floating_nodes":[]}],"floating_nodes":[]}]},
{"type":"output","name":"eDP-1","nodes":[{"type":"workspace","id":20,"name":"2:t writing","num":2,"layout":"tabbed","rect":{"x":0,"y":0,"width":1920,"height":1080},"focus":[30,21,22],"nodes":[{"id":21,"type":"con","pid":3,"app_id":"foot","name":"btop","nodes":[],"floating_nodes":[]}],"floating_nodes":[{"id":22,"type":"floating_con","pid":4,"app_id":"chromium","name":"invoice.pdf","nodes":[],"floating_nodes":[]},{"id":30,"type":"floating_con","pid":5,"app_id":"spark-dialog","focused":true,"name":"dialog","nodes":[],"floating_nodes":[]}]}]}]}
EOF
cat > "$H/ls/swaymsg" <<'EOF'
#!/bin/sh
case "$*" in "-t get_version") echo '{"human_readable":"sway-stub"}' ;; "-t get_tree") cat "$HOME/ls.tree" ;; *) echo "$*" >> "$HOME/ls.log"; echo '[{"success":true}]' ;; esac
EOF
printf '#!/bin/sh\necho Linux\n' > "$H/ls/uname"; chmod +x "$H/ls/uname"   # a window is placed on Linux alone
_d=$(printf '\302\267'); : > "$HOME/ls.log"
mcp window "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 21 resources/read '{"uri":"spark-shell://window/rows"}')" "$(rq 22 resources/read '{"uri":"spark-shell://window/rows/arrange"}')" "$(rq 23 resources/read '{"uri":"spark-shell://window/rows/move/21"}')" "$(rq 24 resources/read '{"uri":"spark-shell://window/rows/place/22"}')" \
    "$(call 5 window_move '{"name":"21","to":"3"}')" "$(call 6 window_place '{"name":"21","how":"floating"}')" "$(call 7 window_stacked)" "$(call 8 window_restore '{"to":"split","now":"tabs"}')" "$(call 9 window_move '{"name":"77","to":"3"}')" "$(call 10 window_place '{"name":"21","how":"left"}')"
_w=$(ans 21 | jq -r '.result.contents[0].text')
[ "$(printf '%s' "$_w" | jq -r .state)" = '4 windows' ] \
    && [ "$(printf '%s' "$_w" | jq -c '[.rows[] | select(.tool.name == "window_focus") | [.text, .columns[0]]]')" = '[["firefox","Claude Code"],["foot","~/projects"],["foot","btop"],["chromium","invoice.pdf"]]' ] \
    && [ "$(printf '%s' "$_w" | jq -r '[.rows[] | select(.group != null) | .group] | unique | join("/")')" = "workspace 1 s $_d HDMI-A-1/workspace 2 t $_d writing $_d this one $_d eDP-1" ] \
    && [ "$(printf '%s' "$_w" | jq -r '.rows[] | select(.front == true) | .id')" = 'window:focus 21' ] \
    && [ "$(printf '%s' "$_w" | jq -r '.rows[] | select(.id == "window:focus 22") | .line')" = "chromium $_d invoice.pdf $_d workspace 2 $_d floating" ] \
    && [ "$(printf '%s' "$_w" | jq -c '.rows[] | select(.id == "window:focus 22") | .wide')" = '["invoice.pdf","floating"]' ] \
    && [ "$(printf '%s' "$_w" | jq -c '[.rows[] | select(.tool.name == "window_capture") | [.text, .key]]')" = '[["capture the screen","Print"],["capture an area","Shift+Print"]]' ] \
    && [ "$(printf '%s' "$_w" | jq -c '.rows[] | select(.id == "window:arrange") | [.columns[0], .children, .choice]')" = '["tabs","spark-shell://window/rows/arrange",true]' ] \
    && [ "$(printf '%s' "$_w" | jq -c '[.rows[] | select(.id == "window:focus 21") | .tool.said, (.more[] | .said)]')" = '["put in front","move to workspace","placement","capture this window","close"]' ] \
    && [ "$(printf '%s' "$_w" | jq -c '.rows[] | select(.id == "window:focus 21") | [.more[0].value, .more[1].value]')" = '["2","tiled"]' ] \
    && ok "provide window rows: a heading per workspace, the app and its title, the window in front marked, the status line, placement wide, the two captures, arrange with what this workspace has; the scratchpad and the dialog left out" || bad "workspace rows" "$_w"
ans 22 | jq -r '.result.contents[0].text' > "$H/ws.arrange"; ans 23 | jq -r '.result.contents[0].text' > "$H/ws.move"; ans 24 | jq -r '.result.contents[0].text' > "$H/ws.place"
[ "$(jq -c '[.rows[] | [.text, .sign, .key, (.tool.name // "")]]' "$H/ws.arrange")" = '[["side by side","blank","Super+e","window_split"],["tabs","check","Super+w",""],["stacked","blank","Super+Shift+s","window_stacked"],["this workspace now, and every new workspace","blank",null,""]]' ] \
    && [ "$(jq -r .title "$H/ws.move")" = foot ] && [ "$(jq -c '[.rows[] | select(.sign == "check") | .text]' "$H/ws.move")" = '["2 t"]' ] && [ "$(jq -c '.rows[0].columns' "$H/ws.move")" = '["firefox, foot"]' ] \
    && [ "$(jq -c '.rows[2] | [.columns, .tool.arguments]' "$H/ws.move")" = '[["empty"],{"name":"21","to":"3"}]' ] && [ "$(jq '[.rows[] | select(.back)] | length' "$H/ws.move")" = 10 ] \
    && [ "$(jq -c '[.rows[] | .text]' "$H/ws.place")" = '["tiled","floating","full screen","left half","right half","top half","bottom half"]' ] && [ "$(jq -c '[.rows[] | select(.sign == "check") | .text]' "$H/ws.place")" = '["floating"]' ] \
    && ok "provide window pickers: arrange with its keys and its note, move to workspace with what each holds, placement with the one in use checked, each pick going back" || bad "workspace pickers" "$(cat "$H/ws.arrange" "$H/ws.move" "$H/ws.place")"
[ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'foot moved to workspace 3' ] && [ "$(ans 5 | jq -c '.result.structuredContent.undo')" = '{"name":"window_move","arguments":{"name":"21","to":"2"}}' ] && grep -qx -- '-- \[con_id=21\] move container to workspace number 3' "$HOME/ls.log" \
    && [ "$(ans 6 | jq -r '.result.structuredContent.receipt')" = 'foot floating' ] && [ "$(ans 6 | jq -c '.result.structuredContent.undo')" = '{"name":"window_place","arguments":{"name":"21","how":"tiled"}}' ] \
    && [ "$(ans 7 | jq -r '.result.structuredContent.receipt')" = 'windows stacked' ] && [ "$(ans 7 | jq -c '.result.structuredContent.undo')" = '{"name":"window_restore","arguments":{"to":"split","now":"tabs"}}' ] \
    && [ "$(ans 8 | jq -r '.result.structuredContent.receipt')" = 'windows in tabs' ] && [ "$(ans 8 | jq -c '.result.structuredContent.undo')" = null ] && grep -qx -- '-- \[workspace=__focused__ tiling\] layout tabbed' "$HOME/ls.log" \
    && [ "$(ans 9 | jq -r '.result.content[0].text')" = 'that window is no longer open' ] \
    && [ "$(ans 10 | jq -r '.result.structuredContent.receipt')" = 'foot on the left half' ] \
    && ok "provide window steps: move and place by the window's ID, each with its undo; arrange undone puts back the default and this workspace; a window gone is said" || bad "workspace steps" "$(cut -c1-300 "$H/mcp.out") $(cat "$HOME/ls.log")"
sed -i.bak '/^WINDOWS=/d' "$HOME/.config/spark-shell/config" 2>/dev/null; rm -f "$HOME/.config/spark-shell/config.bak"
# a layout's delete and rename carry undo, and a save keeps how the workspace stands
printf '{"words":"writing","why":"saved 4 Nov 2026","main":{"app":"foot"},"side":[{"app":"firefox"}]}\n' > "$HOME/.config/spark-shell/layouts/writing"
mcp layout "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 9 tools/list)" "$(rq 21 resources/read '{"uri":"spark-shell://layout/rows"}')" "$(call 2 layout_rename '{"name":"writing","to":"drafting"}')" "$(call 3 layout_delete '{"name":"drafting"}')" "$(call 4 layout_restore '{"name":"drafting"}')" "$(call 5 layout_rename '{"name":"drafting","to":"webdev"}')" "$(call 6 layout_save '{"name":"tabbed"}')"
_l=$(ans 21 | jq -r '.result.contents[0].text')
ans 9 | jq -e '.result.tools[] | select(.name == "layout_delete") | .annotations.destructiveHint == false' >/dev/null \
    && [ "$(printf '%s' "$_l" | jq -c '.rows[] | select(.text == "writing") | [.group, .columns, .wide, .line, .tool.said, .tool.ask]')" = "[\"layouts\",[\"foot, firefox\"],[\"foot, firefox\",\"saved 4 Nov 2026\"],\"writing $_d foot, firefox $_d saved 4 Nov 2026\",\"open\",null]" ] \
    && [ "$(printf '%s' "$_l" | jq -c '.rows[] | select(.id == "layout:save") | [.text, .tool.ask]')" = '["save this workspace",["name"]]' ] \
    && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'writing renamed to drafting' ] && [ "$(ans 2 | jq -c '.result.structuredContent.undo')" = '{"name":"layout_rename","arguments":{"name":"drafting","to":"writing"}}' ] \
    && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = 'deleted drafting' ] && [ "$(ans 3 | jq -c '.result.structuredContent.undo')" = '{"name":"layout_restore","arguments":{"name":"drafting"}}' ] \
    && [ "$(ans 4 | jq -r '.result.structuredContent.receipt')" = 'drafting is back' ] && [ -f "$HOME/.config/spark-shell/layouts/drafting" ] \
    && [ "$(ans 5 | jq -r '.result.content[0].text')" = 'spark-shell layout: webdev is a layout already: pick another name' ] \
    && [ "$(jq -r .arrange "$HOME/.config/spark-shell/layouts/tabbed")" = tabs ] \
    && ok "provide layout: a row with its apps and its reason, the status line; rename and delete with undo, no typed yes; a save keeps how the workspace stands" || bad "workspace layouts" "$_l $(cut -c1-300 "$H/mcp.out")"
printf '21\n' > "$HOME/ls.aside"
SPARK_SHELL_ASIDE="$HOME/ls.aside"; export SPARK_SHELL_ASIDE
mcp window "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 31 resources/read '{"uri":"spark-shell://window/rows"}')" "$(call 32 window_place '{"name":"22","how":"tiled"}')" "$(call 33 window_place '{"name":"21","how":"tiled"}')"
_a=$(ans 31 | jq -r '.result.contents[0].text' | jq -r '.rows[] | select(.tool.arguments.name == "21") | .line'); _u=$(ans 33 | jq -c '.result.structuredContent.undo')
unset SPARK_SHELL_ASIDE
case $_a in *'full screen'*) _ar=1 ;; *) _ar='' ;; esac
[ -n "$_ar" ] && [ "$_u" = '{"name":"window_place","arguments":{"name":"21","how":"full"}}' ] && [ ! -s "$HOME/ls.aside" ] \
    && ok "provide window: a window stepped aside for the dialog reads full screen, another's placing leaves it, its own clears it, and undo makes it full again" || bad "workspace aside" "line=$_a undo=$_u aside=$(cat "$HOME/ls.aside" 2>&1)"
rm -f "$HOME/.config/spark-shell/layouts/drafting" "$HOME/.config/spark-shell/layouts/tabbed"
# a workspace with a name and no number, which sway calls -1: it reads by its name, after the numbered ones, and is no move target
cp "$HOME/ls.tree" "$HOME/ls.tree.keep"
cat > "$HOME/ls.tree" <<'EOF'
{"type":"root","nodes":[{"type":"output","name":"eDP-1","nodes":[{"type":"workspace","id":40,"name":"notes","num":-1,"layout":"splith","rect":{"x":0,"y":0,"width":1920,"height":1080},"focus":[41],"nodes":[{"id":41,"type":"con","pid":7,"app_id":"foot","name":"plan","focused":true,"fullscreen_mode":0,"rect":{"x":0,"y":0,"width":1920,"height":1080}}],"floating_nodes":[]},
{"type":"workspace","id":50,"name":"2","num":2,"layout":"splith","rect":{"x":0,"y":0,"width":1920,"height":1080},"focus":[51],"nodes":[{"id":51,"type":"con","pid":8,"app_id":"firefox","name":"docs","fullscreen_mode":0,"rect":{"x":0,"y":0,"width":1920,"height":1080}}],"floating_nodes":[]}]}]}
EOF
mcp window "$init" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 41 resources/read '{"uri":"spark-shell://window/rows"}')" "$(rq 42 resources/read '{"uri":"spark-shell://window/rows/move/41"}')" "$(call 43 window_move '{"name":"41","to":"2"}')"
_n=$(ans 41 | jq -r '.result.contents[0].text'); _m=$(ans 42 | jq -r '.result.contents[0].text'); _u=$(ans 43 | jq -c '.result.structuredContent.undo')
mv "$HOME/ls.tree.keep" "$HOME/ls.tree"
[ "$(printf '%s' "$_n" | jq -c '[.rows[] | select(.tool.name == "window_focus") | .group]')" = "[\"workspace 2\",\"workspace notes $_d this one\"]" ] \
    && printf '%s' "$_n" | jq -e '.rows[] | select(.tool.arguments.name == "41") | (.line | test("workspace notes")) and (.more[0].value == "notes")' >/dev/null \
    && [ "$(printf '%s' "$_m" | jq -c '[.rows[] | select(.text | startswith("-"))] | length')" = 0 ] && [ "$(printf '%s' "$_m" | jq -c '[.rows[] | select(.sign == "check")] | length')" = 0 ] && [ "$_u" = null ] \
    && ok "provide window: a workspace with no number reads by its name, after the numbered ones; the move list holds no -1, and a move from it has no undo to refuse" || bad "workspace named" "$_n | $_m | undo=$_u"
# no sway: the window section says so, and a layout says tmux
unset SWAYSOCK; mkdir -p "$H/nosway"; printf '#!/bin/sh\nexit 1\n' > "$H/nosway/swaymsg"; chmod +x "$H/nosway/swaymsg"; PATH=$H/nosway:$_lp   # as swaymsg does with no socket
mcp window "$(rq 1 resources/read '{"uri":"spark-shell://window/rows"}')"
_w=$(ans 1 | jq -r '.result.contents[0].text')
mcp layout "$(rq 1 resources/read '{"uri":"spark-shell://layout/rows"}')"
_l=$(ans 1 | jq -r '.result.contents[0].text')
PATH=$_lp
[ "$(printf '%s' "$_w" | jq -c '[.state, (.rows | length)]')" = '["no desktop",0]' ] && printf '%s' "$_l" | jq -e '.rows[] | select(.text == "webdev") | .line | endswith("opens in tmux")' >/dev/null \
    && ok "provide with no sway: no desktop, no rows of windows, and a layout says it opens in tmux" || bad "workspace no desktop" "$_w $_l"
rm -f "$HOME/ls.tree" "$HOME/ls.log" "$H/ls/ps" "$H/ls/uname"   # the layouts after it are webdev alone
# every palette: the dialog's quiet words read at 4.5 to 1 on its surface, or as its author's own text where that reads lower (#18)
_cw=''
for env in "$REPO"/gallery/theme/*.env; do
    name=${env##*/}; name=${name%.env}
    mcp theme "$(call 1 theme_palette "{\"name\":\"$name\"}")"
    ans 1 | jq -r '.result.structuredContent.palette | "\(.PANEL_MUTED) \(.PANEL_BG) \(.HEX_FG)"' > "$H/pal.txt"
    awk -v n="$name" 'function h(c, i) { return index("0123456789abcdef", substr(tolower(c), i, 1)) - 1 }
        function ch(c, i,   v) { v = (h(c, i) * 16 + h(c, i + 1)) / 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(c) { return 0.2126 * ch(c, 1) + 0.7152 * ch(c, 3) + 0.0722 * ch(c, 5) }
        function cr(a, b,   x, y, t) { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }; return (x + 0.05) / (y + 0.05) }
        { if (!(cr($1, $2) >= 4.5 || tolower($1) == tolower($3))) printf "%s %.2f\n", n, cr($1, $2) }' "$H/pal.txt" >> "$H/contrast.bad"
done
[ ! -s "$H/contrast.bad" ] && ok "every palette: the dialog's quiet words read at 4.5 to 1, or as the author's own text where that reads lower" || bad "panel-muted contrast" "$(cat "$H/contrast.bad")"
mcp theme "$(call 1 theme_palette '{"name":"none"}')"
# subscribe: the step's answer carries its rows, so no rows-changed note follows it and the watcher, a beat later,
# counts them as seen (#196); a change made outside it is the one it says. Slow runners wait out a whole poll first.
: > "$H/mcp.out"
{ rq 1 resources/subscribe '{"uri":"spark-shell://theme/rows"}'; rq 2 tools/call '{"name":"theme_transparency","arguments":{"amount":"more"},"_meta":{"progressToken":"p1"}}'
  tries=0
  until jq -e -s 'any(.id == 2)' "$H/mcp.out" >/dev/null 2>&1; do
      tries=$((tries + 1)); [ "$tries" -lt 300 ] || break; sleep 0.1
  done
  sleep 2.5
  printf 'THEME=dracula\n' >> "$HOME/.config/spark-shell/config"
  tries=0
  until jq -e -s '[.[] | select(.method == "notifications/resources/updated")] | length >= 1' "$H/mcp.out" >/dev/null 2>&1; do
      tries=$((tries + 1)); [ "$tries" -lt 300 ] || break; sleep 0.1
  done
  rq 3 resources/unsubscribe '{"uri":"spark-shell://theme/rows"}'; } \
    | SPARK_SHELL_PROVIDE_POLL=1 SPARK_SHELL_PROVIDE_WATCHED=theme sh "$SH" provide theme > "$H/mcp.out" 2> "$H/mcp.err"
order=$(jq -r 'if .id then "r" + (.id | tostring) else .method end' "$H/mcp.out" | uniq | paste -sd ' ' -)
case $order in "r1 notifications/progress r2 notifications/resources/updated r3") ok "provide: progress against the token while a step runs, then its result with its rows, then the rows updated by the watcher alone, unsubscribed" ;;
    *) bad "provide subscribe" "$order $(cat "$H/mcp.err")" ;; esac
[ "$(jq -s '[.[] | select(.method == "notifications/resources/updated")] | length' "$H/mcp.out")" -eq 1 ] && jq -e -s '[.[] | select(.method == "notifications/progress") | .params.progress] | . == (sort | unique)' "$H/mcp.out" >/dev/null \
    && jq -e -s 'any(.id == 2 and .result.structuredContent.rows.title == "theme")' "$H/mcp.out" >/dev/null \
    && ok "provide: the watcher said the palette change made outside it once, and never the step's own, whose rows went with its answer (#196); progress only grows" || bad "provide watcher" "$(cat "$H/mcp.out")"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
st=0; out=$(sh "$SH" provide spark 2>&1 >/dev/null) || st=$?
[ "$st" -eq 1 ] && [ "$out" = 'spark-shell provide: spark is not one: lan, wifi, bt, printers, out, mic, bat, clock, theme, window, display, keyboard, pointer, notifications, storage, power, notes, reminders, bar, layout, apps, tools, about, undo, files' ] && ok "provide spark: no provider (the dialog holds the chat itself), the list on stderr, exit 1" || bad "provide spark" "st=$st $out"
st=0; out=$(sh "$SH" provide theme wifi 2>&1 >/dev/null) || st=$?
[ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell provide: one section: lan, ' && ok "provide with two words: one section, refused on stderr" || bad "provide two" "st=$st $out"
# the dialog exits without waiting for its providers (#60): an answer that finds the reader gone (SIGPIPE)
# never ends a provider mid-request, an error the shell writes itself included; it ends at the end of its
# input, exit 0, through its EXIT trap (dash runs no EXIT trap for a signal that kills it: the box's sh).
# SIGPIPE goes back to its default first, as the dialog's children have it: a shell started with it ignored
# (from Node, say) cannot undo that itself. GNU env does it, else python3; neither, the case is not tried
if env --default-signal=PIPE true 2>/dev/null; then printf '#!/bin/sh\nexec env --default-signal=PIPE "$@"\n' > "$H/dflpipe"
elif command -v python3 >/dev/null 2>&1; then printf '#!/usr/bin/env python3\nimport os, signal, sys\nsignal.signal(signal.SIGPIPE, signal.SIG_DFL)\nos.execvp(sys.argv[1], sys.argv[1:])\n' > "$H/dflpipe"
else rm -f "$H/dflpipe"; fi
if [ -f "$H/dflpipe" ]; then
    chmod +x "$H/dflpipe"; pt=$(tmpd); rm -f "$H/prov.rc"
    { rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}'; sleep 1; rq 2 no/such '{}'; sleep 1; rq 3 ping '{}'; sleep 1; } \
        | { TMPDIR="$pt" "$H/dflpipe" sh "$SH" provide theme 2>/dev/null; echo $? > "$H/prov.rc"; } | head -c 1 > /dev/null
    sleep 1
    [ "$(cat "$H/prov.rc" 2>/dev/null)" = 0 ] && [ -z "$(ls -A "$pt")" ] \
        && ok "provide: an answer that finds its reader gone never ends the provider mid-request; it leaves at the end of its input, exit 0, nothing left (#60)" || bad "provide sigpipe" "exit $(cat "$H/prov.rc" 2>/dev/null) left: $(ls -A "$pt")"
    rm -rf "$pt"
else ok "provide: no GNU env and no python3 to give SIGPIPE back its default here, the closed wire is not tried"; fi
# the files provider: the host's roots, a folder's rows, three read-only tools held to four lines
F=$H/files; mkdir -p "$F/docs/deep/x" "$F/.secret"; printf 'hello\nworld\n' > "$F/notes.md"; printf 'x\000y' > "$F/blob.txt"; printf 'p' > "$F/pic.png"
ln -s /etc "$F/etc-link"; printf 'k' > "$F/.secret/key"; mkfifo "$F/pipe"; printf 'a\n' > "$F/docs/a.txt"
FR=$(realpath "$F"); uri() { printf 'spark-shell://files/rows/%s' "$(printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_')"; }
# a system file manager configured (xdg-open there, xdg-mime naming one for a folder) for the files block, as macOS has Finder; and a PATH with none (#114)
mkdir -p "$H/fm" "$H/nofm"; printf '#!/bin/sh\necho "$*" >> "$HOME/xdg-open.log"\n' > "$H/fm/xdg-open"; printf '#!/bin/sh\n[ "$*" != "query default inode/directory" ] || echo thunar.desktop\n' > "$H/fm/xdg-mime"
cp "$H/fm/xdg-open" "$H/nofm/xdg-open"; printf '#!/bin/sh\n' > "$H/nofm/xdg-mime"; chmod +x "$H/fm/xdg-open" "$H/fm/xdg-mime" "$H/nofm/xdg-open" "$H/nofm/xdg-mime"
_fpath=$PATH; PATH="$H/fm:$PATH"
# the rows as the dialog reads them (#123): a row of a kind takes the list's steps for that kind, with its own args
KX='. as $l | .rows |= map(. as $r | ($l.kinds[$r.kind // ""] // null) as $k | if $k == null then . else . + {tool: ($k.tool | if . == null then null else .arguments = ((.arguments // {}) + $r.args) end), more: ([($k.more // [])[] | .arguments = ((.arguments // {}) + $r.args)])} end)'
rinit=$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{"roots":{}},"clientInfo":{"name":"test","version":"0"}}')
roots=$(jq -cn --arg u "file://$FR" '{jsonrpc: "2.0", id: "roots", result: {roots: [{uri: $u}, {uri: "file:///"}]}}')
mcp files "$rinit" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$roots" "$(rq 2 resources/read '{"uri":"spark-shell://files/rows"}')" \
    "$(rq 3 resources/read "$(jq -cn --arg u "$(uri "$FR")" '{uri: $u}')")" \
    "$(fcall 4 files_show "$FR/notes.md")" "$(fcall 5 files_attach "$FR/notes.md")" "$(fcall 6 files_show "$FR/.secret/key")" "$(fcall 7 files_show "$FR/blob.txt")" \
    "$(fcall 8 files_show "$FR/etc-link/hosts")" "$(fcall 9 files_show /etc/hosts)" "$(fcall 10 files_attach "$FR/pic.png")" \
    "$(rq 11 resources/read "$(jq -cn --arg u "$(uri "$FR/.secret")" '{uri: $u}')")" "$(rq 12 resources/read "$(jq -cn --arg u "$(uri /)" '{uri: $u}')")" \
    "$(rq 13 resources/read "$(jq -cn --arg u "$(uri "$FR/docs")" '{uri: $u}')")" \
    "$(rq 14 resources/read "$(jq -cn --arg u "$(uri "$FR/docs/deep")" '{uri: $u}')")" "$(rq 15 resources/read "$(jq -cn --arg u "$(uri "$FR/docs/deep/x")" '{uri: $u}')")"
[ "$(jq -c 'select(.method == "roots/list") | .id' "$H/mcp.out")" = '"roots"' ] && ok "provide files: a host that has roots is asked for them once initialized" || bad "files roots ask" "$(cat "$H/mcp.out" | head -3)"
ans 2 | jq -r '.result.contents[0].text' | jq -e --arg u "$(uri "$FR")" '.rows | length == 1 and .[0].children == $u and .[0].sign == "opens"' >/dev/null \
    && ok "provide files: the roots are the rows at the top, each opening its folder; / is never a root" || bad "files root rows" "$(ans 2)"
ans 3 | jq -r '.result.contents[0].text' > "$H/folder.raw"; jq "$KX" "$H/folder.raw" > "$H/folder.json"
[ "$(jq -r '[.rows[] | .text] | join("|")' "$H/folder.json")" = "docs|blob.txt|notes.md|pic.png|etc-link -> /etc|this folder $(printf '\302\267') 1 folder $(printf '\302\267') 3 files $(printf '\302\267') 16 B" ] \
    && [ "$(jq -r '.rows[-1] | [.more[].said] | join("|")' "$H/folder.json")" = 'new folder|new file|open in the system file manager' ] \
    && jq -e '(.rows[] | select(.text == "docs") | .children != null and .columns == ["2 items"] and .tool.name == "files_browse") and (.rows[] | select(.text == "notes.md") | .tool.name == "files_open" and .columns[0] == "12 B" and ([.more[].name] == ["files_app", "files_preview", "files_attach", "files_reveal", "files_rename", "files_move", "files_copy", "files_trash"]) and (.page | startswith("spark-shell://files/preview/"))) and (.rows[] | select(.text | startswith("etc-link")) | .tool == null and .children == null)' "$H/folder.json" >/dev/null \
    && ok "provide files: a folder lists its folders, then its files with the size and the date, then one row for itself, its actions behind it (#127); a link is shown and never followed; a hidden file and a pipe are not listed" || bad "files folder" "$(jq -c '.rows[] | [.text, .columns, .tool.name]' "$H/folder.json")"
# #141: a wide list's columns beside the short ones: a file's kind, its size and its date with the time; a folder's
jq -e '(.rows[] | select(.text == "notes.md") | .wide[0] == "Markdown" and .wide[1] == .columns[0] and (.wide[2] | test("^today [0-9][0-9]:[0-9][0-9]$")))
    and (.rows[] | select(.text == "pic.png") | .wide[0] == "picture") and (.rows[] | select(.text == "blob.txt") | .wide[0] == "text")
    and (.rows[] | select(.text == "docs") | .wide[0:2] == ["folder", "2 items"]) and ([.rows[] | select(.text | startswith("this folder")) | .wide] == [null])' "$H/folder.json" >/dev/null \
    && ok "provide files: a wide list's columns, the kind in plain words, the size and the date with the time; a folder's kind and count (#141)" || bad "files wide" "$(jq -c '.rows[] | [.text, .wide]' "$H/folder.json")"
[ "$(ans 4 | jq -r .result.structuredContent.receipt)" = "$(printf 'notes.md\nhello\nworld')" ] && [ "$(ans 5 | jq -r .result.structuredContent.attach)" = "$FR/notes.md" ] \
    && ok "provide files: show gives a text file's first lines; attach gives its path for the next want" || bad "files show attach" "$(ans 4) $(ans 5)"
for i in 6 8 9; do [ "$(ans $i | jq -r '.result.content[0].text')" = 'files: that is not a file in the folders given' ] || bad "files refusal $i" "$(ans $i)"; done
[ "$(ans 7 | jq -r '.result.content[0].text')" = 'files: blob.txt is not text' ] && [ "$(ans 10 | jq -r '.result.content[0].text')" = 'files: pic.png is not a type plus attaches (txt md)' ] \
    && [ "$(ans 11 | jq -r .error.code)" = -32002 ] && [ "$(ans 12 | jq -r .error.code)" = -32002 ] \
    && ok "provide files: a hidden file, a path through a link and a file outside the roots are refused; a binary and a type plus does not take too; a hidden folder and / are no resource" || bad "files refusals" "$(ans 7) $(ans 10) $(ans 11) $(ans 12)"
ans 13 | jq -r '.result.contents[0].text' | jq -e --arg u "$(uri "$FR")" '.rows[0].text == ".." and .rows[0].children == $u and (.rows[] | select(.text == "deep") | .children != null)' >/dev/null \
    && ok "provide files: a folder under a root opens with .. back to its parent" || bad "files up" "$(ans 13 | head -c 300)"
[ "$(ans 14 | jq -r '.result.contents[0].text' | jq -r '.rows[] | select(.id == "files:here") | .text')" = "this folder $(printf '\302\267') 1 folder" ] && [ "$(ans 15 | jq -r '.result.contents[0].text' | jq -r '[.rows[].text] | join("|")')" = "..|this folder $(printf '\302\267') empty" ] \
    && ok "provide files: a folder of folders counts its folders, and an empty folder says empty" || bad "files totals" "$(ans 14 | head -c 300) $(ans 15 | head -c 300)"
mcp files "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}')" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$(rq 2 resources/read '{"uri":"spark-shell://files/rows"}')" "$(fcall 3 files_show "$FR/notes.md")"
! grep -q roots/list "$H/mcp.out" && [ "$(ans 2 | jq -r '.result.contents[0].text' | jq -c .rows)" = '[]' ] && [ "$(ans 3 | jq -r '.result.content[0].text')" = 'files: that is not a file in the folders given' ] \
    && ok "provide files: a host with no roots is never asked, and no file is reachable" || bad "files no roots" "$(cat "$H/mcp.out")"
# the file manager (#112): a home of its own as the root, so the recent files and the trash are its own
F2=$H/home2; mkdir -p "$F2/docs/deep" "$F2/pictures" "$F2/node_modules/x"; printf 'hello\nworld\n' > "$F2/notes.md"; printf 'invoice text here\n' > "$F2/docs/invoice.txt"; printf 'p' > "$F2/pictures/photo.png"; printf 'invoice text here too\n' > "$F2/node_modules/x/invoice.js"
touch -t "$(date -d '-3 day' +%Y%m%d%H%M 2>/dev/null || date -v-3d +%Y%m%d%H%M)" "$F2/docs/invoice.txt"; touch -t 202001010000 "$F2/pictures/photo.png" "$F2/node_modules/x/invoice.js"
F2R=$(realpath "$F2"); roots2=$(jq -cn --arg u "file://$F2R" '{jsonrpc: "2.0", id: "roots", result: {roots: [{uri: $u}]}}')
mcp2() { printf '%s\n' "$rinit" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$roots2" "$@" | HOME=$F2 XDG_DATA_HOME=$F2/.local/share XDG_CACHE_HOME=$F2/.cache SPARK_SHELL_NO_UDISKS=1 SPARK_SHELL_NO_GIO=${NO_GIO-1} SPARK_SHELL_NO_THUMB=1 SPARK_SHELL_NO_SVG=1 sh "$SH" provide files > "$H/mcp.out" 2> "$H/mcp.err"; }
fc2() { call "$1" "$2" "$(jq -cn --arg p "$3" --arg k "${4:-}" --arg v "${5:-}" '{path: $p} + (if $k == "" then {} else {($k): $v} end)')"; }   # fc2 ID TOOL PATH [KEY VALUE]
mcp2 "$(rq 2 resources/read "$(jq -cn --arg u "$(uri "$F2R")" '{uri: $u}')")" "$(rq 3 resources/read "$(jq -cn --arg u "$(uri "$F2R/docs")" '{uri: $u}')")"
ans 2 | jq -r '.result.contents[0].text' | jq "$KX" > "$H/home2.json"; ans 3 | jq -r '.result.contents[0].text' | jq "$KX" > "$H/docs2.json"
[ "$(jq -r '.here' "$H/home2.json")" = "$F2R" ] && [ "$(jq -r '[.rows[] | select(.group == "recent") | .text + " " + (.columns | join(","))] | join("|")' "$H/home2.json")" = "notes.md 12 B,today,~|invoice.txt 18 B,$(date -d '-3 day' '+%d %b' 2>/dev/null || date -v-3d '+%d %b'),docs" ] \
    && [ "$(jq -r '[.rows[] | select(.group == "home") | .text] | join("|")' "$H/home2.json")" = 'docs|node_modules|pictures|notes.md|trash' ] \
    && [ "$(jq -r '[.rows[] | .group // "-"] | reduce .[] as $g ([]; if .[-1] == $g then . else . + [$g] end) | join(",")' "$H/home2.json")" = 'home,recent,-' ] \
    && [ "$(jq -r '.rows[-1] | .text + "|" + ([.more[] | .said + ":" + .name + ":" + ((.ask // []) | join(","))] | join("|"))' "$H/home2.json")" = "this folder $(printf '\302\267') 3 folders $(printf '\302\267') 1 file $(printf '\302\267') 12 B|new folder:files_new_folder:name|new file:files_new_text:name|open in the system file manager:files_browse:" ] \
    && jq -e --arg p "$F2R" '[.rows[-1].more[].arguments.path] | all(. == $p)' "$H/home2.json" >/dev/null \
    && ok "provide files: your home folder: home first, its folders and files, the trash (#130); the files touched in the last days below it (today, 3 days ago; a 2020 picture is not recent), each with its folder's name; then one row for the folder, its actions behind it: new folder and new text file (each asking a name), the system file manager (#127); here is the folder" || bad "files home rows" "$(jq -c '{here, rows: [.rows[] | [.text, .group, .columns, .tool.name]]}' "$H/home2.json")"
[ "$(jq -r '[.rows[] | .text] | join("|")' "$H/docs2.json")" = "..|deep|invoice.txt|this folder $(printf '\302\267') 1 folder $(printf '\302\267') 1 file $(printf '\302\267') 18 B" ] && [ "$(jq -r .here "$H/docs2.json")" = "$F2R/docs" ] \
    && [ "$(jq -r '.rows[] | select(.text == "deep") | .tool.name + ":" + .tool.said + "|" + ([.more[] | .said] | join(","))' "$H/docs2.json")" = 'files_browse:open in the system file manager|open in app,reveal in the system file manager,rename,move to a folder,copy to a folder,trash' ] \
    && [ "$(jq -r '.rows[] | select(.text == "invoice.txt") | .tool.name + "|" + ([.more[] | .name + ":" + ((.ask // []) | join(",")) + ":" + (.pick // "")] | join(" "))' "$H/docs2.json")" = 'files_open|files_app:: files_preview:: files_attach:: files_reveal:: files_rename:name: files_move::to files_copy::to files_trash::' ] \
    && [ "$(jq -r '.rows[] | select(.text == "deep") | .columns[0]' "$H/docs2.json")" = '0 items' ] \
    && ok "provide files: a folder's rows: .. first, a folder with its steps (reveal, rename, move, copy, trash, each in a person's words), a file with show and attach before them; rename asks a name, move and copy pick a folder (to); no recent group below your home" || bad "files docs rows" "$(jq -c '{here, rows: [.rows[] | [.text, .group, .tool.name, [.more[]?.said]]]}' "$H/docs2.json")"
# #130: the trash, a place of its own: what it holds, the folder each came from; restore, delete for good, empty the trash
TR=$F2/.local/share/Trash; rm -rf "$TR"; mkdir -p "$F2/old dir"; printf 'old' > "$F2/docs/old notes.txt"
( NO_GIO=1 mcp2 "$(fc2 2 files_trash "$F2R/docs/old notes.txt")" "$(fc2 3 files_trash "$F2R/old dir")" "$(rq 4 resources/read '{"uri":"spark-shell://files/rows/trash"}')" \
    "$(rq 5 resources/read "$(jq -cn --arg u "$(uri "$F2R")" '{uri: $u}')")" "$(fc2 6 files_purge "$F2R/docs/old notes.txt")" "$(rq 7 tools/list)" )
ans 4 | jq -r '.result.contents[0].text' | jq "$KX" > "$H/trash.json"
[ "$(jq -r '[.rows[] | .text + ":" + (.columns | join(","))] | join("|")' "$H/trash.json")" = "old dir:folder,today,~|old notes.txt:3 B,today,docs|the trash $(printf '\302\267') 2 items $(printf '\302\267') 3 B:" ] \
    && jq -e --arg p "$F2R/docs/old notes.txt" '(.rows[] | select(.text == "old notes.txt") | .tool.name == "files_restore" and .tool.arguments.path == $p and ([.more[].said] == ["delete for good"])) and (.rows[-1] | [.more[].name] == ["files_empty"])' "$H/trash.json" >/dev/null \
    && [ "$(ans 5 | jq -r '.result.contents[0].text | fromjson | .rows[] | select(.id == "files:trash") | .text + ":" + .columns[0] + ":" + .children')" = 'trash:2 items:spark-shell://files/rows/trash' ] \
    && [ "$(ans 6 | jq -r '.result.structuredContent | .receipt + ":" + (.undo // "-" | tostring)')" = 'old notes.txt is deleted for good:-' ] && [ ! -e "$TR/files/old notes.txt" ] && [ ! -e "$TR/info/old notes.txt.trashinfo" ] && [ -d "$TR/files/old dir" ] \
    && [ "$(ans 7 | jq -c '[.result.tools[] | select(.name == "files_purge" or .name == "files_empty" or .name == "files_trash") | [.name, .annotations.destructiveHint]]')" = '[["files_trash",false],["files_purge",true],["files_empty",true]]' ] \
    && ok "provide files: the trash is a place, each in it with its size, the day and the folder it came from, restore on Enter and delete for good behind it, the trash's own row to empty it; your home lists it; delete for good is gone with its record, no undo, and asks a yes (#130)" \
    || bad "files trash place" "$(cat "$H/trash.json") $(ans 5 | head -c 300) $(ans 6) $(ans 7 | jq -c '[.result.tools[] | select(.name | test("trash|purge|empty")) | [.name, .annotations]]')"
( NO_GIO=1 mcp2 "$(call 2 files_empty '{}')" "$(call 3 files_empty '{}')" )
[ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'the trash is empty: 1 deleted for good' ] && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = 'the trash is empty already' ] \
    && [ -z "$(ls -A "$TR/files" 2>/dev/null)" ] && [ -z "$(ls -A "$TR/info" 2>/dev/null)" ] && ok "provide files: empty the trash deletes every file in it for good, its records with them; an empty trash says so (#130)" || bad "files empty" "$(ans 2) $(ans 3) $(ls -A "$TR/files" "$TR/info" 2>&1)"
# two trashed from one path (a file replaced twice is this): a row names its own item, so what you pick is what goes
printf 'OLD' > "$F2/docs/twin.txt"; ( NO_GIO=1 mcp2 "$(fc2 2 files_trash "$F2R/docs/twin.txt")" )
printf 'NEW' > "$F2/docs/twin.txt"; ( NO_GIO=1 mcp2 "$(fc2 2 files_trash "$F2R/docs/twin.txt")" "$(rq 3 resources/read '{"uri":"spark-shell://files/rows/trash"}')" )
ans 3 | jq -r '.result.contents[0].text' | jq "$KX" > "$H/twins.json"
_old=$(jq -c '.rows[] | select(.id == "files:trashed:twin.txt") | .tool.arguments' "$H/twins.json")
_new=$(jq -c '.rows[] | select(.id == "files:trashed:twin.txt.2") | .tool.arguments' "$H/twins.json")
[ "$(printf '%s' "$_old" | jq -r .item)" = twin.txt ] && [ "$(printf '%s' "$_new" | jq -r .item)" = twin.txt.2 ] && ok "provide files: two trashed from one path: each row's step names its own item" || bad "trash item rows" "$(cat "$H/twins.json")"
( NO_GIO=1 mcp2 "$(call 2 files_purge "$(printf '%s' "$_old" | jq -c '.item = "../../docs/keep"')")" "$(call 3 files_purge "$(printf '%s' "$_old" | jq -c '.item = "other.txt"')")" )
ans 2 | jq -e '.error.code == -32602' >/dev/null && [ "$(ans 3 | jq -r .result.isError)" = true ] && [ "$(cat "$TR/files/twin.txt")" = OLD ] && [ "$(cat "$TR/files/twin.txt.2")" = NEW ] \
    && ok "provide files: an item that is a path, or one the trash does not hold from that path, is refused, nothing gone" || bad "trash item refused" "$(ans 2) $(ans 3)"
( NO_GIO=1 mcp2 "$(call 2 files_purge "$_old")" )
[ ! -e "$TR/files/twin.txt" ] && [ ! -e "$TR/info/twin.txt.trashinfo" ] && [ "$(cat "$TR/files/twin.txt.2")" = NEW ] && ok "provide files: delete for good on the older row deletes the older, the newer stays" || bad "trash purge older" "$(ans 2) $(ls "$TR/files")"
printf 'OLDER' > "$F2/docs/twin.txt"; ( NO_GIO=1 mcp2 "$(fc2 2 files_trash "$F2R/docs/twin.txt")" "$(call 3 files_restore "$_new")" )
[ "$(cat "$F2/docs/twin.txt")" = NEW ] && [ "$(cat "$TR/files/twin.txt")" = OLDER ] && ok "provide files: restore on a row brings that item back, not the newest from its path" || bad "trash restore row" "$(ans 3) $(ls "$TR/files")"
( NO_GIO=1 mcp2 "$(fc2 2 files_restore "$F2R/nothing-here.txt")" ); rm -rf "$TR" "$F2/docs/twin.txt"
# #123: a folder of thousands, gracefully. Each row carries its kind and its path, the steps are the list's once; a large folder
# lists a page at a time under the 512 kB of a resource the dialog reads, its last row opening the next; no small pictures (#127); one stat
# for many paths, so a folder of 1,235 answers in moments; a search that reaches its time says so
BIG=$F2R/big; mkdir -p "$BIG/sub" "$F2R/pics" "$H/tstop" "$XDG_STATE_HOME/spark-shell/thumbs/files"; : > "$BIG/sub/x"; : > "$XDG_STATE_HOME/spark-shell/thumbs/files/old.png"
i=0; while [ $i -lt 1234 ]; do : > "$BIG/file-$(printf %04d $i).txt"; i=$((i + 1)); done
i=0; while [ $i -lt 205 ]; do : > "$F2R/pics/photo-$(printf %03d $i).png"; i=$((i + 1)); done
_t0=$(date +%s); mcp2 "$(rq 2 resources/read "$(jq -cn --arg u "$(uri "$BIG")" '{uri: $u}')")" "$(rq 4 resources/read "$(jq -cn --arg u "$(uri "$F2R/pics")" '{uri: $u}')")"; _t1=$(date +%s)
ans 2 | jq -r '.result.contents[0].text' > "$H/big1.json"; ans 4 | jq -r '.result.contents[0].text' > "$H/pics.json"; _b1=$(wc -c < "$H/big1.json" | tr -d ' ')
_nx=$(jq -r '.rows[] | select(.id == "files:more") | .children' "$H/big1.json")
mcp2 "$(rq 3 resources/read "$(jq -cn --arg u "$_nx" '{uri: $u}')")"; ans 3 | jq -r '.result.contents[0].text' > "$H/big2.json"
_n1=$(jq '[.rows[] | select(.kind == "file" or .kind == "dir")] | length' "$H/big1.json"); _n2=$(jq '[.rows[] | select(.kind == "file" or .kind == "dir")] | length' "$H/big2.json")
[ $((_n1 + _n2)) = 1235 ] && [ "$_b1" -lt 524288 ] && [ $((_t1 - _t0)) -le 15 ] && case $_nx in "$(uri "$BIG")?from=$_n1") true ;; *) false ;; esac \
    && jq -e --arg b "$BIG" --arg left "$((1235 - _n1)) more" '(.rows[1] | .text == "sub" and .columns == ["1 item"]) and (.rows[] | select(.id == "files:more") | .text == "the next page" and .columns == [$left])
        and (.rows[] | select(.text == "file-0000.txt") | .kind == "file" and .args == {path: ($b + "/file-0000.txt")} and (has("more") | not) and (has("tool") | not))
        and (.kinds.file.tool.name == "files_open") and ([.kinds.file.more[].name] | index("files_trash") != null) and (.rows[] | select(.id == "files:here") | .text | endswith("1,234 files \u00b7 0 B"))' "$H/big1.json" >/dev/null \
    && jq -e '(.rows[0].id == "files:up") and ([.rows[] | select(.id == "files:more")] | length == 0) and (.rows[] | select(.id == "files:here") | .text | endswith("1,234 files \u00b7 0 B"))' "$H/big2.json" >/dev/null \
    && ok "provide files: a folder of 1,235 lists a page under the dialog's 512 kB, its last row opening the next with what is left; a row carries its kind and path, the steps are the list's once; in moments ($((_t1 - _t0)) s) (#123)" \
    || bad "files big folder" "$_n1 + $_n2 rows, $_b1 bytes, $((_t1 - _t0)) s, next $_nx $(jq -c '[.rows[] | select(.kind == null)]' "$H/big1.json" 2>&1 | head -c 600)"
[ "$(jq '[.rows[] | select(.preview != null)] | length' "$H/pics.json")" = 0 ] && [ ! -d "$XDG_STATE_HOME/spark-shell/thumbs/files" ] \
    && ok "provide files: a picture's row carries no small picture, and the small pictures kept before go: Space shows a file whole (#127)" || bad "files no thumbs" "$(jq -c '[.rows[] | select(.preview != null)] | length' "$H/pics.json") $(ls "$XDG_STATE_HOME/spark-shell/thumbs" 2>&1)"
printf '#!/bin/sh\nexit 124\n' > "$H/tstop/timeout"; chmod +x "$H/tstop/timeout"   # a walk that reaches its time
( PATH="$H/tstop:$PATH" mcp2 "$(rq 5 resources/read "$(jq -cn --arg u "spark-shell://files/rows/find/$(printf 'file-0001' | base64 | tr -d '\n=' | tr '+/' '-_')" '{uri: $u}')")" )
[ "$(ans 5 | jq -r '.result.contents[0].text | fromjson | .rows[] | select(.id == "files:total") | .text')" = 'the search stopped at 8 seconds: 0 found' ] \
    && ok "provide files: a search that reaches its time says it stopped, and how many it found (#123)" || bad "files search stopped" "$(ans 5)"
rm -rf "$BIG" "$F2R/pics"
mcp2 "$(fc2 2 files_rename "$F2R/notes.md" name 'Notes 2026.md')" "$(fc2 3 files_move "$F2R/Notes 2026.md" to "$F2R/docs")" "$(fc2 4 files_copy "$F2R/docs/invoice.txt" to "$F2R/pictures")" "$(fc2 5 files_trash "$F2R/pictures/invoice.txt")" \
    "$(fc2 6 files_copy "$F2R/docs/invoice.txt" to "$F2R/pictures")" "$(fc2 7 files_trash "$F2R/pictures/invoice.txt")" "$(fc2 11 files_move "$F2R/docs/Notes 2026.md" to "$F2R")"
cp "$H/mcp.out" "$H/mcp.first"   # the two trashed, before the restore
mcp2 "$(fc2 8 files_restore "$F2R/pictures/invoice.txt")" "$(fc2 9 files_new_folder "$F2R/docs" name 'new one')" "$(fc2 10 files_new_text "$F2R/docs" name todo.txt)"
cat "$H/mcp.first" >> "$H/mcp.out"
[ "$(ans 2 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/Notes 2026.md" '{receipt: "notes.md renamed to Notes 2026.md", undo: {name: "files_rename", arguments: {path: $p, name: "notes.md"}}}')" ] \
    && [ "$(ans 3 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/docs/Notes 2026.md" --arg t "$F2R" '{receipt: "Notes 2026.md moved to ~/docs", undo: {name: "files_move", arguments: {path: $p, to: $t}}}')" ] \
    && [ "$(ans 11 | jq -r '.result.structuredContent.receipt')" = 'Notes 2026.md moved to ~' ] && [ -f "$F2/Notes 2026.md" ] && [ ! -e "$F2/docs/Notes 2026.md" ] \
    && ok "provide files: rename keeps the name whole (a space, a capital), its undo is the old name; move says the folder as a person writes it, its undo moves it back, and does" || bad "files rename move" "$(ans 2) $(ans 3) $(ans 11)"
[ "$(ans 4 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/pictures/invoice.txt" '{receipt: "invoice.txt copied to ~/pictures", undo: {name: "files_trash", arguments: {path: $p}}}')" ] && [ -f "$F2/docs/invoice.txt" ] \
    && [ "$(ans 5 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/pictures/invoice.txt" '{receipt: "invoice.txt is in the trash", undo: {name: "files_restore", arguments: {path: $p}}}')" ] \
    && [ -f "$F2/.local/share/Trash/files/invoice.txt" ] && grep -qx "Path=$(printf '%s' "$F2R" | sed 's/ /%20/g')/pictures/invoice.txt" "$F2/.local/share/Trash/info/invoice.txt.trashinfo" && grep -q '^DeletionDate=20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$' "$F2/.local/share/Trash/info/invoice.txt.trashinfo" && [ "$(sed -n 1p "$F2/.local/share/Trash/info/invoice.txt.trashinfo")" = '[Trash Info]' ] \
    && [ "$(ans 7 | jq -r '.result.structuredContent.receipt')" = 'invoice.txt is in the trash' ] \
    && [ "$(ans 8 | jq -r '.result.structuredContent.receipt')" = 'invoice.txt is back' ] && [ -f "$F2/pictures/invoice.txt" ] && [ ! -e "$F2/.local/share/Trash/files/invoice.txt.2" ] && [ ! -e "$F2/.local/share/Trash/info/invoice.txt.2.trashinfo" ] && [ -f "$F2/.local/share/Trash/files/invoice.txt" ] \
    && ok "provide files: a copy's undo is the trash; the trash is the freedesktop spec by hand (files/ and info/NAME.trashinfo with the path and the date), a second of one name is NAME.2, and restore brings the newest from that path back, the other kept" || bad "files copy trash restore" "$(ans 4) $(ans 5) $(ans 7) $(ans 8) $(ls -R "$F2/.local/share/Trash" 2>&1)"
[ "$(ans 9 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/docs/new one" '{receipt: "folder new one made in ~/docs", undo: {name: "files_trash", arguments: {path: $p}}}')" ] && [ -d "$F2/docs/new one" ] \
    && [ "$(ans 10 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/docs/todo.txt" '{receipt: "todo.txt made in ~/docs", undo: {name: "files_trash", arguments: {path: $p}}}')" ] && [ -f "$F2/docs/todo.txt" ] && [ ! -s "$F2/docs/todo.txt" ] \
    && ok "provide files: a new folder and a new text file are made in the folder named, each with the trash as its undo (the editor opens on the desktop alone)" || bad "files new" "$(ans 9) $(ans 10)"
# F4: the app the system assigns, a text file too, never the editor; outside the folders given, refused before any opener runs
mcp2 "$(fc2 2 files_app "$H/notes.md")"
[ "$(ans 2 | jq -r '.result.content[0].text')" = 'files: that is not a file or a folder in the folders given' ] && ok "provide files: files_app holds to the folders given" || bad "files app refused" "$(ans 2)"
if [ "$(uname)" = Linux ]; then
    mkdir -p "$H/xo"; printf '#!/bin/sh\nprintf %%s "$1" > "%s/xo/opened"\n' "$H" > "$H/xo/xdg-open"; chmod +x "$H/xo/xdg-open"
    ( PATH="$H/xo:$PATH" WAYLAND_DISPLAY=proof mcp2 "$(fc2 2 files_app "$F2R/docs/invoice.txt")" )
    [ "$(cat "$H/xo/opened" 2>/dev/null)" = "$F2R/docs/invoice.txt" ] && ok "provide files: files_app gives a text file to the system's opener, not the editor" || bad "files app" "$(cat "$H/xo/opened" 2>/dev/null) $(ans 2)"
fi
mcp2 "$(fc2 2 files_trash "$F2R")" "$(fc2 3 files_rename "$F2R/docs" name .hidden)" "$(fc2 4 files_rename "$F2R/docs" name 'a/b')" "$(fc2 5 files_move "$F2R/docs" to "$F2R/docs/deep")" "$(fc2 6 files_move "$F2R/docs/invoice.txt" to "$F2R/docs")" \
    "$(fc2 7 files_restore "$F2R/docs/nothing.txt")" "$(fc2 8 files_trash "$H/notes.md")" "$(fc2 9 files_new_folder "$F2R" name docs)" "$(fc2 10 files_move "$F2R/docs/invoice.txt" to "$F2R/etc-link")" "$(fc2 11 files_rename "$F2R/docs/deep" name "$(printf 'a\tb')")"
[ "$(ans 2 | jq -r '.result.content[0].text')" = 'files: your home and a drive stay as they are' ] && [ "$(ans 3 | jq -r '.result.content[0].text')" = 'files: a name is one plain name: no slash, not hidden, 255 characters at most' ] && [ "$(ans 4 | jq -r '.error.message')" = 'files_rename: name is one name, no slash, 255 characters at most' ] \
    && [ "$(ans 5 | jq -r '.result.content[0].text')" = 'files: a folder does not go inside itself' ] && [ "$(ans 6 | jq -r '.result.content[0].text')" = 'files: invoice.txt is in ~/docs already' ] && [ "$(ans 7 | jq -r '.result.content[0].text')" = 'files: the trash holds nothing from nothing.txt' ] \
    && [ "$(ans 8 | jq -r '.result.content[0].text')" = 'files: that is not a file or a folder in the folders given' ] && [ "$(ans 9 | jq -r '.result.content[0].text')" = 'files: docs already exists' ] && [ "$(ans 10 | jq -r '.result.content[0].text')" = 'files: that is not a folder in the folders given' ] \
    && [ "$(ans 11 | jq -r '.error.code')" = -32602 ] && [ -d "$F2/docs/deep" ] \
    && ok "provide files: refused in one line each: the home itself, a hidden name (the provider) or a slashed one (the schema), a folder into itself, a move to where it is, a restore of nothing, a path outside the roots, a name taken, a folder that is no folder, a control character in a name" || bad "files refusals" "$(for i in 2 3 4 5 6 7 8 9 10 11; do ans $i | jq -c '.result.content[0].text // .error.message'; done)"
# files v0: a name there already. Refused alone (the dialog asks); there says what to do: keep both (notes 2.md, then notes 3.md; a folder album 2) or replace
# (the one there to the trash first, the receipt says so); name alone is the name it takes there
fc3() { call "$1" "$2" "$(jq -cn --arg p "$3" --arg t "$4" --arg n "${5:-}" --arg h "${6:-}" '{path: $p, to: $t} + (if $n == "" then {} else {name: $n} end) + (if $h == "" then {} else {there: $h} end)')"; }   # fc3 ID TOOL PATH TO [NAME] [THERE]
mkdir -p "$F2/inbox/album" "$F2/kept/album"; printf 'one\n' > "$F2/inbox/notes.md"; printf 'two\n' > "$F2/kept/notes.md"
mcp2 "$(fc3 2 files_copy "$F2R/inbox/notes.md" "$F2R/kept")" "$(fc3 3 files_copy "$F2R/inbox/notes.md" "$F2R/kept" '' keep)" "$(fc3 4 files_copy "$F2R/inbox/notes.md" "$F2R/kept" '' keep)" "$(fc3 5 files_copy "$F2R/inbox/album" "$F2R/kept" '' keep)" \
    "$(fc3 6 files_move "$F2R/inbox/notes.md" "$F2R/kept" '' keep)" "$(fc3 7 files_move "$F2R/kept/notes 4.md" "$F2R/inbox" notes.md)" "$(fc3 8 files_move "$F2R/inbox/notes.md" "$F2R/kept" '' replace)" \
    "$(fc3 9 files_copy "$F2R/kept/notes.md" "$F2R/inbox" plan.md)" "$(fc3 10 files_copy "$F2R/kept/notes.md" "$F2R/inbox" plan.md)" "$(fc3 11 files_copy "$F2R/kept/notes.md" "$F2R/inbox" plan.md replace)" \
    "$(fc3 12 files_move "$F2R/kept/notes.md" "$F2R/inbox" .x)" "$(fc3 13 files_move "$F2R/kept/notes.md" "$F2R/inbox" '' both)" "$(fc3 14 files_move "$F2R/kept/notes.md" "$F2R/inbox" 'a/b')" "$(fc3 15 files_copy "$F2R/kept/notes.md" "$F2R/kept" '' keep)"
[ "$(ans 2 | jq -r '.result.content[0].text')" = 'files: notes.md already exists' ] \
    && [ "$(ans 3 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/kept/notes 2.md" '{receipt: "notes.md copied to ~/kept as notes 2.md", undo: {name: "files_trash", arguments: {path: $p}}}')" ] \
    && [ "$(ans 4 | jq -r '.result.structuredContent.receipt')" = 'notes.md copied to ~/kept as notes 3.md' ] && [ "$(cat "$F2/kept/notes 2.md" "$F2/kept/notes 3.md" | tr '\n' ' ')" = 'one one ' ] \
    && [ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'album copied to ~/kept as album 2' ] && [ -d "$F2/kept/album 2" ] && [ -d "$F2/kept/album" ] \
    && ok "provide files: a name there already is refused, so the dialog asks; there=keep copies beside it as notes 2.md, then notes 3.md, the first free, a folder as album 2; the copy's undo trashes the copy (files v0)" || bad "files keep copy" "$(ans 2) $(ans 3) $(ans 4) $(ans 5)"
[ "$(ans 6 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/kept/notes 4.md" --arg t "$F2R/inbox" '{receipt: "notes.md moved to ~/kept as notes 4.md", undo: {name: "files_move", arguments: {path: $p, to: $t, name: "notes.md"}}}')" ] \
    && [ "$(ans 7 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/inbox/notes.md" --arg t "$F2R/kept" '{receipt: "notes 4.md moved to ~/inbox as notes.md", undo: {name: "files_move", arguments: {path: $p, to: $t, name: "notes 4.md"}}}')" ] && [ ! -e "$F2/kept/notes 4.md" ] \
    && [ "$(ans 8 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/kept/notes.md" --arg t "$F2R/inbox" '{receipt: "notes.md moved to ~/kept, the one there is in the trash", undo: {name: "files_move", arguments: {path: $p, to: $t}}}')" ] \
    && [ "$(cat "$F2/kept/notes.md")" = one ] && [ ! -e "$F2/inbox/notes.md" ] && [ "$(cat "$TR/files/notes.md")" = two ] && grep -qx "Path=$(printf '%s' "$F2R" | sed 's/ /%20/g')/kept/notes.md" "$TR/info/notes.md.trashinfo" \
    && ok "provide files: there=keep moves it beside the one there as notes 4.md, its undo the move back under its old name, which brings notes.md back where it was; there=replace puts the one there in the trash first and the receipt says so, its undo the move back as ever (files v0)" || bad "files keep replace move" "$(ans 6) $(ans 7) $(ans 8) $(ls -R "$TR" 2>&1)"
[ "$(ans 9 | jq -c '.result.structuredContent')" = "$(jq -cn --arg p "$F2R/inbox/plan.md" '{receipt: "notes.md copied to ~/inbox as plan.md", undo: {name: "files_trash", arguments: {path: $p}}}')" ] && [ "$(cat "$F2/inbox/plan.md")" = one ] \
    && [ "$(ans 10 | jq -r '.result.content[0].text')" = 'files: plan.md already exists' ] && [ "$(ans 11 | jq -r '.result.structuredContent.receipt')" = 'notes.md copied to ~/inbox as plan.md, the one there is in the trash' ] && [ -f "$TR/files/plan.md" ] \
    && [ "$(ans 12 | jq -r '.result.content[0].text')" = 'files: a name is one plain name: no slash, not hidden, 255 characters at most' ] && [ "$(ans 13 | jq -r '.error.message')" = 'files_move: there is one of keep, replace' ] && [ "$(ans 14 | jq -r '.error.message')" = 'files_move: name is one name, no slash, 255 characters at most' ] \
    && [ "$(ans 15 | jq -r '.result.content[0].text')" = 'files: notes.md is in ~/kept already' ] && [ -f "$F2/kept/notes.md" ] \
    && ok "provide files: name alone is the name it takes there, refused when that name is there unless there says what to do; a hidden name (the provider), a there that is neither, a slashed name (the schema) and the same folder with keep are refused as ever (files v0)" || bad "files name there" "$(for i in 9 10 11 12 13 14 15; do ans $i | jq -c '.result.structuredContent // .result.content[0].text // .error.message'; done)"
mcp2 "$(rq 16 tools/list)" "$(fc2 17 files_purge "$F2R/kept/notes.md")" "$(fc2 18 files_purge "$F2R/inbox/plan.md")"   # the two replaced, out of the trash for the rows below
ans 16 | jq -e '[.result.tools[] | select(.name == "files_copy" or .name == "files_move") | .inputSchema | (.properties | keys) == ["name", "path", "there", "to"] and .required == ["path", "to"] and .properties.there.enum == ["keep", "replace"] and .properties.name.maxLength == 255] | length == 2 and all' >/dev/null \
    && [ "$(ans 17 | jq -r '.result.structuredContent.receipt')" = 'notes.md is deleted for good' ] && [ "$(ans 18 | jq -r '.result.structuredContent.receipt')" = 'plan.md is deleted for good' ] && [ ! -e "$TR/files/notes.md" ] && [ ! -e "$TR/files/plan.md" ] \
    && ok "provide files: copy and move list name and there in their schema, neither required, there one of keep and replace (files v0)" || bad "files schema there" "$(ans 16 | jq -c '[.result.tools[] | select(.name == "files_copy" or .name == "files_move") | .inputSchema]') $(ans 17) $(ans 18)"
rm -rf "$F2/inbox" "$F2/kept"
mcp2 "$(call 2 files_find '{"words":"invoice"}')" "$(call 3 files_find '{"words":"INV txt"}')" "$(call 4 files_say '{"words":"invoice text"}')" "$(call 5 files_say '{"words":"nothing like it"}')" "$(call 6 files_find '{"words":"  "}')" \
    "$(rq 7 resources/read "$(jq -cn --arg u "spark-shell://files/rows/find/$(printf 'invoice' | base64 | tr -d '\n=' | tr '+/' '-_')" '{uri: $u}')")"
[ "$(ans 2 | jq -c '.result.structuredContent')" = "{\"receipt\":\"2 named invoice\",\"open\":\"spark-shell://files/rows/find/$(printf 'invoice' | base64 | tr -d '\n=' | tr '+/' '-_')\"}" ] \
    && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = '2 named INV txt' ] && [ "$(ans 4 | jq -r '.result.structuredContent.receipt')" = '2 say invoice text' ] && [ "$(ans 4 | jq -r '.result.structuredContent.open')" = "spark-shell://files/rows/say/$(printf 'invoice text' | base64 | tr -d '\n=' | tr '+/' '-_')" ] \
    && [ "$(ans 5 | jq -c '.result.structuredContent')" = '{"receipt":"no text file under your home says nothing like it"}' ] && [ "$(ans 6 | jq -r '.result.content[0].text')" = 'files: find takes the words to look for' ] \
    && [ "$(ans 7 | jq -r '.result.contents[0].text' | jq -r '.title + "|" + ([.rows[] | .text + " " + (.columns | join(","))] | join("|"))')" = "find invoice|invoice.txt 18 B,$(date -d '-3 day' '+%d %b' 2>/dev/null || date -v-3d '+%d %b'),docs|invoice.txt 18 B,$(date -d '-3 day' '+%d %b' 2>/dev/null || date -v-3d '+%d %b'),pictures" ] \
    && ok "provide files: find walks the roots for a name that holds every word, whatever the case, node_modules and the hidden left out, and answers the list to open, each row with its folder (the copy kept its date); say greps the text files for the words; nothing found is said; empty words refused" || bad "files find say" "$(ans 2) $(ans 3) $(ans 4) $(ans 5) $(ans 6) $(ans 7 | head -c 400)"
if [ "$(uname -s)" = Linux ]; then   # the Linux half (the uname stub): xdg-open is a stub here, so a file may be opened
    # #114: no system file manager configured: no browse row, no reveal step, a folder's row has no tool (Enter still opens it)
    ( PATH="$H/nofm:$_fpath" mcp2 "$(rq 2 resources/read "$(jq -cn --arg u "$(uri "$F2R")" '{uri: $u}')")" "$(rq 3 resources/read "$(jq -cn --arg u "$(uri "$F2R/docs")" '{uri: $u}')")" )
    ans 2 | jq -r '.result.contents[0].text' | jq "$KX" > "$H/home3.json"; ans 3 | jq -r '.result.contents[0].text' | jq "$KX" > "$H/docs3.json"
    [ "$(jq -r '.rows[-1] | [.more[].said] | join("|")' "$H/home3.json")" = 'new folder|new file' ] \
        && jq -e '(.rows[] | select(.text == "docs") | .tool == null and .children != null and ([.more[].name] == ["files_rename", "files_move", "files_copy", "files_trash"]))' "$H/home3.json" >/dev/null \
        && jq -e '(.rows[] | select(.text == "invoice.txt") | [.more[].name] == ["files_app", "files_preview", "files_attach", "files_rename", "files_move", "files_copy", "files_trash"])' "$H/docs3.json" >/dev/null \
        && ok "provide files: with no system file manager configured the browse row and the reveal step are not offered, and a folder's row keeps its steps and its opening (#114)" || bad "files no file manager" "$(cat "$H/home3.json") $(cat "$H/docs3.json")"
    # #113: a text file opens in the editor in a terminal window, the window the receipt; a picture goes to the system's opener
    mkdir -p "$H/lxo"; cat > "$H/lxo/swaymsg" <<'EOF'
#!/bin/sh
case "$*" in "-t get_version") echo '{"human_readable":"sway-stub"}' ;;
    "-t get_tree") if [ -e "$HOME/opened" ]; then echo '{"nodes":[{"pid":1},{"pid":2}]}'; else echo '{"nodes":[{"pid":1}]}'; fi ;;
    "-r -t subscribe -m "*) echo '{ "first": true, "payload": "" }'; while [ ! -e "$HOME/opened" ]; do sleep 0.05; done; echo '{ "change": "new", "container": { "id": 2 } }' ;;
    "-- exec "*) echo "$*" >> "$HOME/swaymsg.log"; : > "$HOME/opened" ;; *) echo "$*" >> "$HOME/swaymsg.log" ;; esac
EOF
    printf '#!/bin/sh\n' > "$H/lxo/ed-stub"; chmod +x "$H/lxo/swaymsg" "$H/lxo/ed-stub"; rm -f "$F2/opened" "$F2/swaymsg.log" "$F2/xdg-open.log"
    printf 'plain words\n' > "$F2/plain.txt"; printf '\211PNG\000x' > "$F2/photo.png"
    ( SWAYSOCK=$F2/sock WAYLAND_DISPLAY=w EDITOR=ed-stub PATH="$H/lxo:$H/nofm:$_fpath" mcp2 "$(fc2 2 files_open "$F2R/plain.txt")" )
    [ "$(ans 2 | jq -c '.result.structuredContent')" = '{"opened":true}' ] && grep -qxF -- "-- exec foot -e ed-stub '$F2R/plain.txt'" "$F2/swaymsg.log" \
        && ok "provide files: a text file opens in the editor in a terminal window, the window the receipt, as a new text file does (#113)" || bad "files open text" "$(ans 2) $(cat "$F2/swaymsg.log" 2>&1)"
    if command -v python3 >/dev/null 2>&1; then
        ( SWAYSOCK='' WAYLAND_DISPLAY=w PATH="$H/nofm:$_fpath" mcp2 "$(fc2 2 files_open "$F2R/photo.png")" )
        [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'opening requested for photo.png' ] && grep -qF "$F2R/photo.png" "$F2/xdg-open.log" \
            && ok "provide files: a file that is not text keeps the system's opener (#113)" || bad "files open picture" "$(ans 2) $(cat "$F2/xdg-open.log" 2>&1)"
        # #117: inside sway, a file the opener took is opened and the dialog closes at once; a browser already open shows no new window, and the old 30 s wait left the dialog open
        rm -f "$F2/opened" "$F2/xdg-open.log"; _t0=$(date +%s)
        ( SWAYSOCK=$F2/sock WAYLAND_DISPLAY=w PATH="$H/lxo:$H/nofm:$_fpath" mcp2 "$(fc2 2 files_open "$F2R/photo.png")" )
        [ "$(ans 2 | jq -c '.result.structuredContent')" = '{"opened":true}' ] && [ $(( $(date +%s) - _t0 )) -le 5 ] && grep -qF "$F2R/photo.png" "$F2/xdg-open.log" \
            && ok "provide files: a file the system's opener took is opened within a moment, so the dialog closes, tab or window alike (#117)" || bad "files open picture sway" "$(ans 2) $(( $(date +%s) - _t0 )) s $(cat "$F2/xdg-open.log" 2>&1)"
    fi
    rm -f "$F2/plain.txt" "$F2/photo.png"
fi
PATH=$_fpath
# the preview (#120): a file shown as a page, by its kind, behind the files' lines; the tools that draw it are stubs
PV=$F2/pv; mkdir -p "$PV" "$H/pvb"; PVR=$F2R/pv
printf '# Plan\n\nsome words\n' > "$PV/plan.md"; printf 'fn main() {\n\tgo();\n}\n' > "$PV/main.rs"; printf '{"a":1,"b":[2]}' > "$PV/x.json"; printf 'x\000y' > "$PV/blob.bin"
cp "$REPO/asset/favicon-26.png" "$PV/logo.png"; printf '%%PDF-1.4 stub\n' > "$PV/report.pdf"; printf 'flac stub' > "$PV/song.flac"; printf 'webm stub' > "$PV/clip.webm"; printf 'mov stub' > "$PV/phone.mov"; printf 'mp4 stub' > "$PV/tall.mp4"
# the trial's cases: a 24-bit WAV and AIFF by their headers' bytes, a PDF locked by a password, a photo stored 40 by 20 and drawn turned, an empty picture
printf 'RIFF\044\000\000\000WAVEfmt \020\000\000\000\001\000\002\000\000\167\001\000\000\312\010\000\006\000\030\000data\000\000\000\000' > "$PV/hi.wav"
printf 'FORM\000\000\000\056AIFFCOMM\000\000\000\022\000\002\000\000\000\000\000\030\100\016\273\200\000\000\000\000\000\000' > "$PV/take.aif"
printf '%%PDF-1.4 locked\n' > "$PV/locked.pdf"; printf '\211PNG\r\n\032\n\000\000\000\015IHDR\000\000\000\050\000\000\000\024' > "$PV/turned.png"; : > "$PV/empty.png"; printf 'MM\000*tiff stub' > "$PV/scan.tif"
cat > "$H/pvb/pdfinfo" <<'STUB'
#!/bin/sh
case $* in *locked.pdf*) echo 'Command Line Error: Incorrect password' >&2; exit 1 ;; esac
printf 'Pages:          3\nPage    2 size: 612 x 792 pts (letter)\n'
STUB
cat > "$H/pvb/pdftoppm" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/pdftoppm.log"; for a; do o=$a; done; cp "$REPO_PNG" "$o.png"
STUB
cat > "$H/pvb/pdftotext" <<'STUB'
#!/bin/sh
for a; do o=$a; done; echo 'the page text' > "$o"
STUB
cat > "$H/pvb/gdk-pixbuf-thumbnailer" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/thumb.log"
case $3 in *turned.png) printf '\211PNG\r\n\032\n\000\000\000\015IHDR\000\000\000\024\000\000\000\050' > "$4" ;; *empty.png) exit 1 ;; *) cp "$3" "$4" ;; esac
STUB
cat > "$H/pvb/rsvg-convert" <<'STUB'
#!/bin/sh
for a; do case $p in -o) cp "$REPO_PNG" "$a" ;; esac; p=$a; done
STUB
cat > "$H/pvb/mpv" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/mpv.log"; us=$(printf '\037')
case $* in *--lavfi-complex=*) [ -z "${SLOW_WAVE:-}" ] || sleep 8 ;; esac   # a long sound's waveform (#124)
for a; do case $a in --vo-image-outdir=*) cp "$REPO_PNG" "${a#*=}/00000001.png" ;; --no-video) exec sleep 41 ;; esac; done
for a; do f=$a; done
case $* in *--wayland-app-id=spark-preview*) [ -z "${VIDEO_PLAYS:-}" ] || sleep "$VIDEO_PLAYS" ;; esac   # a video that plays on (#172)
case $* in *--term-playing-msg=*) case $f in
    *.flac) printf '20.5%s%s%s44100%s2%ss16%sflac%sEvening%sAda%sProofs\n' "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" ;;
    *.webm) printf '4.5%s1280%s720%s%s%s%svp8%s%s%s\n' "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" ;;
    *.mov) printf '12%s1920%s1080%s%s%s%sh264%s%s%s%s270\n' "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" ;;
    *.mp4) printf '15%s1080%s1920%s%s%s%sh264%s%s%s%s0\n' "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" ;;
    *.wav) printf '3%s%s%s96000%s2%ss32%spcm_s24le%s%s%s\n' "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" ;;
    *.aif) printf '3%s%s%s48000%s2%ss32%spcm_s24be%s%s%s\n' "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" "$us" ;;
    *.tif) echo '5400 2700' ;; esac ;; esac
STUB
chmod +x "$H/pvb/"*
pvu() { printf 'spark-shell://files/preview/%s%s' "$(printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_')" "${2:-}"; }   # pvu PATH [?QUERY] -> its page's uri
pvr() { rq "$1" resources/read "$(jq -cn --arg u "$(pvu "$2" "${3:-}")" '{uri: $u}')"; }
page() { ans "$1" | jq -r '.result.contents[0].text'; }
mcpv() { printf '%s\n' "$rinit" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$roots2" "$@" | REPO_PNG=$REPO/asset/favicon-26.png PATH="$H/pvb:$_fpath" HOME=$F2 XDG_DATA_HOME=$F2/.local/share SPARK_SHELL_NO_UDISKS=1 SPARK_SHELL_NO_GIO=1 sh "$SH" provide files > "$H/mcp.out" 2> "$H/mcp.err"; }   # mcp2 with the preview's stub tools, a thumbnailer among them
mcpv "$(pvr 2 "$PVR/plan.md")" "$(pvr 3 "$PVR/main.rs")" "$(pvr 4 "$PVR/x.json")" "$(pvr 5 "$PVR/blob.bin")" \
    "$(pvr 6 "$PVR/logo.png")" "$(pvr 7 "$PVR/report.pdf" '?page=2')" "$(pvr 8 "$PVR/report.pdf" '?page=2&full=1')" "$(pvr 9 "$PVR/song.flac")" "$(pvr 10 "$PVR/clip.webm")" \
    "$(pvr 11 "$F2R/.hidden-file")" "$(rq 12 resources/read '{"uri":"spark-shell://files/preview/L2V0Yy9ob3N0cw"}')" "$(rq 13 resources/templates/list)" "$(pvr 14 "$PVR/phone.mov")" "$(pvr 15 "$PVR/tall.mp4")" \
    "$(pvr 16 "$PVR/hi.wav")" "$(pvr 17 "$PVR/take.aif")" "$(pvr 18 "$PVR/locked.pdf")" "$(pvr 19 "$PVR/turned.png")" "$(pvr 20 "$PVR/empty.png")" "$(pvr 21 "$PVR/scan.tif")"
page 2 | jq -e '.title == "plan.md" and .lines == ["Plan", "", "some words"] and .bold == [0] and (.attach | endswith(".txt")) and (.facts | length) == 2' >/dev/null \
    && page 3 | jq -e '.numbered == true and .lines[1] == "    go();"' >/dev/null && page 4 | jq -e '.lines == ["{", "  \"a\": 1,", "  \"b\": [", "    2", "  ]", "}"]' >/dev/null \
    && page 5 | jq -e '.say == "this kind of file cannot be viewed: Enter opens it" and .lines == null' >/dev/null \
    && ok "provide files: a text previews read only, a Markdown heading bold without its #, code numbered with its tabs at four, JSON indented, binary bytes no preview (#120)" || bad "preview text" "$(page 2) | $(page 3) | $(page 4) | $(page 5)"
page 6 | jq -e '(.picture | endswith(".png")) and .full == true' >/dev/null && grep -q '^-s 26 ' "$F2/thumb.log" \
    && ok "provide files: a picture previews drawn no larger than itself, the whole of it (#120)" || bad "preview picture" "$(page 6) $(cat "$F2/thumb.log" 2>&1)"
page 7 | jq -e '.page == 2 and .pages == 3 and .size == [816, 1056] and .full == false and (.picture | endswith("-1600-2.png")) and (.attach | endswith("-2.txt"))' >/dev/null \
    && page 8 | jq -e '.full == true and (.picture | endswith("-4096-2.png"))' >/dev/null && grep -q -- '-f 2 -l 2 -png -scale-to 1600 ' "$F2/pdftoppm.log" && grep -q -- '-scale-to 4096 ' "$F2/pdftoppm.log" \
    && ok "provide files: a PDF's page drawn, page 2 of 3, its 100 % the page at 96 pixels an inch, its text for spark; full=1 draws it at 4096 for a zoom (#120)" || bad "preview pdf" "$(page 7) | $(page 8) | $(cat "$F2/pdftoppm.log" 2>&1)"
page 9 | jq -e '.lines == ["Evening", "Ada \u00b7 Proofs"] and .seconds == 20.5 and .facts[0:4] == ["44.1 kHz", "16 bit", "stereo", "FLAC"] and .sound.wave == 160 and (.sound.picture | endswith("-sound.png")) and .play.name == "files_play" and .stop.name == "files_stop"' >/dev/null \
    && grep -q -- '--untimed' "$F2/mpv.log" && grep -q -- 'showwavespic' "$F2/mpv.log" && grep -q -- '--demuxer-lavf-o=protocol_whitelist=file' "$F2/mpv.log" \
    && ok "provide files: a sound's tags, its waveform over its spectrogram drawn once, what an engineer asks first (rate, bits, channels, format); mpv on local files only (#120)" || bad "preview sound" "$(page 9) | $(cat "$F2/mpv.log" 2>&1)"
page 10 | jq -e '.facts[0:2] == ["0:05", "1280 \u00d7 720"] and .size == [1280, 720] and .play.name == "files_open" and (.picture | endswith(".png"))' >/dev/null \
    && ok "provide files: a video's frame, its length and size; right plays it in its app (#120)" || bad "preview video" "$(page 10)"
_vf() { grep -F -- "--vo-image-outdir" "$F2/mpv.log" | grep -F -- "$1" | grep -o -- '--vf=[^ ]*' || :; }   # _vf FILE -> the scale its frame was drawn with
page 14 | jq -e '.facts[1] == "1080 \u00d7 1920" and .size == [1080, 1920]' >/dev/null && page 15 | jq -e '.size == [1080, 1920]' >/dev/null \
    && [ "$(_vf phone.mov)" = '--vf=scale=w=1600:h=-2' ] && [ "$(_vf tall.mp4)" = '--vf=scale=w=-2:h=1600' ] && [ -z "$(_vf clip.webm)" ] \
    && ok "provide files: a phone's clip shows its size as it plays; a frame fits its long side in plain numbers, mpv's own syntax, and one smaller is drawn as it is (#120)" \
    || bad "preview video turned" "$(page 14) | $(page 15) | $(grep -F -- --vo-image-outdir "$F2/mpv.log" 2>&1)"
page 16 | jq -e '.facts[0:4] == ["96 kHz", "24 bit", "stereo", "PCM"] and .sound != null' >/dev/null && page 17 | jq -e '.facts[0:2] == ["48 kHz", "24 bit"] and .sound != null' >/dev/null \
    && ok "provide files: a 24-bit WAV and an AIFF say 24 bit, read from their headers (mpv decodes them to 32); an AIFF is a sound (#120)" || bad "preview bits" "$(page 16) | $(page 17)"
page 18 | jq -e '.say == "cannot view: this PDF is locked by a password, Enter opens it"' >/dev/null && page 19 | jq -e '.size == [20, 40] and .facts[0] == "20 \u00d7 40"' >/dev/null \
    && page 20 | jq -e '.say == "cannot view: nothing here draws this picture, Enter opens it"' >/dev/null && page 21 | jq -e '.size == [5400, 2700] and (.picture | endswith(".png"))' >/dev/null \
    && ok "provide files: a locked PDF says so; a photo turned by its orientation keeps its size the drawn way round; bytes no tool reads draw no empty square; a TIFF is a picture, its size read by mpv (#120)" \
    || bad "preview trial cases" "$(page 18) | $(page 19) | $(page 20) | $(page 21)"
[ "$(ans 11 | jq -r '.error.message')" = 'no file at that uri' ] && [ "$(ans 12 | jq -r '.error.message')" = 'no file at that uri' ] && ans 13 | jq -e '[.result.resourceTemplates[].name] == ["folder", "match", "preview"]' >/dev/null \
    && ok "provide files: a hidden file and a path outside the roots have no page; the template names it (#120)" || bad "preview gate" "$(ans 11) $(ans 12) $(ans 13)"
mkdir -p "$F2/docs-169/reports"; : > "$F2/docs-169/final-report.pdf"; : > "$F2/docs-169/reports/firmware.bin"; : > "$F2/docs-169/field-notes.md"; rm -rf "$F2/.cache/spark-shell"
mcp2 "$(rq 21 resources/read "{\"uri\":\"spark-shell://files/rows/match/$(b64u firmwre)\"}")" "$(rq 22 resources/read "{\"uri\":\"spark-shell://files/rows/match/$(b64u 'feild notes')\"}")" "$(rq 23 resources/read "{\"uri\":\"spark-shell://files/rows/match/$(b64u report)\"}")" "$(rq 24 resources/read "{\"uri\":\"spark-shell://files/preview/$(b64u "$(realpath "$F2/docs-169")")\"}")"
ans 21 | jq -r '.result.contents[0].text' | jq -e '[.rows[] | select(.kind != null) | .text] == ["firmware.bin"] and (.rows[0].page | startswith("spark-shell://files/preview/"))' >/dev/null \
    && ans 22 | jq -r '.result.contents[0].text' | jq -e '[.rows[] | select(.kind != null) | .text] == ["field-notes.md"]' >/dev/null \
    && ans 23 | jq -r '.result.contents[0].text' | jq -e '[.rows[] | select(.kind != null) | .text] | .[0] == "reports" and index("final-report.pdf") != null' >/dev/null \
    && ans 24 | jq -r '.result.contents[0].text' | jq -e '.lines[0:2] == ["docs-169", "1 folder, 2 files"] and .lines[3] == "newest" and .facts == ["~/docs-169"]' >/dev/null \
    && [ "$(ls -l "$F2/.cache/spark-shell/files.names" | cut -c1-10)" = '-rw-------' ] && [ "$(ls -ld "$F2/.cache/spark-shell" | cut -c1-10)" = drwx------ ] \
    && ok "provide files: a search from Home finds the names under your home that hold the words, a letter missing or two swapped too, from a list in your cache yours alone; a folder has a page, what it holds and its newest (#169)" || bad "files match" "$(jq -c 'select(.id > 20) | .result.contents[0].text | fromjson? | [.rows[]? | .text, .lines?]' "$H/mcp.out")"
rm -f "$F2/mpv.log"
mcpv "$(call 2 files_play "$(jq -cn --arg p "$PVR/song.flac" '{path: $p, at: 12.5}')")" "$(call 3 files_stop)" "$(fc2 4 files_play "$PVR/plan.md")" "$(call 5 files_play "$(jq -cn --arg p "$PVR/song.flac" '{path: $p, at: -1}')")"
[ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'playing song.flac' ] && grep -q -- '--no-video --no-terminal --really-quiet --start=+12.5 -- ' "$F2/mpv.log" && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = stopped ] \
    && [ "$(ans 4 | jq -r '.result.content[0].text')" = 'files: plan.md is no sound mpv plays here' ] && [ "$(ans 5 | jq -r '.error.message')" = 'files_play: at is a number of seconds, 0 to 86400' ] \
    && ! ps -A -o args= 2>/dev/null | grep -q '^sleep 41$' \
    && ok "provide files: a sound plays here from a point and stops; anything else, or a point that is no time, is refused; nothing plays on past the provider (#120)" || bad "preview play" "$(ans 2) $(ans 3) $(ans 4) $(ans 5) $(cat "$F2/mpv.log" 2>&1)"
# #124: a long sound's page answers at once, its waveform drawn aside (the stand-in takes 8 s over it; the page is in well before, a slow runner's start included), the picture named for the dialog to read when it comes
_t0=$(date +%s); ( SLOW_WAVE=1 mcpv "$(pvr 2 "$PVR/song.flac")" ); _t1=$(date +%s)
page 2 | jq -e '(.sound.picture | endswith("-sound.png")) and .sound.wave == 160 and .play.name == "files_play" and .seconds == 20.5' >/dev/null && [ $((_t1 - _t0)) -le 5 ] \
    && ok "provide files: a long sound's page comes at once with its facts and Play, its waveform drawn aside at an idle priority and named for the dialog to draw when it is there (#124)" || bad "preview sound aside" "$((_t1 - _t0)) s $(page 2)"
# a picture stopped before it is drawn takes its folder with it: mpv's folder stayed in the temp folder, the picture in it, each time
_st=$(tmpd); rm -rf "$F2/.cache/spark-shell"; ( TMPDIR=$_st SLOW_WAVE=1 mcpv "$(pvr 2 "$PVR/song.flac")" )
_i=0; while [ "$_i" -lt 30 ] && [ -n "$(ls -A "$_st")" ]; do sleep 0.1; _i=$((_i + 1)); done
[ -z "$(ls -A "$_st")" ] && ok "provide files: a sound's picture stopped midway leaves no folder behind" || bad "sound folder" "$(ls -A "$_st") $(page 2 | head -c 200)"
# #125: where sway is, a video plays over its frame: the page offers play and stop; the player laid at the dialog's corner, foot's padding and the frame's box
mkdir -p "$H/pvsw" "$F2/.config/foot"; printf '[main]\npad=24x19\n' > "$F2/.config/foot/dialog.ini"
cat > "$H/pvsw/swaymsg" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/swaymsg.log"
case "$*" in
    "-t get_version") echo '{"human_readable":"sway-stub"}' ;;
    "-t get_outputs") echo '[{"name":"HDMI-A-1","scale":1,"rect":{"x":0,"y":0,"width":1920,"height":1080}}]' ;;
    "-t get_tree") printf '{"nodes":[{"type":"output","name":"HDMI-A-1","nodes":[{"app_id":"spark-dialog","id":42,"focused":true,"fullscreen_mode":%s,"rect":{"x":100,"y":50},"window_rect":{"x":0,"y":0},"geometry":{"width":600,"height":800}},{"app_id":"spark-preview"}]}]}\n' "${FULL:-0}" ;;
esac
STUB
chmod +x "$H/pvsw/swaymsg"
mcpw() { printf '%s\n' "$rinit" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$roots2" "$@" | REPO_PNG=$REPO/asset/favicon-26.png PATH="$H/pvsw:$H/pvb:$_fpath" SWAYSOCK=$H/sock HOME=$F2 XDG_DATA_HOME=$F2/.local/share SPARK_SHELL_NO_UDISKS=1 SPARK_SHELL_NO_GIO=1 sh "$SH" provide files > "$H/mcp.out" 2> "$H/mcp.err"; }   # mcpv with a stand-in sway
rm -f "$F2/swaymsg.log" "$F2/mpv.log"
mcpw "$(pvr 2 "$PVR/clip.webm")" "$(call 3 files_play "$(jq -cn --arg p "$PVR/clip.webm" '{path: $p, at: 1.5, x: 20, y: 200, w: 640, h: 360}')")" "$(call 4 files_play "$(jq -cn --arg p "$PVR/clip.webm" '{path: $p}')")"
_p2=$(page 2); _a3=$(ans 3); _a4=$(ans 4)
# a full screen play's way back runs after its step has answered (#172): its last word is the bar, then the next test may start
full_back() { _fb=0; while [ "$_fb" -lt 50 ] && ! tail -n 1 "$F2/swaymsg.log" 2>/dev/null | grep -q '^bar mode '; do sleep 0.1; _fb=$((_fb + 1)); done; }
( FULL=1 mcpw "$(call 5 files_play "$(jq -cn --arg p "$PVR/clip.webm" '{path: $p, x: 20, y: 200, w: 640, h: 360}')")" ); full_back
printf '%s' "$_p2" | jq -e '.play.name == "files_play" and .stop.name == "files_stop" and .seconds == 4.5' >/dev/null \
    && [ "$(printf '%s' "$_a3" | jq -r '.result.structuredContent.receipt')" = 'playing clip.webm' ] \
    && grep -qF -- '--wayland-app-id=spark-preview --no-border --osc=no' "$F2/mpv.log" && grep -qF -- '--geometry=640x360 --start=+1.5 -- ' "$F2/mpv.log" \
    && grep -qxF '[app_id="spark-preview"] floating enable, border none, resize set 640 360, move absolute position 144 269, opacity 1' "$F2/swaymsg.log" \
    && [ "$(printf '%s' "$_a4" | jq -r '.result.content[0].text')" = 'files: a video plays over its view: the dialog gives the box' ] \
    && ok "provide files: a video plays over its frame where sway is: mpv with no border laid at the window's corner, foot's padding and the frame's box, shown in the same command that places it (#157); no box says why (#125)" \
    || bad "preview video over" "$_p2 | $_a3 | $_a4 | $(cat "$F2/swaymsg.log" 2>&1) | $(grep spark-preview "$F2/mpv.log" 2>&1)"
# #158: full screen, the dialog trades sway's full screen for a floating window on the same pixels while the video plays,
# the bar out of sight, in one command; when the play ends it takes full screen back at its own size first, in one command
rm -f "$F2/swaymsg.log"
( FULL=1 mcpw "$(call 5 files_play "$(jq -cn --arg p "$PVR/clip.webm" '{path: $p, x: 20, y: 200, w: 640, h: 360}')")" ); full_back
[ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'playing clip.webm' ] \
    && [ "$(grep -n -e '^bar mode invisible$' -e 'fullscreen disable' "$F2/swaymsg.log" | cut -d: -f2- | head -2 | paste -sd '|' -)" = 'bar mode invisible|[con_id=42] fullscreen disable, resize set 1920 1080, move absolute position 0 0' ] \
    && [ "$(grep -n -e 'fullscreen enable' -e '^bar mode' "$F2/swaymsg.log" | cut -d: -f2- | tail -2 | paste -sd '|' -)" = '[con_id=42] resize set 600 800, move position center, fullscreen enable|bar mode dock' ] \
    && [ "$(grep -n 'fullscreen disable' "$F2/swaymsg.log" | cut -d: -f1)" -lt "$(grep -n 'spark-preview' "$F2/swaymsg.log" | tail -1 | cut -d: -f1)" ] \
    && ok "provide files: full screen, a video plays in its frame too: the dialog floats on the same pixels for the play and is full screen again at its own size after (#158)" \
    || bad "preview video full screen" "$(ans 5) | $(cat "$F2/swaymsg.log" 2>&1)"
# #172: a full screen play's way back is a job of its own: a video that plays on never holds the step's answer, bash or dash
rm -f "$F2/swaymsg.log"; _t0=$(date +%s)
( FULL=1 VIDEO_PLAYS=6 mcpw "$(call 5 files_play "$(jq -cn --arg p "$PVR/clip.webm" '{path: $p, x: 20, y: 200, w: 640, h: 360}')")" ); _t1=$(date +%s); full_back
[ $((_t1 - _t0)) -le 4 ] && [ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'playing clip.webm' ] \
    && ok "provide files: full screen, the step answers at once while the video plays on, and the provider ends: nothing waits for the play (#172)" \
    || bad "preview video full screen held" "$((_t1 - _t0)) s $(ans 5)"
grep -qxF 'no_focus [app_id="spark-preview"]' "$REPO/template/.config/sway/config" && grep -qxF 'for_window [app_id="spark-preview"] floating enable, border none, opacity 0' "$REPO/template/.config/sway/config" \
    && ok "sway template: a video a preview plays floats with no border, maps unseen until it is placed (#157) and never takes the focus: the keys stay in the dialog (#125)" || bad "sway preview rules" "$(grep spark-preview "$REPO/template/.config/sway/config")"
# the dialog's transitions (#122): the theme's row, the verb, the key the config holds
printf 'DESKTOP=sway\nTHEME=dracula\n' > "$HOME/.config/spark-shell/config"
o1=$(sh "$SH" theme animation 2>&1); o2=$(sh "$SH" theme animation next 2>&1); o3=$(sh "$SH" theme animation back 2>&1); o4=$(sh "$SH" theme animation none 2>&1); st=0; o5=$(sh "$SH" theme animation fireworks 2>&1) || st=$?
[ "$o1" = "animation embers $(printf '\302\267') none, moon, ripple, tide, embers, sun, flight" ] && [ "${o2%% *}" = animation ] && printf '%s' "$o2" | grep -q '^animation sun ' && printf '%s' "$o3" | grep -q '^animation embers ' \
    && printf '%s' "$o4" | grep -q '^animation none ' && grep -qx 'DIALOG_ANIMATION=none' "$HOME/.config/spark-shell/config" && [ "$st" -ne 0 ] \
    && ok "theme animation: the palette's piece when none is set (dracula's embers), next and back step through the six and none, none is no motion, another word refused (#122)" || bad "theme animation" "$o1 | $o2 | $o3 | $o4 | $st $o5"
# each palette brings its piece, as it brings its drawing; none stays none (#122)
printf 'DESKTOP=sway\nTHEME=dracula\n' > "$HOME/.config/spark-shell/config"
sh "$SH" theme nord >/dev/null 2>&1; a1=$(sed -n 's/^DIALOG_ANIMATION=//p' "$HOME/.config/spark-shell/config"); sh "$SH" theme animation none >/dev/null 2>&1; sh "$SH" theme gruvbox-dark >/dev/null 2>&1; a2=$(sed -n 's/^DIALOG_ANIMATION=//p' "$HOME/.config/spark-shell/config")
for e in $(sed -n 's/^ANIM_PAIRED="\(.*\)"$/\1/p' "$SRC"); do [ -d "$REPO/gallery/animation/${e#*:}/${e%%:*}" ] || a3="${a3:-}${e} "; done
[ "$a1" = tide ] && [ "$a2" = none ] && [ -z "${a3:-}" ] && [ "$(sed -n 's/^ANIM_PAIRED="\(.*\)"$/\1/p' "$SRC" | wc -w | tr -d ' ')" = 16 ] \
    && ok "theme: a palette brings its piece (nord the tide), none stays none, every one of the 16 palettes paired with a piece it has (#122)" || bad "animation pairs" "$a1 $a2 missing: ${a3:-}"
printf 'DIALOG_ANIMATION=fireworks\n' >> "$HOME/.config/spark-shell/config"; st=0; o=$(sh "$SH" theme animation 2>&1) || st=$?
[ "$st" -ne 0 ] && printf '%s' "$o" | grep -q 'DIALOG_ANIMATION=fireworks' && ok "config: DIALOG_ANIMATION holds to none and the six (#122)" || bad "animation config" "$st $o"
printf 'DESKTOP=sway\nTHEME=tokyonight-night\n' > "$HOME/.config/spark-shell/config"
_np=0; for _pd in "$REPO"/gallery/animation/*/; do [ -f "$_pd/tokyonight-night/open.gif" ] && [ -f "$_pd/solarized-light/close.gif" ] && _np=$((_np + 1)); done
[ -f "$REPO/gallery/animation/moon/tokyonight-night/open.gif" ] && grep -q -- '--transitions "$_ta"' "$SRC" && [ "$_np" = 6 ] \
    && ok "the dialog is given the piece in the palette in use, every piece in every palette: open, wait, close, at one and two times (#122)" || bad "transitions given" "$(ls "$REPO/gallery/animation")"
# #142: in the dialog's own window nothing is drawn ahead of the opening (#138 drew the prompt first, and the dialog then
# came in parts): the cursor hidden, then the dialog; elsewhere (a terminal) the same
if command -v python3 >/dev/null 2>&1; then
    cat > "$H/pty_first.py" <<'PY'
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp("sh", ["sh", sys.argv[1], "dialog"])
out = b""
while True:
    try:
        b = os.read(fd, 4096)
    except OSError:
        break
    if not b:
        break
    out += b
os.waitpid(pid, 0)
sys.stdout.write(repr(out[:160]))
PY
    _f1=$(SPARK_DIALOG_WINDOW=1 python3 -I "$H/pty_first.py" "$SH" 2>/dev/null); _f2=$(python3 -I "$H/pty_first.py" "$SH" 2>/dev/null)
    case $_f1 in b?"\\x1b[?25l"*) _fo=1 ;; *) _fo='' ;; esac
    [ -n "$_fo" ] && case $_f1$_f2 in *'Type a request.'*) false ;; *) true ;; esac \
        && ok "dialog: in its own window and in a terminal nothing is drawn ahead of the opening, the cursor hidden first (#142)" || bad "dialog first frame" "$_f1 | $_f2"
fi
# #132: the theme's animation row opens a list of the pieces, as the wallpaper's opens its drawings: the one in use checked,
# the palette's own said, each with its folder in the palette in use (none with none), Enter the step that sets it
mcp theme "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}')" "$(rq 2 resources/read '{"uri":"spark-shell://theme/rows/animations"}')"
ans 2 | jq -r '.result.contents[0].text' > "$H/anims.json"
[ "$(jq -r '[.rows[] | .text + ":" + .sign + ":" + (.columns | join(","))] | join("|")' "$H/anims.json")" = "moon:check:the palette's own|ripple:blank:|tide:blank:|embers:blank:|sun:blank:|flight:blank:|none:blank:no motion" ] \
    && jq -e --arg d "$REPO/gallery/animation" '(.rows[0].film == ($d + "/moon/tokyonight-night")) and (.rows[-1] | has("film") | not) and all(.rows[]; .tool.name == "theme_animation" and .tool.arguments.to == .text and .quiet == true)' "$H/anims.json" >/dev/null \
    && ok "provide theme: the animation list: the six and none, the one in use checked, the palette's own said, each piece's folder in the palette in use, Enter sets it in place (#132, #191)" || bad "animation list" "$(cat "$H/anims.json")"
# #247: a palette with no set drawn ahead (a palette of yours, a theme from a picture or words) plays every piece too, the
# dialog drawing it in the palette's colors: the verb, the list and the row as for a shipped palette, no piece its own, and
# the step names draw:PIECE where a shipped palette names a folder (#193's lock is gone)
cp "$HOME/.config/spark-shell/config" "$H/config.anim"; palette_fixture mine '#fe8019'
printf 'DESKTOP=sway\nTHEME=mine\nDIALOG_ANIMATION=ripple\n' > "$HOME/.config/spark-shell/config"
o1=$(sh "$SH" theme animation 2>&1)
mcp theme "$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}')" "$(call 2 theme_animation '{"to":"moon"}')" "$(rq 3 resources/read '{"uri":"spark-shell://theme/rows/animations"}')" "$(rq 4 resources/read '{"uri":"spark-shell://theme/rows"}')"
ans 3 | jq -r '.result.contents[0].text' > "$H/anims.json"; ans 4 | jq -r '.result.contents[0].text' > "$H/trows.json"
a1=$(sed -n 's/^DIALOG_ANIMATION=//p' "$HOME/.config/spark-shell/config")
[ "$o1" = "animation ripple $(printf '\302\267') none, moon, ripple, tide, embers, sun, flight" ] && [ "$a1" = moon ] \
    && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = "animation moon $(printf '\302\267') from the dialog's next opening" ] \
    && [ "$(ans 2 | jq -r '.result.structuredContent.transitions')" = 'draw:moon' ] \
    && [ "$(jq -r '[.rows[] | .text + ":" + .sign + ":" + (.columns | join(","))] | join("|")' "$H/anims.json")" = "moon:check:|ripple:blank:|tide:blank:|embers:blank:|sun:blank:|flight:blank:|none:blank:no motion" ] \
    && jq -e 'all(.rows[]; has("film") | not)' "$H/anims.json" >/dev/null \
    && { [ "$(uname -s)" = Darwin ] || jq -e '.rows[] | select(.id == "theme:show:Animation") | .columns == ["moon"] and .children == "spark-shell://theme/rows/animations" and .tool == null' "$H/trows.json" >/dev/null; } \
    && ok "theme animation, a palette with no pieces drawn ahead (#247): every piece in its list, the one set kept and played, none its own; the step names draw:moon for the dialog to draw" \
    || bad "animation any palette" "$o1 | $a1 | $(ans 2 | jq -c .result.structuredContent 2>&1) | $(cat "$H/anims.json") $(jq -c '.rows[] | select(.id == "theme:show:Animation")' "$H/trows.json" 2>&1)"
printf 'DESKTOP=sway\nTHEME=mine\nDIALOG_ANIMATION=ripple\n' > "$HOME/.config/spark-shell/config"; sh "$SH" theme nord >/dev/null 2>&1
[ "$(sh "$SH" theme animation 2>&1 | cut -d' ' -f1-2)" = 'animation tide' ] && ok "theme animation: a shipped palette after a palette of yours brings its own piece" || bad "animation back" "$(sh "$SH" theme animation 2>&1)"
cp "$H/config.anim" "$HOME/.config/spark-shell/config"; rm -f "$HOME/.config/spark-shell/themes/mine.env"
mkdir -p "$H/gio"; cat > "$H/gio/gio" <<'STUB'
#!/bin/sh
echo "gio $*" >> "$HOME/gio.log"
[ "$1" = trash ] || exit 1; p=$3; t=${XDG_DATA_HOME:-$HOME/.local/share}/Trash; mkdir -p "$t/files" "$t/info"
printf '[Trash Info]\nPath=%s\nDeletionDate=2026-01-01T00:00:00\n' "$p" > "$t/info/${p##*/}.trashinfo" && mv "$p" "$t/files/${p##*/}"
STUB
chmod +x "$H/gio/gio"; rm -f "$F2/gio.log"
( NO_GIO='' PATH="$H/gio:$PATH" mcp2 "$(fc2 2 files_trash "$F2R/docs/todo.txt")" "$(fc2 3 files_restore "$F2R/docs/todo.txt")" )
[ "$(cat "$F2/gio.log" 2>/dev/null)" = "gio trash -- $F2R/docs/todo.txt" ] && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'todo.txt is in the trash' ] && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = 'todo.txt is back' ] && [ -f "$F2/docs/todo.txt" ] \
    && ok "provide files: where gio is, it trashes (the system's own trash view agrees), and restore reads the spec's record it wrote" || bad "files gio" "$(cat "$F2/gio.log" 2>&1) $(ans 2) $(ans 3)"
# the dialog's keys
for kv in DIALOG_ATTACH=maybe DIALOG_MODEL=1 DIALOG_TALK=off 'DIALOG_ATTACH_TYPES=.exe' 'DIALOG_ATTACH_TYPES=TXT'; do
    printf 'DESKTOP=sway\n%s\n' "$kv" > "$HOME/.config/spark-shell/config"; st=0; out=$(sh "$SH" status 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q "^spark-shell: ${kv%%=*}=" || bad "key $kv refused" "st=$st $out"
done
ok "config: DIALOG_ATTACH, DIALOG_MODEL and DIALOG_TALK take yes or no, DIALOG_ATTACH_TYPES lower-case types; anything else is refused in one line"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
grep -q "^CONFIG_UNSET=.* -u DIALOG_ATTACH -u DIALOG_ATTACH_TYPES -u DIALOG_MODEL -u DIALOG_TALK -u DIALOG_ANIMATION -u DIALOG_ICONS -u DIALOG_SPACING -u BAR_GLYPHS -u BAR_WORKSPACES -u GLYPH_FAMILY -u WALLPAPER_MOTION -u DISPLAY_IDLE -u DISPLAY_LOCK -u DISPLAY_SAVER -u KEYBOARD -u DO_NOT_DISTURB -u CLOCK_FORMAT -u WEEK_START -u WINPAD_PLACE -u WINPAD_WIDTH -u WINPAD_SIDE_WIDTH -u WINPAD_BAND -u WINPAD_VIEW -u WINPAD_HEIGHT -u VOICE -u VOICE_ENGINE'" "$SRC" && grep -q '^WINPAD_PLACE=bottom center$' "$REPO/config.example" && grep -q '^WINPAD_WIDTH=0$' "$REPO/config.example" && grep -q '^WINPAD_SIDE_WIDTH=36$' "$REPO/config.example" && grep -q '^WINPAD_BAND=off$' "$REPO/config.example" && grep -q '^WINPAD_VIEW=icons$' "$REPO/config.example" && grep -q '^WINPAD_HEIGHT=0$' "$REPO/config.example" && grep -q '^DIALOG_ATTACH=yes$' "$REPO/config.example" && grep -q '^DIALOG_ATTACH_TYPES=txt md$' "$REPO/config.example" && grep -q '^DIALOG_MODEL=yes$' "$REPO/config.example" && grep -q '^DIALOG_TALK=yes$' "$REPO/config.example" && grep -q '^DIALOG_ANIMATION=$' "$REPO/config.example" && grep -q '^DIALOG_ICONS=on$' "$REPO/config.example" && grep -q '^DIALOG_SPACING=groups$' "$REPO/config.example" && grep -q '^BAR_GLYPHS=signs$' "$REPO/config.example" && grep -q '^GLYPH_FAMILY=stone$' "$REPO/config.example" && ! grep -q '^BAR_WORKSPACES=' "$REPO/config.example" && grep -q '^WALLPAPER_MOTION=off$' "$REPO/config.example" \
    && ok "config: the dialog's keys, the bar's set (#160) and the glyph family (#248) are unset for what spark-shell starts, and config.example shows their defaults, BAR_WORKSPACES no more" || bad "dialog keys" "$(grep -n DIALOG "$REPO/config.example")"
# the local gate (#155): every python3 test ci.yml runs is in the gate's list, read from ci.yml itself, with the lint and the
# dialog's checks; the pre-push hook runs its quick part
_gl=$(sh "$REPO/test/gate.sh" --list 2>/dev/null || :)
_ci=$(grep -oE 'python3( -I)? test/[A-Za-z0-9_]+\.py' "$REPO/.github/workflows/ci.yml" | awk '!seen[$0]++')
_gm=$(printf '%s\n' "$_ci" | while IFS= read -r _l; do printf '%s\n' "$_gl" | grep -qxF "$_l" || echo "$_l"; done)
[ -n "$_ci" ] && [ -z "$_gm" ] && printf '%s\n' "$_gl" | grep -qx 'cargo fmt --check' && printf '%s\n' "$_gl" | grep -qx 'shellcheck' && grep -qx 'exec sh test/gate.sh --quick' "$REPO/.githooks/pre-push" \
    && ok "test/gate.sh (#155): every python3 test of ci.yml in its list, the lint and the dialog's checks too; the pre-push hook runs its quick part" || bad "gate list" "missing: $_gm; $_gl"
# the want verb: one entry for words, the plan as JSON, a file asked about
cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"
case "$*" in
    *--source*) echo 'the notes say to buy bread.' ;;
    *) printf '{"why": "a palette", "steps": [{"page": "theme", "action": "nord"}, {"page": "theme", "action": "rainbow"}, {"page": "out", "action": "level", "arg": "30"}]}\n' ;;
esac
STUB
chmod +x "$H/.local/bin/spark"
st=0; out=$(sh "$SH" want --json the nord palette and quieter 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e --arg c "$(printf '\342\234\227')" '.answer == "" and .steps[0] == {name: "theme_palette", arguments: {name: "nord"}, line: "theme nord"} and .refused[0] == ($c + " rainbow is not in the list now")' >/dev/null \
    && ! grep -q '^THEME=nord' "$HOME/.config/spark-shell/config" && grep -q '^do this on the desktop: the nord palette and quieter$' "$HOME/spark.argv" \
    && ok "want --json: the steps spark picked, each gated and named as a tool with its arguments and its line, the refused ones as lines; nothing run" || bad "want json" "st=$st $out"
if [ "$(uname -s)" != Darwin ]; then
    printf '%s' "$out" | jq -e '.steps[1] == {name: "out_level", arguments: {level: 30}, line: "out level 30"}' >/dev/null && ok "want --json: a level is a number in the arguments, as the tool's schema says" || bad "want json level" "$out"
fi
st=0; out=$(sh "$SH" want the nord palette 2>&1) || st=$?
[ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "^$(printf '\342\234\223') nord is on$" && grep -q '^THEME=nord$' "$HOME/.config/spark-shell/config" \
    && ok "want WORDS: the same steps run, one line each with its sign and a reply, never the command again (#53)" || bad "want run" "st=$st $out"
# spark 1.90's planner (issue 7): the desktop's tools on stdin, the names each tool takes now as the about; each step mapped back and gated here
cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
case $1 in
    help) echo ' spark steps <words> < TOOLS  the tool calls that do what you say (-h)' ;;
    steps) printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"
        case "$*" in
            *'what time'*) printf '{"answer": "It is noon.", "steps": [], "refused": []}\n' ;;
            *zebra*|*sandwich*) printf '{"answer": "", "steps": [], "refused": []}\n' ;;
            *'hush the room'*) printf '{"answer": "", "steps": [{"name": "out_mute", "arguments": {}}], "refused": []}\n' ;;
            *'dim the room'*) printf '{"answer": "", "steps": [{"name": "display_brightness", "arguments": {"level": "down"}}, {"name": "display_brightness", "arguments": {"level": "30"}}], "refused": []}\n' ;;
            *) printf '{"answer": "", "steps": [{"name": "theme_palette", "arguments": {"name": "dracula"}}, {"name": "out_level", "arguments": {"level": 30}}, {"name": "theme_palette", "arguments": {"name": "rainbow"}}, {"name": "rm_rf", "arguments": {}}], "refused": ["out_use: no argument loud"]}\n' ;;
        esac ;;
    *) printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"; case "$*" in *--source*) echo 'the notes say to buy bread.' ;; *) echo '{"steps": []}' ;; esac ;;
esac
STUB
chmod +x "$H/.local/bin/spark"
st=0; out=$(sh "$SH" want --json the nord palette and quieter 2>&1) || st=$?
x=$(printf '\342\234\227')
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e --arg x "$x" '.steps[0] == {name: "theme_palette", arguments: {name: "dracula"}, line: "theme dracula"} and (.refused | index($x + " out_use: no argument loud") != null and index($x + " rainbow is not in the list now") != null and index($x + " spark planned a step this desktop does not have") != null)' >/dev/null \
    && [ "$(sed -n 1p "$HOME/spark.argv")" = steps ] && [ "$(sed -n 2p "$HOME/spark.argv")" = --about ] && sed -n 3p "$HOME/spark.argv" | grep -q 'The names each tool takes now -- .*out_use: HDMI.*whole and exactly as written here' && ! sed -n 3p "$HOME/spark.argv" | grep -q 'theme_palette:' && [ "$(sed -n '4,5p' "$HOME/spark.argv" | paste -sd ' ' -)" = '-- the nord palette and quieter' ] \
    && jq -e '[.tools[].name] as $n | ($n | index("theme_palette") != null and index("undo_all") != null and index("about_open") != null and index("files_open") == null and index("reminders_add") != null and index("notes_add") != null) and (.tools[0].inputSchema.type == "object")' "$HOME/spark.stdin" >/dev/null \
    && ok "want with spark steps: the tools on stdin (notes and reminders among them, the about and undo, never the files'), the names each tool takes now as the about; each step mapped back and gated, spark's refusals and the gate's as lines" || bad "want steps" "st=$st $out $(cat "$HOME/spark.argv")"
if [ "$(uname -s)" != Darwin ]; then
    printf '%s' "$out" | jq -e '.steps[1] == {name: "out_level", arguments: {level: 30}, line: "out level 30"}' >/dev/null && ok "want with spark steps: a level comes back a number" || bad "want steps level" "$out"
    st=0; out=$(sh "$SH" want --json hush the room 2>&1) || st=$?
    sh "$SH" bar panel out use HDMI >/dev/null; st2=0; out2=$(sh "$SH" want --json hush the room 2>&1) || st2=$?
    sh "$SH" bar panel out use Jabra >/dev/null; rm -f "$HOME/.config/alsa/asoundrc"
    [ "$st" -eq 0 ] && printf '%s' "$out" | jq -e '.steps == [{name: "out_mute", arguments: {}, line: "out mute"}] and .refused == []' >/dev/null \
        && [ "$st2" -eq 0 ] && printf '%s' "$out2" | jq -e --arg x "$x" '.steps == [] and .refused == [$x + " out: HDMI has no volume control here, so it cannot be muted or set"]' >/dev/null \
        && ok "want with spark steps: out_mute is planned where the output has a volume, and said why where it has none (#31)" || bad "want mute" "st=$st $out | st2=$st2 $out2"
    st=0; out=$(sh "$SH" want --json dim the room 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s' "$out" | jq -e '.steps == [{name: "display_brightness", arguments: {level: "down"}, line: "display brightness down"}, {name: "display_brightness", arguments: {level: "30"}, line: "display brightness 30"}] and .refused == []' >/dev/null \
        && ok "want with spark steps: the brightness planned as the step word down, and a number as the text its schema publishes, for a host that holds a call to the schema (#31)" || bad "want brightness" "st=$st $out"
fi
st=0; out=$(sh "$SH" want --json what time is it 2>&1) || st=$?; st2=0; out2=$(sh "$SH" want --json zebra stripes 2>&1) || st2=$?; st3=0; out3=$(sh "$SH" want --json make me a sandwich please 2>&1) || st3=$?
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e '.answer == "It is noon." and .steps == []' >/dev/null && [ "$st2" -eq 0 ] && printf '%s' "$out2" | jq -e --arg x "$x" '.steps == [] and .refused == [$x + " no step on the panel does that"]' >/dev/null \
    && [ "$st3" -eq 0 ] && printf '%s' "$out3" | jq -e --arg x "$x" '.steps == [] and .refused == [$x + " no step on the panel does that"]' >/dev/null \
    && ok "want with spark steps: a question gets its answer; words with no step, however many, the honest line and never a layout of ours (spark picks layout_new itself)" || bad "want steps nostep" "$out | $out2 | $out3"
st=0; out=$(sh "$SH" want --json is dracula on? 2>&1) || st=$?; st2=0; out2=$(sh "$SH" want is dracula on? 2>&1) || st2=$?
[ "$st" -eq 0 ] && printf '%s' "$out" | jq -e '.question == true and .steps[0].name == "theme_palette"' >/dev/null && [ "$st2" -eq 0 ] && printf '%s\n' "$out2" | grep -qx "$(printf '\342\226\270') proposed, not run: theme dracula" \
    && ! grep -q '^THEME=dracula' "$HOME/.config/spark-shell/config" && sh "$SH" want --json make it dracula 2>&1 | jq -e '.question == false' >/dev/null \
    && ok "want: a question changes nothing; its steps are proposals (question: true for the dialog), shown and not run at the terminal" || bad "want question" "$out | $out2"
cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
case $1 in
    help) echo ' spark steps <words> < TOOLS  the tool calls that do what you say (-h)' ;;
    steps) cat > /dev/null; printf '{"answer": "", "steps": [{"name": "theme_delete", "arguments": {"name": "work"}}, {"name": "theme_palette", "arguments": {"name": "dracula"}}], "refused": []}\n' ;;
    *) printf '%s\n' "$@" > "$HOME/spark.argv"; cat > "$HOME/spark.stdin"; case "$*" in *--source*) echo 'the notes say to buy bread.' ;; *) echo '{"steps": []}' ;; esac ;;
esac
STUB
chmod +x "$H/.local/bin/spark"
sh "$SH" theme save work >/dev/null 2>&1; sh "$SH" theme nord >/dev/null 2>&1
st=0; out=$(echo no | SPARK_SHELL_TEST_TTY=1 sh "$SH" want drop work and go dracula 2>&1) || st=$?; st2=0; out2=$(sh "$SH" want drop work and go dracula </dev/null 2>&1) || st2=$?
x=$(printf '\342\234\227')
printf '%s\n' "$out" | grep -q "type yes to theme delete work: $x theme delete work: kept, not done (it takes a typed yes)" && printf '%s\n' "$out" | grep -qx "$x not run, for the step before was not done: theme dracula" \
    && printf '%s\n' "$out2" | grep -qx "$x theme delete work: kept, not done (it takes a typed yes)" && ! grep -q '^THEME=dracula' "$HOME/.config/spark-shell/config" \
    && ok "want at the terminal: a risky step (its destructive hint, or this machine's list) asks for yes, and with no terminal is kept; the steps after it are not run" || bad "want risky" "$out | $out2"
rm -f "$HOME/.config/spark-shell/layouts/work"
grep -q '^LOCAL_RISK="wifi_forget window_close bt_pair"$' "$SRC" && grep -q 'pub const LOCAL_RISK: \[&str; 3\] = \["wifi_forget", "window_close", "bt_pair"\];' "$REPO/component/dialog/src/app.rs" \
    && ok "the shell and the dialog hold one list of risky steps" || bad "risk lists" "$(grep -n LOCAL_RISK "$SRC" "$REPO/component/dialog/src/app.rs")"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
printf 'buy bread\n' > "$H/notes.md"; printf 'x\000y' > "$H/blob.txt"; printf 'a' > "$H/pic.png"
awk 'BEGIN { for (i = 0; i < 1601; i++) printf "0123456789" }' > "$H/long.md"; : > "$H/empty.md"; printf 'caf\351\n' > "$H/latin1.txt"
st=0; o1=$(sh "$SH" want --attach "$H/long.md" what 2>&1) || st=$?; st2=0; o2=$(sh "$SH" want --attach "$H/empty.md" what 2>&1) || st2=$?; st3=0; o3=$(sh "$SH" want --attach "$H/latin1.txt" what 2>&1) || st3=$?
[ "$st" -eq 0 ] && [ "$(paste -sd ' ' - < "$HOME/spark.argv")" = 'read --name long.md what' ] && [ "$(wc -c < "$HOME/spark.stdin" | tr -d ' ')" = 16010 ] && [ "$st2" -eq 1 ] && [ "$o2" = 'empty.md is empty' ] && [ "$st3" -eq 1 ] && [ "$o3" = 'latin1.txt is not UTF-8 text' ] \
    && ok "want --attach: a file over 16 kB goes to spark read, which reads it by parts (#120); an empty one, one not UTF-8: refused with the reason, never cut or sent" || bad "want attach limits" "$st $o1 | $st2 $o2 | $st3 $o3"
st=0; out=$(sh "$SH" want --attach "$H/notes.md" "what do these say" 2>&1) || st=$?
[ "$st" -eq 0 ] && [ "$out" = 'the notes say to buy bread.' ] && [ "$(cat "$HOME/spark.stdin")" = 'buy bread' ] && [ "$(paste -sd ' ' - < "$HOME/spark.argv")" = 'edit --source --name notes.md -- ? what do these say' ] \
    && ok "want --attach FILE: the file is the text on stdin of spark edit ? --source, by its name alone, never its path" || bad "want attach" "st=$st $out $(cat "$HOME/spark.argv")"
st=0; o1=$(sh "$SH" want --attach "$H/pic.png" what 2>&1) || st=$?; st2=0; o2=$(sh "$SH" want --attach "$H/blob.txt" what 2>&1) || st2=$?; st3=0; o3=$(sh "$SH" want --attach "$H/none.md" what 2>&1) || st3=$?
[ "$st" -eq 1 ] && [ "$o1" = 'pic.png is not a type plus attaches (txt md)' ] && [ "$st2" -eq 1 ] && [ "$o2" = 'blob.txt is not text: spark reads text' ] && [ "$st3" -eq 1 ] && [ "$o3" = "$H/none.md is not a file that can be read" ] \
    && ok "want --attach: a type outside DIALOG_ATTACH_TYPES, a file that is not text, a file that is not there: one line each, exit 1" || bad "want attach refusals" "$st $o1 | $st2 $o2 | $st3 $o3"
printf 'DIALOG_ATTACH=no\n' > "$HOME/.config/spark-shell/config"; st=0; out=$(sh "$SH" want --json --attach "$H/notes.md" what 2>&1) || st=$?
[ "$st" -eq 1 ] && [ "$out" = '{"answer":"","steps":[],"refused":["attaching is off (DIALOG_ATTACH=no)"]}' ] && ok "want --attach with DIALOG_ATTACH=no: refused; in JSON, as a refused line" || bad "want attach off" "st=$st $out"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
st=0; out=$(sh "$SH" want 2>&1) || st=$?; st2=0; out2=$(sh "$SH" want --loud x 2>&1) || st2=$?
[ "$st" -eq 1 ] && [ "$out" = 'spark-shell want: say what you would like, as spark-shell want "mute everything"' ] && [ "$st2" -eq 1 ] && [ "$out2" = 'spark-shell want: --loud is not an option here: --attach FILE, --json, then the words' ] \
    && ok "want: no words, or an option it lacks, refused in one line" || bad "want usage" "$st $out | $st2 $out2"
if [ "$(uname -s)" != Darwin ]; then
    export SWAYSOCK=$H/sway.sock
    # wifi through the provider: a saved network connects with no password; a secured new one takes it as an argument, never kept
    mcp wifi "$(rq 3 resources/read '{"uri":"spark-shell://wifi/rows"}')" "$(call 2 wifi_forget '{"name":"nowhere"}')"
    ans 3 | jq -r '.result.contents[0].text' | jq -e '.rows[] | select(.text == "home") | .sign == "dot" and .tool == {name: "wifi_disconnect", arguments: {}}' >/dev/null \
        && ok "provide wifi rows: the network in use a dot, its tool disconnects" || bad "provide wifi rows" "$(ans 3 | head -c 400)"
    ans 3 | jq -r '.result.contents[0].text' | jq -e '([.rows[] | select(.tool.name == "wifi_forget")] == []) and ([.rows[] | select(.id == "wifi:saved old")][0] | .tool == null and .more == [{name: "wifi_forget", arguments: {name: "old"}, said: "forget"}] and .columns == ["saved, not around"] and (.page | startswith("spark-shell://wifi/page/")))' >/dev/null \
        && ok "provide wifi rows: forget is behind a saved network, and a saved one not around is a row of its own with forget behind it, no forget row (#169)" || bad "wifi forget behind" "$(ans 3 | head -c 1200)"
    [ "$(ans 2 | jq -r '.result.content[0].text')" = 'nowhere is not in the list now' ] && ok "provide wifi: forget names a saved network or nothing" || bad "provide forget" "$(ans 2)"
    rm -f "$H/.local/state/wpa.log"; mcp wifi "$(call 1 wifi_connect '{"name":"cafe","password":"s3cret-pass"}')"
    grep -q 'set_network 2 psk aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$H/.local/state/wpa.log" && ans 1 | jq -e '.result.content[0].text | startswith("could not connect to cafe")' >/dev/null && ! grep -rq 's3cret-pass' "$H/mcp.out" "$H/mcp.err" "$H/.local/state/spark-shell" \
        && ok "provide wifi: a new secured network takes its password as the tool's argument, straight to the Wi-Fi tool (this stub cannot join it); it is in no answer, no log and no journal" || bad "provide wifi connect" "$(ans 1) $(cat "$H/.local/state/wpa.log") $(grep -rl s3cret "$H/.local/state/spark-shell" 2>&1)"
    rm -f "$H/wpa.sel" "$H/wpa.down"
    [ "$(ls -ld "$H/.local/state/spark-shell/panel" | cut -c1-10)" = drwx------ ] && ok "the panel's journal folder is yours alone (0700)" || bad "journal mode" "$(ls -ld "$H/.local/state/spark-shell/panel")"
    # the scrubber: a name in the air with an escape and a bidi control reaches no screen, no row, no brief
    esc=$(printf '\033'); rlo=$(printf '\342\200\256')
    cp "$H/.local/bin/wpa_cli" "$H/wpa_cli.keep"
    sed "s/\\\\topen\\\\n' ;;/\\\\topen\\\\n00:11:22:33:44:88\\\\t2462\\\\t-60\\\\t[ESS]\\\\tev${esc}[2Jil${rlo}x\\\\n' ;;/" "$H/wpa_cli.keep" > "$H/.local/bin/wpa_cli"; chmod +x "$H/.local/bin/wpa_cli"
    rm -f "$H/.local/state/spark-shell/panel/wifi.scan"
    sh "$SH" panel wifi --list > "$H/wifi.list"; mcp wifi "$(rq 1 resources/read '{"uri":"spark-shell://wifi/rows"}')"
    grep -q 'ev\[2Jilx' "$H/wifi.list" && ! grep -q "$esc" "$H/wifi.list" && ! grep -q "$rlo" "$H/wifi.list" && ans 1 | jq -r '.result.contents[0].text' | jq -e 'any(.rows[]; .text | startswith("ev[2Jilx")) and all(.rows[]; .text | test("[\u001b\u202e]") | not)' >/dev/null \
        && ok "scrub: a network named with an escape and a bidi control is listed without them, in the panel and in the rows" || bad "scrub" "$(cat -v "$H/wifi.list" | grep ev)"
    mv "$H/wpa_cli.keep" "$H/.local/bin/wpa_cli"; rm -f "$H/.local/state/spark-shell/panel/wifi.scan"
    # the rows the dialog reads: a secured network not saved asks its password; the window section in two groups; a save asks its name
    rm -f "$H/.local/state/spark-shell/panel/wifi.scan"
    mcp wifi "$(rq 1 resources/read '{"uri":"spark-shell://wifi/rows"}')"; ans 1 | jq -r '.result.contents[0].text' > "$H/wifi.rows"
    jq -e '(.rows[] | select(.tool.name == "wifi_connect" and .tool.arguments.name == "cafe") | .tool.ask == ["password"]) and (.rows[] | select(.tool.name == "wifi_connect" and .tool.arguments.name == "open") | .tool.ask == null)' "$H/wifi.rows" >/dev/null \
        && ok "provide wifi rows: a secured network not saved asks its password; an open one asks nothing" || bad "wifi ask" "$(jq -c '.rows[] | .tool' "$H/wifi.rows")"
    # a layout by the name it was saved under, a rename row that asks the new name, made as a save makes one (#51, #54)
    mkdir -p "$HOME/.config/spark-shell/layouts"; printf '{"words":"zen and micro","main":{"app":"zen"}}' > "$HOME/.config/spark-shell/layouts/webdev"
    mcp layout "$(rq 1 resources/read '{"uri":"spark-shell://layout/rows"}')" "$(call 2 layout_rename '{"name":"webdev","to":"Web Dev"}')" "$(call 3 layout_rename '{"name":"nowhere","to":"x"}')"
    ans 1 | jq -r '.result.contents[0].text' | jq -e '(.rows[] | select(.text == "webdev") | .tool.name == "layout_open" and .tool.arguments == {name: "webdev"} and .more == [{name: "layout_rename", arguments: {name: "webdev"}, ask: ["to"], said: "rename"}, {name: "layout_delete", arguments: {name: "webdev"}, said: "delete"}]) and ([.rows[] | select(.text | startswith("rename "))] | length == 0)' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = "webdev renamed to web-dev" ] && [ -f "$HOME/.config/spark-shell/layouts/web-dev" ] \
        && [ "$(ans 3 | jq -r '.result.content[0].text')" = "layout: no saved or recent layout named nowhere" ] \
        && ok "provide layout: a layout by its name, rename (it asks the new name) and delete behind it, and the call renames it (#51, #54, #145)" || bad "provide layout rename" "$(cut -c1-300 "$H/mcp.out")"
    rm -f "$HOME/.config/spark-shell/layouts/web-dev"
    # recent (#145): the layouts opened lately and not saved, five at most, a saved one under its name alone, a command's words
    # never one; behind each, save as and forget
    _ks=${XDG_STATE_HOME:-$HOME/.local/state}/spark-shell; mkdir -p "$_ks/layouts"; [ ! -f "$_ks/layout.history" ] || cp "$_ks/layout.history" "$H/layout.history.keep"; : > "$_ks/layout.history"
    for _kn in one two three four five six layout-delete-x webdev; do printf '{"words":"%s","main":{"app":"zen"}}' "$_kn" > "$_ks/layouts/$_kn"; printf '1700000000\t%s\n' "$_kn" >> "$_ks/layout.history"; done
    printf '{"words":"zen","main":{"app":"zen"}}' > "$HOME/.config/spark-shell/layouts/webdev"   # saved: under its name, not in recent
    mcp layout "$(rq 1 resources/read '{"uri":"spark-shell://layout/rows"}')" "$(call 2 layout_rename '{"name":"one","to":"focus"}')" "$(call 3 layout_delete '{"name":"two"}')"
    _kr=$(ans 1 | jq -r '.result.contents[0].text')
    [ "$(printf '%s' "$_kr" | jq -c '[.rows[] | select(.group == "recent") | .text]')" = '["one","two","three","four","five"]' ] \
        && printf '%s' "$_kr" | jq -e '(.rows[] | select(.group == "recent" and .text == "one") | .more) == [{name: "layout_rename", arguments: {name: "one"}, ask: ["to"], said: "save as"}, {name: "layout_delete", arguments: {name: "one"}, said: "forget"}]' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = "saved as focus" ] && [ -f "$HOME/.config/spark-shell/layouts/focus" ] \
        && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = "forgot two" ] && ! cut -f2 "$_ks/layout.history" | grep -qx two \
        && ok "provide layout: recent holds the five last opened and not saved, a command's words never one; save as names one, forget lets it go (#145)" || bad "layout recent" "$_kr $(cut -c1-400 "$H/mcp.out")"
    st=0; o=$(sh "$SH" layout layout delete x 2>&1) || st=$?; st2=0; o2=$(sh "$SH" layout help 2>&1) || st2=$?
    [ "$st" = 1 ] && [ "$st2" = 1 ] && printf '%s' "$o" | grep -q 'is a command, not what a layout is for' && printf '%s' "$o2" | grep -q 'is a command' \
        && ok "layout: a command's words make no layout (layout layout delete x, layout help) (#145)" || bad "layout command words" "$st $o | $st2 $o2"
    rm -f "$HOME/.config/spark-shell/layouts/focus" "$HOME/.config/spark-shell/layouts/webdev"; rm -f "$_ks"/layouts/*; : > "$_ks/layout.history"; [ ! -f "$H/layout.history.keep" ] || mv "$H/layout.history.keep" "$_ks/layout.history"
    # the undo journal plays an ARG as it is: a glob in a name never expands against the folder it runs in
    mkdir -p "$H/globdir"; : > "$H/globdir/Jx"; printf 'out\tuse J*\tout J*\n' > "$H/.local/state/spark-shell/panel/undo"
    out=$(cd "$H/globdir" && sh "$SH" panel undo all 2>&1 || :)
    [ "$out" = "$(printf '\342\234\227') no output named J*" ] && ok "undo: a step's ARG with a glob is played as written, never as the files it matches" || bad "undo glob" "$out"
    unset SWAYSOCK
fi
fi

# --- 22. the dialog: its binary from a signed tag, the verb, its rows -------
if want 22; then
# A fixture clone of this tree: a stub spark-dialog whose sha256 the
# clone's component/dialog/dialog.env pins, a tag signed with a scratch key that the
# clone's allowed-signers names, the release assets in a file:// folder.
fresh
desktop_stubs
theme_fixture '#ff5555'
grep -q '^spark-shell-release namespaces="git" ssh-ed25519 [A-Za-z0-9+/=]*$' "$REPO/allowed-signers" && [ "$(grep -c '' "$REPO/allowed-signers")" = 1 ] \
    && ok "allowed-signers: one key, the release's, its principal a role and no address" || bad "allowed-signers" "$(cut -c1-60 "$REPO/allowed-signers")"
grep -q '^DIALOG_SHA256_X86_64_LINUX_MUSL=[0-9a-f]\{64\}$' "$REPO/component/dialog/dialog.env" && ok "dialog.env: the x86_64 build pinned by its sha256" || bad "dialog.env" "$(cat "$REPO/component/dialog/dialog.env")"
# the about provider: the template's key sentences, each combo a column, the splash's groups
printf '%s\n' "$(rq 1 resources/read '{"uri":"spark-shell://about/rows"}')" | sh "$SH" provide about | jq -r 'select(.id == 1) | .result.contents[0].text' > "$H/about.json"
# the facts as this clone has them: the tag's day (none in a clone without tags), the path, the count of credited projects
_tag=$(cd "$REPO" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); _day=''
[ -z "$_tag" ] || _day=$(cd "$REPO" && LC_ALL=C git log -1 --format=%cd --date=format:'%e %b %Y' "v$_tag" 2>/dev/null | sed 's/^ *//')
_want=$(jq -cn --arg d "$_day" --arg p "$REPO" --arg n "$(grep -c '^- ' "$REPO/CREDITS.md")" --arg v "$_tag" '(if $d == "" then [] else [["about:released", "released " + $d, [], null, null, null, "blank"]] end)
    + [["about:project", "project", ["github.com/forgewright-ai/spark-shell"], ["opens in the browser"], null, "about_site", "opens"],
       ["about:license", "license", ["MIT"], ["MIT", "LICENSE in " + $p], "spark-shell://about/page/YWJvdXQ6bGljZW5zZQ", null, "blank"],
       ["about:credits", "credits", [$n + " projects and their licenses"], [$n + " projects and their licenses", "CREDITS.md in " + $p], "spark-shell://about/page/YWJvdXQ6Y3JlZGl0cw", null, "blank"],
       ["about:installed", "installed at " + $p, [], null, null, null, "blank"],
       ["about:open", "spark-shell " + $v, [], null, null, "about_open", "opens"]]')
[ "$(jq -r '[.rows[] | select(.id | startswith("about:key:"))] | length' "$H/about.json")" = 21 ] \
    && [ "$(jq -c '[.rows[] | select(.id | startswith("about:key:")) | [.group, .text, .key]][0, 2, 15]' "$H/about.json" | paste -sd ' ' -)" = '["windows","open a terminal","Super+Return"] ["windows","move focus","Super+h j k l"] ["desktop","open home","Super+space"]' ] \
    && [ "$(jq -c '[.rows[] | select(.id | startswith("about:key:")) | .group] | unique' "$H/about.json")" = '["desktop","windows","workspaces"]' ] \
    && [ "$(jq -c '.short' "$H/about.json")" = '["about:open"]' ] && jq -e '.rows[] | select(.id == "about:open") | .tool.name == "about_open"' "$H/about.json" >/dev/null \
    && [ "$(jq -c '[.rows[] | select(.id | startswith("about:key") | not) | [.id, .text, .columns, .wide, .page, .tool.name, .sign]]' "$H/about.json")" = "$_want" ] \
    && ok "provide about: the facts by id (released, installed), project with its tool, license and credits with their pages, the short form that opens it; then help's 21 desktop rows, what you do with its key, under windows, workspaces and desktop (the dialog design notes, v0.129)" || bad "about rows" "$(jq -c '[.rows[] | select(.id | startswith("about:key") | not)]' "$H/about.json")"
sh "$SH" desktop keys | grep -v '^[A-Za-z0-9_+]* [a-z][a-z0-9.-]*\.$' > "$H/keys.odd" || :
[ ! -s "$H/keys.odd" ] && ok "desktop keys: each sentence opens with one combo and a verb (the about's two columns)" || bad "key sentences" "$(cat "$H/keys.odd")"
if [ "$(uname -s)" = Darwin ]; then
    st=0; out=$(sh "$SH" dialog 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell dialog: the dialog is the Linux desktop'"'"'s; in a terminal here, spark-shell panel' ] && ok "macOS: dialog refuses in one line, the panel named" || bad "macOS dialog" "st=$st $out"
else
    # The release fixture is a shell script, packaged as x86_64. Keep this
    # packaging test useful on ARM too, without pretending its host is x86.
    if [ "$(uname -m)" != x86_64 ]; then
        mkdir -p "$HOME/.config/spark-shell"
        printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
        out=$(sh "$SH" on --dry-run 2>&1 || :)
        printf '%s\n' "$out" | grep -q 'no build for .* yet' && ok "dialog: this architecture has no release" || bad "dialog architecture" "$out"
    fi
    printf '#!/bin/sh\ncase $1 in -m) echo x86_64 ;; *) exec "%s" "$@" ;; esac\n' "$(command -v uname)" > "$H/.local/bin/uname"
    chmod +x "$H/.local/bin/uname"
    C=$H/clone; mkdir -p "$C"
    (cd "$REPO" && tar --exclude=.git --exclude=target --exclude=target2 -cf - .) | (cd "$C" && tar --no-same-owner -xf -)   # the files ours: git refuses a clone another user owns
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/dialog.argv"\nexit "${DIALOG_EXIT:-0}"\n' > "$H/stub-dialog"
    sum256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
    sha=$(sum256 "$H/stub-dialog")
    sed "s/^DIALOG_SHA256_X86_64_LINUX_MUSL=.*/DIALOG_SHA256_X86_64_LINUX_MUSL=$sha/" "$REPO/component/dialog/dialog.env" > "$C/component/dialog/dialog.env"
    ssh-keygen -q -t ed25519 -N '' -C '' -f "$H/key" >/dev/null
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/key.pub")" > "$C/allowed-signers"
    g() { git -C "$C" -c user.name=test -c user.email=you@example.com -c gpg.format=ssh -c "user.signingkey=$H/key" "$@"; }   # spark:allow-secret (a scratch key, made here)
    g init -q && g add -A && g commit -q -m fixture && g tag -s v9.9 -m 'spark-shell v9.9'
    mkdir -p "$H/assets/v9.9"; cp "$H/stub-dialog" "$H/assets/v9.9/spark-dialog-x86_64-linux-musl"
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    bin=$H/.local/share/spark-shell/spark-dialog
    st=0; out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^ok     dialog       installed for v9.9 ($bin), sha256 checked$" && [ -x "$bin" ] && [ "$(sum256 "$bin")" = "$sha" ] \
        && ok "on: the dialog fetched for the signed release tag, its sha256 the tag's own tree pins, installed" || bad "dialog install" "st=$st $(printf '%s\n' "$out" | grep dialog)"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" check 2>&1 || :)
    printf '%s\n' "$out" | grep -q "^ok     dialog       $bin, the sha256 v9.9 pins$" \
        && ok "check: the dialog in place is the build the release pins" || bad "check dialog ok" "$(printf '%s\n' "$out" | grep dialog)"
    cp "$bin" "$H/dialog.keep"; printf 'x' >> "$bin"
    st=0; out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" check 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q '^FAIL   dialog       not the build v9.9 pins, so home will not open -- spark-shell on$' && [ "$st" -ne 0 ] \
        && ok "check: a dialog that is not the release's fails, and says home will not open" || bad "check dialog fail" "st=$st $(printf '%s\n' "$out" | grep dialog)"
    cp "$H/dialog.keep" "$bin"
    cp "$C/component/dialog/dialog.env" "$H/dialog.env.keep"; sed 's/=.*/=0000000000000000000000000000000000000000000000000000000000000000/' "$H/dialog.env.keep" > "$C/component/dialog/dialog.env"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --dry-run 2>&1 || :); cp "$H/dialog.env.keep" "$C/component/dialog/dialog.env"
    printf '%s\n' "$out" | grep -q '^todo   dialog       this clone is past its release: the dialog comes with the next tag$' && ok "on: a dialog.env edited in the working copy is no release: the tag's own tree decides" || bad "dialog env edited" "$(printf '%s\n' "$out" | grep dialog)"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^ok     dialog       ' && ok "on --dry-run: the dialog in place is ok" || bad "dialog ok" "$(printf '%s\n' "$out" | grep dialog)"
    # a file that is not the pinned one, a tag no key here signed, a tree past its release: nothing installed
    rm -f "$bin"; printf 'x' >> "$H/assets/v9.9/spark-dialog-x86_64-linux-musl"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   dialog       the spark-dialog fetched for v9.9 is not the one the tree pins: not installed$' && [ ! -e "$bin" ] \
        && ok "on: a fetched file with another sha256 is refused, nothing installed" || bad "dialog tampered" "$(printf '%s\n' "$out" | grep dialog)"
    cp "$H/stub-dialog" "$H/assets/v9.9/spark-dialog-x86_64-linux-musl"
    ssh-keygen -q -t ed25519 -N '' -C '' -f "$H/other" >/dev/null
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/other.pub")" > "$C/allowed-signers"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   dialog       v9.9 is not signed by a key in allowed-signers: no dialog installed$' && [ ! -e "$bin" ] \
        && ok "on: a tag no key in allowed-signers signed installs nothing" || bad "dialog unsigned" "$(printf '%s\n' "$out" | grep dialog)"
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/key.pub")" > "$C/allowed-signers"
    printf '\n' >> "$C/component/dialog/src/main.rs"; g commit -q -am 'past the tag'
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   dialog       this clone is past its release: the dialog comes with the next tag$' && [ ! -e "$bin" ] \
        && ok "on: a clone whose component/dialog/ moved past its tag installs nothing" || bad "dialog past" "$(printf '%s\n' "$out" | grep dialog)"
    g reset -q --hard v9.9
    SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes >/dev/null 2>&1 || :
    # spark's MCP list (issue 8): each provider put on it through spark mcp add; a server of yours under one of the names stays; an older clone's line is replaced
    cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
f=${XDG_CONFIG_HOME:-$HOME/.config}/spark/mcp.env; mkdir -p "$(dirname "$f")"; touch "$f"
case $1 in
    help) echo ' spark mcp [NAME]               the MCP servers on the list (-h)' ;;
    mcp) echo "$*" >> "$HOME/mcp.log"; k=MCP_SERVER_$(printf '%s' "$3" | tr 'a-z' 'A-Z')
        case $2 in
            add) if grep -q "^$k=" "$f"; then echo "$3 is on the list already" >&2; exit 1; fi; n=$3; shift 3; printf '%s="%s"\n' "$k" "$*" >> "$f" ;;
            rm) grep -v "^$k=" "$f" > "$f.t" || :; mv "$f.t" "$f" ;;
        esac ;;
esac
STUB
    chmod +x "$H/.local/bin/spark"; mcpf=$HOME/.config/spark/mcp.env; mkdir -p "$HOME/.config/spark"; rm -f "$HOME/mcp.log"
    printf 'MCP_SERVER_FILES="/opt/mine/files-server"\nMCP_SERVER_WIFI="/old/clone/spark-shell provide wifi"\n' > "$mcpf"
    out=$(SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q "^ok     mcp          24 providers on spark's MCP list: the prompt line and spark do know the desktop's tools$" \
        && printf '%s\n' "$out" | grep -q "^todo   mcp          already on spark's MCP list as servers of yours, left as they are: files$" \
        && grep -qx 'MCP_SERVER_FILES="/opt/mine/files-server"' "$mcpf" && grep -qx "MCP_SERVER_WIFI=\"$C/spark-shell provide wifi\"" "$mcpf" && grep -qx "MCP_SERVER_CLOCK=\"$C/spark-shell provide clock\"" "$mcpf" \
        && [ "$(grep -c '^MCP_SERVER_' "$mcpf")" = 25 ] && grep -qx 'mcp rm wifi' "$HOME/mcp.log" && ! grep -q 'mcp add files' "$HOME/mcp.log" \
        && ok "on desktop: each provider on spark's MCP list through spark mcp add; a server of yours under one of the names stays; an older clone's line replaced" || bad "mcp add" "$(printf '%s\n' "$out" | grep mcp); $(cat "$mcpf")"
    rm -f "$HOME/mcp.log"; SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes >/dev/null 2>&1 || :
    [ ! -e "$HOME/mcp.log" ] && sh "$C/spark-shell" check 2>&1 | grep -q "^warn   mcp          24 of 25 providers on spark's MCP list -- spark-shell on desktop$" \
        && ok "on desktop again: nothing asked of spark; check counts the providers on the list" || bad "mcp again" "$(cat "$HOME/mcp.log" 2>&1); $(sh "$C/spark-shell" check 2>&1 | grep mcp)"
    out=$(sh "$C/spark-shell" off desktop --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -q "^would  mcp          take lan wifi bt printers out mic bat clock theme window display keyboard pointer notifications storage power notes reminders bar layout apps tools about undo off spark's MCP list$" \
        && ok "off desktop --dry-run: the lines that are ours, by name; a server of yours is not among them" || bad "mcp off would" "$(printf '%s\n' "$out" | grep mcp)"
    st=0; out=$(sh "$C/spark-shell" off desktop 2>&1) || st=$?
    printf '%s\n' "$out" | grep -q "^ok     mcp          24 providers off spark's MCP list$" && [ "$(cat "$mcpf")" = 'MCP_SERVER_FILES="/opt/mine/files-server"' ] \
        && ok "off desktop: spark-shell's lines off spark's MCP list through spark mcp rm, a server of yours left" || bad "mcp off" "st=$st $(printf '%s\n' "$out" | grep mcp); $(cat "$mcpf")"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"; rm -f "$mcpf" "$H/.local/bin/spark"
    SPARK_SHELL_DIALOG_URL="file://$H/assets" sh "$C/spark-shell" on --yes >/dev/null 2>&1 || :
    # the verb: the providers, the home, the composer; the binary checked each time
    st=0; out=$(sh "$C/spark-shell" dialog 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx -- "$C/spark-shell provide layout" "$HOME/dialog.argv" && grep -qx -- "$C/spark-shell provide about" "$HOME/dialog.argv" && ! grep -q 'provide spark$\|provide undo$' "$HOME/dialog.argv" \
        && grep -qx -- --composer "$HOME/dialog.argv" && grep -qx 'plus,model,talk' "$HOME/dialog.argv" && grep -qx -- "$C/spark-shell provide files" "$HOME/dialog.argv" && grep -qx 'txt md' "$HOME/dialog.argv" && grep -qx -- "$C/spark-shell" "$HOME/dialog.argv" && ! grep -qx -- --home "$HOME/dialog.argv" \
        && ok "dialog: every section a provider but spark and undo, the composer by the keys, the attach types, this spark-shell for the want" || bad "dialog argv" "st=$st $out $(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog about >/dev/null 2>&1; [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = about ] && ! grep -qx -- --mark "$HOME/dialog.argv" \
        && ok "dialog about: the about first, and no logo on it (#40)" || bad "dialog about" "$(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog wifi >/dev/null 2>&1; [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = wifi ] && [ "$(grep -x -- "--provider" "$HOME/dialog.argv" | wc -l)" -ge 3 ] && [ "$(grep -A1 -x -- --provider "$HOME/dialog.argv" | sed -n 2p)" = "$C/spark-shell provide wifi" ] \
        && ok "dialog wifi: the section that opened it first" || bad "dialog wifi" "$(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog >/dev/null 2>&1; c1=$(grep -cx -- "$C/spark-shell provide clock" "$HOME/dialog.argv"); sh "$C/spark-shell" dialog clock >/dev/null 2>&1; c2=$(grep -cx -- "$C/spark-shell provide clock" "$HOME/dialog.argv")
    [ "$c1" = 1 ] && [ "$c2" = 1 ] && [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = clock ] \
        && ok "dialog: the clock is started once however the dialog opens, so the Calendar opens from any view" || bad "dialog clock" "$c1 $c2 $(cat "$HOME/dialog.argv")"
    sh "$C/spark-shell" dialog files >/dev/null 2>&1; [ "$(grep -A1 -x -- --home "$HOME/dialog.argv" | tail -1)" = files ] && [ "$(grep -cx -- "$C/spark-shell provide files" "$HOME/dialog.argv")" = 1 ] \
        && ok "dialog files: the files first, its provider started once" || bad "dialog files" "$(cat "$HOME/dialog.argv")"
    printf 'DESKTOP=sway\nDIALOG_ATTACH=no\nDIALOG_MODEL=no\nDIALOG_TALK=no\n' > "$HOME/.config/spark-shell/config"
    sh "$C/spark-shell" dialog >/dev/null 2>&1; [ "$(grep -A1 -x -- --composer "$HOME/dialog.argv" | tail -1)" = '' ] && ok "dialog: DIALOG_ATTACH, DIALOG_MODEL and DIALOG_TALK at no leave the composer bare" || bad "dialog keys" "$(cat "$HOME/dialog.argv")"
    # the transitions (#122): the piece in the palette in use; a palette with no set drawn ahead names the piece for the dialog
    # to draw (#247); none, or no palette, plays none
    printf 'DESKTOP=sway\nTHEME=tokyonight-night\n' > "$HOME/.config/spark-shell/config"; sh "$C/spark-shell" dialog >/dev/null 2>&1; a1=$(grep -A1 -x -- --transitions "$HOME/dialog.argv" | tail -1)
    printf 'DESKTOP=sway\nTHEME=tokyonight-night\nDIALOG_ANIMATION=none\n' > "$HOME/.config/spark-shell/config"; sh "$C/spark-shell" dialog >/dev/null 2>&1; a2=$(grep -cx -- --transitions "$HOME/dialog.argv" || :)
    printf 'DESKTOP=sway\nTHEME=none\n' > "$HOME/.config/spark-shell/config"; sh "$C/spark-shell" dialog >/dev/null 2>&1; a3=$(grep -cx -- --transitions "$HOME/dialog.argv" || :)
    palette_fixture mine '#fe8019'; printf 'DESKTOP=sway\nTHEME=mine\n' > "$HOME/.config/spark-shell/config"; sh "$C/spark-shell" dialog >/dev/null 2>&1; a4=$(grep -A1 -x -- --transitions "$HOME/dialog.argv" | tail -1)
    rm -f "$HOME/.config/spark-shell/themes/mine.env"
    [ "$a1" = "$C/gallery/animation/moon/tokyonight-night" ] && [ "$a2" = 0 ] && [ "$a3" = 0 ] && [ "$a4" = draw:embers ] \
        && ok "dialog: the transitions are the palette's piece in the palette in use (tokyonight-night's moon); a palette of yours, the piece for the dialog to draw (draw:embers); none, or no palette, plays none (#122, #247)" || bad "dialog transitions" "$a1 $a2 $a3 $a4"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    st=0; out=$(sh "$C/spark-shell" dialog nonsense 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell dialog: nonsense is not a section of the dialog' ] && ok "dialog WORD: a word that is no section, refused" || bad "dialog nonsense" "st=$st $out"
    printf 'x' >> "$bin"; st=0; out=$(sh "$C/spark-shell" dialog 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell dialog: the dialog is not installed, or not the release'"'"'s -- spark-shell on' ] && ok "dialog: a binary changed since it was installed is not run" || bad "dialog changed" "st=$st $out"
    rm -f "$H/.local/bin/uname"
fi
unset SPARK_SHELL_SYS SPARK_SHELL_PROC SWAYSOCK

fi

# --- 22b. the dialog's search by meaning (v0.130): spark's engine, the model pinned, a socket of the session
if want 22b; then
# A clone of this tree whose pins are a small file's (the tree's model is 310 MB), spark a stub, spark's
# engines stand-ins that write their words and stay up, curl's health answer a file. No socket is made.
grep -qx 'SEMANTIC_SHA256=2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135' "$SRC" && grep -qx 'SEMANTIC_SIZE=309855456   # bytes, 310 MB' "$SRC" \
    && grep -q '^SEMANTIC_URL=${SPARK_SHELL_SEMANTIC_URL:-https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/6ea3e3a309d12a4779cfda98b8c19800d2d5da71/embeddinggemma-2-Q8_0.gguf}' "$SRC" \
    && ok "semantic: the model pinned in the tree by its revision, its sha256 and its size" || bad "semantic pins" "$(grep -n '^SEMANTIC_' "$SRC")"
if [ "$(uname -s)" != Darwin ]; then
    fresh
    desktop_stubs
    sum256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
    upto() { _u=0; while [ ! -s "$1" ] && [ "$_u" -lt 50 ]; do sleep 0.1; _u=$((_u + 1)); done; }   # upto FILE -- until a stand-in has written it, 5 s at most
    gone() { [ ! -d "/proc/$1" ] || grep -q '^State:[[:space:]]*Z' "/proc/$1/status" 2>/dev/null; }   # gone PID -- ended (a process no one has reaped yet is ended too)
    C=$H/clone; mkdir -p "$C"
    for e in "$REPO"/*; do case ${e##*/} in spark-shell|src) ;; *) ln -s "$e" "$C/${e##*/}" ;; esac; done
    cp "$SH" "$C/spark-shell"; mkdir "$C/src"; for e in "$REPO"/src/*.sh; do [ "${e##*/}" = dialog.sh ] || ln -s "$e" "$C/src/${e##*/}"; done   # a real entry, so its REPO is the clone; the pins' module a copy
    printf 'a small model\n' > "$H/model.gguf"; printf 'another model\n' > "$H/other.gguf"
    sed -e "s/^SEMANTIC_SHA256=.*/SEMANTIC_SHA256=$(sum256 "$H/model.gguf")/" -e "s/^SEMANTIC_SIZE=.*/SEMANTIC_SIZE=$(wc -c < "$H/model.gguf" | tr -d ' ')/" "$REPO/src/dialog.sh" > "$C/src/dialog.sh"
    S=$C/spark-shell; M=$H/.local/share/spark-shell/models/embeddinggemma-2-Q8_0.gguf; SOCK=$H/run/spark-shell/semantic.sock; PIDF=$H/run/spark-shell/semantic.pid
    printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    printf '#!/bin/sh\ncase " $* " in *" --unix-socket "*) [ -e "$HOME/healthy" ] ;; *) exec %s "$@" ;; esac\n' "$(command -v curl)" > "$H/.local/bin/curl"; chmod +x "$H/.local/bin/curl"
    cat > "$H/engine-stub" <<'STUB'
#!/bin/sh
printf '%s\n' "$0" "$@" > "$HOME/engine.argv"
sleep 60 & s=$!
trap 'kill $s; exit 0' TERM
wait $s
STUB
    E=$H/.local/share/spark/engine
    for b in b1 b9 b10; do mkdir -p "$E/llama.cpp-$b"; cp "$H/engine-stub" "$E/llama.cpp-$b/llama-server"; chmod +x "$E/llama.cpp-$b/llama-server"; done
    mkdir -p "$E/llama.cpp-b20"; cp "$H/engine-stub" "$E/llama.cpp-b20/llama-server"   # the newest, but not executable: not an engine
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    grep -qx 'DIALOG_SEMANTIC=yes' "$REPO/config.example" && ok "config.example: DIALOG_SEMANTIC=yes, its default" || bad "semantic config.example"
    printf 'DESKTOP=sway\nDIALOG_SEMANTIC=maybe\n' > "$HOME/.config/spark-shell/config"; st=0; out=$(sh "$S" status 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s\n' "$out" | grep -q '^spark-shell: DIALOG_SEMANTIC=maybe in .*: yes or no$' && ok "config: DIALOG_SEMANTIC takes yes or no, anything else refused in one line" || bad "semantic key" "st=$st $out"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    # no model yet: start refuses, the dialog gets no socket, check fails, the warning names the download
    st=0; out=$(sh "$S" semantic start 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell semantic: the model is not installed (spark-shell on), so the dialog keeps its word search' ] && [ ! -e "$PIDF" ] \
        && ok "semantic start: no model, one line, nothing started" || bad "semantic start no model" "st=$st $out"
    out=$(sh "$S" check 2>&1 || :)
    printf '%s\n' "$out" | grep -qx 'FAIL   semantic     the model is missing -- spark-shell on' && ok "check: spark and its engine here, the model missing: a fail, on its remedy" || bad "check semantic missing" "$(printf '%s\n' "$out" | grep semantic)"
    out=$(printf 'n\n' | SPARK_SHELL_SEMANTIC_URL="file://$H/model.gguf" SPARK_SHELL_TEST_TTY=1 sh "$S" on desktop 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^  search       EmbeddingGemma 2 from Hugging Face, 310 MB, sha256 checked, for' \
        && ok "warning: on desktop, with spark, names the model it fetches, its size and its check" || bad "semantic warning" "$out"
    out=$(SPARK_SHELL_SEMANTIC_URL="file://$H/model.gguf" sh "$S" on --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -qx "would  semantic     fetch EmbeddingGemma 2 (310 MB) for the dialog's search by meaning and check its sha256" && [ ! -e "$M" ] \
        && ok "on --dry-run: the model would be fetched and checked, nothing fetched" || bad "semantic would" "$(printf '%s\n' "$out" | grep semantic)"
    # install: a file with another sha256 refused, the pinned one put in place
    out=$(SPARK_SHELL_SEMANTIC_URL="file://$H/other.gguf" sh "$S" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -qx 'todo   semantic     the EmbeddingGemma 2 fetched is not the one spark-shell pins: not installed' && [ ! -e "$M" ] && [ ! -e "$M.new" ] \
        && ok "on: a model with another sha256 is refused, nothing left in place" || bad "semantic wrong sha" "$(printf '%s\n' "$out" | grep semantic)"
    out=$(SPARK_SHELL_SEMANTIC_URL="file://$H/model.gguf" sh "$S" on --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -qx "ok     semantic     EmbeddingGemma 2 installed ($M), sha256 checked" && cmp -s "$M" "$H/model.gguf" && [ ! -e "$M.new" ] \
        && ok "on: the model fetched, its sha256 the pinned one, moved into place" || bad "semantic install" "$(printf '%s\n' "$out" | grep semantic)"
    out=$(SPARK_SHELL_SEMANTIC_URL="file://$H/model.gguf" sh "$S" on --dry-run 2>&1 || :)
    out2=$(printf 'n\n' | SPARK_SHELL_SEMANTIC_URL="file://$H/model.gguf" SPARK_SHELL_TEST_TTY=1 sh "$S" on desktop 2>&1 || :)
    printf '%s\n' "$out" | grep -qx "ok     semantic     $M, the sha256 spark-shell pins" && ! printf '%s\n' "$out2" | grep -q '^  search ' \
        && ok "on again: the model in place is ok, and the warning no longer names it" || bad "semantic in place" "$(printf '%s\n' "$out" | grep semantic) | $out2"
    # start: the newest executable engine by its number (b10 over b9, never b20), the flags, the pid; a folder of yours alone
    rm -f "$HOME/engine.argv"; st=0; out=$(sh "$S" semantic start 2>&1) || st=$?; upto "$HOME/engine.argv"
    want_argv="$E/llama.cpp-b10/llama-server -m $M --embedding --pooling mean --host $SOCK -ngl 0 -t 4 -c 2048 -b 2048 -ub 2048 --no-webui --log-disable --offline"
    p1=$(cat "$PIDF" 2>/dev/null || :)
    [ "$st" -eq 0 ] && [ -z "$out" ] && [ "$(paste -sd' ' - < "$HOME/engine.argv")" = "$want_argv" ] && [ -n "$p1" ] && tr '\0' '\n' < "/proc/$p1/cmdline" | grep -qxF "$SOCK" \
        && [ "$(ls -ld "$H/run/spark-shell" | cut -c1-10)" = drwx------ ] \
        && ok "semantic start: spark's newest engine (llama.cpp-b10), the model on the session's socket with the flags, its pid kept, the folder 0700" || bad "semantic start" "st=$st $out $(cat "$HOME/engine.argv" 2>&1) pid=$p1"
    [ "$(sh "$S" semantic status)" = "semantic search: not running ($SOCK)" ] && ok "semantic status: not answering yet is not running, the socket named" || bad "semantic status off" "$(sh "$S" semantic status)"
    touch "$HOME/healthy"; rm -f "$HOME/engine.argv"; sh "$S" semantic start; sleep 0.3
    [ "$(cat "$PIDF")" = "$p1" ] && [ ! -e "$HOME/engine.argv" ] && [ "$(sh "$S" semantic status)" = "semantic search: running at $SOCK" ] \
        && ok "semantic start again: a server that answers stays, nothing started; status says it runs" || bad "semantic start again" "$(cat "$PIDF") $p1"
    # ours, alive and not answering yet, is loading (home opened in the second after the desktop's start): left to finish
    rm -f "$HOME/healthy" "$HOME/engine.argv"; sh "$S" semantic start; sleep 0.3
    [ "$(cat "$PIDF")" = "$p1" ] && [ ! -e "$HOME/engine.argv" ] && ! gone "$p1" \
        && ok "semantic start: ours still loading is left to finish, nothing started beside it" || bad "semantic loading" "$(cat "$PIDF") $p1"
    # ours gone: a new one starts
    kill "$p1"; for _i in 1 2 3 4 5 6 7 8 9 10; do gone "$p1" && break; sleep 0.1; done
    sh "$S" semantic start; upto "$HOME/engine.argv"; p2=$(cat "$PIDF" 2>/dev/null || :)
    [ -n "$p2" ] && [ "$p2" != "$p1" ] && [ -s "$HOME/engine.argv" ] \
        && ok "semantic start: ours gone, a new one started" || bad "semantic restart" "p1=$p1 p2=$p2"
    # stop: our pid alone; a pid the system gave another process is never killed
    : > "$SOCK"; sh "$S" semantic stop
    gone "$p2" && [ ! -e "$PIDF" ] && [ ! -e "$SOCK" ] && ok "semantic stop: the server gone, its pid file and socket with it" || bad "semantic stop" "$(ls -la "$H/run/spark-shell")"
    sleep 60 & fp=$!; echo "$fp" > "$PIDF"; : > "$SOCK"; sh "$S" semantic stop
    kill -0 "$fp" 2>/dev/null && [ ! -e "$PIDF" ] && [ ! -e "$SOCK" ] && ok "semantic stop: a pid whose words do not hold the socket is left alone, the files go" || bad "semantic stop other" "$(ls -la "$H/run/spark-shell")"
    kill "$fp" 2>/dev/null || :
    # a server whose pid file a lost start overwrote: stop finds it by its socket; the dialog, whose --semantic names
    # the same socket, is never one
    "$E/llama.cpp-b10/llama-server" -m "$M" --host "$SOCK" & op=$!
    sh -c 'sleep 60; :' sh --semantic "$SOCK" & dp=$!
    sleep 0.3; rm -f "$PIDF"; sh "$S" semantic stop
    gone "$op" && kill -0 "$dp" 2>/dev/null \
        && ok "semantic stop: a server with no pid file is found by its socket and stopped; the dialog, which only names the socket, is left alone" || bad "semantic stop orphan" "op=$op dp=$dp"
    kill "$dp" 2>/dev/null || :
    # two starts at once (the desktop's start and a quick first home): one server
    # a process forked by a server and not yet its own program (the stub's sleep, a moment on a loaded runner)
    # carries the server's words: one whose parent is counted is that server's, not another (servers=2 on ubuntu CI,
    # three runs in four on 2026-11-08); a fail names each process it counted
    servers_pids() { grep -lF -- "$SOCK" /proc/[0-9]*/cmdline 2>/dev/null | while read -r f; do tr '\0' '\n' < "$f" 2>/dev/null | grep -A1 -xF -- --host | grep -qxF -- "$SOCK" && { f=${f#/proc/}; echo "${f%/cmdline}"; }; done; }
    ppid_of() { awk '/^PPid:/ { print $2 }' "/proc/$1/status" 2>/dev/null; }
    servers_up() {   # -> how many processes serve on the socket
        _sp=" $(servers_pids | tr '\n' ' ') "; _sn=0
        for _p in $_sp; do case $_sp in *" $(ppid_of "$_p") "*) ;; *) _sn=$((_sn + 1)) ;; esac; done
        echo "$_sn"
    }
    servers_said() { for _p in $(servers_pids); do printf '%s (parent %s, %s): %s; ' "$_p" "$(ppid_of "$_p")" "$(awk '/^State:/ { print $2 }' "/proc/$_p/status" 2>/dev/null)" "$(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null)"; done; }   # -> each counted process, so a fail says which
    rm -f "$HOME/engine.argv"; sh "$S" semantic start & sh "$S" semantic start & wait
    sleep 0.5
    servers=$(servers_up)
    [ "$servers" = 1 ] && ok "semantic start twice at once: one server, the other start leaves it to the first" || bad "semantic start race" "servers=$servers $(servers_said)"
    sh "$S" semantic stop
    # uutils' mkdir before 0.11 (Ubuntu 26.04's) says yes to a folder that is there, and both starts took the lock: a
    # lock held, a mkdir that says yes to anything, and a start starts nothing (the lock is the shell's, not mkdir's)
    mkdir -p "$H/uu"; printf '#!/bin/sh\n%s "$@" 2>/dev/null || :\n' "$(command -v mkdir)" > "$H/uu/mkdir"; chmod +x "$H/uu/mkdir"
    : > "$H/run/spark-shell/semantic.lock"; rm -f "$HOME/engine.argv" "$PIDF"
    PATH="$H/uu:$PATH" sh "$S" semantic start; sleep 0.3
    servers=$(servers_up)
    [ "$servers" = 0 ] && [ ! -e "$HOME/engine.argv" ] && [ -e "$H/run/spark-shell/semantic.lock" ] \
        && ok "semantic start: a start the lock holds starts nothing, with a mkdir that says yes to a folder that is there (uutils before 0.11)" \
        || bad "semantic lock, mkdir that says yes" "servers=$servers $(servers_said)"
    rm -f "$H/run/spark-shell/semantic.lock"; sh "$S" semantic stop
    # the second start comes while the first one's process is not the server yet, between its fork and its exec
    # (here the log, a FIFO, holds it there until a reader opens it): the first keeps its lock until then
    LOGF=$H/.local/state/spark-shell/semantic.log; rm -f "$LOGF" "$HOME/engine.argv"; mkfifo "$LOGF"
    sh "$S" semantic start & sa=$!
    upto "$PIDF"; sh "$S" semantic start; cat "$LOGF" > /dev/null & sr=$!; wait "$sa"
    sleep 0.5
    servers=$(servers_up)
    [ "$servers" = 1 ] && ok "semantic start: a second start before the first one's server has begun leaves it to the first" || bad "semantic start before exec" "servers=$servers $(servers_said)"
    sh "$S" semantic stop; kill "$sr" 2>/dev/null || :; rm -f "$LOGF"
    # the engine spark.env names wins over spark's own
    mkdir -p "$H/own"; cp "$H/engine-stub" "$H/own/llama-server"; chmod +x "$H/own/llama-server"
    printf 'SPARK_ENGINE_DIR="%s"\n' "$H/own" > "$HOME/.config/spark/spark.env"
    rm -f "$HOME/engine.argv"; sh "$S" semantic start; upto "$HOME/engine.argv"
    [ "$(sed -n 1p "$HOME/engine.argv" 2>/dev/null)" = "$H/own/llama-server" ] && ok "semantic start: SPARK_ENGINE_DIR in spark.env names the engine, as spark reads it" || bad "semantic engine dir" "$(cat "$HOME/engine.argv" 2>&1)"
    sh "$S" semantic stop; rm -f "$HOME/.config/spark/spark.env"
    # check: the model by its sha256, whether the server answers
    out=$(sh "$S" check 2>&1 || :); touch "$HOME/healthy"; out2=$(sh "$S" check 2>&1 || :)
    printf '%s\n' "$out" | grep -qx "ok     semantic     $M, the sha256 spark-shell pins, not running" && printf '%s\n' "$out2" | grep -qx "ok     semantic     $M, the sha256 spark-shell pins, running at $SOCK" \
        && ok "check: the model the sha256 spark-shell pins, and whether its server answers" || bad "check semantic ok" "$(printf '%s\n' "$out" "$out2" | grep semantic)"
    # the dialog: the socket handed over where all is in place (a server that answers is not started again)
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/dialog.argv"\n' > "$H/stub-dialog"; chmod +x "$H/stub-dialog"
    SPARK_SHELL_DIALOG=$H/stub-dialog sh "$S" dialog >/dev/null 2>&1 || :
    [ "$(grep -A1 -x -- --semantic "$HOME/dialog.argv" | tail -1)" = "$SOCK" ] && ok "dialog: --semantic and the session's socket, with spark, its engine and the model" || bad "dialog semantic" "$(cat "$HOME/dialog.argv" 2>&1)"
    printf 'DESKTOP=sway\nDIALOG_SEMANTIC=no\n' > "$HOME/.config/spark-shell/config"
    SPARK_SHELL_DIALOG=$H/stub-dialog sh "$S" dialog >/dev/null 2>&1 || :; d1=$(grep -cx -- --semantic "$HOME/dialog.argv" || :)
    out=$(sh "$S" check 2>&1 || :); st=0; out3=$(sh "$S" semantic start 2>&1) || st=$?
    [ "$d1" = 0 ] && printf '%s\n' "$out" | grep -qx 'ok     semantic     na (DIALOG_SEMANTIC=no)' && [ "$st" -eq 1 ] && [ "$out3" = 'spark-shell semantic: DIALOG_SEMANTIC=no, so the dialog keeps its word search' ] \
        && ok "DIALOG_SEMANTIC=no: no socket for the dialog, check says na, start refuses" || bad "semantic no" "d1=$d1 $(printf '%s\n' "$out" | grep semantic) st=$st $out3"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    mv "$E" "$H/engines.away"; out=$(sh "$S" check 2>&1 || :); SPARK_SHELL_DIALOG=$H/stub-dialog sh "$S" dialog >/dev/null 2>&1 || :; d1=$(grep -cx -- --semantic "$HOME/dialog.argv" || :)
    st=0; out3=$(sh "$S" semantic start 2>&1) || st=$?; mv "$H/engines.away" "$E"
    [ "$d1" = 0 ] && printf '%s\n' "$out" | grep -qx "ok     semantic     na (spark's engine is not installed)" && [ "$st" -eq 1 ] && [ "$out3" = "spark-shell semantic: spark's engine is not installed (llama-server), so the dialog keeps its word search" ] \
        && ok "no engine: no socket for the dialog, check says na, start refuses" || bad "semantic no engine" "d1=$d1 $(printf '%s\n' "$out" | grep semantic) st=$st $out3"
    printf 'x' >> "$M"; out=$(sh "$S" check 2>&1 || :); SPARK_SHELL_DIALOG=$H/stub-dialog sh "$S" dialog >/dev/null 2>&1 || :; d1=$(grep -cx -- --semantic "$HOME/dialog.argv" || :)
    printf '%s\n' "$out" | grep -qx 'FAIL   semantic     the model is not the one spark-shell pins -- spark-shell on' && [ "$d1" = 0 ] \
        && ok "a model changed since: check fails on it, and the dialog gets no socket (its size is not the pinned one)" || bad "semantic changed" "d1=$d1 $(printf '%s\n' "$out" | grep semantic)"
    cp "$H/model.gguf" "$M"
    rm -f "$H/.local/bin/spark"; without_tools "$H/nospark" spark
    out=$(PATH=$H/nospark sh "$S" check 2>&1 || :); PATH=$H/nospark SPARK_SHELL_DIALOG=$H/stub-dialog sh "$S" dialog >/dev/null 2>&1 || :; d1=$(grep -cx -- --semantic "$HOME/dialog.argv" || :)
    out3=$(printf 'n\n' | PATH=$H/nospark SPARK_SHELL_SEMANTIC_URL="file://$H/model.gguf" SPARK_SHELL_TEST_TTY=1 sh "$S" on desktop 2>&1 || :)
    printf '%s\n' "$out" | grep -qx 'ok     semantic     na (spark is not installed)' && [ "$d1" = 0 ] && ! printf '%s\n' "$out3" | grep -q '^  search ' \
        && ok "no spark: check says na, the dialog gets no socket, the warning names no model" || bad "semantic no spark" "d1=$d1 $(printf '%s\n' "$out" | grep semantic)"
    printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"; out=$(sh "$S" check 2>&1 || :)
    printf '%s\n' "$out" | grep -qx 'ok     semantic     na (no desktop)' && ok "check: no desktop, the search is na" || bad "semantic no desktop" "$(printf '%s\n' "$out" | grep semantic)"
    printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"; rm -f "$HOME/healthy"
    # off desktop: the server stopped, the model kept (as the dialog's binary is)
    rm -f "$HOME/engine.argv"; sh "$S" semantic start; upto "$HOME/engine.argv"; p3=$(cat "$PIDF" 2>/dev/null || :)
    out=$(sh "$S" off desktop --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -qx "would  semantic     stop the server of the dialog's search ($SOCK)" && [ -d "/proc/$p3" ] \
        && ok "off desktop --dry-run: the server would be stopped, it runs on" || bad "semantic off would" "$(printf '%s\n' "$out" | grep semantic)"
    out=$(sh "$S" off desktop 2>&1 || :)
    printf '%s\n' "$out" | grep -qx "ok     semantic     the server of the dialog's search stopped" && gone "$p3" && [ ! -e "$PIDF" ] && cmp -s "$M" "$H/model.gguf" \
        && ok "off desktop: the server stopped, the model kept" || bad "semantic off" "$(printf '%s\n' "$out" | grep semantic) pid=$p3"
    st=0; out=$(sh "$S" semantic nonsense 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = 'spark-shell semantic: start, stop or status: spark-shell semantic status' ] && ok "semantic WORD: anything but start, stop or status refused in one line" || bad "semantic word" "st=$st $out"
    sh "$S" semantic stop 2>/dev/null || :
fi

fi

# --- 23. the login screen: greetd on tty1, its own switch -----------------
if want 23; then
# on login writes the screen's root files under a throwaway root and
# hands tty1 to greetd at the next boot only: systemd enables and
# disables, never starts or stops; Void's line in rc.local runs
# login-boot before runit. A clone with a signed tag pins the stub
# dialog, as section 22 does. Every root tool is a stub that logs.
if [ "$(uname -s)" = Darwin ]; then
    fresh
    st=0; out=$(sh "$SH" on login --yes 2>&1) || st=$?
    [ "$st" -eq 1 ] && [ "$out" = "spark-shell login: not on macOS, which has its own login screen" ] && [ ! -e "$HOME/.config/spark-shell/config" ] \
        && ok "macOS: on login refuses in one line, nothing written" || bad "macOS on login" "st=$st $out"
else
    login_clone() {   # login_clone -- $C: this tree, a tag signed by a key in its allowed-signers, the stub dialog pinned and in place
        C=$H/clone; mkdir -p "$C"
        (cd "$REPO" && tar --exclude=.git --exclude=target --exclude=target2 -cf - .) | (cd "$C" && tar --no-same-owner -xf -)
        printf '#!/bin/sh\nexit 0\n' > "$H/stub-dialog"
        sha=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$H/stub-dialog"; else shasum -a 256 "$H/stub-dialog"; fi | cut -d' ' -f1)
        sed "s/^DIALOG_SHA256_X86_64_LINUX_MUSL=.*/DIALOG_SHA256_X86_64_LINUX_MUSL=$sha/" "$REPO/component/dialog/dialog.env" > "$C/component/dialog/dialog.env"
        ssh-keygen -q -t ed25519 -N '' -C '' -f "$H/key" >/dev/null
        printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$H/key.pub")" > "$C/allowed-signers"
        git -C "$C" -c user.name=test -c user.email=you@example.com -c gpg.format=ssh -c "user.signingkey=$H/key" init -q   # spark:allow-secret (a scratch key, made here)
        git -C "$C" add -A
        git -C "$C" -c user.name=test -c user.email=you@example.com commit -q -m fixture
        git -C "$C" -c user.name=test -c user.email=you@example.com -c gpg.format=ssh -c "user.signingkey=$H/key" tag -s v9.9 -m 'spark-shell v9.9'   # spark:allow-secret
        mkdir -p "$H/.local/share/spark-shell"; cp "$H/stub-dialog" "$H/.local/share/spark-shell/spark-dialog"; chmod 755 "$H/.local/share/spark-shell/spark-dialog"
    }
    LC() { PATH=$H/lx:$PATH sh "$C/spark-shell" "$@" </dev/null; }   # the clone as the uname stub says
    login_root() {   # login_root ID -- a root with greetd installed, its package config, its account
        fresh
        console_stubs Linux
        # Like the dialog fixture, this is an x86 package with a shell stub.
        printf '#!/bin/sh\ncase $1 in -m) echo x86_64 ;; -s) echo Linux ;; *) exec /usr/bin/uname "$@" ;; esac\n' > "$H/lx/uname"
        desktop_stubs
        printf 'ID=%s\n' "$1" > "$H/os-release"
        mkdir -p "$H/root/etc/greetd" "$H/root/usr/bin" "$H/root/usr/sbin"
        printf '[terminal]\nvt = 1\n# agreety, the package'"'"'s\n' > "$H/root/etc/greetd/config.toml"
        printf 'root:x:0:0::/root:/bin/sh\n_greeter:x:900:900::/var/lib/_greeter:/sbin/nologin\n_greetd:x:901:901::/var/lib/greetd:/bin/false\ngreetd:x:902:902::/var/lib/greetd:/sbin/nologin\ngreeter:x:903:903::/var/lib/greeter:/sbin/nologin\n' > "$H/root/etc/passwd"
        printf 'root:x:0:\n_seatd:x:990:\n' > "$H/root/etc/group"
        printf '#!/bin/sh\necho "visudo $*" >> "$HOME/log"\n! grep -q BAD "$2"\n' > "$H/lx/visudo"
        printf '#!/bin/sh\n[ "$2" = greetd ] && [ -e "$HOME/greetd-running" ]\n' > "$H/lx/pgrep"
        printf '#!/bin/sh\necho "usermod $*" >> "$HOME/log"\nsed "s/^%s:x:990:.*/&,$3/;s/:,/:/" "$SPARK_SHELL_ROOT/etc/group" > "$HOME/g" && cat "$HOME/g" > "$SPARK_SHELL_ROOT/etc/group"\n' '_seatd' > "$H/lx/usermod"
        printf '#!/bin/sh\necho "gpasswd $*" >> "$HOME/log"\nsed "s/^\\(_seatd:x:990:\\).*/\\1/" "$SPARK_SHELL_ROOT/etc/group" > "$HOME/g" && cat "$HOME/g" > "$SPARK_SHELL_ROOT/etc/group"\n' > "$H/lx/gpasswd"
        printf '#!/bin/sh\nexit 0\n' > "$H/lx/xbps-query"; printf '#!/bin/sh\necho "install ok installed"\n' > "$H/lx/dpkg-query"
        printf '#!/bin/sh\nexit 0\n' > "$H/lx/rpm"   # Fedora/openSUSE packages are installed in this fixture too
        chmod +x "$H/lx"/*
        login_clone
        : > "$H/log"
    }
    le=$H/root/etc/spark-shell/login   # moved by each fresh: set again below
    # Void: runit, the boot hook, the account in _seatd, sudoers for the power keys
    login_root void
    le=$H/root/etc/spark-shell/login; ll=$H/root/usr/local/lib/spark-shell
    mkdir -p "$H/root/etc/runit/runsvdir/default" "$H/root/etc/sv/greetd" "$H/root/etc/sv/agetty-tty1"
    ln -s /etc/sv/agetty-tty1 "$H/root/etc/runit/runsvdir/default/agetty-tty1"; : > "$H/root/usr/bin/greetd"
    out=$(LC on login --dry-run)
    printf '%s\n' "$out" | grep -q '^would  config       LOGIN=yes' && printf '%s\n' "$out" | grep -q "^would  login        write the login screen's files: session window run sway.conf foot.ini screens.conf spark-dialog config.toml sudoers login-boot (sudo)\$" \
        && [ ! -e "$le" ] && [ ! -e "$HOME/.config/spark-shell/config" ] && ok "Void: on login --dry-run says the config and the files, touches nothing" || bad "void login dry" "$out"
    st=0; out=$(LC on login --yes 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^LOGIN=yes$' "$HOME/.config/spark-shell/config" && ok "Void: on login writes LOGIN=yes" || bad "void login config" "st=$st $out"
    for f in session window run sway.conf foot.ini screens.conf; do [ -f "$le/$f" ] || bad "Void: on login: $f missing"; done
    [ -x "$le/session" ] && [ -x "$le/window" ] && [ -x "$le/run" ] && [ -x "$ll/spark-dialog" ] && [ -x "$ll/login-boot" ] && cmp -s "$ll/spark-dialog" "$H/stub-dialog" \
        && ok "Void: on login writes the screen's files, the pinned dialog copied for its account" || bad "void login files" "$(ls -la "$le" "$ll" 2>&1)"
    grep -qx 'include "/etc/spark-shell/login/screens.conf"' "$le/sway.conf" && [ -f "$le/screens.conf" ] && ! grep -q '^output ' "$le/screens.conf" \
        && ok "Void: the login's sway includes its own screens.conf, no screen placed yet (#116)" || bad "login screens empty" "$(grep -n include "$le/sway.conf"; cat "$le/screens.conf" 2>&1)"
    printf '%s\n' '# rendered by spark-shell: the screens' 'output "BOE 0x0BCA Unknown" position -1920 0' '# beside "BOE 0x0BCA Unknown" left-of "Lenovo Group Limited T24i-30 V30A1"' > "$HOME/.config/spark-shell/screens.conf"
    _o=$(LC check 2>&1 || :); printf '%s\n' "$_o" | grep -q '^FAIL   login        out of date: screens.conf -- spark-shell on login$' && ok "Void: check says the login's screens are out of date once a screen was placed" || bad "login screens check" "$(printf '%s\n' "$_o" | grep login)"
    _st=0; _o=$(LC on login --yes 2>&1) || _st=$?
    [ "$_st" -eq 0 ] && grep -qxF 'output "BOE 0x0BCA Unknown" position -1920 0' "$le/screens.conf" && ! grep -q beside "$le/screens.conf" \
        && ok "Void: on login writes your screens into the login's screens.conf, the output lines alone (#116)" || bad "login screens" "st=$_st $_o $(cat "$le/screens.conf" 2>&1)"
    grep -q '^user = "_greeter"$' "$H/root/etc/greetd/config.toml" && grep -q '^command = "/etc/spark-shell/login/session"$' "$H/root/etc/greetd/config.toml" && grep -q agreety "$H/root/etc/greetd/config.toml.spark-shell-orig" \
        && ok "Void: greetd's config.toml is ours (the session as _greeter), the package's kept" || bad "void greetd conf" "$(cat "$H/root/etc/greetd/config.toml")"
    grep -q -- '--desktop off --restart "/usr/bin/sudo -n /usr/bin/reboot" --shutdown "/usr/bin/sudo -n /usr/bin/poweroff"\( --spark-port [0-9]*\)\{0,1\}$' "$le/run" && grep -q '^export PANEL_BG=[0-9a-f]\{6\} ' "$le/run" \
        && ok "Void: the run file: no desktop yet, the power keys through sudo, the palette" || bad "void run" "$(cat "$le/run")"
    [ "$(cat "$H/root/etc/sudoers.d/spark-shell-login")" = "$(sed -n '$p' "$REPO/template/login/sudoers" | sed 's/@LOGIN_ACCOUNT@/_greeter/')" ] || [ "$(sed -n '$p' "$H/root/etc/sudoers.d/spark-shell-login")" = '_greeter ALL=(root) NOPASSWD: /usr/bin/reboot, /usr/bin/poweroff' ] \
        && grep -q '^visudo -cf ' "$H/log" && ok "Void: sudoers lets _greeter run reboot and poweroff only, checked by visudo first" || bad "void sudoers" "$(cat "$H/root/etc/sudoers.d/spark-shell-login" "$H/log")"
    grep -q '^_seatd:x:990:_greeter$' "$H/root/etc/group" && [ -e "$le/seatd.group" ] && ok "Void: _greeter joins _seatd, recorded" || bad "void seatd" "$(cat "$H/root/etc/group")"
    [ "$(cat "$le/boot")" = on ] && grep -q '/usr/local/lib/spark-shell/login-boot #spark-shell-login#$' "$H/root/etc/rc.local" \
        && [ -L "$H/root/etc/runit/runsvdir/default/agetty-tty1" ] && [ ! -e "$H/root/etc/runit/runsvdir/default/greetd" ] \
        && ok "Void: tty1 changes hands at the next boot (a line in rc.local), getty untouched now" || bad "void boot" "$(cat "$H/root/etc/rc.local" 2>&1; ls -la "$H/root/etc/runit/runsvdir/default")"
    printf '%s\n' "$out" | grep -q '^ok     login        the login screen takes tty1 from the next boot (tty2 keeps the console login)$' && ok "Void: one line says it" || bad "void line" "$out"
    out=$(LC on --dry-run); printf '%s\n' "$out" | grep -q '^Nothing to do$' && ok "Void: on again: Nothing to do" || bad "void login again" "$out"
    out=$(LC check 2>&1 || :); printf '%s\n' "$out" | grep -q '^ok     login        the login screen takes tty1 at boot, tty2 keeps the console login$' && ok "Void: check says the login screen is set up" || bad "void check" "$(printf '%s\n' "$out" | grep login)"
    out=$(LC status); printf '%s\n' "$out" | grep -q '^  login screen  *the login screen on tty1 from the next boot, the console login on tty2$' && ok "Void: status says from the next boot" || bad "void status" "$(printf '%s\n' "$out" | grep login)"
    # the boot: login-boot as rc.local runs it, its paths under the root
    sed "s|/etc/|$H/root/etc/|g" "$ll/login-boot" > "$H/boot.sh"
    sh "$H/boot.sh" && [ ! -e "$H/root/etc/runit/runsvdir/default/agetty-tty1" ] && [ "$(readlink "$H/root/etc/runit/runsvdir/default/greetd")" = "$H/root/etc/sv/greetd" ] && [ -e "$le/getty.off" ] && [ -e "$le/greetd.on" ] \
        && ok "Void: at boot greetd takes tty1 from its getty, each change recorded" || bad "void hook on" "$(ls -la "$H/root/etc/runit/runsvdir/default" "$le")"
    sh "$H/boot.sh" && [ -e "$le/greetd.on" ] && ok "Void: the hook at the next boot again changes nothing" || bad "void hook twice"
    : > "$HOME/greetd-running"
    out=$(LC status); printf '%s\n' "$out" | grep -q '^  login screen  *the login screen on tty1, the console login on tty2$' && ok "Void: status with greetd running" || bad "void status live" "$(printf '%s\n' "$out" | grep login)"
    # a new palette reaches the screen; a program the screen runs is put in place by a rename, so a running one (a link held here) keeps its old file
    ln "$le/run" "$H/run.held"
    palette_fixture other '#123456'; LC theme other >/dev/null 2>&1 || :
    grep -q '^export HEX_BG=282828 HEX_FG=ebdbb2 HEX_ACCENT=123456 ' "$le/run" && ok "Void: theme NAME writes the login screen's palette too" || bad "void theme follow" "$(grep HEX_BG "$le/run")"
    ! grep -q 'HEX_ACCENT=123456' "$H/run.held" && [ -x "$le/run" ] && [ -z "$(find "$le" "$ll" -name '*.spark-shell-new')" ] \
        && ok "Void: the screen's programs are replaced by a rename, never written over (Linux refuses a write to a running binary)" || bad "void swap" "$(ls -la "$le" "$ll")"
    rm -f "$H/run.held"
    # off login while greetd runs: the boot goes back, the files stay until it stopped
    out=$(LC off login 2>&1)
    grep -q '^LOGIN=no$' "$HOME/.config/spark-shell/config" && [ "$(cat "$le/boot")" = off ] && [ -f "$le/session" ] && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && grep -q '^_seatd:x:990:$' "$H/root/etc/group" \
        && printf '%s\n' "$out" | grep -q "^todo   login        the login screen runs until the next boot, then tty1 has the console login" \
        && ok "Void: off login with greetd running: the boot back, sudoers and the group gone, the screen's files kept" || bad "void off live" "$out $(ls "$le")"
    rm -f "$HOME/greetd-running"; sh "$H/boot.sh"
    [ -L "$H/root/etc/runit/runsvdir/default/agetty-tty1" ] && [ ! -e "$H/root/etc/runit/runsvdir/default/greetd" ] && [ ! -e "$le/getty.off" ] && [ ! -e "$le/greetd.on" ] \
        && ok "Void: at the next boot the hook gives tty1 back to getty" || bad "void hook off" "$(ls -la "$H/root/etc/runit/runsvdir/default")"
    out=$(LC off login 2>&1)
    [ ! -e "$le" ] && [ ! -e "$ll" ] && ! grep -q 'spark-shell-login' "$H/root/etc/rc.local" 2>/dev/null && grep -q agreety "$H/root/etc/greetd/config.toml" && [ ! -e "$H/root/etc/greetd/config.toml.spark-shell-orig" ] \
        && printf '%s\n' "$out" | grep -q "^ok     login        the console login is back on tty1 from the next boot, the login screen's files are gone (its package stays)$" \
        && ok "Void: off login after it: every file gone, the package's config.toml back" || bad "void off" "$out $(find "$H/root/etc/spark-shell" "$H/root/usr/local" 2>&1)"
    out=$(LC off login 2>&1); ! printf '%s\n' "$out" | grep -q '^\(ok\|todo\) *login' && ok "Void: off login twice: nothing left, nothing said" || bad "void off twice" "$out"
    # visudo refuses: nothing written
    sed 's|/usr/bin/reboot|BAD|' "$C/template/login/sudoers" > "$H/s" && cp "$H/s" "$C/template/login/sudoers"
    out=$(LC on login --yes 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^todo   login        visudo refused the sudoers file -- nothing written' && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && [ ! -e "$le/run" ] \
        && ok "Void: a sudoers file visudo refuses is never written, nor the rest" || bad "void visudo" "$out"
    # Debian: systemd enables and disables, never starts or stops; logind lets the screen restart and shut down
    login_root debian
    le=$H/root/etc/spark-shell/login; ll=$H/root/usr/local/lib/spark-shell
    mkdir -p "$H/root/run/systemd/system" "$H/root/units"; : > "$H/root/units/getty@tty1.service"; : > "$H/root/usr/sbin/greetd"
    mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    unset FONT; nf=$HOME/.local/share/fonts/monaspace-neon; mkdir -p "$nf"   # Monaspace Neon as on put it in your fonts, FONT the default
    for s in Regular Bold Italic BoldItalic; do printf 'face %s\n' "$s" > "$nf/MonaspaceNeon-$s.otf"; done
    st=0; out=$(LC on login --yes 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^user = "_greetd"$' "$H/root/etc/greetd/config.toml" && [ -e "$H/root/units/greetd.service" ] && [ ! -e "$H/root/units/getty@tty1.service" ] \
        && [ "$(grep -n 'enable greetd' "$H/log" | cut -d: -f1)" -lt "$(grep -n 'disable getty@tty1' "$H/log" | cut -d: -f1)" ] && ! grep -Eq '^systemctl (start|stop|restart|kill)' "$H/log" \
        && ok "Debian: greetd enabled before getty@tty1 is disabled, nothing started or stopped" || bad "debian login" "st=$st $out $(cat "$H/log")"
    lf=$H/root/usr/share/fonts/spark-shell
    cmp -s "$lf/MonaspaceNeon-Regular.otf" "$nf/MonaspaceNeon-Regular.otf" && cmp -s "$lf/MonaspaceNeon-BoldItalic.otf" "$nf/MonaspaceNeon-BoldItalic.otf" && [ "$(ls "$lf" | wc -l | tr -d ' ')" = 4 ] \
        && grep -qxF "fc-cache -f $lf" "$H/fc.log" && grep -qx 'font=Monaspace Neon:size=11,DejaVu Sans Mono:size=11' "$le/foot.ini" \
        && ok "Debian: the login screen's account gets its own copy of Monaspace Neon under /usr/share/fonts (it cannot read your fonts), and its foot the same font" || bad "login font copy" "$(ls -la "$lf" 2>&1; cat "$H/fc.log" 2>&1; grep -n '^font' "$le/foot.ini")"
    out=$(LC check 2>&1 || :); printf '%s\n' "$out" | grep -q '^ok     login ' && ok "Debian: check's login row is ok with the copy in place" || bad "login font check" "$(printf '%s\n' "$out" | grep login)"
    [ -e "$le/greetd.on" ] && [ -e "$le/getty.off" ] && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && [ ! -e "$ll/login-boot" ] && ! grep -q usermod "$H/log" \
        && grep -q -- '--desktop on --restart "/usr/bin/systemctl reboot" --shutdown "/usr/bin/systemctl poweroff"\( --spark-port [0-9]*\)\{0,1\}$' "$le/run" \
        && ok "Debian: no sudoers, no boot hook, no group; the power keys are systemctl's; the desktop offered" || bad "debian extras" "$(cat "$le/run"; ls "$le")"
    out=$(LC off login 2>&1)
    [ -e "$H/root/units/getty@tty1.service" ] && [ ! -e "$H/root/units/greetd.service" ] && [ "$(grep -n 'enable getty@tty1' "$H/log" | cut -d: -f1)" -lt "$(grep -n 'disable greetd' "$H/log" | cut -d: -f1)" ] \
        && [ ! -e "$le" ] && grep -q agreety "$H/root/etc/greetd/config.toml" && ok "Debian: off login: getty@tty1 enabled first, greetd disabled, the files gone" || bad "debian off" "$out $(cat "$H/log")"
    [ ! -e "$lf" ] && [ -f "$nf/MonaspaceNeon-Regular.otf" ] && ok "Debian: off login removes the login screen's copy of the font; yours stays" || bad "login font off" "$(ls -la "$lf" "$nf" 2>&1)"
    # Fedora: systemd as Debian, the account greetd's package makes is greetd; openSUSE: greeter
    login_root fedora
    le=$H/root/etc/spark-shell/login; ll=$H/root/usr/local/lib/spark-shell
    mkdir -p "$H/root/run/systemd/system" "$H/root/units"; : > "$H/root/units/getty@tty1.service"; : > "$H/root/usr/bin/greetd"
    st=0; out=$(LC on login --yes 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^user = "greetd"$' "$H/root/etc/greetd/config.toml" && [ -e "$H/root/units/greetd.service" ] && [ ! -e "$H/root/units/getty@tty1.service" ] \
        && [ ! -e "$ll/login-boot" ] && [ ! -e "$H/root/etc/sudoers.d/spark-shell-login" ] && ! grep -q usermod "$H/log" \
        && ok "Fedora: the login screen as the greetd account, systemd's switch, no runit file, no sudoers, no group" || bad "fedora login" "st=$st $out $(cat "$H/log")"
    out=$(LC check 2>&1 || :); printf '%s\n' "$out" | grep -q '^ok     login        the login screen takes tty1 at boot, tty2 keeps the console login$' && ok "Fedora: check says the login screen is set up" || bad "fedora check" "$(printf '%s\n' "$out" | grep login)"
    login_root opensuse
    mkdir -p "$H/root/run/systemd/system" "$H/root/units"; : > "$H/root/units/getty@tty1.service"; : > "$H/root/usr/bin/greetd"
    st=0; out=$(LC on login --yes 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -q '^user = "greeter"$' "$H/root/etc/greetd/config.toml" && [ -e "$H/root/units/greetd.service" ] && ok "openSUSE: the login screen as the greeter account" || bad "opensuse login" "st=$st $out"
    # a family the screen does not know, and no greetd yet
    login_root fixture
    out=$(LC on login --yes 2>&1 || :); printf '%s\n' "$out" | grep -q '^todo   login        the login screen knows Debian, Ubuntu, Arch, Void, Fedora and openSUSE$' && ok "an unknown family: a todo row, nothing written" || bad "login unknown" "$out"
    login_root void; mkdir -p "$H/root/etc/runit"
    out=$(LC on login --yes 2>&1 || :); printf '%s\n' "$out" | grep -q '^todo   login        greetd is not installed -- spark-shell on login (the packages)$' && [ ! -e "$H/root/etc/spark-shell" ] && ok "Void without greetd: a todo row, nothing written" || bad "login no greetd" "$out"
fi
[ "$(grep -h '^PKG_LOGIN=' "$REPO"/distro/*.env | sort -u)" = 'PKG_LOGIN=greetd swayidle' ] && grep -q '^LOGIN_ACCOUNT=_greeter$' "$REPO/distro/void.env" && grep -q '^LOGIN_ACCOUNT=greeter$' "$REPO/distro/arch.env" && grep -q '^LOGIN_ACCOUNT=greetd$' "$REPO/distro/fedora.env" && grep -q '^LOGIN_ACCOUNT=greeter$' "$REPO/distro/opensuse.env" && grep -q '^LOGIN_ACCOUNT=_greetd$' "$REPO/distro/debian.env" \
    && ok "distro/*.env: greetd, swayidle and each package's account for the login screen" || bad "distro login keys"
keys_bad=''
for f in "$REPO"/distro/*.env; do
    [ "$(grep -o '^[A-Z_]*=' "$f" | sort | paste -sd' ' -)" = 'LOGIN_ACCOUNT= PKG_CLI= PKG_CONSOLE= PKG_DESKTOP= PKG_LOGIN= PKG_SHELL= PKG_SOUND= PM=' ] || keys_bad="$keys_bad ${f##*/}"
    grep -q '^PKG_DESKTOP=.*\(librsvg\|rsvg-convert\)' "$f" || keys_bad="$keys_bad ${f##*/}:rsvg"
done
[ -z "$keys_bad" ] && [ "$(ls "$REPO"/distro/*.env | wc -l | tr -d ' ')" = 5 ] && ok "distro/*.env: five families, the same eight keys in each, every desktop list with rsvg-convert's package" || bad "distro keys" "$keys_bad"
! grep -v '^#' "$REPO/template/login/sway.conf" | grep -q fullscreen && grep -q '^gaps outer 0$' "$REPO/template/login/sway.conf" && grep -q '^alpha=0.0$' "$REPO/template/login/foot.ini" \
    && ok "template/login: the window fills the screen tiled, never fullscreen (foot draws a fullscreen background solid), clear over the wallpaper" || bad "login sway fullscreen"
sw=$(grep '^exec swayidle ' "$REPO/template/login/sway.conf"); [ "$sw" = "exec swayidle timeout 300 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"'" ] \
    && ok "template/login: five idle minutes turn the display off, a key or a move turns it on" || bad "login swayidle" "$(grep -n swayidle "$REPO/template/login/sway.conf")"
# the session says nothing on tty1: the console cleared and its cursor hidden, then what sway and its children say lands in login.log
ls_d=$(tmpd); mkdir -p "$ls_d/bin" "$ls_d/run"
printf '#!/bin/sh\necho "sway $*"\necho "[main.c:332] Found config * for output" >&2\n' > "$ls_d/bin/sway"; chmod +x "$ls_d/bin/sway"
sed 's|@LOGIN_ETC@|etc/spark-shell/login|g' "$REPO/template/login/session" > "$ls_d/session"
out=$(PATH="$ls_d/bin:$PATH" XDG_RUNTIME_DIR="$ls_d/run" sh "$ls_d/session" 2>&1)
[ "$out" = "$(printf '\033[2J\033[H\033[?25l')" ] && grep -qx 'sway -c /etc/spark-shell/login/sway.conf' "$ls_d/run/login.log" && grep -q 'Found config' "$ls_d/run/login.log" \
    && ok "template/login/session: tty1 is cleared, its cursor hidden, and sway's words go to login.log, none on the screen" || bad "login session quiet" "$(printf '%s' "$out" | od -c | head -3) $(cat "$ls_d/run/login.log" 2>&1)"
rm -rf "$ls_d"
# the login window opens on the main screen (#116): the screen at 0 0 is focused before foot opens it
lw_d=$(tmpd); mkdir -p "$lw_d/bin"
lw_etc=${lw_d#/}/etc/spark-shell/login   # the script reads /@LOGIN_ETC@/screens.conf: a scratch path, never the machine's own
printf '#!/bin/sh\necho "foot $*" >> "%s/log"\n' "$lw_d" > "$lw_d/bin/foot"
cat > "$lw_d/bin/swaymsg" <<EOF
#!/bin/sh
case "\$*" in
    '-t get_outputs') echo '[{"name":"DP-3","active":true,"rect":{"x":-1920,"y":0}},{"name":"HDMI-A-1","active":true,"rect":{"x":0,"y":0}}]' ;;
    *) echo "swaymsg \$*" >> "$lw_d/log" ;;
esac
EOF
chmod +x "$lw_d/bin/foot" "$lw_d/bin/swaymsg"
sed "s|@LOGIN_ETC@|$lw_etc|g" "$REPO/template/login/window" > "$lw_d/window"
PATH="$lw_d/bin:$PATH" sh "$lw_d/window" >/dev/null 2>&1
[ "$(cat "$lw_d/log")" = "$(printf 'swaymsg focus output HDMI-A-1\nfoot -c /%s/foot.ini -a spark-login /%s/run\nswaymsg exit' "$lw_etc" "$lw_etc")" ] \
    && ok "template/login/window: the screen at 0 0 is focused first, so the login opens on the main screen; then sway ends with the window (#116)" || bad "login window main screen" "$(cat "$lw_d/log" 2>&1)"
rm -rf "$lw_d"
bp=$REPO/template/linux/.bash_profile
grep -q 'SPARK_SHELL_SESSION:-}" != shell' "$bp" && ok ".bash_profile: the login screen's shell session never starts the desktop" || bad ".bash_profile shell session"

fi

# --- 24. the theme end to end (#24): one choice brings the rest, saved and tracked like layouts, from a picture and from words
if want 24; then
# On a Mac the palette reaches Terminal.app through the helper: here it builds and prints, never touching Terminal.app (SPARK_SHELL_NO_APPLY), with Menlo pinned as installed
fresh
desktop_stubs
export SPARK_SHELL_NO_APPLY=1 SPARK_SHELL_MAC_FONTS=Menlo-Regular
SEP=$(printf '\302\267')
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
cfg=$HOME/.config/spark-shell/config; st_dir=$HOME/.local/state/spark-shell; th_dir=$HOME/.config/spark-shell/themes
# every shipped SVG names the role of every color it uses on its second line, so a drawing can be drawn again in any palette
_rb=''
for f in "$REPO"/gallery/wallpaper/*.svg; do
    n=${f##*/}; n=${n%.svg}
    sed -n 2p "$f" | grep -q '^<!-- roles: .* -->$' || { _rb="$_rb $n:line"; continue; }
    for c in $(grep -o '#[0-9a-fA-F]\{6\}' "$f" | sort -u); do sed -n 2p "$f" | grep -q "$c " || _rb="$_rb $n:$c"; done
    sed -n 2p "$f" | tr ';' '\n' | sed 's/^ *//; s/ -->$//; s/^<!-- roles: //' | awk '$2 !~ /^(bg|fg|accent|muted|ansi_[0-9]+|black|white)(\+(bg|fg|accent|muted|ansi_[0-9]+|black|white):[0-9]+)?$/ {exit 1}' || _rb="$_rb $n:role"
done
[ -z "$_rb" ] && ok "gallery/wallpaper/: every SVG names the role of every color it uses on its second line, a role or a mix of two" || bad "svg roles" "$_rb"
sh "$SH" on --yes >/dev/null 2>&1
# the kept kinds: theme save makes a folder, theme list shows it, theme NAME brings it back, the history keeps the last ten, back steps through them
sh "$SH" theme nord >/dev/null 2>&1
rc=0; out=$(sh "$SH" theme save 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: save NAME -- a name for this look' ] && ok "theme save (bare) on a palette: a name is asked for in one line" || bad "theme save bare" "rc=$rc $out"
rc=0; out=$(sh "$SH" theme save nord 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = "spark-shell theme: nord is a palette's name -- give the theme another" ] && ok "theme save nord: a palette's name is refused" || bad "theme save palette name" "rc=$rc $out"
_te=$(cksum < "$HOME/.config/spark/theme.env")
out=$(sh "$SH" theme save Winter Desk 2>&1)
[ "$(printf '%s\n' "$out" | sed -n 1p)" = "saved winter-desk ($th_dir/winter-desk) -- spark-shell theme winter-desk brings the look back" ] && [ -f "$th_dir/winter-desk/palette.env" ] && cmp -s "$th_dir/winter-desk/palette.env" "$REPO/gallery/theme/nord.env" \
    && grep -qx 'PALETTE=nord' "$th_dir/winter-desk/look.env" && grep -qx "WALLPAPER=$([ "$(uname -s)" = Darwin ] && echo default || echo fjord)" "$th_dir/winter-desk/look.env" && [ "$(sed -n 1p "$th_dir/winter-desk/look.env")" = FORMAT=2 ] && grep -qx 'TEXT_SIZE=12' "$th_dir/winter-desk/look.env" && ! grep -q '^FACE=\|^FONT=' "$th_dir/winter-desk/look.env" && grep -qx 'ALPHA=0.95' "$th_dir/winter-desk/look.env" \
    && grep -qx 'THEME=winter-desk' "$cfg" \
    && ok "theme save WORDS: a folder named by the words with the palette and the look (format 2: the size, and no face for a face of your own), the theme in use now, said in one line" || bad "theme save" "$out $(ls "$th_dir" 2>&1; cat "$th_dir/winter-desk/look.env" 2>&1)"
[ "$(printf '%s\n' "$out" | grep -c '')" = 1 ] && [ "$_te" = "$(cksum < "$HOME/.config/spark/theme.env")" ] && [ "$(sed -n 1p "$st_dir/theme.history" | cut -f2)" = winter-desk ] \
    && ok "theme save: the look on the screen is the one kept, so nothing is drawn or written again (theme.env as it was, no terminal repainted); first in the history (#196)" || bad "theme save no apply" "$out"
out=$(sh "$SH" theme list)
printf '%s\n' "$out" | grep -q "^Saved themes (folders in $th_dir):$" && printf '%s\n' "$out" | grep -q "^  winter-desk  *nord $SEP $([ "$(uname -s)" = Darwin ] && echo default || echo fjord), current$" && printf '%s\n' "$out" | grep -q '^  nord  *fjord$' && printf '%s\n' "$out" | grep -q '^  tokyonight-night  *skyline$' \
    && printf '%s\n' "$out" | grep -q '^The last looks (spark-shell theme back steps through them):$' && [ "$(printf '%s\n' "$out" | grep -c '^  winter-desk  *today ')" = 1 ] && printf '%s\n' "$out" | grep -q '^  nord  *today ' \
    && ok "theme list: the saved themes first with the palette and the wallpaper each holds, the palettes with the drawing made for each, then the last looks with the time" || bad "theme list" "$out"
sh "$SH" theme tokyonight-night >/dev/null 2>&1
[ "$(cut -f2 "$st_dir/theme.history" | paste -sd ' ' -)" = 'tokyonight-night winter-desk nord' ] && ok "the history: the last applied first, one line a look, EPOCH then the name" || bad "history" "$(cat "$st_dir/theme.history")"
out=$(sh "$SH" theme back 2>&1); grep -qx 'THEME=winter-desk' "$cfg" && [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'back to winter-desk' ] && ok "theme back: the look before this one, said first; the history stays as it was" || bad "theme back" "$out $(grep THEME= "$cfg")"
out=$(sh "$SH" theme back 2>&1); grep -qx 'THEME=nord' "$cfg" && [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'back to nord' ] && [ "$(cut -f2 "$st_dir/theme.history" | paste -sd ' ' -)" = 'tokyonight-night winter-desk nord' ] && ok "theme back again: one step further, the history still the same three" || bad "theme back twice" "$out"
rc=0; out=$(sh "$SH" theme back 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: no look before this one in the last ten' ] && ok "theme back at the end: refused in one line" || bad "theme back end" "rc=$rc $out"
sh "$SH" theme dracula >/dev/null 2>&1
[ "$(cut -f2 "$st_dir/theme.history" | paste -sd ' ' -)" = 'dracula tokyonight-night winter-desk nord' ] && [ ! -f "$st_dir/theme.history.back" ] && ok "a new choice goes on top and starts the steps over" || bad "history after back" "$(cat "$st_dir/theme.history")"
for n in 1 2 3 4 5 6 7 8; do sh "$SH" theme nord >/dev/null 2>&1; sh "$SH" theme dracula >/dev/null 2>&1; done
[ "$(grep -c '' "$st_dir/theme.history")" = 4 ] && [ "$(cut -f2 "$st_dir/theme.history" | paste -sd ' ' -)" = 'dracula nord tokyonight-night winter-desk' ] && ok "the same look again moves up, never twice in the list" || bad "history dedup" "$(cat "$st_dir/theme.history")"
sh "$SH" theme save undo-196 >/dev/null 2>&1; sh "$SH" theme winter-desk >/dev/null 2>&1
mcp theme "$(call 1 theme_delete '{"name":"undo-196"}')"
ans 1 | jq -e '.result.isError == false and (.result.structuredContent | has("undo") | not)' >/dev/null && [ ! -d "$th_dir/undo-196" ] \
    && ok "provide theme_delete: the saved theme gone and no undo offered, where its undo once put the palette in use on again (#196)" || bad "theme delete undo" "$(cat "$H/mcp.out" | head -c 400)"
rc=0; out=$(sh "$SH" theme delete nord 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: nord is a palette spark-shell ships, not a saved theme' ] && ok "theme delete nord: a shipped palette is refused" || bad "theme delete shipped" "rc=$rc $out"
sh "$SH" theme winter-desk >/dev/null 2>&1
rc=0; out=$(sh "$SH" theme delete winter-desk 2>&1 </dev/null) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: winter-desk is the theme in use -- spark-shell theme NAME another first' ] && ok "theme delete of the theme in use: refused in one line" || bad "theme delete in use" "rc=$rc $out"
sh "$SH" theme dracula >/dev/null 2>&1
out=$(sh "$SH" theme delete winter-desk </dev/null 2>&1)
[ "$out" = 'deleted winter-desk' ] && [ ! -e "$th_dir/winter-desk" ] && ! grep -q 'winter-desk' "$st_dir/theme.history" && ok "theme delete NAME: the folder and its history lines gone, one line" || bad "theme delete" "$out $(ls "$th_dir"; cat "$st_dir/theme.history")"
rc=0; out=$(sh "$SH" theme delete winter-desk 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: no saved theme named winter-desk -- spark-shell theme list shows them' ] && ok "theme delete of nothing: refused in one line" || bad "theme delete none" "rc=$rc $out"
# the text size and the transparency, one number each; the pointer follows the text
out=$(sh "$SH" theme text); [ "$out" = "text 12 $SEP the pointer 24 pixels" ] && ok "theme text (bare): the size and the pointer's pixels" || bad "theme text bare" "$out"
out=$(sh "$SH" theme text 16); [ "$out" = "text at 16 $SEP new windows and the bar take it; the pointer 32 pixels" ] && grep -qx 'FONT=DejaVu Sans Mono:size=16' "$cfg" && ok "theme text 16: FONT's size, the pointer 32 from 14 points" || bad "theme text 16" "$out $(grep FONT "$cfg")"
rc=0; out=$(sh "$SH" theme text 99 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: text takes a size, 6 to 40, or bigger or smaller' ] && grep -qx 'FONT=DejaVu Sans Mono:size=16' "$cfg" && ok "theme text 99: refused in one line, FONT kept" || bad "theme text 99" "rc=$rc $out"
out=$(sh "$SH" theme text smaller); [ "$out" = "text at 15 $SEP new windows and the bar take it; the pointer 32 pixels" ] && ok "theme text smaller: one point less" || bad "theme text smaller" "$out"
sh "$SH" theme text 12 >/dev/null
out=$(sh "$SH" theme transparency); [ "$out" = 'transparency 5%' ] && ok "theme transparency (bare): the percent" || bad "transparency bare" "$out"
out=$(sh "$SH" theme transparency 30); [ "$out" = "transparency at 30%" ] && grep -qx 'ALPHA=0.7' "$cfg" && ok "theme transparency 30: ALPHA 0.7" || bad "transparency 30" "$out $(grep ALPHA "$cfg")"
out=$(sh "$SH" theme transparency 0); [ "$out" = 'transparency off' ] && grep -qx 'ALPHA=1.0' "$cfg" && ok "theme transparency 0: off, ALPHA 1.0" || bad "transparency 0" "$out $(grep ALPHA "$cfg")"
rc=0; out=$(sh "$SH" theme transparency 60 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: transparency takes a percent, 0 to 50, or more or less' ] && ok "theme transparency 60: refused in one line" || bad "transparency 60" "rc=$rc $out"
sh "$SH" theme transparency 15 >/dev/null
# the palette math: lib/look.py makes a palette from words, every rule kept; a picture read by its colors (a PNG, with no gdk-pixbuf needed)
if command -v python3 >/dev/null 2>&1; then
    cr() { python3 -c '
import sys
def rgb(h): h=h.lstrip("#"); return tuple(int(h[i:i+2],16) for i in (0,2,4))
def lum(c):
    def ch(v):
        v/=255.0; return v/12.92 if v<=0.03928 else ((v+0.055)/1.055)**2.4
    r,g,b=c; return 0.2126*ch(r)+0.7152*ch(g)+0.0722*ch(b)
x,y=sorted([lum(rgb(sys.argv[1])),lum(rgb(sys.argv[2]))],reverse=True); print("%.2f" % ((x+0.05)/(y+0.05)))' "$1" "$2"; }
    python3 -I "$REPO/lib/look.py" words --hue blue --warmth cool --contrast normal --light dark > "$H/words.env"
    [ "$(grep -c '^THEME_' "$H/words.env")" = 20 ] && [ "$(sed -n 's/^THEME_BG=//p' "$H/words.env" | cut -c1-1)" = '#' ] \
        && awk -v f="$(cr "$(sed -n 's/^THEME_FG=//p' "$H/words.env")" "$(sed -n 's/^THEME_BG=//p' "$H/words.env")")" 'BEGIN { exit !(f >= 7) }' \
        && awk -v a="$(cr "$(sed -n 's/^THEME_ACCENT=//p' "$H/words.env")" "$(sed -n 's/^THEME_BG=//p' "$H/words.env")")" -v r="$(cr "$(sed -n 's/^THEME_ANSI_1=//p' "$H/words.env")" "$(sed -n 's/^THEME_BG=//p' "$H/words.env")")" 'BEGIN { exit !(a >= 3 && r >= 3) }' \
        && ok "look.py words: twenty keys, the text at 7 to 1 on the background, the accent and the red at 3 to 1" || bad "look.py words" "$(cat "$H/words.env")"
    python3 -I "$REPO/lib/look.py" words --hue blue --warmth cool --contrast normal --light light > "$H/light.env"
    awk -v l="$(python3 -c 'import sys; h=sys.argv[1].lstrip("#"); print(sum(int(h[i:i+2],16) for i in (0,2,4)))' "$(sed -n 's/^THEME_BG=//p' "$H/light.env")")" 'BEGIN { exit !(l > 600) }' && ok "look.py words --light light: a light background" || bad "look.py light" "$(sed -n 's/^THEME_BG=//p' "$H/light.env")"
    rc=0; out=$(python3 -I "$REPO/lib/look.py" words --hue mauve --warmth cool --contrast normal --light dark 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'a hue is one of red, orange, yellow, green, teal, blue, violet, pink, grey; the accent one of them or same' ] && ok "look.py words: a hue off the list is refused in one line" || bad "look.py hue" "rc=$rc $out"
    # a small PNG written here: 8 by 8, two colors, no zlib tricks; its palette is light (white wins) and its accent the orange
    python3 - "$H/pic.png" <<'EOF'
import struct, sys, zlib
w = h = 8
rows = b""
for y in range(h):
    rows += b"\x00" + b"".join((b"\xff\xff\xff" if (x + y) % 3 else b"\xf0\x80\x10") for x in range(w))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
open(sys.argv[1], "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
EOF
    python3 -I "$REPO/lib/look.py" palette "$H/pic.png" > "$H/pic.env" 2>"$H/pic.err"
    [ "$(grep -c '^THEME_' "$H/pic.env")" = 20 ] && awk -v l="$(python3 -c 'import sys; h=sys.argv[1].lstrip("#"); print(sum(int(h[i:i+2],16) for i in (0,2,4)))' "$(sed -n 's/^THEME_BG=//p' "$H/pic.env")")" 'BEGIN { exit !(l > 600) }' \
        && ok "look.py palette PNG: the picture read by its own decoder, a light palette from a light picture" || bad "look.py palette" "$(cat "$H/pic.err" "$H/pic.env")"
    mkdir -p "$HOME/pictures"; cp "$H/pic.png" "$HOME/pictures/sunny.png"
    out=$(SPARK_SHELL_NO_THUMB=1 SPARK_SHELL_NO_SVG=1 sh "$SH" theme picture ~/pictures/sunny.png 2>&1)
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'a theme from sunny.png: sunny -- spark-shell theme save NAME keeps it, theme back returns' ] && [ -f "$st_dir/looks/sunny/palette.env" ] && [ -f "$st_dir/looks/sunny/sunny.png" ] \
        && grep -qx 'PALETTE=picture' "$st_dir/looks/sunny/look.env" && grep -qx 'WALLPAPER=picture' "$st_dir/looks/sunny/look.env" && grep -qx 'THEME=sunny' "$cfg" && grep -qx "WALLPAPER=$st_dir/looks/sunny/sunny.png" "$cfg" \
        && [ "$(sed -n 1p "$st_dir/theme.history" | cut -f2)" = sunny ] \
        && ok "theme picture PATH: a look under the picture's name with the palette and the picture, the picture the wallpaper, applied, first in the history" || bad "theme picture" "$out $(ls -R "$st_dir/looks" 2>&1; grep 'THEME\|WALLPAPER' "$cfg")"
    out=$(sh "$SH" theme save 2>&1 | sed -n 1p)
    [ "$out" = "saved sunny ($th_dir/sunny) -- spark-shell theme sunny brings the look back" ] && [ -f "$th_dir/sunny/sunny.png" ] && grep -qx 'PICTURE=sunny.png' "$th_dir/sunny/look.env" && grep -qx "WALLPAPER=$th_dir/sunny/sunny.png" "$cfg" \
        && ok "theme save (bare) on a look: kept under its own name, the picture copied into the folder, the wallpaper now the folder's copy" || bad "theme save look" "$out $(ls "$th_dir/sunny" 2>&1; grep WALLPAPER "$cfg")"
    # a theme from a picture picks every part too (#247, arc 4): the face, the family and the animation the words asked for, else
    # the face and the family in use and the animation the colors suggest; a pick off its list refused in one line
    cp "$cfg" "$H/cfg.picks"; cp "$H/pic.png" "$HOME/pictures/meadowpic.png"
    out=$(SPARK_SHELL_NO_THUMB=1 SPARK_SHELL_NO_SVG=1 sh "$SH" theme picture "$HOME/pictures/meadowpic.png" face=radon family=star animation=moon 2>&1)
    [ "$(sed -n 1p "$st_dir/looks/meadowpic/look.env")" = FORMAT=2 ] && grep -qx 'FACE=radon' "$st_dir/looks/meadowpic/look.env" && grep -qx 'GLYPH_FAMILY=star' "$st_dir/looks/meadowpic/look.env" && grep -qx 'ANIMATION=moon' "$st_dir/looks/meadowpic/look.env" \
        && grep -qx 'GLYPH_FAMILY=star' "$cfg" && grep -q '^FONT=Monaspace Radon:' "$cfg" && grep -qx 'DIALOG_ANIMATION=moon' "$cfg" \
        && ok "theme picture PATH face= family= animation=: the look takes the picks, format 2, and the desktop wears them (#247)" || bad "theme picture picks" "$out $(cat "$st_dir/looks/meadowpic/look.env" 2>&1)"
    rc=0; out=$(sh "$SH" theme picture "$HOME/pictures/meadowpic.png" family=runes 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: family takes stone, star or banner' ] && ok "theme picture with a pick off its list: refused in one line (#247)" || bad "theme picture pick off" "rc=$rc $out"
    sed -i.bak '/^DIALOG_ANIMATION=/d' "$cfg"; rm -f "$cfg.bak"
    out=$(SPARK_SHELL_NO_THUMB=1 SPARK_SHELL_NO_SVG=1 sh "$SH" theme picture "$HOME/pictures/meadowpic.png" 2>&1); _pa=$(sed -n 's/^ANIMATION=//p' "$st_dir/looks/meadowpic/look.env")
    case $_pa in moon|ripple|tide|embers|sun|flight) grep -qx 'GLYPH_FAMILY=star' "$st_dir/looks/meadowpic/look.env" && ok "theme picture with no picks: the family in use, the animation the colors suggest ($_pa) (#247)" || bad "theme picture no picks" "$(cat "$st_dir/looks/meadowpic/look.env")" ;;
        *) bad "theme picture no picks" "$out $(cat "$st_dir/looks/meadowpic/look.env" 2>&1)" ;; esac
    cp "$H/cfg.picks" "$cfg"; sh "$SH" theme sunny >/dev/null 2>&1
    rc=0; out=$(sh "$SH" theme picture /etc/hosts 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a picture comes from under your home' ] && ok "theme picture: a file outside home is refused in one line" || bad "theme picture outside" "rc=$rc $out"
    printf 'x' > "$HOME/pictures/a&b.jpg"; cp "$cfg" "$H/cfg.before"
    if [ "$(uname -s)" != Darwin ]; then   # the wallpaper is the desktop's: a Mac refuses it before the path is read
        rc=0; out=$(sh "$SH" theme wallpaper "$HOME/pictures/a&b.jpg" 2>&1) || rc=$?
        [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a path with one of ; ` $ ( ) | & < >, a quote, a backslash or a control character cannot be a wallpaper -- rename the picture' ] && cmp -s "$cfg" "$H/cfg.before" \
            && ok "theme wallpaper PATH with a character the config refuses: one line, the config untouched (it would refuse the next read)" || bad "wallpaper path chars" "rc=$rc $out"
        printf 'x' > "$HOME/pictures/a\"b.jpg"; rc=0; out=$(sh "$SH" theme wallpaper "$HOME/pictures/a\"b.jpg" 2>&1) || rc=$?
        [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a path with one of ; ` $ ( ) | & < >, a quote, a backslash or a control character cannot be a wallpaper -- rename the picture' ] && cmp -s "$cfg" "$H/cfg.before" \
            && ok "theme wallpaper PATH with a double quote: refused, since sway reads the path inside quotes (#61)" || bad "wallpaper quote" "rc=$rc $out"
    fi
    rc=0; out=$(sh "$SH" theme picture "$HOME/pictures/a&b.jpg" 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a path with one of ; ` $ ( ) | & < >, a quote, a backslash or a control character cannot be a wallpaper -- rename the picture' ] && cmp -s "$cfg" "$H/cfg.before" \
        && ok "theme picture PATH with such a character: the same line, nothing written" || bad "picture path chars" "rc=$rc $out"
    nl='
'   # a new line; $(printf '\n') would be nothing, command substitution drops it
    printf 'x' > "$HOME/pictures/two${nl}lines.jpg"; rc=0; out=$(sh "$SH" theme picture "$HOME/pictures/two${nl}lines.jpg" 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a path with one of ; ` $ ( ) | & < >, a quote, a backslash or a control character cannot be a wallpaper -- rename the picture' ] && cmp -s "$cfg" "$H/cfg.before" \
        && ok "theme picture PATH with a new line in it: refused, never a second line of the config (#61)" || bad "picture path newline" "rc=$rc $out"
    # a saved theme from elsewhere (#61): its look.env is held to the config's shapes before anything changes, every key
    bent() {   # bent KEY=VALUE -- a copy of sunny named bent, that one line of its look.env in place of its own
        rm -rf "$th_dir/bent"; cp -R "$th_dir/sunny" "$th_dir/bent"
        grep -v "^${1%%=*}=" "$th_dir/sunny/look.env" > "$th_dir/bent/look.env"; printf '%s\n' "$1" >> "$th_dir/bent/look.env"
    }
    bent_refused() {   # bent_refused WHY WHAT -- theme bent refused with WHY, the config and the screen as they were
        rm -f "$H/pwned"; rc=0; out=$(sh "$SH" theme bent 2>&1) || rc=$?
        [ "$rc" = 1 ] && [ "$out" = "spark-shell theme: bent cannot be used: $1. Nothing was changed" ] && cmp -s "$cfg" "$H/cfg.before" && [ ! -e "$H/pwned" ] \
            && ok "theme folder (#61): $2" || bad "theme folder: $2" "rc=$rc $out"
    }
    bent "FONT=x' -e touch $H/pwned '"; bent_refused 'its FONT is not a face and a size (letters, digits, spaces and : = . + _ -)' "a FONT with a quote is refused (the idle screen's sh -c)"
    bent "FONT=Monaspace Neon:size=11, exec touch $H/pwned"; bent_refused 'its FONT is not a face and a size (letters, digits, spaces and : = . + _ -)' "a FONT with a comma is refused (a second sway command in the bar's font)"
    bent 'WALLPAPER=/tmp/a".png'; bent_refused "its WALLPAPER is not default, a drawing's name, #rrggbb or a picture's full path with none of ; \` \$ ( ) | & < >, no quote, no backslash, no control character" "a WALLPAPER with a quote is refused (sway's output bg line)"
    bent 'PICTURE=../../../etc/hosts'; bent_refused 'its PICTURE is not a file name in the folder' "a PICTURE outside the folder is refused"
    bent 'PICTURE=link.png'; ln -s "$HOME/pictures/sunny.png" "$th_dir/bent/link.png"; bent_refused "its PICTURE is not a file of the folder's own" "a PICTURE that is a link is refused"
    bent "POINTER=spark-white 24, exec touch $H/pwned"; bent_refused "its POINTER is not a cursor theme's NAME and SIZE" "a POINTER with a comma is refused (seat xcursor_theme)"
    bent 'ALPHA=2'; bent_refused 'its ALPHA is not 0 to 1' "an ALPHA out of range is refused"
    bent 'DRAWING=elsewhere'; bent_refused 'its DRAWING is not one of the drawings' "a DRAWING that is not one of the drawings is refused"
    bent 'FORMAT=3'; bent_refused 'it was made by a newer spark-shell (format 3, this one reads 2) -- spark-shell update' "a theme of a newer format is refused, never half read (#247)"
    bent 'FACE=comic'; bent_refused 'its FACE is not neon, argon, xenon, radon or krypton' "a FACE not of the five is refused (#247)"
    bent 'TEXT_SIZE=99'; bent_refused 'its TEXT_SIZE is not 6 to 40' "a TEXT_SIZE out of range is refused (#247)"
    bent 'ANIMATION=disco'; bent_refused 'its ANIMATION is not none or one of moon, ripple, tide, embers, sun, flight' "an ANIMATION not of the pieces is refused (#247)"
    bent "WORDS=sun$(printf '\033')[2Jny"; bent_refused 'its look.env holds a control character' "a control character anywhere in look.env is refused (a row would redraw the screen)"
    bent 'WORDS=sunny'; printf 'touch %s/pwned\n' "$H" >> "$th_dir/bent/look.env"; bent_refused "line $(grep -c '' "$th_dir/bent/look.env") of its look.env is not KEY=value" "a line that is not KEY=value is refused, by its number"
    rm -rf "$th_dir/bent"
    # the config itself takes the same shapes for FONT and WALLPAPER, and status says which key
    for kv in "FONT=x' -e y" 'FONT=Neon:size=11, exec y' 'WALLPAPER=/tmp/a".png' 'WALLPAPER=a/relative/path.png'; do
        printf 'DESKTOP=sway\n%s\n' "$kv" > "$cfg"; rc=0; out=$(sh "$SH" status 2>&1) || rc=$?
        [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qF "${kv%%=*}=" || bad "config shape ${kv%%=*}" "rc=$rc $out"
    done
    ok "config (#61): a FONT with a quote or a comma, a WALLPAPER with a quote or not a full path: refused at the read, by key"
    cp "$H/cfg.before" "$cfg"
    # a theme from words, the engine's half: the four words make a look named by the words, applied, kept in the history
    printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=default\n' > "$cfg"; rm -rf "$st_dir/theme.history" "$st_dir/looks"; sh "$SH" theme nord >/dev/null 2>&1
    out=$(sh "$SH" panel theme words 'teal accent=same warmth=warm contrast=soft light=dark' 2>&1)
    [ "$out" = "teal, dark is on $SEP spark-shell theme save NAME keeps it, theme back returns" ] && grep -qx 'THEME=teal-dark' "$cfg" && [ -f "$st_dir/looks/teal-dark/palette.env" ] \
        && grep -qx 'WORDS=teal, dark' "$st_dir/looks/teal-dark/look.env" && [ "$(sed -n 1p "$st_dir/theme.history" | cut -f2)" = teal-dark ] \
        && ok "panel theme words HUE accent= warmth= contrast= light=: the palette made from the five, a look named by the hue and the light, applied and first in the history" || bad "theme words" "$out $(grep THEME= "$cfg"; ls "$st_dir/looks" 2>&1)"
    out=$(sh "$SH" panel theme --list); printf '%s\n' "$out" | grep -q "^  theme      nord	theme nord$" && printf '%s\n' "$out" | sed -n 1p | grep -q "^theme      teal, dark$" && ok "the panel's theme title names a look by its words, alone (#27)" || bad "theme words title" "$(printf '%s\n' "$out" | head -3)"
    out=$(sh "$SH" panel theme words 'green accent=yellow warmth=neutral contrast=normal light=light name=brazilian-flag' 2>&1)
    [ "$out" = "brazilian flag is on $SEP spark-shell theme save NAME keeps it, theme back returns" ] && grep -qx 'THEME=brazilian-flag' "$cfg" && grep -qx 'WORDS=brazilian flag' "$st_dir/looks/brazilian-flag/look.env" \
        && python3 -c 'import sys; h=sys.argv[1].lstrip("#"); r,g,b=(int(h[i:i+2],16) for i in (0,2,4)); sys.exit(0 if r>b and g>b and abs(r-g)<70 else 1)' "$(sed -n 's/^THEME_ACCENT=//p' "$st_dir/looks/brazilian-flag/palette.env")" \
        && ok "theme words with an accent and a name: green ground, a yellow accent, the look named by the name" || bad "theme words accent" "$out $(cat "$st_dir/looks/brazilian-flag/palette.env" 2>&1 | head -4)"
    rc=0; out=$(sh "$SH" panel theme words 'teal accent=same warmth=hot contrast=soft light=dark' 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'theme: words take a hue, then accent, warmth, contrast and light' ] || [ "$out" = 'no palette from those words: warmth is warm, neutral or cool; contrast is soft, normal or high; light is dark or light' ] && ok "panel theme words with a word off the list: refused in one line" || bad "theme words bad" "rc=$rc $out"
    out=$(sh "$SH" theme back 2>&1 | sed -n 1p); [ "$out" = 'back to teal, dark' ] && grep -qx 'THEME=teal-dark' "$cfg" && ok "theme back from a look made from words: the look before, named by its words" || bad "back from words" "$out"
    out=$(sh "$SH" theme back 2>&1 | sed -n 1p); [ "$out" = 'back to nord' ] && grep -qx 'THEME=nord' "$cfg" && ok "theme back again: the palette before the looks" || bad "back from words twice" "$out"
    sh "$SH" theme none >/dev/null 2>&1; sh "$SH" theme nord >/dev/null 2>&1
    ! grep -q '	none$' "$st_dir/theme.history" && ! sh "$SH" theme list | sed -n '/last looks/,$p' | grep -q '^  none ' && ok "theme none is no look to come back to: not in the history, not in the list (#25)" || bad "none in history" "$(cat "$st_dir/theme.history")"
    sh "$SH" theme none >/dev/null 2>&1; out=$(sh "$SH" theme back 2>&1 | sed -n 1p)
    [ "$out" = 'back to nord' ] && grep -qx 'THEME=nord' "$cfg" && ok "theme back from none: the look before none, not the one before that (#25)" || bad "back from none" "$out $(grep THEME= "$cfg")"
    # one look a request: of two words steps the second is refused, and a save the model put first runs after the look
    cat > "$H/.local/bin/spark" <<'STUB'
#!/bin/sh
case $1 in
    help) echo ' spark steps <words> < TOOLS  the tool calls that do what you say (-h)' ;;
    steps) cat > /dev/null; printf '{"answer": "", "steps": [{"name": "theme_save", "arguments": {"name": "flag"}}, {"name": "theme_words", "arguments": {"hue": "green", "accent": "yellow", "warmth": "neutral", "contrast": "normal", "light": "light", "face": "argon", "family": "banner", "animation": "sun", "drawing": "meadow", "name": "Brazilian flag"}}, {"name": "theme_words", "arguments": {"hue": "blue", "accent": "same", "warmth": "cool", "contrast": "normal", "light": "dark", "face": "neon", "family": "stone", "animation": "tide", "drawing": "fjord"}}, {"name": "theme_palette", "arguments": {"name": "flag"}}], "refused": []}\n' ;;
    *) cat > /dev/null; echo '{"steps": []}' ;;
esac
STUB
    chmod +x "$H/.local/bin/spark"
    st=0; out=$(sh "$SH" want --json a theme like the brazilian flag 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s' "$out" | jq -e --arg x "$(printf '\342\234\227')" '.steps[0] == {name: "theme_words", arguments: {hue: "green", accent: "yellow", warmth: "neutral", contrast: "normal", light: "light", face: "argon", family: "banner", animation: "sun", drawing: "meadow", name: "brazilian-flag"}, line: "theme words green accent=yellow warmth=neutral contrast=normal light=light face=argon family=banner animation=sun drawing=meadow name=brazilian-flag"} and .steps[1].name == "theme_save" and .steps[1].arguments == {name: "flag"} and (.steps | length) == 2 and (.refused | length) == 1 and (.refused | index($x + " one look a request: the first words step made it, blue accent=same warmth=cool contrast=normal light=dark face=neon family=stone animation=tide drawing=fjord was not") != null)' >/dev/null \
        && ok "want: the words step first with its name a slug, the save after it, the second words step refused in one line, the palette step naming the saved theme dropped" || bad "want one look" "st=$st $out"
    st=0; out=$(sh "$SH" want a theme like the brazilian flag 2>&1) || st=$?
    [ "$st" -eq 0 ] && printf '%s\n' "$out" | grep -q "brazilian flag is on $SEP" && printf '%s\n' "$out" | grep -q 'saved flag' && grep -qx 'THEME=flag' "$cfg" && [ -f "$th_dir/flag/palette.env" ] && grep -qx 'WORDS=brazilian flag' "$th_dir/flag/look.env" \
        && grep -qx 'FACE=argon' "$th_dir/flag/look.env" && grep -qx 'GLYPH_FAMILY=banner' "$th_dir/flag/look.env" && grep -qx 'ANIMATION=sun' "$th_dir/flag/look.env" && grep -qx 'GLYPH_FAMILY=banner' "$cfg" \
        && sh "$SH" panel theme --list | sed -n 1p | grep -q "^theme      flag$" && sh "$SH" theme list | grep -q "^  flag  *brazilian flag $SEP \(default\|meadow\), current$" && [ "$(sh "$SH" theme nord >/dev/null 2>&1; sh "$SH" theme back 2>&1 | sed -n 1p)" = 'back to flag' ] \
        && ok "want played: the look made with the face, the family, the animation and the drawing the model picked (#247), then saved as flag with its words kept; the saved theme goes by its name in the title and in back" || bad "want one look played" "st=$st $out $(ls "$th_dir" 2>&1) $(sh "$SH" panel theme --list | sed -n 1p)"
    sh "$SH" theme nord >/dev/null 2>&1; rm -f "$H/.local/bin/spark"
else
    ok "look.py: skipped, no python3 here (the CI containers)"
fi
printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=default\n' > "$cfg"; rm -rf "$st_dir/theme.history" "$st_dir/looks" "$th_dir"
if [ "$(uname -s)" != Darwin ]; then
    sway=$HOME/.config/sway/config
    # one choice brings the rest: the palette brings the drawing made for it over a drawing, a color, the ground or none; a picture of yours stays; another drawing is drawn again in the palette
    sh "$SH" theme wallpaper fjord >/dev/null 2>&1
    sh "$SH" theme tokyonight-night >/dev/null 2>&1
    grep -qx 'WALLPAPER=skyline' "$cfg" && grep -qF "output * bg \"$REPO/gallery/wallpaper/skyline.png\" fill" "$sway" && ok "theme tokyonight-night under fjord: skyline comes with the palette, the clone's own picture" || bad "palette brings drawing" "$(grep WALLPAPER "$cfg"; grep ' bg ' "$sway")"
    sh "$SH" theme wallpaper navy >/dev/null 2>&1; sh "$SH" theme nord >/dev/null 2>&1
    grep -qx 'WALLPAPER=fjord' "$cfg" && grep -qF "output * bg \"$REPO/gallery/wallpaper/fjord.png\" fill" "$sway" && ok "theme nord under a color: fjord replaces the color, as the row says (#25)" || bad "color under nord" "$(grep WALLPAPER "$cfg"; grep ' bg ' "$sway")"
    mkdir -p "$HOME/pictures"; printf x > "$HOME/pictures/mine.png"
    sh "$SH" theme wallpaper "$HOME/pictures/mine.png" >/dev/null 2>&1; sh "$SH" theme tokyonight-night >/dev/null 2>&1
    grep -qxF "WALLPAPER=$HOME/pictures/mine.png" "$cfg" && ! sh "$SH" theme list | grep -q '^  nord  *fjord' && sh "$SH" panel theme --list | grep -q "^  theme      nord	theme nord$" \
        && ok "theme tokyonight-night under a picture of yours: the picture stays, and the list names no drawing then" || bad "picture stays" "$(grep WALLPAPER "$cfg"; sh "$SH" theme list | grep nord)"
    sh "$SH" theme wallpaper navy >/dev/null 2>&1; sh "$SH" theme nord >/dev/null 2>&1
    rc=0; out=$(sh "$SH" theme wallpaper skyline 2>&1) || rc=$?
    if command -v rsvg-convert >/dev/null 2>&1 || command -v gdk-pixbuf-thumbnailer >/dev/null 2>&1; then
        [ "$rc" = 0 ] && [ -f "$st_dir/wallpapers/skyline-nord.svg" ] && [ -f "$st_dir/wallpapers/skyline-nord.png" ] && grep -qF "output * bg \"$st_dir/wallpapers/skyline-nord.png\" fill" "$sway" \
            && grep -q "^<rect .*fill=\"#2e3440\"" "$st_dir/wallpapers/skyline-nord.svg" && ! grep -q '#1a1b26' "$st_dir/wallpapers/skyline-nord.svg" \
            && [ "$(printf '%s\n' "$out" | tail -1)" = 'a running sway shows skyline now, drawn in nord -- it follows the palette: a palette with a drawing of its own brings that one' ] \
            && ok "theme wallpaper skyline under nord: the drawing drawn again in nord (its background nord's), the PNG under the state, sway shows it" || bad "drawing recolored" "rc=$rc $out $(ls "$st_dir/wallpapers" 2>&1; grep ' bg ' "$sway")"
    else
        [ "$rc" = 0 ] && [ -f "$st_dir/wallpapers/skyline-nord.svg" ] && [ ! -f "$st_dir/wallpapers/skyline-nord.png" ] && grep -qF "output * bg \"$REPO/gallery/wallpaper/skyline.png\" fill" "$sway" && printf '%s\n' "$out" | grep -q '^todo   wallpaper .*rsvg-convert is not installed to draw it in nord (the librsvg package)$' \
            && ok "theme wallpaper skyline under nord with no renderer: the SVG recolored, a todo row, the clone's picture meanwhile" || bad "drawing no renderer" "rc=$rc $out $(ls "$st_dir/wallpapers" 2>&1)"
    fi
    # the drawing through rsvg-convert alone (gdk-pixbuf 2.44 ships no thumbnailer: Arch, Fedora, Tumbleweed): a stub logs the call and writes a picture
    mkdir -p "$H/rsvg"; printf '#!/bin/sh\necho "rsvg-convert $*" >> "$HOME/rsvg.log"\nwhile [ $# -gt 0 ]; do case $1 in -o) cp "%s" "$2"; shift ;; esac; shift; done\n' "$REPO/gallery/wallpaper/skyline.png" > "$H/rsvg/rsvg-convert"; chmod +x "$H/rsvg/rsvg-convert"
    rm -rf "$st_dir/wallpapers"; : > "$H/rsvg.log"
    rc=0; out=$(SPARK_SHELL_NO_THUMB=1 PATH=$H/rsvg:$H/.local/bin:$sys sh "$SH" theme wallpaper skyline 2>&1) || rc=$?
    [ "$rc" = 0 ] && grep -qx "rsvg-convert -w 3840 -o $st_dir/wallpapers/skyline-nord.png.new $st_dir/wallpapers/skyline-nord.svg" "$H/rsvg.log" && [ -f "$st_dir/wallpapers/skyline-nord.png" ] \
        && grep -qF "output * bg \"$st_dir/wallpapers/skyline-nord.png\" fill" "$sway" && ok "theme wallpaper skyline under nord through rsvg-convert: drawn 3840 wide from the recolored SVG, sway shows it" || bad "rsvg drawing" "rc=$rc $out $(cat "$H/rsvg.log")"
    rm -rf "$st_dir/wallpapers"
    rc=0; out=$(SPARK_SHELL_NO_SVG=1 sh "$SH" theme wallpaper skyline 2>&1) || rc=$?
    [ "$rc" = 0 ] && printf '%s\n' "$out" | grep -q '^todo   wallpaper    skyline as drawn for tokyonight-night: rsvg-convert is not installed to draw it in nord (the librsvg package)$' && grep -qF "output * bg \"$REPO/gallery/wallpaper/skyline.png\" fill" "$sway" \
        && ok "theme wallpaper skyline with no renderer: the todo row names the package, the clone's picture meanwhile" || bad "no renderer row" "rc=$rc $out"
    # a picture of yours read small through rsvg-convert when the thumbnailer is gone: the picture inside a square SVG, its margins clear (python3 reads the colors: CI's bare containers have none)
    if command -v python3 >/dev/null 2>&1; then
        mkdir -p "$HOME/pictures"; printf '\377\330\377 a JPEG by its first bytes alone' > "$HOME/pictures/photo.jpg"; : > "$H/rsvg.log"
        rc=0; out=$(SPARK_SHELL_NO_THUMB=1 PATH=$H/rsvg:$H/.local/bin:$sys sh "$SH" theme picture ~/pictures/photo.jpg 2>&1) || rc=$?
        [ "$rc" = 0 ] && grep -q '^rsvg-convert -w 256 -h 256 -o .*/small.png.new .*/pic/wrap.svg$' "$H/rsvg.log" && [ -f "$st_dir/looks/photo/palette.env" ] && grep -qx 'THEME=photo' "$cfg" \
            && ok "theme picture PATH through rsvg-convert: the picture drawn 256 wide inside an SVG, a look made from it" || bad "rsvg picture" "rc=$rc $out $(cat "$H/rsvg.log")"
        rc=0; out=$(SPARK_SHELL_NO_THUMB=1 SPARK_SHELL_NO_SVG=1 sh "$SH" theme picture ~/pictures/photo.jpg 2>&1) || rc=$?
        [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a picture is read through rsvg-convert (the librsvg package), which is not installed; a PNG is read without it' ] && ok "theme picture PATH with no reader: one line names the package" || bad "no reader" "rc=$rc $out"
    fi
    sh "$SH" theme nord >/dev/null 2>&1; sh "$SH" theme wallpaper skyline >/dev/null 2>&1   # the look the tests below expect: nord, skyline drawn in it
    [ "$(sh "$SH" theme wallpaper | sed -n 1p | cut -d' ' -f1-2)" = 'wallpaper skyline' ] && ok "theme wallpaper (bare): the drawing's name" || bad "wallpaper bare drawing" "$(sh "$SH" theme wallpaper)"
    # the idle screen: its lines in the render, the verb's refusals away from a desktop, and its window through the stub
    grep -qxF 'for_window [app_id="spark-idle"] border none' "$sway" && grep -qx 'workspace idle gaps inner 0' "$sway" && grep -qx 'workspace idle gaps outer 0' "$sway" && ok "sway render: the idle workspace has no gaps and the idle window no border" || bad "idle render" "$(grep -n idle "$sway")"
    rc=0; out=$(sh "$SH" desktop idle 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = "spark-shell desktop: the idle screen is the desktop's: run it inside it" ] && ok "desktop idle outside sway: refused in one line" || bad "idle outside" "rc=$rc $out"
    rc=0; out=$(sh "$SH" desktop idle now 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: idle takes off, or nothing: the idle screen now' ] && ok "desktop idle with a wrong word: refused in one line" || bad "idle word" "rc=$rc $out"
    mkdir -p "$H/ix"; cat > "$H/ix/swaymsg" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/swaymsg.log"
case "$*" in
    "-t get_version") echo '{"human_readable":"sway-stub"}' ;;
    "-t get_tree") cat "$HOME/tree.json" 2>/dev/null || echo '{"nodes":[]}' ;;   # the idle windows a test says are up, or none
    "-t get_workspaces") printf '[{"name":"%s","focused":true,"visible":true}]\n' "$(cat "$HOME/ws.focused" 2>/dev/null || echo idle)" ;;   # the workspace in front: idle, unless a test says another
    "-t get_outputs") printf '%s\n' '[{"name":"DP-3","make":"ASUSTek COMPUTER INC","model":"MB16AH","serial":"S1","active":true,"focused":false,"current_workspace":"1"},' \
        '{"name":"HDMI-A-1","make":"Lenovo Group Limited","model":"T24i-30","serial":"V30A1","active":true,"focused":true,"current_workspace":"2 webdev"},' \
        '{"name":"HDMI-A-2","make":"Unknown","model":"Unknown","serial":"","active":false,"focused":false}]' ;;   # two screens on, the focus on HDMI-A-1, a third one off
esac
STUB
    chmod +x "$H/ix/swaymsg"
    tb=$(printf '\t')
    rm -f "$HOME/swaymsg.log" "$HOME/tree.json" "$HOME/.local/state/spark-shell/idle.from" "$HOME/.config/spark-shell/screens.conf"; printf '2 webdev\n' > "$HOME/ws.focused"
    rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/ix:$PATH" sh "$SH" desktop idle 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ "$(cat "$HOME/.local/state/spark-shell/idle.from" 2>/dev/null)" = "DP-3${tb}1
HDMI-A-1${tb}2 webdev" ] && ok "desktop idle: each screen's workspace kept by name, the focused screen's last: the way back (#70, #177)" || bad "idle from" "rc=$rc $(cat "$HOME/.local/state/spark-shell/idle.from" 2>&1)"
    rm -f "$HOME/ws.focused"
    foot="foot --app-id spark-idle -o 'font=DejaVu Sans Mono:size=24' -o colors[a-z-]*\.alpha=0\.8 -o colors[a-z-]*\.background=2e3440 -o pad=0x0 -e $REPO/spark-shell desktop idle"
    [ "$rc" = 0 ] && grep -qx -- '-- bar mode invisible' "$HOME/swaymsg.log" \
        && grep -qx -- "-- mouse_warping none; focus output \"DP-3\"; workspace \"idle DP-3\"; gaps inner current set 0; gaps outer current set 0; exec $foot --side; mouse_warping output" "$HOME/swaymsg.log" \
        && grep -qx -- "-- mouse_warping none; focus output \"HDMI-A-1\"; workspace idle; exec $foot --clock; mouse_warping output" "$HOME/swaymsg.log" \
        && [ "$(grep 'exec foot' "$HOME/swaymsg.log" | sed 's/.*desktop idle --//; s/;.*//' | tr '\n' ' ')" = 'side clock ' ] && ! grep -q 'HDMI-A-2' "$HOME/swaymsg.log" \
        && ok "desktop idle: the bar away; every screen on gets a foot at twice the text size, 80% over the wallpaper, on an idle workspace of its own: the saver alone beside, the clock last on the screen with the focus; the pointer stays (#177)" || bad "idle on" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
    printf '# rendered by spark-shell\nworkspace 1 output "ASUSTek COMPUTER INC MB16AH S1"\n' > "$HOME/.config/spark-shell/screens.conf"; rm -f "$HOME/swaymsg.log"
    SWAYSOCK=$H/sock PATH="$H/ix:$PATH" sh "$SH" desktop idle >/dev/null 2>&1 || :
    grep -q -- '-- mouse_warping none; focus output "DP-3"; workspace idle; exec foot .*--clock; mouse_warping output$' "$HOME/swaymsg.log" && grep -q -- '-- mouse_warping none; focus output "HDMI-A-1"; workspace "idle HDMI-A-1"; .*--side; mouse_warping output$' "$HOME/swaymsg.log" \
        && ok "desktop idle: the clock goes on Display's main screen, named by its make and model, wherever the focus is (#177)" || bad "idle main" "$(cat "$HOME/swaymsg.log" 2>&1)"
    rm -f "$HOME/.config/spark-shell/screens.conf" "$HOME/swaymsg.log"
    printf '%s\n' '{"nodes":[{"type":"con","app_id":"spark-idle","pid":4011,"id":51},{"type":"con","app_id":"foot","pid":4012,"id":52},{"type":"con","app_id":"spark-idle","pid":4013,"id":53}]}' > "$HOME/tree.json"
    rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/ix:$PATH" sh "$SH" desktop idle off 2>&1) || rc=$?
    [ "$rc" = 0 ] && grep -qxF -- '-- mouse_warping none; focus output "DP-3"; workspace "1"; focus output "HDMI-A-1"; workspace "2 webdev"; mouse_warping output' "$HOME/swaymsg.log" \
        && grep -qxF -- '-- [con_id=51] kill' "$HOME/swaymsg.log" && grep -qxF -- '-- [con_id=53] kill' "$HOME/swaymsg.log" && ! grep -q 'con_id=52' "$HOME/swaymsg.log" && grep -qx -- '-- bar mode dock' "$HOME/swaymsg.log" \
        && awk '/workspace "1"/ { w = NR } /con_id=51/ { k = NR } END { exit !(w && k && w < k) }' "$HOME/swaymsg.log" \
        && ok "desktop idle off: every screen back to its workspace by name in one command (never a toggle, #70), the focus where it was, the bar back, then every idle window closed, nothing else (#177)" || bad "idle off" "rc=$rc $out $(cat "$HOME/swaymsg.log" 2>&1)"
    rm -f "$HOME/swaymsg.log"; printf '2 webdev\n' > "$HOME/ws.focused"
    SWAYSOCK=$H/sock PATH="$H/ix:$PATH" sh "$SH" desktop idle off >/dev/null 2>&1 || :
    ! grep -q -- '-- workspace' "$HOME/swaymsg.log" && ! grep -q 'workspace "' "$HOME/swaymsg.log" && grep -qx -- '-- bar mode dock' "$HOME/swaymsg.log" && ok "desktop idle off a second time, no idle workspace shown: nothing moves, the bar stays (#70)" || bad "idle off twice" "$(cat "$HOME/swaymsg.log" 2>&1)"
    rm -f "$HOME/swaymsg.log" "$HOME/ws.focused" "$HOME/tree.json"; printf '2 webdev\n' > "$HOME/.local/state/spark-shell/idle.from"
    SWAYSOCK=$H/sock PATH="$H/ix:$PATH" sh "$SH" desktop idle off >/dev/null 2>&1 || :
    grep -qxF -- '-- mouse_warping none; workspace "2 webdev"; mouse_warping output' "$HOME/swaymsg.log" && ok "desktop idle off with one name kept (a window from before #177): that workspace back" || bad "idle off old file" "$(cat "$HOME/swaymsg.log" 2>&1)"
    rm -f "$HOME/swaymsg.log" "$HOME/.local/state/spark-shell/idle.from"
    SWAYSOCK=$H/sock PATH="$H/ix:$PATH" sh "$SH" desktop idle off >/dev/null 2>&1 || :
    grep -qx -- '-- workspace back_and_forth' "$HOME/swaymsg.log" && ok "desktop idle off with no name kept (a window from before v0.102): back and forth, as it was" || bad "idle off no name" "$(cat "$HOME/swaymsg.log" 2>&1)"
    printf '2 webdev\n' > "$HOME/.local/state/spark-shell/idle.from"
    # the idle window's drawing (#42): the Calendar's large figures at the lower left in the accent's slot, the date in the panel's muted one; one frame, then a sleep that fails ends the loop
    mkdir -p "$H/ic"; printf '#!/bin/sh\necho "${IC_SIZE:-28 100}"\n' > "$H/ic/stty"; printf '#!/bin/sh\nexit 1\n' > "$H/ic/sleep"; chmod +x "$H/ic/stty" "$H/ic/sleep"
    esc=$(printf '\033'); blk=$(printf '\342\226\210'); day=$(date '+%A %e %B' | tr -s ' ')   # blk: the full block's bytes, for the C locale of CI's containers
    rc=0; out=$(PATH="$H/ic:$PATH" sh "$SH" desktop idle --clock 2>&1) || rc=$?
    [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "${esc}\[21;3H${esc}\[38;5;16m" && printf '%s' "$out" | grep -q "${esc}\[25;3H${esc}\[38;5;16m" && ! printf '%s' "$out" | grep -q "${esc}\[26;3H${esc}\[38;5;16m" \
        && printf '%s' "$out" | grep -qF "${esc}[27;3H${esc}[38;5;20m$day" && [ "$(printf '%s' "$out" | grep -o "$blk" | wc -l | tr -d ' ')" -ge 20 ] \
        && ok "desktop idle --clock: the time in five rows of large figures at the lower left in the accent (slot 16), a row of air, the date in the muted color (slot 20) (#42)" || bad "idle clock" "rc=$rc $(printf '%s' "$out" | od -c | head -8)"
    rc=0; out=$(IC_SIZE='8 30' PATH="$H/ic:$PATH" sh "$SH" desktop idle --clock 2>&1) || rc=$?
    [ "$rc" = 0 ] && printf '%s' "$out" | grep -q "${esc}\[6;3H${esc}\[38;5;16m[0-9][0-9]:[0-9][0-9]" && printf '%s' "$out" | grep -qF "${esc}[7;3H${esc}[38;5;20m$day" \
        && ok "desktop idle --clock in a window under 9 rows: the time on one line, the date under it" || bad "idle clock small" "rc=$rc $(printf '%s' "$out" | od -c | head -6)"
    # whatever ends the idle window brings the desktop back (#70): the clock's end, here its sleep failing; and in its own terminal, a key
    rm -f "$HOME/swaymsg.log"
    rc=0; out=$(SWAYSOCK=$H/sock PATH="$H/ix:$H/ic:$PATH" sh "$SH" desktop idle --clock 2>&1) || rc=$?
    [ "$rc" = 0 ] && grep -qxF -- '-- mouse_warping none; workspace "2 webdev"; mouse_warping output' "$HOME/swaymsg.log" && grep -qx -- '-- bar mode dock' "$HOME/swaymsg.log" \
        && ok "desktop idle --clock: when the clock ends, the workspace it left and the bar come back (#70)" || bad "idle clock end" "rc=$rc $(cat "$HOME/swaymsg.log" 2>&1)"
    if [ -n "$py3" ]; then   # the real python3 (CI's bare containers have none)
        cat > "$H/keypty.py" <<'PY'
import os, pty, select, sys, time
# keypty.py CMD... -- CMD at a pty; after 1.5 s an x is typed; exit 0 when CMD ended within 3 s of it
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
t0, typed = time.time(), None
while time.time() - t0 < 8:
    if select.select([fd], [], [], 0.05)[0]:
        try:
            os.read(fd, 65536)
        except OSError:
            pass
    if typed is None and time.time() - t0 > 1.5:
        os.write(fd, b"x"); typed = time.time()
    p, st = os.waitpid(pid, os.WNOHANG)
    if p:
        sys.exit(0 if typed and time.time() - typed < 3 else 1)
os.kill(pid, 9); sys.exit(1)
PY
        rm -f "$HOME/swaymsg.log"; printf 'DESKTOP=sway\nDISPLAY_SAVER=clock\n' > "$HOME/.config/spark-shell/config"
        rc=0; SWAYSOCK=$H/sock PATH="$H/ix:$PATH" "$py3" "$H/keypty.py" sh "$SH" desktop idle --clock || rc=$?
        [ "$rc" = 0 ] && grep -qxF -- '-- mouse_warping none; workspace "2 webdev"; mouse_warping output' "$HOME/swaymsg.log" && grep -qx -- '-- bar mode dock' "$HOME/swaymsg.log" \
            && ok "desktop idle --clock in its terminal: a key ends the clock within a second or two, and the desktop comes back (#70)" || bad "idle clock key" "rc=$rc $(cat "$HOME/swaymsg.log" 2>&1)"
        printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
    fi
    rm -f "$HOME/.local/state/spark-shell/idle.from"
    # the pointer's size follows the text size
    sh "$SH" theme text 20 >/dev/null 2>&1; grep -qx 'seat \* xcursor_theme spark-white 48' "$sway" && ok "theme text 20: the pointer at 48" || bad "pointer 48" "$(grep xcursor "$sway")"
    sh "$SH" theme text 12 >/dev/null 2>&1; grep -qx 'seat \* xcursor_theme spark-white 24' "$sway" && ok "theme text 12: the pointer at 24 again" || bad "pointer 24" "$(grep xcursor "$sway")"
    # the lock's font size follows the text size
    mkdir -p "$H/lk"; printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$HOME/swaylock.args"\n' > "$H/lk/swaylock"; printf '#!/bin/sh\nexit 1\n' > "$H/lk/pgrep"; chmod +x "$H/lk/swaylock" "$H/lk/pgrep"
    sh "$SH" theme text 15 >/dev/null 2>&1
    WAYLAND_DISPLAY=wayland-9 PATH="$H/lk:$PATH" sh "$SH" desktop lock >/dev/null 2>&1 || :
    grep -qx -- '--font-size' "$HOME/swaylock.args" && [ "$(grep -A1 -x -- '--font-size' "$HOME/swaylock.args" | sed -n 2p)" = 25 ] && ok "desktop lock: the font size five thirds of the text size (15 points: 25)" || bad "lock font size" "$(cat "$HOME/swaylock.args" 2>&1 | head -12)"
    sh "$SH" theme text 12 >/dev/null 2>&1
    # the desktop verb's old wallpaper word says where it went
    rc=0; out=$(sh "$SH" desktop wallpaper skyline 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: the wallpaper is a theme word now: spark-shell theme wallpaper skyline' ] && ok "desktop wallpaper: one line to the theme word" || bad "desktop wallpaper moved" "rc=$rc $out"
fi
# the dialog's theme section: saved, back, the palettes with their drawings, the wallpaper row that opens the list, the text size; the wallpaper list as a resource
printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=default\n' > "$cfg"; rm -rf "$st_dir/theme.history" "$st_dir/looks" "$th_dir"
sh "$SH" theme nord >/dev/null 2>&1; sh "$SH" theme save desk >/dev/null 2>&1; sh "$SH" theme dracula >/dev/null 2>&1
mcp theme "$(rq 1 resources/read '{"uri":"spark-shell://theme/rows"}')" "$(rq 2 resources/read '{"uri":"spark-shell://theme/rows/wallpapers"}')"
ans 1 | jq -r '.result.contents[0].text' > "$H/trows.json"; ans 2 | jq -r '.result.contents[0].text' > "$H/wrows.json"
jq -e --arg dw "$([ "$(uname -s)" = Darwin ] && echo default || echo fjord)" '(.rows[] | select(.id == "theme:desk") | .group == "custom" and .columns == ["nord \u00b7 " + $dw] and .tool == {name: "theme_palette", arguments: {name: "desk"}} and (.chip | length) == 9)
    and (.rows[] | select(.id == "theme:save") | .group == "custom" and .text == "save this look as" and .tool.name == "theme_save" and .tool.ask == ["name"])
    and ([.rows[] | select(.group == "back" or .group == "palettes")] | length == 0)
    and (.rows[] | select(.id == "theme:nord") | .group == "dark" and .columns == [] and .quiet == true and .look == {name: "theme_preview", arguments: {name: "nord"}} and .tool == {name: "theme_palette", arguments: {name: "nord"}}
        and .chip == ["#2e3440", "#d8dee9", "#88c0d0", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0"])
    and (.rows[] | select(.id == "theme:solarized-light") | .group == "light") and (.rows[] | select(.id == "theme:dracula") | .sign == "check" and .group == "dark" and .tool.arguments.name == "dracula" and .quiet == true)
    and (.rows[] | select(.id == "theme:show:Text size") | .step.values[.step.at] == {shown: "12", sent: "12"} and (.step.values | length) == 35 and .step.values[0].sent == "6"
        and .step.set == {name: "theme_text", arguments: {}} and .step.key == "size" and .step.words == ["smaller", "bigger"] and .group == "text and bar" and .tool == null)
    and (.rows[] | select(.id == "theme:show:Transparency") | .step.values[.step.at] == {shown: "5%", sent: "5"} and .step.values[0] == {shown: "off", sent: "0"} and .step.values[-1].shown == "50%"
        and .step.key == "amount" and .group == "screen")
    and (has("side_by_side") | not) and .look_back == {name: "theme_preview", arguments: {name: "off"}}
    and ([.rows[] | .group] | index("dark") < index("custom") and index("custom") < index("screen"))
    and ([.rows[] | select(.text | test("^(text bigger|text smaller|more transparency|less transparency)"))] | length == 0) and (.short == ["theme:more"])' "$H/trows.json" >/dev/null \
    && ok "provide theme rows (#36, #183, #192): the palettes first, dark then light in one column, each its own step kept in place with a look, its chip and no drawing; custom: the saved theme, the save row that asks a name; then the settings: the text size and the transparency, each with every value it takes and the one in use; no back rows" || bad "theme rows" "$(head -c 900 "$H/trows.json")"
# a value set as it is, the dialog's own way (#183); a palette looked at is on the screen and nothing is kept
mcp theme "$(call 1 theme_text '{"size":"14"}')" "$(call 2 theme_transparency '{"amount":"30"}')" "$(call 3 theme_preview '{"name":"nord"}')" "$(call 4 theme_preview '{"name":"none"}')" "$(call 5 theme_preview '{"name":"off"}')"
[ "$(ans 1 | jq -r '.result.structuredContent.receipt' | cut -c1-10)" = 'text at 14' ] && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'transparency at 30%' ] \
    && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = 'nord on the screen' ] && ans 3 | jq -e '.result.structuredContent | (.palette.HEX_FG | ascii_downcase) == "d8dee9" and .undo == null and .transitions == null' >/dev/null && grep -qx 'THEME=dracula' "$cfg" && [ "$(ans 4 | jq -r '.result.isError')" = true ] && [ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'the look in use is on the screen again' ] \
    && ok "provide theme: a size and a percent set as they are (#183); a palette looked at says so and keeps nothing, none has nothing to show, off puts the look in use back" || bad "theme exact values" "$(cut -c1-400 "$H/mcp.out")"
sh "$SH" theme text 12 >/dev/null 2>&1; sh "$SH" theme transparency 15 >/dev/null 2>&1   # the steps below start from these
mcp theme "$(call 1 theme_text '{"size":"bigger"}')" "$(call 2 theme_transparency '{"amount":"more"}')"
[ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = "text at 13 $SEP new windows and the bar take it; the pointer 24 pixels" ] && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = 'transparency at 25%' ] \
    && ok "provide theme: a value's step passes without the rows drawn (#33), a step with its receipt" || bad "theme quick steps" "$(cat "$H/mcp.out" | cut -c1-300)"
sh "$SH" theme text 12 >/dev/null 2>&1; sh "$SH" theme transparency 15 >/dev/null 2>&1
if [ "$(uname -s)" != Darwin ]; then
    jq -e '(.rows[] | select(.id == "theme:wallpaper") | .text == "Wallpaper" and .columns == ["dunes"] and .tool == null and .children == "spark-shell://theme/rows/wallpapers")
        and (.rows[] | select(.id == "theme:picture") | .text == "a theme from a picture" and .children == "spark-shell://files/rows" and .pick == {tool: "theme_picture", types: ["jpg", "jpeg", "png", "webp"]})' "$H/trows.json" >/dev/null \
        && jq -e --arg th "$HOME/.local/state/spark-shell/thumbs" '.title == "wallpaper" and (.rows[] | select(.id == "theme:wallpaper skyline") | .group == "drawings" and .columns == ["for tokyonight-night"] and .preview == ($th + "/skyline-dracula.png") and .tool == {name: "theme_wallpaper", arguments: {name: "skyline"}} and .quiet == true)
            and (.rows[] | select(.id == "theme:wallpaper-picture") | .group == "custom" and .text == "a picture" and (has("quiet") | not) and .children == "spark-shell://files/rows" and .pick.tool == "theme_wallpaper_picture")
            and (.rows[] | select(.id == "theme:wallpaper-color") | .text == "a color" and .tool.name == "theme_wallpaper_color" and .tool.ask == ["color"])
            and (.rows[] | select(.id == "theme:wallpaper default") | .text == "the ground" and .group == "custom" and .quiet == true and (.chip | length) == 1) and ([.rows[] | select(.text == "none" or .group == "colors")] | length == 0)
            and (.rows[] | select(.id == "theme:wallpaper dunes") | .sign == "check" and .quiet == true and .tool.arguments.name == "dunes") and .rows[0].id == "theme:wallpaper skyline"' "$H/wrows.json" >/dev/null \
        && ok "provide theme: the wallpaper row opens the list resource (#36): the drawings first, each with the palette it was drawn for and its picture in this palette, each kept in place (#191); custom: a picture to pick, a color asked for, the ground with its color; no none, no color rows; dunes checked, its step kept" || bad "wallpaper rows" "$(head -c 700 "$H/trows.json"; head -c 900 "$H/wrows.json")"
    jq -e --arg th "$HOME/.local/state/spark-shell/thumbs" '(.rows[] | select(.id == "theme:wallpaper watch") | .group == "drawings" and .columns == ["moves, in any palette"] and .preview == ($th + "/watch-dracula.png") and .quiet == true)
        and ([.rows[] | select(.group == "drawings") | .text] | index("watch") > index("embers")) and ([.rows[] | .text, (.columns[]?)] | map(select(test("^(cozy|night)$"))) | length == 0)' "$H/wrows.json" >/dev/null \
        && ok "provide theme: the scenes are wallpapers after the drawings, each moving in any palette, its picture drawn in this one; no collection named (#188)" || bad "scene rows" "$(jq -c '[.rows[] | select(.text == "watch")]' "$H/wrows.json")"
    mcp theme "$(call 1 theme_wallpaper_color '{"color":"teal"}')" "$(call 2 theme_wallpaper_color '{"color":"chartreuse"}')"
    [ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = 'the wallpaper is teal' ] && grep -qx 'WALLPAPER=#008080' "$cfg" && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'theme: a color is a name (black, white, gray, silver, navy, blue, teal, green, olive, maroon, red, purple, brown, orange) or #rrggbb' ] \
        && ok "provide theme_wallpaper_color: a color by its name or #rrggbb, a word that is no color refused" || bad "wallpaper color call" "$(cat "$H/mcp.out" | cut -c1-300)"
    # the bar's set (#160) and the glyph family (#248): a switch and a value left and right change in Settings > theme; a
    # step with its undo, the same value again a refusal; a saved theme keeps both and brings them back
    jq -e '(.rows[] | select(.id == "theme:show:Words on the bar") | .switch == {on: false, turn_on: {name: "theme_glyphs", arguments: {to: "words"}}, turn_off: {name: "theme_glyphs", arguments: {to: "signs"}}} and .tool == null and .group == "text and bar")
        and (.rows[] | select(.id == "theme:show:Glyph family") | .step == {values: [{shown: "stone", sent: "stone"}, {shown: "star", sent: "star"}, {shown: "banner", sent: "banner"}], at: 0, set: {name: "theme_family", arguments: {}}, key: "to", words: ["back", "next"]} and .tool == null and .group == "text and bar")
        and ([.rows[] | select(.id | test("[Ww]orkspaces"))] | length == 0)' "$H/trows.json" >/dev/null \
        && ok "provide theme rows (#160, #183, #248): words on the bar a switch, the glyph family a value, stone first; no workspaces row" || bad "bar rows" "$(jq -c '[.rows[] | select(.group == "text and bar")]' "$H/trows.json")"
    mcp theme "$(call 1 theme_glyphs '{"to":"words"}')" "$(call 2 theme_glyphs '{"to":"words"}')" "$(call 3 theme_family '{"to":"star"}')" "$(call 4 theme_family '{"to":"star"}')" "$(call 5 theme_family '{"to":"runes"}')" "$(call 6 theme_workspaces '{"to":"numbers"}')"
    [ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = 'the bar in words' ] && ans 1 | jq -e '.result.structuredContent.undo | .name == "theme_glyphs" and .arguments.to == "signs"' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'the bar is in words already' ] \
        && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = 'glyph family star' ] && ans 3 | jq -e '.result.structuredContent.undo == {name: "theme_family", arguments: {to: "stone"}} and .result.structuredContent.palette.GLYPH_FAMILY == "star"' >/dev/null \
        && [ "$(ans 4 | jq -r '.result.content[0].text')" = 'the glyph family is star already' ] && ans 5 | jq -e '.error.message | startswith("theme_family: to is one of stone, star, banner")' >/dev/null \
        && ans 6 | jq -e '.error != null' >/dev/null && grep -qx 'BAR_GLYPHS=words' "$cfg" && grep -qx 'GLYPH_FAMILY=star' "$cfg" \
        && ok "provide theme_glyphs and theme_family (#160, #248): each a step with its receipt and undo, kept in the config, the family in the palette the dialog wears; the same value again refused, a family not of the three refused, theme_workspaces gone" || bad "bar steps" "$(cut -c1-400 "$H/mcp.out")"
    # the bar's own section: where it sits, a check on the place it has; its text size a value left and right change,
    # auto standing where its size is; the tray a switch, off
    mcp bar "$(rq 1 resources/read '{"uri":"spark-shell://bar/rows"}')"; ans 1 | jq -r '.result.contents[0].text' > "$H/brows.json"
    jq -e '(.rows[0] | .id == "bar:show:at the top of the screen" and .sign == "check" and .group == "place")
        and (.rows[1] | .tool == {name: "bar_bottom", arguments: {}} and .group == "place") and (.rows[2] | .text == "hidden" and .tool == {name: "bar_off", arguments: {}})
        and (.rows[] | select(.id == "bar:show:Text size") | (.step.values | length) == 36 and .step.values[.step.at].sent == "auto" and (.step.values[.step.at].shown | test("^auto [0-9]+$"))
            and .step.values[.step.at - 1].sent == ((.step.values[.step.at].shown | ltrimstr("auto ") | tonumber) - 1 | tostring) and .step.set == {name: "bar_text", arguments: {}} and .step.key == "size")
        and (.rows[] | select(.id == "bar:show:App icons (the tray)") | .switch == {on: false, turn_on: {name: "bar_tray", arguments: {state: "on"}}, turn_off: {name: "bar_tray", arguments: {state: "off"}}})' "$H/brows.json" >/dev/null \
        && ok "provide bar rows: the top checked, the bottom and hidden a tool each; the text size a step, auto where its size is; the tray a switch, off" || bad "bar section rows" "$(cut -c1-600 "$H/brows.json")"
    mcp bar "$(call 1 bar_text '{"size":"14"}')" "$(call 2 bar_text '{"size":"huge"}')"
    [ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = 'bar text 14' ] && ans 1 | jq -e '.result.structuredContent.undo == {name: "bar_text", arguments: {size: "auto"}}' >/dev/null && grep -qx 'BAR_TEXT=14' "$cfg" \
        && ans 2 | jq -e '.error.message | startswith("bar_text: size is one of auto, bigger, smaller, 6")' >/dev/null \
        && ok "provide bar_text: a size kept in the config, its undo back to auto; a word that is no size refused" || bad "bar_text call" "$(cut -c1-400 "$H/mcp.out")"
    sh "$SH" bar text auto >/dev/null 2>&1 || :
    sh "$SH" theme save barlook >/dev/null 2>&1; sh "$SH" theme glyphs signs >/dev/null 2>&1; sh "$SH" theme family stone >/dev/null 2>&1; sh "$SH" theme barlook >/dev/null 2>&1
    grep -qx 'BAR_GLYPHS=words' "$th_dir/barlook/look.env" && grep -qx 'GLYPH_FAMILY=star' "$th_dir/barlook/look.env" && ! grep -q '^BAR_WORKSPACES=' "$th_dir/barlook/look.env" && grep -qx 'BAR_GLYPHS=words' "$cfg" && grep -qx 'GLYPH_FAMILY=star' "$cfg" \
        && ok "theme save keeps the bar's set and the glyph family, and the theme brings them back (#160, #248)" || bad "bar look kept" "$(cat "$th_dir/barlook/look.env" 2>&1; grep -E 'BAR_|GLYPH_' "$cfg")"
    # a theme saved before the families (#248): its BAR_WORKSPACES, whatever its value, is read without an error and changes nothing
    printf 'BAR_WORKSPACES=numbers\n' >> "$th_dir/barlook/look.env"; sed -i.bak '/^GLYPH_FAMILY=/d' "$th_dir/barlook/look.env"; rm -f "$th_dir/barlook/look.env.bak"
    sh "$SH" theme family banner >/dev/null 2>&1; st=0; out=$(sh "$SH" theme barlook 2>&1) || st=$?
    [ "$st" -eq 0 ] && grep -qx 'GLYPH_FAMILY=banner' "$cfg" && ! grep -q '^BAR_WORKSPACES=' "$cfg" \
        && ok "a saved theme from before the families loads: its BAR_WORKSPACES ignored, the family in use kept (#248)" || bad "old theme loads" "st=$st $out $(grep -E 'GLYPH_|BAR_W' "$cfg")"
    printf 'GLYPH_FAMILY=runes\n' >> "$th_dir/barlook/look.env"; st=0; out=$(sh "$SH" theme barlook 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s' "$out" | grep -q 'its GLYPH_FAMILY is not stone, star or banner' && grep -qx 'GLYPH_FAMILY=banner' "$cfg" \
        && ok "a saved theme naming a family not of the three is refused, nothing changed (#248)" || bad "theme family refuse" "st=$st $out"
    sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme delete barlook </dev/null >/dev/null 2>&1; sh "$SH" theme glyphs signs >/dev/null 2>&1; sh "$SH" theme family stone >/dev/null 2>&1
    printf 'BAR_GLYPHS=letters\n' >> "$cfg"; st=0; out=$(sh "$SH" theme 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s' "$out" | grep -q 'BAR_GLYPHS=letters in .*: signs or words' && ok "config: BAR_GLYPHS other than signs or words is refused in one line (#160)" || bad "bar glyphs refuse" "st=$st $out"
    sed -i.bak '/^BAR_GLYPHS=letters$/d' "$cfg"; rm -f "$cfg.bak"
    printf 'GLYPH_FAMILY=runes\n' >> "$cfg"; st=0; out=$(sh "$SH" theme 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s' "$out" | grep -q 'GLYPH_FAMILY=runes in .*: stone, star or banner' && ok "config: GLYPH_FAMILY other than stone, star or banner is refused in one line (#248)" || bad "family refuse" "st=$st $out"
    sed -i.bak '/^GLYPH_FAMILY=runes$/d' "$cfg"; rm -f "$cfg.bak"
    printf 'BAR_WORKSPACES=numbers\n' >> "$cfg"; st=0; out=$(sh "$SH" theme family 2>&1) || st=$?
    st2=0; sed -i.bak 's/^BAR_WORKSPACES=numbers$/BAR_WORKSPACES=anything/' "$cfg"; rm -f "$cfg.bak"; out2=$(sh "$SH" theme family 2>&1) || st2=$?
    [ "$st" -eq 0 ] && [ "$out" = "glyph family stone $(printf '\302\267') stone, star or banner" ] && [ "$st2" -eq 0 ] && [ "$out2" = "$out" ] \
        && ok "config: BAR_WORKSPACES, the setting before the families, loads whatever its value and is ignored (#248)" || bad "old config loads" "st=$st $out st2=$st2 $out2"
    sed -i.bak '/^BAR_WORKSPACES=/d' "$cfg"; rm -f "$cfg.bak"
    rc=0; out=$(sh "$SH" theme workspaces numbers 2>&1) || rc=$?
    [ "$rc" -ne 0 ] && [ "$out" = 'spark-shell theme: the glyph family names the workspaces now -- spark-shell theme family stone, star or banner' ] \
        && ok "theme workspaces is gone, refused in a line that names theme family, never read as words for a theme (#248)" || bad "theme workspaces gone" "rc=$rc $out"
    # the text's face (#247, arc 3): a face of your own, the row says yours and offers none; one of Monaspace's five, a value
    # left and right change, a step with its undo; a saved theme keeps it, and one naming another face brings its size alone
    { [ "$(uname -s)" = Darwin ] || jq -e '.rows[] | select(.id == "theme:show:Text face") | .columns == ["yours"] and (has("step") | not) and .group == "text and bar"' "$H/trows.json" >/dev/null; } \
        && ok "provide theme rows: a FONT of your own, its Text face row says yours, no value to step (#247)" || bad "face row yours" "$(jq -c '.rows[] | select(.id == "theme:show:Text face")' "$H/trows.json")"
    if [ "$(uname -s)" != Darwin ]; then
        printf 'FONT=Monaspace Neon:size=12\n' >> "$cfg"
        mcp theme "$(rq 1 resources/read '{"uri":"spark-shell://theme/rows"}')" "$(call 2 theme_face '{"to":"argon"}')" "$(call 3 theme_face '{"to":"comic"}')"
        ans 1 | jq -r '.result.contents[0].text' > "$H/frows.json"
        jq -e '.rows[] | select(.id == "theme:show:Text face") | .step.at == 0 and (.step.values | map(.sent)) == ["neon", "argon", "xenon", "radon", "krypton"] and .step.set == {name: "theme_face", arguments: {}}' "$H/frows.json" >/dev/null \
            && [ "$(ans 2 | jq -r '.result.structuredContent.receipt')" = "text in argon $(printf '\302\267') from spark-shell on, which installs it; neon until then" ] \
            && ans 2 | jq -e '.result.structuredContent.undo == {name: "theme_face", arguments: {to: "neon"}}' >/dev/null && grep -qx 'FONT=Monaspace Argon:size=12' "$cfg" \
            && ans 3 | jq -e '.error.message | startswith("theme_face: to is one of neon, argon, xenon, radon, krypton")' >/dev/null \
            && ok "provide theme_face (#247): neon first among the five, a step that keeps the size, its undo the face before; a face not of the five refused" || bad "face step" "$(cut -c1-400 "$H/mcp.out")"
        sh "$SH" theme save facelook >/dev/null 2>&1; sh "$SH" theme face neon >/dev/null 2>&1; sh "$SH" theme facelook >/dev/null 2>&1
        grep -qx 'FACE=argon' "$th_dir/facelook/look.env" && grep -qx 'TEXT_SIZE=12' "$th_dir/facelook/look.env" && ! grep -q '^FONT=' "$th_dir/facelook/look.env" && grep -qx 'FONT=Monaspace Argon:size=12' "$cfg" \
            && ok "theme save keeps the face and its size as FACE and TEXT_SIZE, and the theme brings them back (#247)" || bad "face kept" "$(cat "$th_dir/facelook/look.env"; grep FONT "$cfg")"
        { grep -v -e '^FACE=' -e '^TEXT_SIZE=' -e '^FORMAT=' "$th_dir/facelook/look.env"; printf 'FONT=Iosevka Term:size=15\n'; } > "$th_dir/facelook/look.env.new" && mv "$th_dir/facelook/look.env.new" "$th_dir/facelook/look.env"
        sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme facelook >/dev/null 2>&1
        grep -qx 'FONT=Monaspace Argon:size=15' "$cfg" && ok "a theme of format 1 naming a face not of the five brings its size alone, the face in use kept (#247)" || bad "face size only" "$(grep FONT "$cfg")"
        { grep -v '^FONT=' "$th_dir/facelook/look.env"; printf 'FORMAT=2\nTEXT_SIZE=17\n'; } > "$th_dir/facelook/look.env.new" && mv "$th_dir/facelook/look.env.new" "$th_dir/facelook/look.env"
        sh "$SH" theme face xenon >/dev/null 2>&1; sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme facelook >/dev/null 2>&1
        grep -qx 'FONT=Monaspace Xenon:size=17' "$cfg" && ok "a theme of format 2 with a size and no face: its size, the face in use kept (#247)" || bad "format 2 size only" "$(grep FONT "$cfg")"
        sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme delete facelook </dev/null >/dev/null 2>&1
        sed -i.bak '/^FONT=/d' "$cfg"; rm -f "$cfg.bak"
    fi
    # the apps' icons (#230): a switch in Settings > theme, the dialog's group; a step with its undo, the same value again a
    # refusal; kept with a saved theme and brought back; a wrong word in the config refused in one line
    jq -e '.rows[] | select(.id == "theme:show:App icons") | .switch == {on: true, turn_on: {name: "theme_icons", arguments: {to: "on"}}, turn_off: {name: "theme_icons", arguments: {to: "off"}}} and .tool == null and .group == "dialog"' "$H/trows.json" >/dev/null \
        && ok "provide theme rows (#230): app icons a switch, on" || bad "icons row" "$(jq -c '[.rows[] | select(.id | test("icons"))]' "$H/trows.json")"
    mcp theme "$(call 1 theme_icons '{"to":"off"}')" "$(call 2 theme_icons '{"to":"off"}')" "$(call 3 theme_icons '{"to":"maybe"}')"
    [ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = 'app icons off' ] && ans 1 | jq -e '.result.structuredContent.undo | .name == "theme_icons" and .arguments.to == "on"' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'app icons are off already' ] && ans 3 | jq -e '.error.message | startswith("theme_icons:")' >/dev/null && grep -qx 'DIALOG_ICONS=off' "$cfg" \
        && ok "provide theme_icons (#230): a step with its receipt and undo, kept in the config; the same value again refused, a wrong word too" || bad "icons steps" "$(cut -c1-400 "$H/mcp.out")"
    sh "$SH" theme save iconlook >/dev/null 2>&1; sh "$SH" theme icons on >/dev/null 2>&1; sh "$SH" theme iconlook >/dev/null 2>&1
    grep -qx 'DIALOG_ICONS=off' "$th_dir/iconlook/look.env" && grep -qx 'DIALOG_ICONS=off' "$cfg" \
        && ok "theme save keeps the app icons, and the theme brings them back (#230)" || bad "icons look kept" "$(cat "$th_dir/iconlook/look.env" 2>&1; grep DIALOG_ICONS "$cfg")"
    sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme delete iconlook </dev/null >/dev/null 2>&1; sh "$SH" theme icons on >/dev/null 2>&1
    printf 'DIALOG_ICONS=yes\n' >> "$cfg"; st=0; out=$(sh "$SH" theme 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s' "$out" | grep -q 'DIALOG_ICONS=yes in .*: on or off' && ok "config: DIALOG_ICONS other than on or off is refused in one line (#230)" || bad "icons refuse" "st=$st $out"
    sed -i.bak '/^DIALOG_ICONS=yes$/d' "$cfg"; rm -f "$cfg.bak"
    # their space (#232): a value in Settings > theme that left and right change, groups to begin with; a step with its
    # undo, the same value again a refusal; kept with a saved theme and brought back; a wrong word refused in one line
    jq -e '.rows[] | select(.id == "theme:show:App spacing") | .step == {values: [{shown: "none", sent: "none"}, {shown: "groups", sent: "groups"}, {shown: "rows", sent: "rows"}], at: 1, set: {name: "theme_spacing", arguments: {}}, key: "to", words: ["less", "more"]} and .group == "dialog"' "$H/trows.json" >/dev/null \
        && ok "provide theme rows (#232): app spacing a value, none, groups or rows, at groups" || bad "spacing row" "$(jq -c '[.rows[] | select(.id | test("spacing"))]' "$H/trows.json")"
    mcp theme "$(call 1 theme_spacing '{"to":"rows"}')" "$(call 2 theme_spacing '{"to":"rows"}')" "$(call 3 theme_spacing '{"to":"lots"}')"
    [ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = 'app spacing rows' ] && ans 1 | jq -e '.result.structuredContent.undo | .name == "theme_spacing" and .arguments.to == "groups"' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'app spacing is rows already' ] && ans 3 | jq -e '.error.message | startswith("theme_spacing:")' >/dev/null && grep -qx 'DIALOG_SPACING=rows' "$cfg" \
        && ok "provide theme_spacing (#232): a step with its receipt and undo, kept in the config; the same value again refused, a wrong word too" || bad "spacing steps" "$(cut -c1-400 "$H/mcp.out")"
    sh "$SH" theme save roomlook >/dev/null 2>&1; sh "$SH" theme spacing none >/dev/null 2>&1; sh "$SH" theme roomlook >/dev/null 2>&1
    grep -qx 'DIALOG_SPACING=rows' "$th_dir/roomlook/look.env" && grep -qx 'DIALOG_SPACING=rows' "$cfg" \
        && ok "theme save keeps the app spacing, and the theme brings it back (#232)" || bad "spacing look kept" "$(cat "$th_dir/roomlook/look.env" 2>&1; grep DIALOG_SPACING "$cfg")"
    sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme delete roomlook </dev/null >/dev/null 2>&1; sh "$SH" theme spacing groups >/dev/null 2>&1
    printf 'DIALOG_SPACING=lots\n' >> "$cfg"; st=0; out=$(sh "$SH" theme 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s' "$out" | grep -q 'DIALOG_SPACING=lots in .*: none, groups or rows' && ok "config: DIALOG_SPACING other than none, groups or rows is refused in one line (#232)" || bad "spacing refuse" "st=$st $out"
    sed -i.bak '/^DIALOG_SPACING=lots$/d' "$cfg"; rm -f "$cfg.bak"
    # the moving wallpaper (#180): a value in Settings > theme that left and right change; a step with its undo, the same value
    # again a refusal; kept with a saved theme; refused in one line where the tools are not here; a wrong word in the config refused
    jq -e '.rows[] | select(.id == "theme:show:Moving wallpaper") | .switch == {on: false, turn_on: {name: "theme_motion", arguments: {to: "on"}}, turn_off: {name: "theme_motion", arguments: {to: "off"}}} and .tool == null and .group == "screen"' "$H/trows.json" >/dev/null \
        && ok "provide theme rows (#180, #183): the moving wallpaper, a switch" || bad "motion row" "$(jq -c '[.rows[] | select(.id | test("Moving"))]' "$H/trows.json")"
    mkdir -p "$H/mot"; for t in python3 rsvg-convert mpv spark-wallpaper; do printf '#!/bin/sh\nexit 0\n' > "$H/mot/$t"; chmod +x "$H/mot/$t"; done
    ( PATH=$H/mot:$PATH; SPARK_SHELL_WALLPAPER=$H/mot/spark-wallpaper; export SPARK_SHELL_WALLPAPER; mcp theme "$(call 1 theme_motion '{"to":"on"}')" "$(call 2 theme_motion '{"to":"on"}')" )
    ans 1 | jq -r '.result.structuredContent.receipt' | grep -q '^moving wallpaper on .* dunes is still; 13 wallpapers move$' && ans 1 | jq -e '.result.structuredContent.undo | .name == "theme_motion" and .arguments.to == "off"' >/dev/null \
        && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'the moving wallpaper is on already' ] && grep -qx 'WALLPAPER_MOTION=on' "$cfg" \
        && ok "provide theme_motion (#180): a step with its receipt (the drawing in use still, the ones that move named) and undo, kept in the config; the same value again refused" || bad "motion step" "$(cut -c1-300 "$H/mcp.out")"
    sh "$SH" theme save motionlook >/dev/null 2>&1; sh "$SH" theme motion off >/dev/null 2>&1; sh "$SH" theme motionlook >/dev/null 2>&1
    grep -qx 'WALLPAPER_MOTION=on' "$th_dir/motionlook/look.env" && grep -qx 'WALLPAPER_MOTION=on' "$cfg" && ok "theme save keeps the moving wallpaper, and the theme brings it back (#180)" || bad "motion look kept" "$(cat "$th_dir/motionlook/look.env" 2>&1; grep MOTION "$cfg")"
    sh "$SH" theme dracula >/dev/null 2>&1; sh "$SH" theme delete motionlook </dev/null >/dev/null 2>&1; sh "$SH" theme motion off >/dev/null 2>&1
    rc=0; out=$(env -u SPARK_SHELL_WALLPAPER sh "$SH" theme motion on 2>&1) || rc=$?   # no player of the release's in this clone
    [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -q 'the moving wallpaper needs .*spark-wallpaper' && grep -qx 'WALLPAPER_MOTION=off' "$cfg" \
        && ok "theme motion on: refused in one line where the wallpaper loop is not here, the setting left off (#180, #187)" || bad "motion skip" "rc=$rc $out"
    printf 'WALLPAPER_MOTION=fast\n' >> "$cfg"; st=0; out=$(sh "$SH" theme 2>&1) || st=$?
    [ "$st" -eq 1 ] && printf '%s' "$out" | grep -q 'WALLPAPER_MOTION=fast in .*: on or off' && ok "config: WALLPAPER_MOTION other than on or off is refused in one line (#180)" || bad "motion refuse" "st=$st $out"
    sed -i.bak '/^WALLPAPER_MOTION=fast$/d' "$cfg"; rm -f "$cfg.bak"
    sh "$SH" theme wallpaper dunes >/dev/null 2>&1
    mcp theme "$(call 1 theme_wallpaper '{"name":"sunset"}')" "$(call 2 theme_wallpaper '{"name":"nowhere"}')" "$(call 3 theme_wallpaper '{"name":"sunset"}')" "$(call 4 theme_palette '{"name":"dracula"}')"
    [ "$(ans 1 | jq -r '.result.structuredContent.receipt')" = 'the wallpaper is sunset' ] && grep -qx 'WALLPAPER=dunes' "$cfg" && [ "$(ans 1 | jq -c '.result.structuredContent.undo')" = '{"name":"theme_wallpaper","arguments":{"name":"dunes"}}' ] \
        && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'nowhere is not in the list now' ] \
        && [ "$(ans 3 | jq -r '.result.structuredContent.receipt')" = 'the wallpaper is sunset' ] && [ "$(ans 4 | jq -r '.result.structuredContent.receipt')" = 'dracula is on' ] \
        && ok "provide theme_wallpaper: a row of the list is a step with its undo; a name no row holds is refused; what is in use, chosen again, is a receipt (#29), and dracula chosen again brings dunes back over sunset" || bad "theme_wallpaper call" "$(cat "$H/mcp.out")"
fi
mcp theme "$(rq 1 tools/list)" "$(call 2 theme_words '{"hue":"blue","accent":"same","warmth":"cool","contrast":"normal"}')" "$(call 3 theme_words '{"hue":"blue","accent":"same","warmth":"cool","contrast":"normal","light":"dim","face":"neon","family":"stone","animation":"tide","drawing":"fjord"}')" "$(call 4 theme_delete '{"name":"nord"}')" "$(call 5 theme_back '{}')" "$(call 6 theme_words '{"hue":"blue","accent":"same","warmth":"cool","contrast":"normal","light":"dark","face":"neon","family":"stone","animation":"tide","drawing":"fjord","name":"a name that runs on and on past forty letters"}')" "$(call 7 theme_words '{"hue":"blue","accent":"same","warmth":"cool","contrast":"normal","light":"dark","face":"comic","family":"stone","animation":"tide","drawing":"fjord"}')"
ans 1 | jq -e '.result.tools[] | select(.name == "theme_words") | .inputSchema.required == ["hue", "accent", "warmth", "contrast", "light", "face", "family", "animation", "drawing"] and .inputSchema.properties.light.enum == ["dark", "light"] and .inputSchema.properties.hue.enum[0] == "red" and .inputSchema.properties.accent.enum[-1] == "same" and .inputSchema.properties.name.maxLength == 40
        and .inputSchema.properties.face.enum == ["neon", "argon", "xenon", "radon", "krypton"] and .inputSchema.properties.family.enum == ["stone", "star", "banner"] and .inputSchema.properties.animation.enum == ["moon", "ripple", "tide", "embers", "sun", "flight"] and (.inputSchema.properties.drawing.enum | index("fjord") != null and index("onsen") == null)' >/dev/null \
    && ans 1 | jq -e '.result.tools[] | select(.name == "theme_picture") | .inputSchema.required == ["path"] and .inputSchema.properties.face.enum[0] == "neon" and .inputSchema.properties.family.enum[-1] == "banner" and .inputSchema.properties.animation.enum[0] == "moon" and (.inputSchema.properties | has("drawing") | not)' >/dev/null \
    && ans 7 | jq -e '.error.message | startswith("theme_words: face is one of neon")' >/dev/null \
    && [ "$(ans 2 | jq -r .error.message)" = 'theme_words: missing light' ] && [ "$(ans 3 | jq -r .error.message)" = 'theme_words: light is one of dark, light' ] && [ "$(ans 6 | jq -r .error.message)" = 'theme_words: name is plain text, 40 characters at most' ] \
    && [ "$(ans 4 | jq -r '.result.content[0].text')" = 'theme: no saved theme named nord' ] && [ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'back to desk' ] && grep -qx 'THEME=desk' "$cfg" \
    && ok "provide theme: theme_words takes nine closed words, each required (the palette's five, the face, the family, the animation and the drawing, #247), and a short name; theme_picture may take the face, the family and the animation; a palette is no saved theme to delete; theme_back steps back with the receipt" || bad "theme tools" "$(cat "$H/mcp.out" | cut -c1-300)"
# layouts keep the same history: a layout made from words is kept, layout back opens it again with no model call
printf 'DESKTOP=sway\n' > "$cfg"
if [ "$(uname -s)" != Darwin ]; then
    layout_stubs
    printf '{"main":{"app":"gimp-3.0"},"side":[{"app":"firefox"}]}\n' > "$H/answer.json"
    st=0; out=$(SWAYSOCK=$H/sock sh "$SH" layout "photo editing for instagram" 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ -f "$st_dir/layouts/photo-editing-for-instagram" ] && [ "$(sed -n 1p "$st_dir/layout.history" | cut -f2)" = photo-editing-for-instagram ] && ok "layout WORDS: kept under the words' name in the state, first in the layout history" || bad "layout kept" "$out $(ls "$st_dir/layouts" 2>&1; cat "$st_dir/layout.history" 2>&1)"
    sh "$SH" layout save studio >/dev/null 2>&1
    rm -f "$st_dir/spark.argv"; st=0; out=$(SWAYSOCK=$H/sock sh "$SH" layout photo-editing-for-instagram 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ ! -e "$st_dir/spark.argv" ] && printf '%s\n' "$out" | grep -q 'the layout photo-editing-for-instagram again' && ok "layout NAME of a kept one: opened again from the kept copy, no model call" || bad "layout kept open" "$out"
    st=0; out=$(SWAYSOCK=$H/sock sh "$SH" layout back 2>&1) || st=$?
    [ "$st" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = 'back to studio' ] && [ ! -e "$st_dir/spark.argv" ] && ok "layout back: the layout before, opened again, no model call" || bad "layout back" "$out $(cat "$st_dir/layout.history")"
    out=$(sh "$SH" panel layout --list); printf '%s\n' "$out" | grep -q "	layout open studio$" && [ "$(printf '%s\n' "$out" | grep -c 'layout open photo-editing-for-instagram')" -ge 1 ] && ok "panel layout: the back rows open the kept layouts by name" || bad "layout back rows" "$out"
    out=$(sh "$SH" layout delete studio </dev/null 2>&1); [ "$out" = 'deleted studio' ] && ! grep -q studio "$st_dir/layout.history" && ok "layout delete: the file and its history lines gone" || bad "layout delete history" "$out $(cat "$st_dir/layout.history")"
    rm -f "$H/answer.json"
fi

# --- update: the clone moves to the newest signed tag, never a plain pull (#30)
# A bare origin and a scratch key stand in for GitHub and the release key;
# the user's clone is at v9.0. Newer tags: one signed by the key, one
# unsigned, one signed by a key the file does not hold, one whose object
# names another tag. ssh-keygen reads the signatures; without it the
# section is a note.
if command -v ssh-keygen >/dev/null 2>&1; then
    fresh
    U=$(tmpd)
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
    ssh-keygen -q -t ed25519 -N '' -C t -f "$U/key"
    ssh-keygen -q -t ed25519 -N '' -C o -f "$U/other"
    git init -q --bare -b main "$U/origin.git"
    git init -q -b main "$U/w"
    # the whole tree, on --yes needs the templates: a tar copy owned by this
    # user (CI's containers run as root over a checkout another user owns:
    # git archive refuses it, and tar as root would keep that owner, which
    # git then refuses as dubious); the dialog's build dir left out
    (cd "$REPO" && tar -cf - --exclude=.git --exclude=target --exclude=target2 .) | tar -xf - --no-same-owner -C "$U/w"   # no crate's build: the dialog's, the player's or the pad's, hundreds of MB each
    cp "$SH" "$U/w/spark-shell"
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$U/key.pub")" > "$U/w/allowed-signers"
    git -C "$U/w" config gpg.format ssh
    git -C "$U/w" config user.signingkey "$U/key"
    git -C "$U/w" remote add origin "$U/origin.git"
    git -C "$U/w" add -A && git -C "$U/w" commit -q -m v9.0 && git -C "$U/w" tag -s -m v9.0 v9.0 && git -C "$U/w" push -q origin main v9.0
    git clone -q "$U/origin.git" "$U/c"
    C=$U/c/spark-shell
    out=$(sh "$C" update 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$out" = "spark-shell update: at v9.0, the newest release" ] && ok "update: nothing newer: one line, exit 0" || bad "update: nothing newer" "$rc $out"
    echo one > "$U/w/one"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.1; git -C "$U/w" tag -s -m v9.1 v9.1
    echo two > "$U/w/two"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.2; git -C "$U/w" tag -a -m v9.2 v9.2
    echo three > "$U/w/three"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.3; git -C "$U/w" -c user.signingkey="$U/other" tag -s -m v9.3 v9.3
    git -C "$U/w" tag -s -m v9.4 v9.4
    git -C "$U/w" push -q origin main v9.1 v9.2 v9.3 refs/tags/v9.4:refs/tags/v9.5
    out=$(sh "$C" update --dry-run 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$out" = "spark-shell update: would move v9.0 -> v9.1, signed by spark-shell-release (skipped, not a signed release: v9.5 v9.3 v9.2)" ] \
        && [ "$(git -C "$U/c" rev-parse HEAD)" = "$(git -C "$U/c" rev-parse 'v9.0^{commit}')" ] \
        && ok "update --dry-run: names the move and the tags skipped (unsigned, another key, another name), moves nothing" || bad "update --dry-run" "$rc $out"
    echo x >> "$U/c/spark-shell"
    out=$(sh "$C" update 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 1 ] && [ "$out" = "spark-shell update: the clone has changes of its own (git -C $U/c status) -- nothing moved" ] && ok "update: a clone with changes of its own is refused, nothing moved" || bad "update: dirty clone" "$rc $out"
    git -C "$U/c" checkout -q -- spark-shell
    out=$(sh "$C" update 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$out" = "spark-shell update: v9.1, signed by spark-shell-release (was v9.0) (skipped, not a signed release: v9.5 v9.3 v9.2)" ] \
        && [ "$(git -C "$U/c" rev-parse HEAD)" = "$(git -C "$U/c" rev-parse 'v9.1^{commit}')" ] && [ ! -e "$HOME/.tmux.conf" ] \
        && ok "update: moves to the newest signed tag, says who signed it, runs no on while the seat is off" || bad "update: the move" "$rc $out"
    out=$(sh "$C" update 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 1 ] && [ "$out" = "spark-shell update: the releases past v9.1 are not signed by a key in allowed-signers: v9.5 v9.3 v9.2 -- nothing moved" ] \
        && [ "$(git -C "$U/c" rev-parse HEAD)" = "$(git -C "$U/c" rev-parse 'v9.1^{commit}')" ] \
        && ok "update: newer tags none of which is a signed release: refused, named, nothing moved" || bad "update: none signed" "$rc $out"
    # the seat on: on --yes runs from the new tree after the move
    sh "$C" on --yes >/dev/null 2>&1 || :
    echo six > "$U/w/six"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.6; git -C "$U/w" tag -s -m v9.6 v9.6; git -C "$U/w" push -q origin main v9.6
    mkdir "$U/t"; out=$(TMPDIR=$U/t sh "$C" update 2>&1) && rc=0 || rc=$?
    first=$(printf '%s\n' "$out" | sed -n 1p)
    [ -z "$(ls -A "$U/t")" ] && ok "update with the seat on: its temp folder goes before the new tree takes over (an exec runs no trap)" || bad "update temp folder" "$(ls -A "$U/t")"
    [ "$rc" -eq 0 ] && [ "$first" = "spark-shell update: v9.6, signed by spark-shell-release (was v9.1)" ] \
        && [ "$(printf '%s\n' "$out" | wc -l)" -gt 1 ] && [ "$(git -C "$U/c" rev-parse HEAD)" = "$(git -C "$U/c" rev-parse 'v9.6^{commit}')" ] \
        && ok "update with the seat on: the move, then on --yes from the new tree" || bad "update: seat on" "$rc $out"
    # a tag is up before its release: a seat stays where it is until the build can be fetched (the owner's box, v0.124.2)
    mkdir -p "$U/bin" "$U/rel"
    printf '#!/bin/sh\ncase "$1" in -m) echo x86_64 ;; *) exec "%s" "$@" ;; esac\n' "$(command -v uname)" > "$U/bin/uname"; chmod +x "$U/bin/uname"
    echo seven > "$U/w/seven"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.7; git -C "$U/w" tag -s -m v9.7 v9.7; git -C "$U/w" push -q origin main v9.7
    out=$(PATH=$U/bin:$PATH SPARK_SHELL_DIALOG_URL="file://$U/rel" sh "$C" update 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 1 ] && [ "$out" = "spark-shell update: v9.7 is signed, but its release is not published yet -- nothing moved; try again in a few minutes" ] \
        && [ "$(git -C "$U/c" rev-parse HEAD)" = "$(git -C "$U/c" rev-parse 'v9.6^{commit}')" ] \
        && ok "update: a tag whose release is not up moves nothing, and says so" || bad "update: release not up" "$rc $out"
    mkdir -p "$U/rel/v9.7"; : > "$U/rel/v9.7/spark-dialog-x86_64-linux-musl"
    out=$(PATH=$U/bin:$PATH SPARK_SHELL_DIALOG_URL="file://$U/rel" sh "$C" update 2>&1) && rc=0 || rc=$?
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "spark-shell update: v9.7, signed by spark-shell-release (was v9.6)" ] \
        && [ "$(git -C "$U/c" rev-parse HEAD)" = "$(git -C "$U/c" rev-parse 'v9.7^{commit}')" ] \
        && ok "update: once the release is up, the same command moves" || bad "update: release up" "$rc $out"
    # the floor is the newest tag a key in allowed-signers signed: an unsigned tag at the clone's commit stops nothing (v0.129.3)
    git clone -q "$U/origin.git" "$U/d"; D=$U/d/spark-shell; git -C "$U/d" -c advice.detachedHead=false checkout -q --detach v9.7
    git -C "$U/w" tag -a -m v99.0 v99.0 v9.7; git -C "$U/w" push -q origin v99.0
    out=$(sh "$D" update --dry-run 2>&1) && rc=0 || rc=$?
    out2=$(sh "$D" update --dry-run 2>&1) && rc2=0 || rc2=$?
    [ "$rc" -eq 1 ] && [ "$rc2" -eq 1 ] && [ "$out2" = "spark-shell update: the releases past v9.7 are not signed by a key in allowed-signers: v99.0 -- nothing moved" ] \
        && ok "update: an unsigned tag at the clone's commit is no floor: refused and named, every run, never the newest release" || bad "update: unsigned floor" "$rc $out | $rc2 $out2"
    [ "$(sh "$D" panel about --list 2>/dev/null | grep -c 'spark-shell 9\.7')" -ge 1 ] && ok "about: the version is the signed release, not an unsigned tag beside it" || bad "version floor" "$(sh "$D" panel about --list 2>&1)"
    echo eight > "$U/w/eight"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.8; git -C "$U/w" tag -s -m v9.8 v9.8; git -C "$U/w" push -q origin main v9.8
    out=$(sh "$D" update --dry-run 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = "spark-shell update: would move v9.7 -> v9.8, signed by spark-shell-release (skipped, not a signed release: v99.0)" ] \
        && ok "update: a real release past that tag is found and moved to" || bad "update: past the unsigned" "$rc $out"
    # a signature that is not ssh is never read: gpg's keyring is no allowed-signers
    mkdir -p "$U/gpg"; cat > "$U/gpg/gpg" <<'GPG'
#!/bin/sh
printf '[GNUPG:] NEWSIG\n[GNUPG:] GOODSIG 0000000000000000 mallory\n[GNUPG:] VALIDSIG 00 2026-01-01 0 4 0 22 8 00 00\n[GNUPG:] TRUST_UNDEFINED 0 pgp\n'
GPG
    chmod +x "$U/gpg/gpg"
    echo nine > "$U/w/nine"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.9
    _obj=$(printf 'object %s\ntype commit\ntag v9.9\ntagger m <m> 1700000000 +0000\n\nv9.9\n-----BEGIN PGP SIGNATURE-----\n\nAAAA\n-----END PGP SIGNATURE-----\n' "$(git -C "$U/w" rev-parse HEAD)" | git -C "$U/w" hash-object -t tag -w --stdin)
    git -C "$U/w" update-ref refs/tags/v9.9 "$_obj"; git -C "$U/w" push -q origin main v9.9
    out=$(PATH=$U/gpg:$PATH sh "$D" update --dry-run 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = "spark-shell update: would move v9.7 -> v9.8, signed by spark-shell-release (skipped, not a signed release: v99.0 v9.9)" ] \
        && ok "update: a PGP signature gpg calls good is not a key in allowed-signers: skipped, named" || bad "update: pgp" "$rc $out"
    # a tag moved on origin stays as it was seen here, is said, and stops nothing after it
    git -C "$U/w" tag -d v9.8 >/dev/null; git -C "$U/w" tag -s -m v9.8 v9.8; git -C "$U/w" push -q -f origin v9.8
    echo ten > "$U/w/ten"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v9.10; git -C "$U/w" tag -s -m v9.10 v9.10; git -C "$U/w" push -q origin main v9.10
    _was=$(git -C "$U/d" rev-parse v9.8)
    out=$(sh "$D" update --dry-run 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && [ "$(printf '%s\n' "$out" | sed -n 1p)" = "spark-shell update: v9.8 moved on origin: the copy here stays" ] \
        && [ "$(printf '%s\n' "$out" | sed -n 2p)" = "spark-shell update: would move v9.7 -> v9.10, signed by spark-shell-release (skipped, not a signed release: v99.0)" ] && [ "$(git -C "$U/d" rev-parse v9.8)" = "$_was" ] \
        && ok "update: a tag moved on origin is said, the copy here stays, and the release after it is found" || bad "update: moved tag" "$rc $out"
    # a tag the release key signs that is no dotted release name (the gallery's are gallery-vN; v77 stands for any other) is never a release
    echo eleven > "$U/w/eleven"; git -C "$U/w" add -A; git -C "$U/w" commit -q -m v77; git -C "$U/w" tag -s -m v77 v77; git -C "$U/w" push -q origin main v77
    out=$(sh "$D" update --dry-run 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 0 ] && ! printf '%s\n' "$out" | grep -q 'v77' && ok "update: a signed tag that is no dotted release name (v77) is never taken as a release (#247)" || bad "update: undotted tag" "$rc $out"
    git -C "$U/d" remote set-url origin "$U/gone.git"
    out=$(sh "$D" update --dry-run 2>&1) && rc=0 || rc=$?
    [ "$rc" -eq 1 ] && [ "$out" = "spark-shell update: could not fetch the tags from origin" ] && ok "update: an origin that does not answer is still refused" || bad "update: no origin" "$rc $out"
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_NOSYSTEM
    rm -rf "$U"
else
    printf '  note update: ssh-keygen not found; the section is skipped\n'
fi
# the gallery (#247, arc 5): its newest release (gallery-vN) a key in allowed-signers signed for the gallery, every file its
# index line's size and sha256, data alone; a newer unsigned tag, another key's and the key's for something else skipped
# and named; a stale index, a key a shared theme never sets, a list's value of two words, a picture not as its name, its
# header or its chunks say, more files than a theme holds, a link in the tree and another format refused; a damaged floor
# refused, and an older release than was seen; a theme installed as a saved theme and worn, a wallpaper installed and shown
if command -v ssh-keygen >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    fresh
    U=$(tmpd)
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
    ssh-keygen -q -t ed25519 -N '' -C t -f "$U/key"; ssh-keygen -q -t ed25519 -N '' -C o -f "$U/other"
    mkdir -p "$U/c"; (cd "$REPO" && tar -cf - --exclude=.git --exclude=target .) | tar -xf - --no-same-owner -C "$U/c"; cp "$SH" "$U/c/spark-shell"
    printf 'spark-shell-release namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$U/key.pub")" > "$U/c/allowed-signers"
    G=$U/gallery; mkdir -p "$G/themes/harbor" "$G/wallpapers"
    python3 -I "$REPO/lib/look.py" words --hue teal --accent orange --warmth cool --contrast normal --light dark > "$G/themes/harbor/palette.env"
    printf 'FORMAT=2\nPALETTE=words\nWORDS=harbor at dusk\nWALLPAPER=fjord\nFACE=xenon\nGLYPH_FAMILY=banner\nANIMATION=tide\nALPHA=0.9\n' > "$G/themes/harbor/look.env"
    cp "$REPO/gallery/wallpaper/kites.png" "$G/wallpapers/tidelines.png"
    gsum() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
    gindex() { (cd "$G" && { echo '# spark-shell gallery 1'
        for f in themes/*/* wallpapers/*; do [ -f "$f" ] || continue
            case $f in themes/*) k=theme; n=${f#themes/}; n=${n%%/*} ;; *) k=wallpaper; n=${f#wallpapers/}; n=${n%.*} ;; esac
            printf '%s\t%s\t%s\t%s\t%s\n' "$k" "$n" "$f" "$(wc -c < "$f" | tr -d ' ')" "$(gsum "$f")"
        done; } > index.tsv); }
    gtag() {   # gtag TAG [KEY [MESSAGE]] -- the tree committed and tagged: signed with KEY when one is given, its message the gallery's line unless another is
        git -C "$G" add -A; git -C "$G" commit -q --allow-empty -m "$1"
        if [ -n "${2:-}" ]; then git -C "$G" -c gpg.format=ssh -c user.signingkey="$2" tag -s -m "${3:-spark-shell-gallery $1}" "$1"; else git -C "$G" tag -a -m "spark-shell-gallery $1" "$1"; fi
    }
    GS() { SPARK_SHELL_GALLERY_URL=$G sh "$U/c/spark-shell" "$@"; }
    git init -q -b main "$G"; gindex; gtag gallery-v1 "$U/key"
    cfg=$HOME/.config/spark-shell/config; mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$cfg"
    GS theme nord >/dev/null 2>&1
    out=$(GS theme gallery 2>&1) || :
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "The gallery at gallery-v1 ($G), signed by a key in allowed-signers:" ] && printf '%s\n' "$out" | grep -qx '  harbor               xenon, banner, tide, fjord' \
        && printf '%s\n' "$out" | grep -qx "  tidelines            png, $(($(wc -c < "$G/wallpapers/tidelines.png") / 1024)) KiB" && [ "$(printf '%s\n' "$out" | tail -1)" = 'spark-shell theme install NAME puts one in place and uses it.' ] \
        && [ "$(cat "$HOME/.local/state/spark-shell/gallery.floor")" = gallery-v1 ] \
        && ok "theme gallery: the release a key in allowed-signers signed, its themes with their face, family, animation and wallpaper, its wallpapers with their size; the floor at it (#247)" || bad "theme gallery" "$out"
    printf 'POINTER=spark-white 32\n' >> "$cfg"
    out=$(GS theme install harbor 2>&1) || :
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "installed the theme harbor from the gallery's gallery-v1, signed and its sha256s checked -- spark-shell theme harbor brings it back" ] \
        && grep -qx 'PALETTE=gallery' "$HOME/.config/spark-shell/themes/harbor/look.env" && grep -qx 'GALLERY=gallery-v1' "$HOME/.config/spark-shell/themes/harbor/look.env" \
        && cmp -s "$G/themes/harbor/palette.env" "$HOME/.config/spark-shell/themes/harbor/palette.env" && grep -qx 'THEME=harbor' "$cfg" && grep -qx 'GLYPH_FAMILY=banner' "$cfg" && grep -qx 'POINTER=spark-white 32' "$cfg" \
        && { [ "$(uname -s)" = Darwin ] || { grep -q '^FONT=Monaspace Xenon:' "$cfg" && grep -qx 'DIALOG_ANIMATION=tide' "$cfg"; }; } \
        && ok "theme install NAME: a theme becomes a saved theme from the gallery's release, its face, family and animation worn, the pointer yours (#247)" || bad "theme install" "$out $(cat "$cfg")"
    if [ "$(uname -s)" != Darwin ]; then
        out=$(GS theme install tidelines 2>&1) || :
        [ "$(printf '%s\n' "$out" | sed -n 1p)" = "installed the wallpaper tidelines from the gallery's gallery-v1, signed and its sha256 checked ($HOME/.local/share/spark-shell/gallery/tidelines.png)" ] \
            && grep -qx "WALLPAPER=$HOME/.local/share/spark-shell/gallery/tidelines.png" "$cfg" && cmp -s "$G/wallpapers/tidelines.png" "$HOME/.local/share/spark-shell/gallery/tidelines.png" \
            && GS theme gallery 2>&1 | grep -qx '  harbor               xenon, banner, tide, fjord, installed' \
            && ok "theme install NAME: a wallpaper is put in place and shown; the gallery's list says what is installed (#247)" || bad "theme install wallpaper" "$out $(grep WALLPAPER "$cfg")"
    fi
    rc=0; out=$(GS theme install nothing 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = "spark-shell theme: the gallery's gallery-v1 has no theme or wallpaper named nothing -- spark-shell theme gallery lists them" ] && ok "theme install with a name the gallery has not: refused in one line" || bad "install nothing" "rc=$rc $out"
    rc=0; out=$(GS theme install ../harbor 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: install takes a gallery name: lowercase letters, digits and -' ] && ok "theme install with a name that is not one: refused before anything is fetched" || bad "install bad name" "rc=$rc $out"
    sed -i.bak '/^GALLERY=/d' "$HOME/.config/spark-shell/themes/harbor/look.env"; rm -f "$HOME/.config/spark-shell/themes/harbor/look.env.bak"
    rc=0; out=$(GS theme install harbor 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: a saved theme of yours is named harbor -- spark-shell theme delete harbor first, or keep yours' ] && ok "theme install over a saved theme of yours: refused, yours kept" || bad "install over yours" "rc=$rc $out"
    printf 'GALLERY=gallery-v1\n' >> "$HOME/.config/spark-shell/themes/harbor/look.env"
    # newer tags: one no key signed, one another key signed, one the key signed for something else (no gallery line); skipped
    # and named, the release before them taken
    printf 'FORMAT=2\nPALETTE=words\nWALLPAPER=fjord\nFACE=radon\n' > "$G/themes/harbor/look.env"; gindex; gtag gallery-v2
    gtag gallery-v3 "$U/other"; gtag gallery-v4 "$U/key" 'gallery-v4'
    out=$(GS theme gallery 2>&1) || :
    [ "$(printf '%s\n' "$out" | sed -n 1p)" = "The gallery at gallery-v1 ($G), signed by a key in allowed-signers:" ] && printf '%s\n' "$out" | grep -qx 'Not taken, as no key in allowed-signers signed them: gallery-v4 gallery-v3 gallery-v2.' \
        && ok "theme gallery: a newer tag no key signed, another key's, or the key's for something else (no gallery line) is skipped and named; the release before them taken" || bad "gallery unsigned" "$out"
    gex() {   # gex TAG WHY WHAT -- the gallery's TAG, signed; theme install harbor refused with WHY after "was not installed: "
        gtag "$1" "$U/key"; rc=0; out=$(GS theme install harbor 2>&1) || rc=$?
        [ "$rc" = 1 ] && [ "$out" = "spark-shell theme: harbor from the gallery's $1 was not installed: $2" ] && ok "theme install (#247): $3" || bad "install: $3" "rc=$rc $out"
    }
    printf 'FORMAT=2\nPALETTE=words\nWALLPAPER=fjord\nFACE=krypton\n' > "$G/themes/harbor/look.env"
    gex gallery-v5 'themes/harbor/look.env is not the file the gallery'"'"'s index names: its size or its sha256 differs' "a file not as its index line says is refused, even in a signed release"
    printf 'FORMAT=2\nPALETTE=words\nWALLPAPER=fjord\nPOINTER=Adwaita 24\n' > "$G/themes/harbor/look.env"; gindex
    gex gallery-v6 'its look.env holds POINTER, which a shared theme never sets' "a key a shared theme never sets (the pointer, the text size, a file) is refused"
    printf 'FORMAT=2\nPALETTE=words\nWALLPAPER=fjord\nFACE=neon argon\n' > "$G/themes/harbor/look.env"; gindex
    gex gallery-v7 'its FACE is not neon, argon, xenon, radon or krypton' "a list's value of two words is refused, never matched inside the list"
    printf 'FORMAT=2\nPALETTE=words\nWALLPAPER=picture\nPICTURE=dusk.png\n' > "$G/themes/harbor/look.env"
    printf '\377\330\377\300\000\021\010\000\020\000\040\003\001\021\000\002\021\000\003\021\000\377\331' > "$G/themes/harbor/dusk.png"; gindex
    gex gallery-v8 'its picture is a jpeg named dusk.png' "a picture not of the kind its name says is refused"
    printf '\211PNG\r\n\032\n\000\000\000\015IHDR\000\000\043\050\000\000\000\020\010\002\000\000\000\000\000\000\000\000\000\000\000IEND\256B`\202' > "$G/themes/harbor/dusk.png"; gindex
    gex gallery-v9 'its picture is 9000x16, past 7680x4320' "a picture past the pixels a gallery picture may have is refused from its header, nothing decoded"
    printf '\211PNG\r\n\032\n\000\000\000\015IHDR\000\000\000\001\000\000\000\001\010\002\000\000\000\000\000\000\000\000\000\000\010acTL\000\000\000\001\000\000\000\000\000\000\000\000\000\000\000\000IEND\256B`\202' > "$G/themes/harbor/dusk.png"; gindex
    gex gallery-v10 "its picture is a PNG with a 'acTL' chunk, which a still picture has not" "a picture with more than a still picture's chunks (an animation, metadata) is refused"
    cp "$G/themes/harbor/dusk.png" "$G/themes/harbor/dawn.png"; gindex; gtag gallery-v11 "$U/key"
    rc=0; out=$(GS theme install harbor 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = "spark-shell theme: the gallery's index is not as its format says (line 5: more files than its kind holds)" ] && [ "$(cat "$HOME/.local/state/spark-shell/gallery.floor")" = gallery-v10 ] \
        && ok "theme install: a theme of more files than a theme holds is refused at the index, nothing taken out, the floor where it was (#247)" || bad "install four files" "rc=$rc $out"
    rm "$G/themes/harbor/dusk.png" "$G/themes/harbor/dawn.png"; printf 'FORMAT=2\nPALETTE=words\nWALLPAPER=fjord\n' > "$G/themes/harbor/look.env"
    mv "$G/themes/harbor/palette.env" "$U/palette.env"; ln -s "$U/palette.env" "$G/themes/harbor/palette.env"; gindex
    awk -F '\t' -v OFS='\t' -v z="$(wc -c < "$U/palette.env" | tr -d ' ')" -v h="$(gsum "$U/palette.env")" '$3 == "themes/harbor/palette.env" { $4 = z; $5 = h } { print }' "$G/index.tsv" > "$U/i" && mv "$U/i" "$G/index.tsv"
    gex gallery-v12 'themes/harbor/palette.env is not a plain file in the gallery' "a link in the gallery's tree is never followed or kept"
    sed -i.bak '1s/1$/2/' "$G/index.tsv"; rm -f "$G/index.tsv.bak"; gtag gallery-v13 "$U/key"
    rc=0; out=$(GS theme gallery 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = "spark-shell theme: the gallery's gallery-v13 is of another format than this spark-shell reads -- spark-shell update" ] && ok "theme gallery: a release of another format is refused, never half read" || bad "gallery format" "rc=$rc $out"
    cp "$HOME/.local/state/spark-shell/gallery.floor" "$U/floor"; printf 'garbage\n' > "$HOME/.local/state/spark-shell/gallery.floor"
    rc=0; out=$(GS theme gallery 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = "spark-shell theme: the gallery's floor ($HOME/.local/state/spark-shell/gallery.floor) names no release: remove it to start over" ] && ok "theme gallery: a damaged floor is refused, never read as no floor" || bad "gallery floor damaged" "rc=$rc $out"
    cp "$U/floor" "$HOME/.local/state/spark-shell/gallery.floor"
    git clone -q --bare "$G" "$U/old.git"; for t in 2 3 4 5 6 7 8 9 10 11 12 13; do git -C "$U/old.git" tag -d "gallery-v$t" >/dev/null; done
    rc=0; out=$(SPARK_SHELL_GALLERY_URL=$U/old.git sh "$U/c/spark-shell" theme gallery 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell theme: the gallery offers gallery-v1, older than the gallery-v12 seen before: not taken' ] && ok "theme gallery: a release older than one seen before is not taken (a floor against an old release served again)" || bad "gallery floor" "rc=$rc $out"
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_NOSYSTEM
else
    printf '  note gallery: ssh-keygen or python3 not found; the gallery'"'"'s tests are skipped\n'
fi

fi

# --- 25. the notifications, the drives and the power (#71, #72, #73) ------
if want 25; then
# mako's config from the palette, the session bus at the desktop's start,
# then the three sections as providers against stand-ins for makoctl,
# notify-send, lsblk, udisksctl, df, systemctl, sudo and zzz, and the two
# rules of runit written once and taken back. The Linux half is guarded
# by uname like 14.
fresh
desktop_stubs
theme_fixture '#ff5555'
mkdir -p "$HOME/.config/spark-shell"; printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
if [ "$(uname -s)" = Darwin ]; then
    _nb=''
    for v in notifications storage power; do
        rc=0; out=$(sh "$SH" desktop "$v" 2>&1) || rc=$?
        [ "$rc" = 1 ] && case $out in "spark-shell desktop: not on macOS, which has its own "*) true ;; *) false ;; esac || _nb="$_nb $v:$out"
    done
    [ -z "$_nb" ] && ok "macOS: desktop notifications, storage and power are refused, the Mac has its own" || bad "macOS desktop verbs" "$_nb"
    out=$(sh "$SH" panel --list 2>&1 || :)
    printf '%s\n' "$out" | grep -qE '^. (notifications|storage|power) ' && bad "macOS: a desktop section is listed" "$out" || ok "macOS: the panel lists no notifications, storage or power"
else
    nlog=$HOME/notify.log
    cat > "$H/.local/bin/makoctl" <<'STUB'
#!/bin/sh
[ -e "$HOME/mako.up" ] || exit 1
printf '%s\n' "$*" >> "$HOME/mako.log"
case $1 in
    mode) shift; if [ $# -eq 0 ]; then echo default; [ ! -e "$HOME/mako.dnd" ] || echo do-not-disturb; exit 0; fi
        case $1 in -a) touch "$HOME/mako.dnd" ;; -r) rm -f "$HOME/mako.dnd" ;; esac ;;
    list|history) cat "$HOME/mako.$1" 2>/dev/null || : ;;
esac
STUB
    printf '#!/bin/sh\nexit 0\n' > "$H/.local/bin/mako"
    printf '#!/bin/sh\nprintf "%%s|" "$@" >> "$HOME/notify.log"; echo >> "$HOME/notify.log"\n' > "$H/.local/bin/notify-send"
    chmod +x "$H/.local/bin/makoctl" "$H/.local/bin/mako" "$H/.local/bin/notify-send"
    # the render: mako's config in the palette and the text size, a click on spark-shell's own opening the dialog
    sh "$SH" on --yes >/dev/null 2>&1 || :
    mk=$HOME/.config/mako/config
    grep -q '^# rendered by spark-shell from templates/.config/mako/config' "$mk" && ! grep -q '@[A-Z_0-9]*@' "$mk" \
        && grep -qx 'font=DejaVu Sans Mono 12' "$mk" && grep -qx 'background-color=#0f0f0f' "$mk" && grep -qx 'text-color=#aaaaaa' "$mk" && grep -qx 'progress-color=over #ff555540' "$mk" \
        && grep -qx 'padding=12,18' "$mk" && grep -qx 'width=360' "$mk" && grep -qx 'height=96' "$mk" && grep -qx 'border-size=0' "$mk" && ! grep -q '^border-color=' "$mk" && grep -qx 'anchor=top-right' "$mk" \
        && ok "mako's config: the dialog's surface and the text color, the bar's face, half the dialog's air and thirty cells from the text size, the accent at a quarter for a progress, no frame on any (#71)" || bad "mako config" "$(cat "$mk" 2>&1)"
    # the look: spark's angle in the accent before the app's name, the edge on the windows' content (gaps 16 and the clear border 4), 8 between, an app's own together and counted, one line for the rest, a low one muted through, a glyph before what a card says where its category names the kind, a critical one's a red warning sign, a middle click clears
    _pm=$(sed -n 's/^format=<span foreground="#ff5555">&#x276F;<\/span> <span foreground="#\([0-9a-f]*\)">%a<\/span>\\n&#x25CF; <b>%s<\/b>\\n%b$/\1/p' "$mk" | head -1)
    _a='<span foreground="#ff5555">&#x276F;</span> <span foreground="#'"$_pm"'">'   # the first line's head: the angle, then the muted span open
    _t='</span>\n&#x25CF; <b>%s</b>\n%b'   # the plain tail, the filled dot before the summary (a literal backslash-n, as the file has it)
    glyph() { printf '</span>\\n&#x%s; <b>%%s</b>\\n%%b' "$1"; }   # glyph HEX -> the tail with that glyph before the summary
    after() { sed -n "/^\\[$1\\]\$/{n;p;}" "$mk"; }   # after CRITERIA -> the line under that section's header
    block() { sed -n "/^\\[$1\\]\$/,/^\$/p" "$mk" | sed -n '2,4p'; }   # block CRITERIA -> the three lines under the header
    [ -n "$_pm" ] && [ "$_pm" != aaaaaa ] && grep -qx 'margin=8' "$mk" && grep -qx 'outer-margin=12' "$mk" && grep -qx 'group-by=app-name' "$mk" && grep -qxF "on-button-middle=exec makoctl dismiss -a; $REPO/spark-shell bar seen" "$mk" && grep -qxF "on-button-right=exec makoctl dismiss -n \"\$id\"; $REPO/spark-shell bar seen \"\$id\"" "$mk" && grep -qx 'icons=0' "$mk" && grep -qx 'default-timeout=6000' "$mk" \
        && [ "$(after grouped)" = "format=$_a%a &#183; %g$_t" ] \
        && [ "$(after hidden)" = "format=<span foreground=\"#$_pm\">&#x25B8; and %h more</span>" ] \
        && [ "$(block 'urgency=low')" = "$(printf '%s\n' "text-color=#$_pm" 'default-timeout=4000' "format=<span foreground=\"#$_pm\">&#x276F; %a$_t")" ] \
        && [ "$(after 'category=email.arrived')" = "format=$_a%a$(glyph 2261)" ] && [ "$(after 'category=email')" = "format=$_a%a$(glyph 2261)" ] \
        && [ "$(after 'grouped category=email.arrived')" = "format=$_a%a &#183; %g$(glyph 2261)" ] && [ "$(after 'grouped category=email')" = "format=$_a%a &#183; %g$(glyph 2261)" ] \
        && [ "$(after 'category=transfer.complete')" = "format=$_a%a$(glyph 2713)" ] && [ "$(after 'category=transfer.error')" = "format=$_a%a$(glyph 2717)" ] && [ "$(after 'category=device.added')" = "format=$_a%a$(glyph 25AD)" ] \
        && [ "$(block 'urgency=critical')" = "$(printf '%s\n' 'default-timeout=0' 'layer=overlay' "format=$_a%a</span>\n<span foreground=\"#aa0000\">&#x26A0;</span> <b>%s</b>\n%b")" ] && ! grep -q '^border-color=' "$mk" \
        && ok "mako's config: the angle in the accent, the edge on the windows' content and 8 between, an app's own together with their count, 'and N more' under three, a low one muted through and gone in four seconds, a filled dot before what any card says, a low one's too (quiet is not off), three lines, a check or a cross and a hollow stick before what mail, a transfer and a drive say, a red warning sign before a critical one with no frame and over a full-screen window, a middle click dismisses all and a right click one, each looked at for the bar's count (#71)" || bad "mako look" "$(cat "$mk")"
    grep -qxF "on-button-left=exec makoctl dismiss -n \"\$id\"; $REPO/spark-shell bar seen \"\$id\"; foot --config $HOME/.config/foot/dialog.ini --app-id spark-dialog -e $REPO/spark-shell dialog reminders" "$mk" \
        && grep -qxF "on-button-left=exec makoctl dismiss -n \"\$id\"; $REPO/spark-shell bar seen \"\$id\"; foot --config $HOME/.config/foot/dialog.ini --app-id spark-dialog -e $REPO/spark-shell dialog storage" "$mk" \
        && [ "$(after 'app-name=spark-shell category=x-spark-shell.reminder')" = "format=${_a}reminder &#x25B8; a click opens it$(glyph 29D7)" ] \
        && [ "$(after 'app-name=spark-shell category=device.added')" = "format=${_a}drive &#x25B8; a click opens Storage$(glyph 25AD)" ] \
        && [ "$(sed -n '/^\[mode=do-not-disturb\]$/,$p' "$mk" | grep -c .)" = 4 ] && tail -1 "$mk" | grep -qx 'invisible=0' \
        && ok "mako's config: a reminder or a drive says so on its first line, the bar's hourglass or a hollow stick before what it says, and a click opens the dialog there; do not disturb last, a critical one through it" || bad "mako criteria" "$(cat "$mk")"
    grep -qx 'exec mako' "$HOME/.config/sway/config" && ok "sway config: mako starts with the desktop" || bad "sway exec mako" "$(grep -n mako "$HOME/.config/sway/config")"
    # a new look: the file again, and a mako that runs reads it at once
    touch "$HOME/mako.up"; rm -f "$HOME/mako.log"
    sh "$SH" theme nord >/dev/null 2>&1 || :
    grep -qx 'reload' "$HOME/mako.log" && ! grep -qx 'background-color=#0f0f0f' "$mk" && ok "theme NAME: mako's config in the new palette, and mako told to read it (#71)" || bad "mako reload" "$(cat "$HOME/mako.log" 2>&1)"
    sh "$SH" theme none >/dev/null 2>&1 || :; theme_fixture '#ff5555'; sh "$SH" on --yes >/dev/null 2>&1 || :; rm -f "$HOME/mako.up"
    # the session bus: sway inside dbus-run-session where there is none, never where logind made one
    printf '#!/bin/sh\necho "dbus-run-session $*" >> "%s/bus.log"\nexec "$@"\n' "$H" > "$H/.local/bin/dbus-run-session"
    printf '#!/bin/sh\necho "sway $*" >> "%s/bus.log"\n' "$H" > "$H/.local/bin/sway"
    chmod +x "$H/.local/bin/dbus-run-session" "$H/.local/bin/sway"
    rm -f "$H/bus.log"; env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS TEST_TTY=/dev/tty1 sh "$SH" desktop >/dev/null 2>&1 || :
    [ "$(sed -n 1p "$H/bus.log" 2>/dev/null)" = 'dbus-run-session sway' ] && [ "$(sed -n 2p "$H/bus.log")" = 'sway ' ] \
        && ok "desktop: with no session bus, sway starts inside dbus-run-session, so a program reaches mako (#71)" || bad "desktop bus" "$(cat "$H/bus.log" 2>&1)"
    rm -f "$H/bus.log"; env -u WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1/bus TEST_TTY=/dev/tty1 sh "$SH" desktop >/dev/null 2>&1 || :
    [ "$(cat "$H/bus.log" 2>/dev/null)" = 'sway ' ] && ok "desktop: a session bus there already (logind's), sway starts as it was" || bad "desktop own bus" "$(cat "$H/bus.log" 2>&1)"
    desktop_stubs
    # the notifications section: mako not there, not running, then running
    rq() { jq -cn --argjson i "$1" --arg m "$2" --argjson p "${3:-null}" '{jsonrpc: "2.0", id: $i, method: $m} + (if $p == null then {} else {params: $p} end)'; }
    call() { rq "$1" tools/call "$(jq -cn --arg n "$2" --argjson a "${3:-"{}"}" '{name: $n, arguments: $a}')"; }
    mcp() { _s=$1; shift; printf '%s\n' "$@" | sh "$SH" provide "$_s" > "$H/mcp.out" 2> "$H/mcp.err"; }
    ans() { jq -c --argjson i "$1" 'select(.id == $i)' "$H/mcp.out"; }
    rows() { mcp "$1" "$(rq 1 resources/read "{\"uri\":\"spark-shell://$1/rows\"}")"; ans 1 | jq -r '.result.contents[0].text'; }
    out=$(env -u DBUS_SESSION_BUS_ADDRESS SPARK_SHELL_NO_MAKO=1 sh "$SH" panel notifications --list 2>&1 | sed -n 2p)   # a runner may have a mako of its own: the switch, never PATH
    [ "$out" = "  notifications  mako is not installed (spark-shell on desktop)	notifications show" ] && ok "notifications: no mako, said as the section's one row" || bad "notifications no mako" "$out"
    out=$(env -u DBUS_SESSION_BUS_ADDRESS sh "$SH" panel notifications --list 2>&1 | sed -n 2p)
    [ "$out" = "  notifications  no session bus yet: notifications start at your next login	notifications show" ] && ok "notifications: no session bus, the next login says when" || bad "notifications no bus" "$out"
    out=$(DBUS_SESSION_BUS_ADDRESS=unix:path=/nowhere sh "$SH" panel notifications --list 2>&1 | sed -n 2p)
    [ "$out" = "  notifications  the notifications are not running: they start at your next login	notifications show" ] && ok "notifications: a bus but no mako answering, said so" || bad "notifications not running" "$out"
    touch "$HOME/mako.up"
    printf 'Notification 9: Download complete\n  App name: firefox\n  Urgency: normal\n' > "$HOME/mako.list"
    printf 'Notification 5: Build passed\n  App name: \nNotification 4: New mail from Ada\n  App name: aerc\n  Category: email\nNotification 3: New mail from Ada\n  App name: aerc\n' > "$HOME/mako.history"
    rows notifications > "$H/n.json"
    jq -e '.state == "1 on the screen"
        and ([.rows[] | .text] == ["turn on do not disturb", "dismiss the one on the screen", "show the last one again", "Build passed", "New mail from Ada", "New mail from Ada"])
        and (.rows[0].tool == {name: "notifications_do_not_disturb", arguments: {state: "on"}}) and (.rows[1].tool.name == "notifications_dismiss") and (.rows[2].tool.name == "notifications_restore")
        and ([.rows[3:][] | .group] == ["earlier", "earlier", "earlier"]) and (.rows[4].columns == ["aerc"]) and (.rows[3].columns == []) and ([.rows[] | .id] | unique | length) == 6' "$H/n.json" >/dev/null \
        && ok "notifications rows: do not disturb, dismiss what is on the screen, the last one again, then the history, newest first, each its app a column, two alike apart by mako's id (#71)" || bad "notifications rows" "$(cat "$H/n.json")"
    printf '{"type":"aa{sv}","data":[[{"id":{"type":"u","data":12},"app-name":{"type":"s","data":"firefox"},"summary":{"type":"s","data":"Saved"}}]]}\n' > "$HOME/mako.history"
    [ "$(rows notifications | jq -c '[.rows[] | select(.group == "earlier") | [.text, .columns]]')" = '[["Saved",["firefox"]]]' ] && ok "notifications rows: mako 1.7 and 1.8's history, busctl's JSON, read the same" || bad "mako 1.7 history" "$(rows notifications)"
    rm -f "$HOME/mako.log"
    mcp notifications "$(call 1 notifications_do_not_disturb '{"state":"on"}')" "$(call 2 notifications_do_not_disturb '{"state":"on"}')" "$(call 3 notifications_do_not_disturb '{"state":"maybe"}')"
    [ "$(ans 1 | jq -c '.result.structuredContent | del(.rows)')" = '{"receipt":"do not disturb on: notifications wait out of sight","undo":{"name":"notifications_do_not_disturb","arguments":{"state":"off"}}}' ] \
        && [ "$(ans 2 | jq -c '.result.structuredContent | del(.rows)')" = '{"receipt":"do not disturb on: notifications wait out of sight"}' ] && [ "$(ans 3 | jq -r .error.message)" = 'notifications_do_not_disturb: state is one of on, off' ] \
        && [ -e "$HOME/mako.dnd" ] && grep -qx 'DO_NOT_DISTURB=yes' "$HOME/.config/spark-shell/config" \
        && ok "notifications do-not-disturb on: mako's mode and the config, undo puts it off; asked again, a receipt with nothing to undo (#71)" || bad "dnd on" "$(cat "$H/mcp.out")"
    [ "$(rows notifications | jq -r '.state + " | " + .rows[0].text + " | " + .rows[0].sign')" = 'do not disturb | turn off do not disturb | dot' ] && ok "notifications: with do not disturb on, the row in use turns it off" || bad "dnd row" "$(rows notifications | head -c 300)"
    REM_LOOK=1 sh "$SH" bar status --once 2>/dev/null | jq -e 'any(.[]; .name == "notifications" and (.full_text | test("\u23fe")))' >/dev/null && ok "bar: do not disturb is said while it is on, a click opens its section" || bad "bar dnd" "$(REM_LOOK=1 sh "$SH" bar status --once 2>&1 | head -c 400)"
    # the bar's count: mako's notifications, on the screen (9) and gone (12), that nobody looked at; bar seen ID (mako's click) and bare (the block's click, dismiss) count them looked at
    nb() { REM_LOOK=1 XDG_RUNTIME_DIR=$H/run sh "$SH" bar status --once 2>/dev/null | jq -r '[.[] | select(.name == "notifications") | .instance + "=" + (.full_text | gsub("<[^>]*>"; ""))] | join(" ")'; }
    mkdir -p "$H/run"; rm -f "$H/run/spark-shell/notify-seen"
    _n1=$(nb); XDG_RUNTIME_DIR=$H/run sh "$SH" bar seen 12 >/dev/null 2>&1; _n2=$(nb); XDG_RUNTIME_DIR=$H/run sh "$SH" bar seen 9 77 >/dev/null 2>&1; _n3=$(nb)
    _dnd=$(printf '\342\217\276'); _note=$(printf '\342\232\221')
    [ "$_n1" = "dnd=$_dnd count=$_note 2" ] && [ "$_n2" = "dnd=$_dnd count=$_note 1" ] && [ "$_n3" = "dnd=$_dnd" ] && [ "$(cat "$H/run/spark-shell/notify-seen")" = "$(printf '9\n12')" ] \
        && ok "bar: the notifications nobody looked at, the flag and how many beside do not disturb; one looked at by its id, then the other: do not disturb alone, an id mako does not hold not kept (#71)" || bad "bar count" "$_n1 | $_n2 | $_n3 | $(cat "$H/run/spark-shell/notify-seen" 2>&1)"
    printf 'Notification 14: Ping\n  App name: chat\n' > "$HOME/mako.list"; _n4=$(nb)
    cp "$HOME/.config/spark-shell/config" "$H/config.keep"; printf 'BAR_GLYPHS=words\n' >> "$HOME/.config/spark-shell/config"; _n5=$(nb); cp "$H/config.keep" "$HOME/.config/spark-shell/config"
    XDG_RUNTIME_DIR=$H/run sh "$SH" bar seen >/dev/null 2>&1; _n6=$(nb)
    [ "$_n4" = "dnd=$_dnd count=$_note 1" ] && [ "$_n5" = "dnd=do not disturb count=new 1" ] && [ "$_n6" = "dnd=$_dnd" ] \
        && ok "bar: a new one on the screen counts, the one looked at stays looked at; in words, new 1; bar seen, bare, looks at them all" || bad "bar count new" "$_n4 | $_n5 | $_n6"
    rm -f "$HOME/mako.dnd"; sh "$SH" desktop --pending >/dev/null 2>&1 || :; _i=0; while [ "$_i" -lt 20 ] && [ ! -e "$HOME/mako.dnd" ]; do sleep 0.25; _i=$((_i + 1)); done
    [ -e "$HOME/mako.dnd" ] && ok "desktop --pending (the desktop's start): do not disturb as the config left it" || bad "dnd kept" "$(cat "$HOME/mako.log")"
    out=$(sh "$SH" desktop notifications do-not-disturb off 2>&1 || :); [ "$out" = 'do not disturb off' ] && [ ! -e "$HOME/mako.dnd" ] && grep -qx 'DO_NOT_DISTURB=no' "$HOME/.config/spark-shell/config" \
        && ok "desktop notifications do-not-disturb off: said, mako's mode gone, the config too" || bad "dnd off cli" "$out"
    [ -z "$(nb)" ] && ok "bar: do not disturb off and every notification looked at: no notifications block" || bad "bar no count" "$(nb)"
    out=$(sh "$SH" desktop notifications 2>&1 || :); [ "$out" = "$(printf 'do not disturb off\n  firefox: Saved')" ] && ok "desktop notifications: do not disturb, then the last few with their app" || bad "notifications cli" "$out"
    # a notification's words are any site's: scrubbed text stays plain, dash's echo made \033 a real escape again
    _mk=$(cat "$HOME/mako.history"); printf 'Notification 21: hello\\033[2Jgone\n  App name: browser\n' > "$HOME/mako.history"
    out=$(sh "$SH" desktop notifications 2>&1 || :)
    printf '%s\n' "$out" | grep -qF 'browser: hello\033[2Jgone' && ! printf '%s' "$out" | LC_ALL=C grep -q "$(printf '\033')" && ok "desktop notifications: an escape written out in a notification stays words" || bad "notification escape" "$(printf '%s' "$out" | od -c | head -5)"
    printf '%s\n' "$_mk" > "$HOME/mako.history"
    rc=0; out=$(sh "$SH" desktop notifications loud 2>&1) || rc=$?; [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: notifications takes do-not-disturb on|off, dismiss or restore' ] && ok "desktop notifications WORD: refused in one line" || bad "notifications refuse" "rc=$rc $out"
    # a reminder due comes as a notification once, on the desktop alone
    mkdir -p "$HOME/calendar"; rm -f "$nlog"
    printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:spark-shell-test-n@box\r\nDTSTART:%s\r\nSUMMARY:call the vet\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' "$(ago 1)" > "$HOME/calendar/vet.ics"
    SPARK_SHELL_NO_CHIME=1 WAYLAND_DISPLAY=wayland-1 sh "$SH" bar due >/dev/null 2>&1 || :; SPARK_SHELL_NO_CHIME=1 WAYLAND_DISPLAY=wayland-1 sh "$SH" bar due >/dev/null 2>&1 || :
    [ "$(cat "$nlog" 2>/dev/null)" = '-a|spark-shell|-c|x-spark-shell.reminder|--|call the vet|due now|' ] && ok "a reminder due: one notification, spark-shell's, its category for a click to open the reminders (#71)" || bad "reminder notification" "$(cat "$nlog" 2>&1)"
    rm -f "$HOME/calendar/vet.ics"
    # the drives: what lsblk and df say, a stand-in udisksctl
    cat > "$H/.local/bin/lsblk" <<'STUB'
#!/bin/sh
cat "$HOME/lsblk.json"
STUB
    cat > "$H/.local/bin/df" <<'STUB'
#!/bin/sh
echo 'Filesystem 1024-blocks Used Available Capacity Mounted on'
case "$*" in *" /") echo '/dev/nvme0n1p2 488281250 288281250 200000000 60% /' ;; *) echo '/dev/sdb1 30000000 27000000 3000000 90% /run/media/ada/BACKUP' ;; esac
STUB
    cat > "$H/.local/bin/udisksctl" <<'STUB'
#!/bin/sh
echo "$*" >> "$HOME/udisks.log"
[ ! -e "$HOME/udisks.no" ] || { echo "Error mounting $3: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedCanObtain: Not authorized to perform operation"; exit 1; }
case $1 in mount) echo "Mounted $3 at /run/media/ada/BACKUP" ;; unmount) echo "Unmounted $3." ;; esac
STUB
    chmod +x "$H/.local/bin/lsblk" "$H/.local/bin/df" "$H/.local/bin/udisksctl"
    blk() {   # blk MOUNT -> the fixture: the system's disk, a stick (BACKUP, mounted at MOUNT or not, and a small part with no label), a disk the system mounts (fstab), an encrypted card
        _m=null; [ -z "${1:-}" ] || _m="\"$1\""
        cat > "$HOME/lsblk.json" <<JSON
{"blockdevices": [
 {"name":"nvme0n1","path":"/dev/nvme0n1","type":"disk","rm":false,"hotplug":false,"size":512110190592,"model":"WD SN770","vendor":null,"label":null,"fstype":null,"mountpoint":null,
  "children":[{"name":"nvme0n1p2","path":"/dev/nvme0n1p2","type":"part","rm":false,"hotplug":false,"size":511000000000,"label":null,"fstype":"ext4","mountpoint":"/"}]},
 {"name":"sdb","path":"/dev/sdb","type":"disk","rm":true,"hotplug":true,"size":31004295168,"model":"Ultra","vendor":"SanDisk ","label":null,"fstype":null,"mountpoint":null,
  "children":[{"name":"sdb1","path":"/dev/sdb1","type":"part","rm":true,"hotplug":true,"size":31003246592,"label":"BACKUP","fstype":"exfat","mountpoint":$_m},
              {"name":"sdb2","path":"/dev/sdb2","type":"part","rm":true,"hotplug":true,"size":1048576,"label":null,"fstype":"vfat","mountpoint":null}]},
 {"name":"sdc","path":"/dev/sdc","type":"disk","rm":"0","hotplug":"1","size":1000204886016,"model":"Elements","vendor":"WD","label":null,"fstype":null,"mountpoint":null,
  "children":[{"name":"sdc1","path":"/dev/sdc1","type":"part","rm":"0","hotplug":"1","size":1000202273280,"label":"data","fstype":"ext4","mountpoint":"/mnt/data"}]},
 {"name":"mmcblk0","path":"/dev/mmcblk0","type":"disk","rm":false,"hotplug":true,"size":63864569856,"model":null,"vendor":null,"label":null,"fstype":null,"mountpoint":null,
  "children":[{"name":"mmcblk0p1","path":"/dev/mmcblk0p1","type":"part","rm":false,"hotplug":true,"size":63863521280,"label":"cam|era","fstype":"crypto_LUKS","mountpoint":null}]}
]}
JSON
    }
    blk ''
    rows storage > "$H/s.json"
    jq -e '.state == "2 drives"
        and ([.rows[] | .text] == ["BACKUP", "SanDisk Ultra 1.0 MB", "cam/era is encrypted: udisksctl unlock -b /dev/mmcblk0p1", "465.7 GB, 190.7 GB free"])
        and (.rows[0] | .sign == "ring" and .tool == {name: "storage_mount", arguments: {name: "BACKUP"}} and .group == "SanDisk Ultra" and .columns == ["28.9 GB"])
        and (.rows[0].more == [{name: "storage_eject", arguments: {name: "SanDisk Ultra"}, said: "eject"}]) and (.rows[1].more == .rows[0].more)
        and (.rows[2].tool == null and .rows[2].more == [{name: "storage_eject", arguments: {name: "drive"}, said: "eject"}]) and (.rows[3].group == "this computer" and .rows[3].more == [])
        and (.rows[0].page | startswith("spark-shell://storage/page/"))' "$H/s.json" >/dev/null \
        && ok "storage rows: a drive a group, its parts (Enter mounts), eject behind each part (#169); an encrypted part says how to unlock it; never the system's disk or one it mounts itself (fstab); this computer's free space (#73)" || bad "storage rows" "$(cat "$H/s.json")"
    rm -f "$HOME/udisks.log"
    mcp storage "$(call 1 storage_mount '{"name":"BACKUP"}')" "$(call 2 storage_mount '{"name":"nothing"}')"
    [ "$(ans 1 | jq -c '.result.structuredContent | del(.rows)')" = '{"receipt":"BACKUP mounted at /run/media/ada/BACKUP","undo":{"name":"storage_unmount","arguments":{"name":"BACKUP"}}}' ] && [ "$(sed -n 1p "$HOME/udisks.log")" = 'mount -b /dev/sdb1 --no-user-interaction' ] \
        && [ "$(ans 2 | jq -r '.result.content[0].text')" = 'nothing is not in the list now' ] \
        && ok "storage mount: udisksctl mounts the part by its device, with no question; undo unmounts it; a name not listed is refused" || bad "storage mount" "$(cat "$H/mcp.out") $(cat "$HOME/udisks.log" 2>&1)"
    blk /run/media/ada/BACKUP
    [ "$(rows storage | jq -c '[.rows[0] | .sign, .tool, .columns, [.more[].name]], [.rows[1] | .text]')" = "$(printf '%s\n%s' '["dot",{"name":"storage_open","arguments":{"name":"BACKUP"}},["2.9 GB free"],["storage_unmount","storage_eject"]]' '["SanDisk Ultra 1.0 MB"]')" ] \
        && ok "storage rows: a part that is mounted opens on Enter, its free space a column; unmount and eject behind it (#169)" || bad "storage mounted rows" "$(rows storage)"
    mcp storage "$(rq 1 resources/read "{\"uri\":\"spark-shell://storage/page/$(printf 'storage:open BACKUP' | base64 | tr -d '\n=' | tr '+/' '-_')\"}")"
    ans 1 | jq -r '.result.contents[0].text' | jq -e '.lines[0] == "BACKUP" and .bold == [0] and (.lines | index("drive        SanDisk Ultra")) and (.lines | any(startswith("mounted at   ")))' >/dev/null \
        && ok "storage page: Space on a part shows its drive, its size, its free space, where it is mounted, its format (#169)" || bad "storage page" "$(cat "$H/mcp.out")"
    # a mounted drive is a root of the files beside your home (#112): its row in the home folder, its folder opened, a path on it held to the lines, its trash its own (.Trash-UID at its top)
    mkdir -p "$H/stick/photos"; printf 'on the stick\n' > "$H/stick/photos/trip.txt"; blk "$H/stick"
    rinit=$(rq 1 initialize '{"protocolVersion":"2025-06-18","capabilities":{"roots":{}},"clientInfo":{"name":"test","version":"0"}}')
    roots=$(jq -cn --arg u "file://$(realpath "$HOME")" '{jsonrpc: "2.0", id: "roots", result: {roots: [{uri: $u}]}}')
    uri() { printf 'spark-shell://files/rows/%s' "$(printf '%s' "$1" | base64 | tr -d '\n=' | tr '+/' '-_')"; }
    SR=$(realpath "$H/stick")
    mkdir -p "$H/fm"; printf '#!/bin/sh\n' > "$H/fm/xdg-open"; printf '#!/bin/sh\n[ "$*" != "query default inode/directory" ] || echo thunar.desktop\n' > "$H/fm/xdg-mime"; chmod +x "$H/fm/xdg-open" "$H/fm/xdg-mime"   # a file manager configured, so the browse row is offered on Linux (#114)
    files2() { printf '%s\n' "$rinit" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$roots" "$@" | PATH="$H/fm:$PATH" SPARK_SHELL_MEDIA=$H/stick SPARK_SHELL_NO_GIO=1 SPARK_SHELL_NO_THUMB=1 SPARK_SHELL_NO_SVG=1 sh "$SH" provide files 2> "$H/mcp.err"; }   # SPARK_SHELL_MEDIA: the stick's mount counts as a drive's (udisks2 mounts under /run/media)
    files2 "$(rq 2 resources/read "$(jq -cn --arg u "$(uri "$(realpath "$HOME")")" '{uri: $u}')")" "$(rq 3 resources/read "$(jq -cn --arg u "$(uri "$SR")" '{uri: $u}')")" "$(call 4 files_trash "$(jq -cn --arg p "$SR/photos/trip.txt" '{path: $p}')")" > "$H/mcp.out"
    _tin=''; [ ! -f "$H/stick/.Trash-$(id -u)/files/trip.txt" ] || ! grep -qx 'Path=photos/trip.txt' "$H/stick/.Trash-$(id -u)/info/trip.txt.trashinfo" || _tin=1   # the two files of the spec on the drive, before the restore
    files2 "$(call 5 files_restore "$(jq -cn --arg p "$SR/photos/trip.txt" '{path: $p}')")" >> "$H/mcp.out"
    [ "$(ans 2 | jq -r '.result.contents[0].text' | jq -r --arg u "$(uri "$SR")" '[.rows[] | select(.group == "drives") | .text + " " + (.columns | join(",")) + " " + (if .children == $u then "opens" else "no" end)] | join("|")')" = 'BACKUP 2.9 GB free opens' ] \
        && [ "$(ans 3 | jq -r '.result.contents[0].text' | jq -r '.title + "|" + ([.rows[] | .text] | join(","))')" = "$(printf '~')/stick|photos,this folder $(printf '\302\267') 1 folder" ] \
        && [ "$(ans 4 | jq -r '.result.structuredContent.receipt')" = 'trip.txt is in the trash' ] && [ -n "$_tin" ] \
        && [ "$(ans 5 | jq -r '.result.structuredContent.receipt')" = 'trip.txt is back' ] && [ -f "$H/stick/photos/trip.txt" ] && [ ! -e "$H/stick/.Trash-$(id -u)/files/trip.txt" ] \
        && ok "provide files: a drive mounted is a root beside your home: its row under drives opens it (no .. at its top), a file on it is trashed into the drive's own .Trash-UID with the path from the drive's top, as the spec says, and comes back" || bad "files drive root" "$(ans 2 | head -c 300) $(ans 3 | head -c 300) $(ans 4) $(ans 5) $(ls -R "$H/stick" 2>&1)"
    blk /run/media/ada/BACKUP; rm -rf "$H/stick"   # the fixture as the eject test below expects it: the stick mounted
    rm -f "$HOME/udisks.log"; out=$(sh "$SH" desktop storage eject SanDisk Ultra 2>&1 || :)
    [ "$out" = 'SanDisk Ultra can be taken out' ] && [ "$(cat "$HOME/udisks.log")" = "$(printf 'unmount -b /dev/sdb1 --no-user-interaction\npower-off -b /dev/sdb --no-user-interaction')" ] \
        && ok "desktop storage eject: every mounted part unmounted, then the drive powered off" || bad "storage eject" "$out $(cat "$HOME/udisks.log" 2>&1)"
    blk ''; touch "$HOME/udisks.no"; out=$(sh "$SH" desktop storage mount BACKUP 2>&1 || :); rm -f "$HOME/udisks.no"
    [ "$out" = 'could not mount BACKUP: Not authorized to perform operation' ] && ok "desktop storage mount: udisks2's refusal said in its own last words" || bad "storage refused" "$out"
    out=$(sh "$SH" desktop storage 2>&1 || :)
    [ "$out" = "$(printf 'SanDisk Ultra  28.9 GB\n  BACKUP  28.9 GB\n  SanDisk Ultra 1.0 MB  1.0 MB\ndrive  59.5 GB\n  cam/era  59.5 GB\nthis computer  465.7 GB, 190.7 GB free')" ] && ok "desktop storage: each drive, its parts, this computer's free space" || bad "storage cli" "$out"
    out=$(sh "$SH" desktop storage open BACKUP 2>&1 || :); [ "$out" = 'BACKUP is at /run/media/ada/BACKUP' ] && grep -qx 'mount -b /dev/sdb1 --no-user-interaction' "$HOME/udisks.log" && ok "desktop storage open: a part not mounted is mounted first; away from the desktop, where it is" || bad "storage open" "$out"
    out=$(SPARK_SHELL_NO_UDISKS=1 sh "$SH" panel storage --list 2>&1 | sed -n 2p)   # GitHub's Ubuntu runner has a udisksctl of its own: the switch, never PATH
    [ "$out" = "  storage    udisksctl is not installed (spark-shell on desktop)	storage show" ] && ok "storage: no udisks2, said first" || bad "storage no udisks" "$out"
    # a drive plugged in while the bar runs: one notification within a second or two, none for what was there at its start
    S=$H/sys; mkdir -p "$S/block/nvme0n1"; rm -f "$nlog"
    cp "$HOME/lsblk.json" "$H/lsblk.full"; jq '.blockdevices |= map(select(.name != "sdb"))' "$H/lsblk.full" > "$HOME/lsblk.json"
    ( SPARK_SHELL_SYS=$S WAYLAND_DISPLAY=wayland-1 SPARK_SHELL_NO_CHIME=1 sh "$SH" bar status < /dev/null > "$H/bar.out" 2>/dev/null ) & bp=$!
    _i=0; while [ "$_i" -lt 40 ] && [ "$(grep -c '^\[{' "$H/bar.out" 2>/dev/null)" = 0 ]; do sleep 0.25; _i=$((_i + 1)); done
    cp "$H/lsblk.full" "$HOME/lsblk.json"; mkdir -p "$S/block/sdb"
    _i=0; while [ "$_i" -lt 40 ] && [ ! -s "$nlog" ]; do sleep 0.25; _i=$((_i + 1)); done
    pkill -P "$bp" 2>/dev/null || :; kill "$bp" 2>/dev/null || :; wait "$bp" 2>/dev/null || :   # its own bar alone, by its parent: another suite's may run beside it
    [ "$(cat "$nlog" 2>/dev/null)" = '-a|spark-shell|-c|device.added|--|SanDisk Ultra plugged in|28.9 GB, not mounted|' ] && ! grep -q 'Elements\|drive plugged' "$nlog" \
        && ok "bar: a drive plugged in while it runs is said once, within its second's look; what was there at its start is not (#73)" || bad "drive notice" "$(cat "$nlog" 2>&1) $(head -c 300 "$H/bar.out")"
    # the power: what logind does, or the sudo rule of runit; the keys and the lid said, never changed
    # No lock is running in this fixture, even if the host is locked.
    printf '#!/bin/sh\nexit 1\n' > "$H/.local/bin/pgrep"
    chmod +x "$H/.local/bin/pgrep"
    printf '#!/bin/sh\necho "systemctl $*" >> "$HOME/power.log"\n' > "$H/.local/bin/systemctl"
    printf '#!/bin/sh\n[ "$1" != -n ] || shift; echo "sudo $*" >> "$HOME/power.log"\n' > "$H/.local/bin/sudo"
    printf '#!/bin/sh\necho "swaylock" >> "$HOME/power.log"\n' > "$H/.local/bin/swaylock"
    cat > "$H/.local/bin/swaymsg" <<'STUB'
#!/bin/sh
case "$*" in "-t get_version") echo '{"human_readable":"stub"}' ;; "-t get_tree") echo '{}' ;; *) echo "$*" >> "$HOME/swaymsg.log" ;; esac
STUB
    chmod +x "$H/.local/bin/systemctl" "$H/.local/bin/sudo" "$H/.local/bin/swaylock" "$H/.local/bin/swaymsg"
    mkdir -p "$S/power" "$H/proc"; echo 'freeze mem disk' > "$S/power/state"; echo '273000.12 100.0' > "$H/proc/uptime"
    pw() { SPARK_SHELL_SYS=$S SPARK_SHELL_PROC=$H/proc WAYLAND_DISPLAY=wayland-1 SWAYSOCK=$H/sock "$@"; }
    out=$(pw sh "$SH" panel power --list 2>&1 | sed -n '1,3p')
    [ "$out" = "$(printf 'power      up 3 days\n  power      lock\tpower lock\n  power      logout\tpower logout')" ] && pw sh "$SH" panel power --list 2>&1 | grep -qF 'restart and shut down: no logind or sudo rule here' \
        && ok "power: up 3 days; lock and logout always, one word each; restart and shutdown where something does them, said when nothing does (#72)" || bad "power none" "$(pw sh "$SH" panel power --list 2>&1 | head -6)"
    mkdir -p "$H/root/run/systemd/system" "$H/root/etc/systemd" "$H/proc/acpi/button/lid/LID0"; printf '[Login]\nHandlePowerKey=ignore\n' > "$H/root/etc/systemd/logind.conf"; echo 'state: open' > "$H/proc/acpi/button/lid/LID0/state"
    pw sh -c 'sh "$1" provide power' _ "$SH" > "$H/mcp.out" 2>/dev/null <<EOF
$(rq 1 resources/read '{"uri":"spark-shell://power/rows"}')
EOF
    [ "$(ans 1 | jq -r '.result.contents[0].text' | jq -c '[.rows[] | .text]')" = '["lock","suspend","logout","restart","shutdown","up 3 days"]' ] \
        && [ "$(ans 1 | jq -r '.result.contents[0].text' | jq -c '[.rows[] | [.columns, .wide]]')" = "$(printf '[[[],["the screen \302\267 Super+Escape"]],[[],["the screen locks first"]],[[],["every window closes"]],[[],["asks first"]],[[],["asks first"]],[[],null]]')" ] \
        && ok "power rows with logind: lock, suspend, logout, restart, shutdown, one word each, what each does its wide column, the uptime a fact; what the buttons do is no row (#143)" || bad "power systemd rows" "$(cat "$H/mcp.out")"
    rm -f "$HOME/power.log" "$HOME/swaymsg.log"
    pw sh -c 'sh "$1" provide power' _ "$SH" > "$H/mcp.out" 2>/dev/null <<EOF
$(call 1 power_restart)
$(call 2 power_suspend)
EOF
    [ "$(ans 1 | jq -c '.result.structuredContent | del(.rows)')" = '{"receipt":"restarting"}' ] && grep -qx 'systemctl reboot' "$HOME/power.log" \
        && [ "$(ans 2 | jq -c '.result.structuredContent | del(.rows)')" = '{"receipt":"back from suspend"}' ] && grep -qx 'swaylock' "$HOME/power.log" && grep -qx 'systemctl suspend' "$HOME/power.log" && ! grep -qs 'power suspend' "$HOME/swaymsg.log" \
        && ok "power restart: logind restarts it; power suspend: the screen locks, logind suspends, and the receipt comes on waking (the dialog design notes, v0.127)" || bad "power calls" "$(cat "$H/mcp.out") $(cat "$HOME/power.log" "$HOME/swaymsg.log" 2>&1)"
    rm -rf "$H/root/run/systemd" "$HOME/power.log"; mkdir -p "$H/root/etc/runit" "$H/root/usr/bin"
    printf '#!/bin/sh\n' > "$H/root/usr/bin/zzz"; printf '#!/bin/sh\n' > "$H/root/usr/bin/reboot"; chmod +x "$H/root/usr/bin/zzz" "$H/root/usr/bin/reboot"
    printf '#!/bin/sh\necho "visudo $*" >> "$HOME/root.log"\n[ ! -e "$HOME/visudo.no" ]\n' > "$H/.local/bin/visudo"; chmod +x "$H/.local/bin/visudo"
    touch "$HOME/visudo.no"; out1=$(sh "$SH" on desktop --yes 2>&1 || :); rm -f "$HOME/visudo.no"
    printf '%s\n' "$out1" | grep -q '^todo   power        visudo refused the sudoers file -- nothing written$' && [ ! -e "$H/root/etc/sudoers.d/spark-shell-power" ] \
        && ok "runit: a sudoers file visudo refuses is never written (#72)" || bad "power visudo" "$out1"
    out=$(sh "$SH" on desktop --yes 2>&1 || :); me=$(id -un); sud=$H/root/etc/sudoers.d/spark-shell-power; pol=$H/root/etc/polkit-1/rules.d/50-spark-shell-storage.rules
    printf '%s\n' "$out" | grep -q '^ok     power        you suspend, restart and shut down from the dialog (/etc/sudoers.d/spark-shell-power)$' && printf '%s\n' "$out1" | grep -q '^ok     storage      you mount and eject drives (/etc/polkit-1/rules.d/50-spark-shell-storage.rules)$' \
        && grep -qxF "$me ALL=(root) NOPASSWD: /usr/bin/zzz \"\", /usr/bin/reboot \"\", /usr/bin/poweroff \"\"" "$sud" && [ "$(ls -l "$sud" | cut -c1-10)" = '-r--r-----' ] \
        && grep -qF "subject.user == \"$me\"" "$pol" && grep -qF '"org.freedesktop.udisks2.filesystem-mount"' "$pol" && ! grep -q 'filesystem-mount-system\|encrypted-unlock' "$pol" \
        && ok "runit: on desktop writes the sudo rule (zzz, reboot, poweroff, no argument, 0440, checked by visudo) and the polkit rule for your drives alone (#72, #73)" || bad "runit rules" "$out $(cat "$sud" "$pol" 2>&1)"
    _vs=$(grep -c . "$HOME/root.log"); out=$(sh "$SH" on desktop --yes -v 2>&1 || :)
    [ "$(grep -c . "$HOME/root.log")" = "$_vs" ] && printf '%s\n' "$out" | grep -q '^ok     power ' && ok "runit: on again finds both rules as written and writes neither" || bad "runit rules again" "$out"
    out=$(pw sh "$SH" panel power --list 2>&1 | sed -n '2,6p' | cut -f2)
    [ "$out" = "$(printf 'power lock\npower suspend\npower logout\npower restart\npower shutdown')" ] && ok "power rows on runit with the rule: suspend, restart and shut down through sudo" || bad "power runit rows" "$out"
    rm -f "$HOME/power.log"; out=$(pw sh "$SH" desktop power suspend 2>&1 || :)
    [ "$out" = 'suspending' ] && [ "$(cat "$HOME/power.log")" = "$(printf 'swaylock\nsudo /usr/bin/zzz')" ] && ok "desktop power suspend: the screen locks first, then zzz through the rule (#72)" || bad "power suspend" "$out $(cat "$HOME/power.log" 2>&1)"
    printf '#!/bin/sh\ncase "$*" in *"-x sway") echo 4242 ;; *) exit 1 ;; esac\n' > "$H/.local/bin/pgrep"; chmod +x "$H/.local/bin/pgrep"
    rm -f "$HOME/power.log"; out=$(SPARK_SHELL_SYS=$S env -u WAYLAND_DISPLAY sh "$SH" desktop power suspend 2>&1 || :); rm -f "$H/.local/bin/pgrep"
    [ "$out" = 'the desktop could not be locked, so the machine did not suspend' ] && ! grep -q zzz "$HOME/power.log" 2>/dev/null \
        && ok "desktop power suspend from outside the desktop (ssh): a desktop it cannot lock keeps the machine up" || bad "power suspend unlocked" "$out $(cat "$HOME/power.log" 2>&1)"
    out=$(sh "$SH" check 2>&1 || :)
    printf '%s\n' "$out" | grep -q '^ok     storage      udisks2 mounts and ejects drives for you$' && printf '%s\n' "$out" | grep -q '^ok     power        lock, log out' && printf '%s\n' "$out" | grep -q '^ok     notify       the notifications show on the desktop$' \
        && ok "check: the notify, storage and power rows" || bad "check rows" "$out"
    sh "$SH" off desktop >/dev/null 2>&1 || :
    [ ! -e "$sud" ] && [ ! -e "$pol" ] && [ ! -e "$HOME/.local/state/spark-shell/power.sudoers" ] && [ ! -e "$HOME/.local/state/spark-shell/storage.polkit" ] && [ ! -e "$mk" ] \
        && ok "off desktop: both rules gone, by spark-shell's records, and mako's config with them" || bad "off rules" "$(ls -R "$H/root/etc" 2>&1)"
    rm -rf "$H/root/etc/runit"
fi

# --- the machine folder (#159): what only the desktop knows, for spark's prompt line ---
# spark-shell.facts and spark-shell.now in spark's machine folder, against stand-ins for
# sway, wpctl, bluetoothctl, wpa_cli, makoctl and lsblk that also hold what must never be
# written there: a window's title, a network around that is not saved, a note's words, a
# reminder's, a notification's, the wire's address, a screen's serial, a device's address.
# The Linux half is guarded by uname like 25.
fresh
desktop_stubs
mkdir -p "$HOME/.config/spark-shell" "$HOME/.config/sway" "$HOME/.config/foot"
printf 'DESKTOP=sway\nTHEME=nord\nKEYBOARD=us br\nDISPLAY_SAVER=starfield\n' > "$HOME/.config/spark-shell/config"
printf '# rendered by spark-shell from templates/.config/sway/config\n' > "$HOME/.config/sway/config"; : > "$HOME/.config/foot/foot.ini"
M=$H/machine; mf=$M/spark-shell.facts; mn=$M/spark-shell.now
inode() { ls -i "$1" 2>/dev/null | awk '{ print $1 }'; }
if [ "$(uname -s)" = Darwin ]; then
    rc=0; out=$(SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sock sh "$SH" desktop --machine 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ ! -e "$M" ] && ok "macOS: the machine folder is the desktop's (#159), and the Mac has its own: nothing written" || bad "macOS machine" "rc=$rc $out $(ls -la "$M" 2>&1)"
else
    bar_fixture   # a wire up (eth0 at 192.0.2.10), wlan0 through wpa_cli (home saved and in use, old saved, cafe around), a controller, a battery
    cat > "$H/.local/bin/swaymsg" <<'STUB'
#!/bin/sh
case "$*" in
    '-t get_version') echo '{"human_readable":"1.12","major":1,"minor":12,"patch":0}' ;;
    '-t get_outputs') if [ -e "$HOME/asleep" ]; then   # the lock turned them off: sway says power false, and a 0x0 mode for one
            echo '[{"name":"DP-3","active":true,"power":false,"make":"Fakemake","model":"Portable 16","serial":"SN0001","transform":"270","scale":1.0,"rect":{"x":-1920,"y":0,"width":1200,"height":1920},"current_mode":{"width":1920,"height":1200,"refresh":60000}},{"name":"HDMI-A-1","active":true,"power":false,"make":"Othermake","model":"Desk 24","serial":"SN0002","transform":"normal","scale":1.0,"rect":{"x":-720,"y":0,"width":0,"height":0},"current_mode":{"width":0,"height":0,"refresh":0}}]'
        else echo '[{"name":"DP-3","active":true,"power":true,"make":"Fakemake","model":"Portable 16","serial":"SN0001","transform":"270","scale":1.0,"rect":{"x":0,"y":0,"width":1200,"height":1920},"current_mode":{"width":1920,"height":1200,"refresh":60000}},{"name":"HDMI-A-1","active":true,"make":"Othermake","model":"Desk 24","serial":"SN0002","transform":"normal","scale":1.0,"rect":{"x":1200,"y":0,"width":1920,"height":1080},"current_mode":{"width":1920,"height":1080,"refresh":60000}}]'; fi ;;
    '-t get_workspaces') echo '[{"num":1,"name":"1:X","output":"DP-3","focused":true,"visible":true},{"num":2,"name":"2:Y writing","output":"HDMI-A-1","focused":false,"visible":true}]' ;;
    '-t get_tree') echo '{"type":"root","nodes":[{"type":"output","name":"DP-3","nodes":[{"type":"workspace","num":1,"name":"1:X","nodes":[{"type":"con","id":42,"pid":100,"app_id":"firefox","name":"Bank statement - SECRET TITLE","focused":true,"nodes":[]},{"type":"con","id":7,"pid":101,"app_id":"foot","name":"ada: ~/hidden-dir","focused":false,"nodes":[]}],"floating_nodes":[{"type":"floating_con","id":9,"pid":102,"app_id":"spark-dialog","name":"dialog","focused":false}]}]},{"type":"output","name":"HDMI-A-1","nodes":[{"type":"workspace","num":2,"name":"2:Y writing","nodes":[{"type":"con","id":12,"pid":103,"app_id":"mpv","name":"secret-movie.mkv","focused":false,"nodes":[]}]}]}]}' ;;
    '-t get_inputs') echo '[{"type":"keyboard","xkb_active_layout_index":1,"xkb_layout_names":["English (US)","Portuguese (Brazil)"]}]' ;;
esac
STUB
    cat > "$H/.local/bin/wpctl" <<'STUB'
#!/bin/sh
case "$*" in
    status) printf 'Audio\n |- Devices:\n |      45. Built-in Audio [alsa]\n |\n |- Sinks:\n |  *   52. Fake Speaker [vol: 0.38]\n |      60. HD-Audio Generic Digital Stereo (HDMI 2) [Desk 24] [vol: 1.00]\n |\n |- Sources:\n |\n' ;;
    'get-volume @DEFAULT_AUDIO_SINK@') echo 'Volume: 0.38' ;;
    *) exit 1 ;;
esac
STUB
    cat > "$H/.local/bin/bluetoothctl" <<'STUB'
#!/bin/sh
case "$*" in
    show) printf 'Controller 00:11:22:33:44:55 (public)\n\tPowered: yes\n' ;;
    'devices Paired') printf 'Device 00:25:D1:4A:C2:AA Major V\nDevice 00:25:D1:4A:C2:BB Fake Speaker\n' ;;
    'devices Connected') echo 'Device 00:25:D1:4A:C2:BB Fake Speaker' ;;
    devices) printf 'Device 00:25:D1:4A:C2:AA Major V\nDevice 00:25:D1:4A:C2:BB Fake Speaker\nDevice 11:22:33:44:55:66 Buds Nearby\n' ;;
    'info 00:25:D1:4A:C2:AA') printf 'Device 00:25:D1:4A:C2:AA (public)\n\tName: Major V\n\tIcon: audio-headphones\n' ;;
    'info 00:25:D1:4A:C2:BB') printf 'Device 00:25:D1:4A:C2:BB (public)\n\tName: Fake Speaker\n\tIcon: audio-card\n' ;;
esac
STUB
    printf '#!/bin/sh\ncase $1 in mode) echo default ;; list|history) echo "1 app SECRET NOTICE TEXT" ;; esac\n' > "$H/.local/bin/makoctl"
    printf '#!/bin/sh\necho %s\n' "'{\"blockdevices\":[{\"name\":\"sdb\",\"path\":\"/dev/sdb\",\"type\":\"disk\",\"rm\":true,\"hotplug\":true,\"size\":16000000000,\"model\":\"Fakestick\",\"vendor\":\"Acme\",\"label\":null,\"fstype\":null,\"mountpoint\":null}]}'" > "$H/.local/bin/lsblk"
    for t in grim wl-copy notify-send; do printf '#!/bin/sh\n:\n' > "$H/.local/bin/$t"; done
    chmod +x "$H/.local/bin/swaymsg" "$H/.local/bin/wpctl" "$H/.local/bin/bluetoothctl" "$H/.local/bin/makoctl" "$H/.local/bin/lsblk" "$H/.local/bin/grim" "$H/.local/bin/wl-copy" "$H/.local/bin/notify-send"
    mkdir -p "$HOME/notes" "$HOME/calendar" "$HOME/.config/spark-shell/layouts"
    printf '# my hidden words\nmore of them\n' > "$HOME/notes/alpha.md"; printf 'x\n' > "$HOME/notes/beta.md"
    printf 'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:r1\r\nDTSTART:20991231T090000\r\nSUMMARY:call the dentist\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n' > "$HOME/calendar/r1.ics"
    printf '{"words": "write", "main": {"app": "micro"}}\n' > "$HOME/.config/spark-shell/layouts/writing"
    printf 'MCP_SERVER_OUT="%s/spark-shell provide out"\n' "$REPO" > "$HOME/.config/spark/mcp.env"
    MW() { SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sock sh "$SH" desktop --machine 2>&1; }   # the writer, now
    rc=0; out=$(MW) || rc=$?
    [ "$rc" = 0 ] && [ -z "$out" ] && [ "$(ls -ld "$M" | cut -c1-10)" = drwx------ ] && [ "$(ls -l "$mf" | cut -c1-10)" = -rw------- ] && [ "$(ls -l "$mn" | cut -c1-10)" = -rw------- ] \
        && [ "$(ls -A "$M" | paste -sd' ' -)" = 'spark-shell.facts spark-shell.now' ] \
        && ok "desktop --machine: spark-shell.facts and spark-shell.now, 0600 each, in a folder it made 0700, nothing else left there (#159)" || bad "machine files" "rc=$rc $out $(ls -la "$M" 2>&1)"
    # only the printers section asks CUPS (#186): the facts, the theme's list and its rows never run lpstat or
    # lib/printers.py; the facts name the printers the printers section saw last, from its cache
    mkdir -p "$H/prl"; printf '#!/bin/sh\necho "lpstat $*" >> "$HOME/cups.log"\nexit 1\n' > "$H/prl/lpstat"
    printf '#!/bin/sh\ncase "$*" in *printers.py*) echo "python3 $*" >> "$HOME/cups.log"; exit 1 ;; esac\nexec %s "$@"\n' "$(command -v python3 || echo false)" > "$H/prl/python3"
    chmod +x "$H/prl/lpstat" "$H/prl/python3"; rm -f "$HOME/cups.log" "$HOME/.local/state/spark-shell/panel/printers.status"
    PATH="$H/prl:$PATH" MW >/dev/null 2>&1 || :
    PATH="$H/prl:$PATH" SWAYSOCK=$H/sock sh "$SH" bar panel theme --list >/dev/null 2>&1 || :
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
        '{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"spark-shell://theme/rows"}}' | PATH="$H/prl:$PATH" SWAYSOCK=$H/sock sh "$SH" provide theme >/dev/null 2>&1 || :
    [ ! -s "$HOME/cups.log" ] && [ ! -e "$HOME/.local/state/spark-shell/panel/printers.status" ] && ! grep -q '^- Printers:' "$mf" \
        && ok "the facts, the theme's list and its rows ask CUPS nothing, and keep nothing of it (#186)" || bad "printers asked" "$(cat "$HOME/cups.log" 2>&1)"
    mkdir -p "$HOME/.local/state/spark-shell/panel"; printf '%s\n%s\n' "$(date +%s)" '{"default":"office","queues":[{"name":"office","state":"idle","enabled":true},{"name":"lab","state":"idle","enabled":true}]}' > "$HOME/.local/state/spark-shell/panel/printers.status"
    PATH="$H/prl:$PATH" MW >/dev/null 2>&1 || :
    grep -qxF -- '- Printers: office (the default), lab.' "$mf" && [ ! -s "$HOME/cups.log" ] \
        && ok "the facts name the printers the printers section saw last, from its cache, and still ask CUPS nothing (#186)" || bad "printers from cache" "$(grep Printers "$mf"; cat "$HOME/cups.log" 2>&1)"
    rm -f "$HOME/.local/state/spark-shell/panel/printers.status" "$HOME/cups.log"
    PATH="$H/prl:$PATH" MW >/dev/null 2>&1 || :   # the facts as they were, no printer seen: the checks below read them so
    grep -qx -- '- Session: sway 1.12 on Wayland (X11 apps run through Xwayland), set up by spark-shell\( v[0-9.]*\)\{0,1\}; screenshots grim, clipboard wl-copy, notifications notify-send, swaymsg.' "$mf" \
        && grep -qxF -- '- Screens: DP-3 = Fakemake Portable 16, on the left, turned 270, portrait, 1920x1200; HDMI-A-1 = Othermake Desk 24, on the right, 1920x1080.' "$mf" \
        && grep -qxF -- '- spark-shell is this desktop: the bar at the top; home (Super+space) holds native actions and optional conversation.' "$mf" \
        && grep -q -- '^- Keys: .*terminal.open.*window.close' "$mf" \
        && ok "facts: the session with the Wayland tools that are here, the dialog's keys and the key table's, the screens by port with their make and model, place, turn and mode (#159)" || bad "facts session" "$(cat "$mf")"
    grep -qF -- '- Sound outputs: "Fake Speaker" (Bluetooth speaker), "HD-Audio Generic Digital Stereo (HDMI 2) [Desk 24]" (HDMI). Inputs: none.' "$mf" \
        && grep -qF -- '- Bluetooth, paired: "Fake Speaker" (speaker), "Major V" (headphones).' "$mf" \
        && grep -qF -- '- Network: wired eth0; Wi-Fi wlan0 through wpa_cli, saved networks: home, old.' "$mf" \
        && grep -qF -- '- Keyboard layouts: us (English (US)), br (Portuguese (Brazil)); caps key caps' "$mf" \
        && grep -qF -- '- Saved layouts: writing. Notes in ~/notes, by file: alpha.md, beta.md.' "$mf" \
        && grep -q "^- Palettes, dark: .*nord.*; light: .*solarized-light.*; none is terminal default colors.$" "$mf" && grep -q '^- Wallpapers: .*dunes.*, or default. Savers: clock' "$mf" \
        && ok "facts: the sound devices by their exact names with what each is, the paired devices with their kinds, the saved networks, the keyboard's codes and names, the layouts, the notes by file, the palettes (#159)" || bad "facts names" "$(cat "$mf")"
    # spark-shell's providers on spark's list: its own commands are the ways to read and list, a change is a tool's (a model that read
    # the commands as the ways to change wrote spark-shell bar off, spark-shell layout list); its own command only where no tool does it
    grep -qxF -- '- To read or list with spark-shell: spark-shell theme list, spark-shell font list, spark-shell layout (the saved layouts), spark-shell notes (your notes), spark-shell reminders, spark-shell desktop keys (the desktop'"'"'s keys), spark-shell desktop display.' "$mf" \
        && grep -qxF -- '- A change to a desktop setting goes through its MCP tool below (spark mcp call SERVER TOOL KEY=VALUE, SERVER the first word of its tool line), not a spark-shell command; with no tool for it: spark-shell font FACE SIZE|none (set the console font, or use its own); spark-shell dialog [SECTION] (open home (Super+Space), SECTION first); spark-shell desktop idle [off] (the idle screen now, or down).' "$mf" \
        && grep -qxF -- '- Reading state: spark mcp read SERVER spark-shell://SERVER/rows (SERVER is the first word of a tool line below); swaymsg -t get_outputs|get_workspaces|get_tree|get_inputs, wpctl status, bluetoothctl show.' "$mf" \
        && ! grep -qE '^- spark-shell (theme|font|layout|notes|reminders|desktop|bar|dialog) ' "$mf" && [ "$(grep -n '^- A change ' "$mf" | cut -d: -f1)" -lt "$(grep -n '^- Keys: ' "$mf" | cut -d: -f1)" ] \
        && ok "facts: how to read the state; spark-shell's own ways to read and list, from its help; a change is the setting's MCP tool, spark-shell's command only where no tool does it (the font, the dialog, the idle screen now); then the keys (#159)" || bad "facts commands" "$(cat "$mf")"
    mv "$HOME/.config/spark/mcp.env" "$H/mcp.env.kept"; rm -rf "$H/m2"; SPARK_MACHINE_DIR=$H/m2 SWAYSOCK=$H/sock sh "$SH" desktop --machine >/dev/null 2>&1
    grep -qxF -- '- spark-shell theme [NAME|none|list|save [NAME]|delete NAME|back|wallpaper X|text N|transparency N|glyphs SET|icons on|off|spacing SET|family NAME|face NAME|motion on|off|picture PATH|"WORDS"|gallery|install NAME]' "$H/m2/spark-shell.facts" \
        && grep -qF -- '- spark-shell desktop lock; capture screen|area|window; display [idle|lock N|saver [NAME]|brightness N|up|down]; keyboard [' "$H/m2/spark-shell.facts" \
        && grep -qxF -- '- Reading state: swaymsg -t get_outputs|get_workspaces|get_tree|get_inputs, wpctl status, bluetoothctl show.' "$H/m2/spark-shell.facts" \
        && ! grep -q '^- A change ' "$H/m2/spark-shell.facts" && [ "$(wc -m < "$H/m2/spark-shell.facts" | tr -d ' ')" -le 3000 ] \
        && ok "facts, no provider of spark-shell's on spark's list (no tool to change with): spark-shell's own commands from its help, a verb's alternatives in one bracket, within 3000 characters" || bad "facts no tools" "$(cat "$H/m2/spark-shell.facts" 2>&1)"
    mv "$H/mcp.env.kept" "$HOME/.config/spark/mcp.env"; rm -rf "$H/m2"
    grep -qxF -- '- Windows open (sway con id, app_id, workspace): 42 firefox on 1, focused; 7 foot on 1; 12 mpv on 2.' "$mn" \
        && grep -qxF -- '- Workspaces: 1:X on DP-3 (focused), 2:Y writing on HDMI-A-1 (shown).' "$mn" \
        && grep -qxF -- '- Sound: output "Fake Speaker" in use, volume 38%, not muted; no microphone connected.' "$mn" \
        && grep -qxF -- '- Bluetooth on; connected now: "Fake Speaker".' "$mn" \
        && grep -qxF -- '- Network: wired eth0 up with an address; Wi-Fi wlan0 connected to home, signal 70%, with an address.' "$mn" \
        && grep -qxF -- '- Keyboard layout in use: br. Palette nord, wallpaper default. Idle screen after 10 minutes (saver starfield), lock after 15 minutes.' "$mn" \
        && grep -qxF -- '- Drives plugged in: "Acme Fakestick".' "$mn" && grep -qxF -- '- The bar is shown at the top of the screen; do not disturb is off.' "$mn" \
        && ok "now: the windows by con id and app_id, the focused one said, the dialog left out; the workspaces; the sound in use; who is connected; the wire and the radio; the layout, the look and the minutes; the drive; the bar (#159)" || bad "now" "$(cat "$mn")"
    hit=$(grep -iF -e 'SECRET' -e 'hidden words' -e 'hidden-dir' -e 'secret-movie' -e 'cafe' -e 'dentist' -e '192.0.2' -e 'SN0001' -e 'SN0002' -e '00:25:D1' -e 'Buds Nearby' "$mf" "$mn" || :)
    [ -z "$hit" ] && ok "the machine folder holds no window's title, no network around that is not saved, no note's or reminder's words, no notification, no address, no serial, no device's address, no device that is not paired (#159)" || bad "machine never-list" "$hit"
    [ "$(wc -m < "$mf" | tr -d ' ')" -le 3000 ] && [ "$(wc -m < "$mn" | tr -d ' ')" -le 1200 ] && ! LC_ALL=C grep -q "$(printf '[\001-\010\011\013-\037\177]')" "$mf" "$mn" && ! grep -q '^$' "$mf" "$mn" \
        && ok "the two files: within what spark reads (3000 and 1200 characters), no tab, no control character, no empty line (#159)" || bad "machine sizes" "$(wc -m "$mf" "$mn")"
    fi1=$(inode "$mf"); ni1=$(inode "$mn"); rc=0; out=$(MW) || rc=$?
    [ "$rc" = 0 ] && [ "$(inode "$mf")" = "$fi1" ] && [ "$(inode "$mn")" = "$ni1" ] && [ "$(ls -A "$M" | paste -sd' ' -)" = 'spark-shell.facts spark-shell.now' ] \
        && ok "desktop --machine again, nothing changed: neither file is written again (.facts is in spark's cached prompt)" || bad "machine unchanged" "rc=$rc $(ls -lai "$M")"
    printf '{"words": "mail", "main": {"app": "aerc"}}\n' > "$HOME/.config/spark-shell/layouts/mail"; MW >/dev/null
    [ "$(inode "$mf")" != "$fi1" ] && grep -qF 'Saved layouts: mail, writing.' "$mf" && [ "$(inode "$mn")" = "$ni1" ] \
        && ok "a new saved layout: .facts written again through a new file, .now left as it was" || bad "machine facts change" "$(ls -lai "$M") $(grep layouts "$mf")"
    # the screens asleep (the lock turns them off): .now says so; the bar's look at .facts leaves it as it was while they were on
    touch "$HOME/notes/alpha.md"; fi1=$(inode "$mf"); MW >/dev/null
    [ "$(inode "$mf")" = "$fi1" ] && ok "a note edited (the newest now): .facts lists the notes by name, so it is not written again" || bad "machine note edited" "$(grep Notes "$mf")"
    touch "$HOME/asleep"; fi1=$(inode "$mf"); SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sock sh "$SH" desktop --machine tick >/dev/null 2>&1
    [ "$(inode "$mf")" = "$fi1" ] && grep -qxF -- '- Screens off now (the lock turns them off): DP-3, HDMI-A-1.' "$mn" && ! grep -q 'Screens off' "$mf" \
        && ok "the screens asleep: .now says they are off, and the bar's look at .facts leaves it as the screens on had it" || bad "machine asleep" "$(cat "$mn")"
    MW >/dev/null
    grep -qF -- '- Screens: DP-3 = Fakemake Portable 16, on the left, turned 270, portrait, 1920x1200; HDMI-A-1 = Othermake Desk 24, on the right.' "$mf" \
        && ok "a screen powered off says 0x0: no mode is written for it" || bad "machine 0x0" "$(grep Screens "$mf")"
    rm -f "$HOME/asleep"; fi1=$(inode "$mf"); SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sock sh "$SH" desktop --machine tick >/dev/null 2>&1
    [ "$(inode "$mf")" != "$fi1" ] && grep -qF 'HDMI-A-1 = Othermake Desk 24, on the right, 1920x1080.' "$mf" && ! grep -q 'Screens off' "$mn" \
        && ok "awake again: the bar's look writes .facts with the screens as they are" || bad "machine awake" "$(grep Screens "$mf" "$mn")"
    rc=0; out=$(SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sock sh "$SH" desktop --machine later 2>&1) || rc=$?
    [ "$rc" = 1 ] && [ "$out" = 'spark-shell desktop: --machine takes all, now or tick' ] && ok "desktop --machine WORD: all, now or tick, or one line and exit 1" || bad "machine door word" "rc=$rc $out"
    touch -t 202001010000 "$mn"; ni1=$(inode "$mn"); MW >/dev/null
    [ "$(inode "$mn")" != "$ni1" ] && [ -z "$(find "$mn" -mmin +3)" ] && ok ".now the same but older than 3 minutes: written again, its time is its freshness" || bad "machine now refresh" "$(ls -lai "$M")"
    rm -f "$mn"; printf 'theirs\n' > "$H/target"; ln -s "$H/target" "$mn"; MW >/dev/null
    [ -f "$mn" ] && [ ! -L "$mn" ] && [ "$(cat "$H/target")" = theirs ] && [ "$(ls -l "$mn" | cut -c1-10)" = -rw------- ] \
        && ok "a link where .now goes: the rename puts a file of its own in its place, nothing written through the link" || bad "machine link" "$(ls -la "$M") $(cat "$H/target")"
    : > "$M/.spark-shell.lock"; fi1=$(inode "$mf"); rm -f "$HOME/.config/spark-shell/layouts/mail"; MW >/dev/null
    [ "$(inode "$mf")" = "$fi1" ] && ok "a writer that runs already (its mark): this one gives way" || bad "machine lock" "$(ls -lai "$M")"
    touch -t 202001010000 "$M/.spark-shell.lock"; MW >/dev/null
    [ "$(inode "$mf")" != "$fi1" ] && [ ! -e "$M/.spark-shell.lock" ] && ! grep -q 'mail' "$mf" && ok "a mark a writer left when it died is taken after 2 minutes, and given back" || bad "machine stale lock" "$(ls -lai "$M")"
    mkdir "$M/.spark-shell.lock"; touch -t 202001010000 "$M/.spark-shell.lock"; MW >/dev/null
    [ ! -e "$M/.spark-shell.lock" ] && ok "a lock folder an older spark-shell left is taken after 2 minutes too, and given back" || bad "machine old lock folder" "$(ls -lai "$M")"
    rm -rf "$M"; printf 'DESKTOP=none\n' > "$HOME/.config/spark-shell/config"; MW >/dev/null
    [ ! -e "$M" ] && ok "the desktop off (DESKTOP=none): nothing written" || bad "machine desktop off" "$(ls -la "$M")"
    printf 'DESKTOP=sway\nTHEME=nord\nKEYBOARD=us br\nDISPLAY_SAVER=starfield\n' > "$HOME/.config/spark-shell/config"
    if ! command -v spark >/dev/null 2>&1; then   # a machine of the suite's with spark on its PATH has it here too
        rc=0; out=$(SWAYSOCK=$H/sock sh "$SH" desktop --machine 2>&1) || rc=$?
        [ "$rc" = 0 ] && [ ! -e "$HOME/.local/state/spark/machine" ] && ok "without SPARK_MACHINE_DIR and no spark here to read it: nothing written" || bad "machine no spark" "$(ls -la "$HOME/.local/state/spark" 2>&1)"
    fi
    printf '#!/bin/sh\necho "$*" >> "$HOME/spark.calls"\n' > "$H/.local/bin/spark"; chmod +x "$H/.local/bin/spark"
    rc=0; out=$(SWAYSOCK=$H/sock sh "$SH" desktop --machine 2>&1) || rc=$?
    [ "$rc" = 0 ] && [ -f "$HOME/.local/state/spark/machine/spark-shell.facts" ] && [ -f "$HOME/.local/state/spark/machine/spark-shell.now" ] && [ "$(ls -ld "$HOME/.local/state/spark/machine" | cut -c1-10)" = drwx------ ] && [ ! -e "$HOME/spark.calls" ] \
        && ok "with spark here, the default folder: spark's state, then machine (~/.local/state/spark/machine), 0700; spark itself not asked" || bad "machine default dir" "rc=$rc $out $(ls -la "$HOME/.local/state/spark" 2>&1)"
    MW >/dev/null; out=$(SPARK_MACHINE_DIR=$M sh "$SH" off desktop --dry-run 2>&1 || :)
    printf '%s\n' "$out" | grep -qF "would  machine      remove what the desktop told spark's prompt line (~/machine)" && [ -f "$mf" ] && [ -f "$mn" ] \
        && ok "off desktop --dry-run: a would row for the machine folder's two files, both kept" || bad "machine off dry-run" "$out"
    out=$(SPARK_MACHINE_DIR=$M sh "$SH" off desktop 2>&1 || :)
    printf '%s\n' "$out" | grep -qF "ok     machine      what the desktop told spark's prompt line is gone (~/machine)" && [ ! -e "$mf" ] && [ ! -e "$mn" ] \
        && ok "off desktop: both files gone, said once (#159)" || bad "machine off desktop" "$out $(ls -la "$M" 2>&1)"
    out=$(SPARK_MACHINE_DIR=$M sh "$SH" off desktop 2>&1 || :)
    printf '%s\n' "$out" | grep -q 'machine' && bad "off desktop again names the machine folder" "$out" || ok "off desktop again: nothing to remove, nothing said"
    printf 'DESKTOP=sway\nTHEME=nord\nKEYBOARD=us br\nDISPLAY_SAVER=starfield\n' > "$HOME/.config/spark-shell/config"; printf '# rendered by spark-shell from templates/.config/sway/config\n' > "$HOME/.config/sway/config"
    MW >/dev/null; [ -f "$mf" ] || bad "machine before off" "$(ls -la "$M" 2>&1)"
    SPARK_MACHINE_DIR=$M sh "$SH" off >/dev/null 2>&1 || :
    [ ! -e "$mf" ] && [ ! -e "$mn" ] && ok "off: both files gone too" || bad "machine off" "$(ls -la "$M" 2>&1)"
    # the session ends (sway returns): .now goes, nothing is open or in use any more; .facts stays
    printf 'DESKTOP=sway\nTHEME=nord\nKEYBOARD=us br\nDISPLAY_SAVER=starfield\n' > "$HOME/.config/spark-shell/config"; printf '# rendered by spark-shell from templates/.config/sway/config\n' > "$HOME/.config/sway/config"; : > "$HOME/.config/foot/foot.ini"
    MW >/dev/null; printf '#!/bin/sh\n:\n' > "$H/.local/bin/sway"; chmod +x "$H/.local/bin/sway"
    SPARK_MACHINE_DIR=$M env -u WAYLAND_DISPLAY -u SWAYSOCK TEST_TTY=/dev/tty1 sh "$SH" desktop >/dev/null 2>&1 || :
    [ ! -e "$mn" ] && [ -f "$mf" ] && ok "the desktop over (sway returned): .now gone, .facts kept" || bad "machine session end" "$(ls -la "$M" 2>&1)"
    # the desktop's start and the bar's loop, inside a running sway: its socket is a real one (python3 makes it)
    if [ -n "$py3" ]; then
        "$py3" -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$H/sway.sock"
        rm -rf "$M"; rm -f "$HOME/spark.calls"; SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sway.sock sh "$SH" desktop --pending >/dev/null 2>&1
        i=0; while [ "$i" -lt 50 ] && { [ ! -s "$mf" ] || [ ! -s "$HOME/spark.calls" ]; }; do sleep 0.1; i=$((i + 1)); done
        [ -s "$mf" ] && [ -s "$mn" ] && [ "$(cat "$HOME/spark.calls" 2>/dev/null)" = mcp ] && ! grep -q 'Brightness' "$mn" \
            && ok "the desktop's start (desktop --pending): both files aside, then spark mcp once, inside the session (#159)" || bad "machine start" "$(ls -la "$M" 2>&1) $(cat "$HOME/spark.calls" 2>&1)"
        rm -rf "$M"; SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sway.sock sh "$SH" bar status </dev/null >/dev/null 2>&1 & bp=$!
        i=0; while [ "$i" -lt 50 ] && [ ! -s "$mn" ]; do sleep 0.1; i=$((i + 1)); done; kill "$bp" 2>/dev/null; wait "$bp" 2>/dev/null
        [ -s "$mn" ] && [ ! -e "$mf" ] && ok "the bar's loop: .now at its first pass, aside; .facts a minute in" || bad "machine bar" "$(ls -la "$M" 2>&1)"
        rm -rf "$M"; SPARK_MACHINE_DIR=$M SWAYSOCK=$H/sock sh "$SH" desktop --pending >/dev/null 2>&1; sleep 1
        [ ! -e "$M" ] && ok "no running sway's socket there: the start writes nothing" || bad "machine no socket" "$(ls -la "$M" 2>&1)"
    fi
fi
rm -rf "$H"

# --- the voice: the docs and the help hold to it -------------------------
# README.md, the top entry of CHANGELOG.md, CREDITS.md, config.example, the
# help (sh spark-shell -h) and the comment lines of the sway template are
# plain English: none of the made-up words that are out, no contraction,
# capitals only for acronyms and placeholders, 80 columns. README is read
# without its fenced and indented blocks (a command block is quoted there,
# not prose). The key sentences are held above (desktop keys: a period
# each, verbatim in README). Not uname-guarded: the words are the same on
# both OSes. Each check names the file and the words it found. Runs last:
# a red row here belongs to a document, not to the program.
# Native settings and portals: a fake bus and settings store, never the
# developer's desktop preference. Exercise the command and the theme path.
fresh
console_stubs Linux
mkdir -p "$HOME/.config/spark-shell"
printf 'DESKTOP=sway\nTHEME=nord\n' > "$HOME/.config/spark-shell/config"
printf "'default'\n" > "$H/scheme"
cat > "$H/lx/gsettings" <<'PORTAL_STUB'
#!/bin/sh
case $1 in
    list-keys) echo color-scheme ;;
    get) cat "$HOME/scheme" ;;
    set) printf '%s\n' "$4" > "$HOME/scheme"; echo "$4" >> "$HOME/scheme.log" ;;
esac
PORTAL_STUB
printf '#!/bin/sh\necho "$XDG_CURRENT_DESKTOP $*" > "$HOME/portal.env"\n' > "$H/lx/dbus-update-activation-environment"
chmod +x "$H/lx/gsettings" "$H/lx/dbus-update-activation-environment"
DBUS_SESSION_BUS_ADDRESS=fixture WAYLAND_DISPLAY=fixture L desktop portals >/dev/null
[ "$(cat "$H/scheme")" = "'prefer-dark'" ] && grep -qx 'sway WAYLAND_DISPLAY XDG_CURRENT_DESKTOP SWAYSOCK' "$H/portal.env"     && ok "portals: the session imports its environment and shares a dark preference" || bad "portals dark environment"
DBUS_SESSION_BUS_ADDRESS=fixture WAYLAND_DISPLAY=fixture L desktop portals >/dev/null
[ "$(wc -l < "$H/scheme.log" | tr -d ' ')" = 1 ] && ok "portals: the same preference needs no write" || bad "portals repeat"
DBUS_SESSION_BUS_ADDRESS=fixture L theme gruvbox-light >/dev/null
[ "$(cat "$H/scheme")" = "'prefer-light'" ] && [ "$(sed -n 1p "$H/.local/state/spark-shell/portal-color-scheme")" = "'default'" ]     && ok "portals: a light palette changes the preference and keeps the original" || bad "portals light"
DBUS_SESSION_BUS_ADDRESS=fixture L off desktop >/dev/null
[ "$(cat "$H/scheme")" = "'default'" ] && [ ! -e "$H/.local/state/spark-shell/portal-color-scheme" ]     && ok "portals: off restores the original preference" || bad "portals restore"
printf 'DESKTOP=sway\nTHEME=nord\n' > "$HOME/.config/spark-shell/config"
DBUS_SESSION_BUS_ADDRESS=fixture L theme nord >/dev/null
DBUS_SESSION_BUS_ADDRESS=fixture WAYLAND_DISPLAY=fixture L desktop portals >/dev/null
printf "'prefer-light'\n" > "$H/scheme"
DBUS_SESSION_BUS_ADDRESS=fixture L off desktop >/dev/null
[ "$(cat "$H/scheme")" = "'prefer-light'" ] && ok "portals: off keeps a preference changed by another program" || bad "portals external change"
printf 'DESKTOP=sway\nTHEME=nord\n' > "$HOME/.config/spark-shell/config"
DBUS_SESSION_BUS_ADDRESS=fixture L theme nord --dry-run >/dev/null
[ "$(cat "$H/scheme")" = "'prefer-light'" ] && ok "portals: dry-run leaves native settings alone" || bad "portals dry-run"
L on --yes >/dev/null 2>&1 || :
f=$HOME/.config/xdg-desktop-portal/sway-portals.conf
grep -qx 'default=gtk' "$f" && grep -qx 'org.freedesktop.impl.portal.ScreenCast=wlr' "$f" && grep -qx 'org.freedesktop.impl.portal.Screenshot=wlr' "$f"     && ok "portals: the desktop renders the native backend choices" || bad "portals config"
rm -rf "$H"

# The home's folders (#119): ours where no file is, a missing folder made lowercase, a capitalized one alone named
# as it is; on again is quiet; a file of yours is kept whole and off never touches it; off takes ours back
fresh
console_stubs Linux
mkdir -p "$HOME/.config/spark-shell" "$HOME/Music"
_mu=Music; [ ! -d "$HOME/music" ] || _mu=music   # a Mac's folders are one of any case: there ~/music is ~/Music, and is named so
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
L on --yes >/dev/null 2>&1 || :
u=$HOME/.config/user-dirs.dirs
[ "$(head -1 "$u" 2>/dev/null)" = '# rendered by spark-shell: the user folders (#119)' ] && grep -qx 'XDG_DESKTOP_DIR="$HOME"' "$u" && grep -qx 'XDG_DOWNLOAD_DIR="$HOME/downloads"' "$u" \
    && grep -qx 'XDG_PICTURES_DIR="$HOME/pictures"' "$u" && grep -qx 'XDG_DOCUMENTS_DIR="$HOME/documents"' "$u" && grep -qx "XDG_MUSIC_DIR=\"\$HOME/$_mu\"" "$u" && grep -qx 'XDG_VIDEOS_DIR="$HOME/videos"' "$u" \
    && [ -d "$HOME/downloads" ] && [ -d "$HOME/pictures" ] && [ -d "$HOME/documents" ] && [ -d "$HOME/videos" ] && { [ "$_mu" = music ] || [ ! -d "$HOME/music" ]; } && [ ! -e "$u.bak" ] \
    && ok "on desktop: ~/.config/user-dirs.dirs names the five folders, a missing one made lowercase, ~/Music alone named as it is, no .bak (#119)" || bad "user dirs" "$(cat "$u" 2>&1)"
out=$(L on --yes -v 2>&1 || :)
printf '%s\n' "$out" | grep -q '^ok .*folders' && ! printf '%s\n' "$out" | grep -q '^render .*folders' && ok "on desktop again: the folders' file quiet (#119)" || bad "user dirs again" "$(printf '%s\n' "$out" | grep folders)"
mkdir -p "$HOME/Downloads2"; L off desktop >/dev/null 2>&1 || :
[ ! -e "$u" ] && [ -d "$HOME/downloads" ] && [ -d "$HOME/Music" ] && ok "off desktop: ours goes, the folders stay (#119)" || bad "user dirs off" "$(ls -a "$HOME/.config" "$HOME")"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
printf 'XDG_DOWNLOAD_DIR="$HOME/Stuff"\n' > "$u"; L on --yes >/dev/null 2>&1 || :; m1=$(cat "$u"); L off desktop >/dev/null 2>&1 || :; m2=$(cat "$u" 2>/dev/null)
[ "$m1" = 'XDG_DOWNLOAD_DIR="$HOME/Stuff"' ] && [ "$m2" = "$m1" ] && [ ! -e "$u.bak" ] && ok "on and off desktop: a folders' file of yours is kept whole, never backed up (#119)" || bad "user dirs yours" "$m1 | $m2"
rm -rf "$H"

# Native time settings: isolated files, root prefix and time service stubs.
fresh
console_stubs Linux
mkdir -p "$HOME/.config/spark-shell" "$H/root/etc" "$H/root/usr/share/zoneinfo/Etc"
printf 'DESKTOP=sway\n' > "$HOME/.config/spark-shell/config"
printf TZif > "$H/root/usr/share/zoneinfo/Etc/UTC"
printf TZif > "$H/root/usr/share/zoneinfo/Etc/GMT"
ln -s "$H/root/usr/share/zoneinfo/Etc/UTC" "$H/root/etc/localtime"
L desktop time format 12 >/dev/null
L desktop time week monday >/dev/null
out=$(L desktop time)
printf '%s' "$out" | grep -qx 'format 12' && printf '%s' "$out" | grep -qx 'week monday' && grep -qx 'CLOCK_FORMAT=12' "$HOME/.config/spark-shell/config"     && ok "time: clock format and first weekday are saved and read together" || bad "time preferences" "$out"
rc=0; out=$(L desktop time format 13 2>&1) || rc=$?
[ "$rc" = 1 ] && grep -qx 'CLOCK_FORMAT=12' "$HOME/.config/spark-shell/config" && ok "time: invalid presentation values leave preferences alone" || bad "time invalid format" "$out"
rc=0; out=$(L desktop time zone Etc/GMT </dev/null 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$(readlink "$H/root/etc/localtime")" = "$H/root/usr/share/zoneinfo/Etc/UTC" ]     && ok "time: a native zone change needs confirmation" || bad "time confirmation" "$out"
# No systemd tools here: the native link is the contract on runit.
printf '#!/bin/sh\nexit 1\n' > "$H/lx/timedatectl"; chmod +x "$H/lx/timedatectl"
mkdir -p "$H/root/etc/runit"
L desktop time zone Etc/GMT --yes >/dev/null
[ "$(readlink "$H/root/etc/localtime")" = "$H/root/usr/share/zoneinfo/Etc/GMT" ]     && ok "time: a confirmed runit zone uses the native localtime link" || bad "time runit zone"
rc=0; out=$(L desktop time zone ../passwd --yes 2>&1) || rc=$?
[ "$rc" = 1 ] && [ "$(readlink "$H/root/etc/localtime")" = "$H/root/usr/share/zoneinfo/Etc/GMT" ]     && ok "time: paths outside zoneinfo are refused" || bad "time invalid zone" "$out"
printf '#!/bin/sh\necho "$*" >> "$HOME/chronyc.args"; echo "Leap status     : Normal"\n' > "$H/lx/chronyc"; chmod +x "$H/lx/chronyc"
rm -f "$HOME/.local/state/spark-shell/panel/time_sync"   # the probe's minute, from before the stub
out=$(L desktop time); L desktop time >/dev/null
printf '%s' "$out" | grep -qx 'clock synced by chrony' && [ "$(cat "$HOME/chronyc.args")" = '-n tracking' ] \
    && ok "time: native sync is read from chrony with no name lookup (-n), once a minute: a lookup that times out held every clock row 5 s (#97)" || bad "time sync" "$out $(cat "$HOME/chronyc.args" 2>&1)"
L desktop time zone Etc/UTC --yes --dry-run >/dev/null
[ "$(readlink "$H/root/etc/localtime")" = "$H/root/usr/share/zoneinfo/Etc/GMT" ] && ok "time: dry-run does not change the native zone" || bad "time dry-run"
rm -rf "$H"

# Bluetooth uses the native services. Dry-run writes nothing; a service
# already linked is kept, and check distinguishes a stopped daemon.
fresh
console_stubs Linux
mkdir -p "$H/root/etc/runit" "$H/root/etc/sv/dbus" "$H/root/etc/sv/bluetoothd" "$H/root/var/service" "$HOME/.config/spark-shell"
printf 'DESKTOP=sway\nTHEME=nord\n' > "$HOME/.config/spark-shell/config"
printf 'bluetooth:x:900:\n' > "$H/root/etc/group"
printf '#!/bin/sh\nexit 0\n' > "$H/lx/bluetoothctl"
printf '#!/bin/sh\necho "$*" >> "$HOME/bt.service.log"\n' > "$H/lx/sv"
printf '#!/bin/sh\necho "$*" >> "$HOME/bt.group.log"\n' > "$H/lx/usermod"
printf '#!/bin/sh\n[ ! -e "$HOME/bt.up" ] || echo "boolean true"\n' > "$H/lx/dbus-send"
chmod +x "$H/lx/bluetoothctl" "$H/lx/sv" "$H/lx/usermod" "$H/lx/dbus-send"
L on desktop --dry-run >/dev/null
[ ! -e "$H/root/var/service/dbus" ] && [ ! -e "$H/bt.service.log" ] && [ ! -e "$H/bt.group.log" ]     && ok "bluetooth: service and group dry-run writes nothing" || bad "bluetooth dry-run"
L on desktop --yes >/dev/null 2>&1
[ "$(readlink "$H/root/var/service/dbus")" = "$H/root/etc/sv/dbus" ] && [ "$(readlink "$H/root/var/service/bluetoothd")" = "$H/root/etc/sv/bluetoothd" ]     && grep -q 'bluetoothd' "$H/bt.service.log" && grep -q -- '-aG bluetooth' "$H/bt.group.log"     && ok "bluetooth: native runit services and group are enabled" || bad "bluetooth native setup"
out=$(L check || :)
printf '%s' "$out" | grep -q '^warn *bluetooth *bluetoothd is not running'     && ok "bluetooth: check names a stopped daemon" || bad "bluetooth check stopped" "$out"
rm -rf "$H"

# --- the credits: each tool's licence is distro/licenses' (#106) ---------
# Every package of PKG_SHELL, PKG_CLI and PKG_CONSOLE in distro/*.env has a
# line in distro/licenses, and its CREDITS.md entry (the line that opens
# "- NAME ", up to the next entry) says that licence after a " -- ". eza
# read MIT there for months; its own repository says EUPL-1.2.
lic=$REPO/distro/licenses
miss=
for p in $(sed -n 's/^PKG_SHELL=//p; s/^PKG_CLI=//p; s/^PKG_CONSOLE=//p' "$REPO"/distro/*.env | tr ' ' '\n' | sort -u); do
    grep -q "^$p " "$lic" || miss="$miss $p"
done
[ -z "$miss" ] && ok "credits: every tool package of distro/*.env has a licence in distro/licenses" || bad "credits: a package with no licence line" "$miss"
wrong=$(grep -v '^#' "$lic" | while read -r p l c; do
    awk -v name="${c:-$p}" -v lic="$l" '
        index($0, "- " name " ") == 1 { on = 1; text = $0; next }
        on && (/^- / || /^$/ || /^#/) { on = 0 }
        on { text = text " " $0 }
        END {
            n = split(text, part, " -- ")
            for (i = 2; i <= n; i++) {
                s = part[i]
                if (index(s, lic) == 1) { c = substr(s, length(lic) + 1, 1); if (c == "." || c == "," || c == " " || c == "(") found = 1 }
            }
            if (!found) printf "%s ", name
        }' "$REPO/CREDITS.md"
done)
[ -z "$wrong" ] && ok "credits: each tool's CREDITS.md entry says the licence distro/licenses holds" || bad "credits: an entry with another licence, or none" "$wrong"

voice=$(mktemp -d)
awk '/^```/ {fence = !fence; next} fence {next} /^    / {next} {print}' "$REPO/README.md" > "$voice/README.md"
awk '/^## v/ {n++} n == 1' "$REPO/CHANGELOG.md" > "$voice/CHANGELOG.md"
cp "$REPO/CREDITS.md" "$voice/CREDITS.md"
cp "$REPO/config.example" "$voice/config.example"
sh "$SH" -h > "$voice/help"
grep '^ *#' "$REPO/template/.config/sway/config" > "$voice/sway-config-comments"
out_words="colours?|desks?|rooms?|seat|login box|marks?|marked|player|this machine's cycles|the forge wallpaper|greeter|the box|stranger|newcomer|founder|inventory|the hands|shell layer|monitors?"
contractions="[A-Za-z]*n't\b|\bit's\b|\byou'll\b|\bwe're\b|\bthat's\b|\bthere's\b|\blet's\b"
caps_ok='CUPS|DAY|TIME|KEYBOARD|POINTER|VOICE|ASCII|ALSA|A2DP|POSIX|JSON|SGR|SBOM|PATH|NAME|WORDS|PAGE|SECTION|KEY|VALUE|FILE|DIR|PLACE|WIDTH|SIDE|HEIGHT|HOME|EDITOR|FACE|SIZE|GRUB|FAIL|WARN|TODO|LICENSE|MIT|ISC|EUPL|GPL|LGPL|GNOME|CC|README|CHANGELOG|CREDITS|VGA|RGB|ANSI|CI|LAN|XDG|PPT|HDMI|URL|HTTP|THEME|SITE|SPARK|DESKTOP|LOGIN|WALLPAPER|ALPHA|WINDOWS|FONT|PROMPT|GIT|PM|PKG|CDX|CP437|UKI|macOS'
for n in README.md CHANGELOG.md CREDITS.md config.example help sway-config-comments; do
    f=$voice/$n
    # (a) the words that are out, as whole words in any case
    hit=$(grep -ioEw "$out_words" "$f" | sort -u | paste -sd, -)
    [ -z "$hit" ] && ok "voice: $n has none of the words that are out" || bad "voice: $n has a word that is out" "$hit"
    # (b) no contraction
    hit=$(grep -ioE "$contractions" "$f" | sort -u | paste -sd, -)
    [ -z "$hit" ] && ok "voice: $n has no contraction" || bad "voice: $n has a contraction" "$hit"
    # (c) capitals only for acronyms: a word of 4+ capitals outside a code span is on the list or carries an underscore
    hit=$(sed 's/`[^`]*`//g' "$f" | tr -c 'A-Za-z0-9_' '\n' | grep -E '^[A-Z][A-Z0-9]{3,}$' | grep -vxE "($caps_ok)" | sort -u | paste -sd, -)
    [ -z "$hit" ] && ok "voice: $n has capitals only for acronyms" || bad "voice: $n has a word in capitals" "$hit"
    # (d) ASCII only
    LC_ALL=C grep -q "[^ -~${tab}]" "$f" && bad "voice: $n has a byte outside ASCII" "$(LC_ALL=C grep -n "[^ -~${tab}]" "$f" | head -2)" || ok "voice: $n is ASCII"
done
# (e) the widths: the help and README at most 80 columns a line
wide=$(awk 'length > 80 {print FNR ": " length}' "$voice/help" | head -3 | paste -sd, -)
[ -z "$wide" ] && ok "voice: every help line is 80 columns or fewer" || bad "voice: a help line is wider than 80 (line: width)" "$wide"
wide=$(awk 'length > 80 {print FNR ": " length}' "$REPO/README.md" | head -3 | paste -sd, -)
[ -z "$wide" ] && ok "voice: every README line is 80 columns or fewer" || bad "voice: a README line is wider than 80 (line: width)" "$wide"
rm -rf "$voice"

fi

printf '%s\n' "shell_test: $pass ok, $fail failed"
[ "$fail" -eq 0 ]
