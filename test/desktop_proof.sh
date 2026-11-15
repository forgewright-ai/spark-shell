#!/bin/sh
# desktop_proof.sh -- the desktop proven in a container, as a plain user
# (CI's desktop job, one family a run): spark-shell on with DESKTOP=sway
# against a throwaway root, the renders in place, a drawing drawn again in
# the palette through rsvg-convert, the sway config read by sway -C, then a
# headless sway (no seat, no GPU: wlroots' headless backend and the pixman
# renderer) with a foot window in it, asked through swaymsg, on a session
# bus of its own as the desktop has where no logind makes one; then mako's
# notifications in it, drawn in two palettes and with do not disturb on,
# each captured into $HOME/proof for a look (CI keeps them). Every step
# prints what it found; the first failure ends it. REPO is the clone.
# The root tools a plain user cannot run (usermod, gpasswd) are shims that
# edit the throwaway root's group file, as the suite's do.
set -eu
REPO=${REPO:?the clone path}
export HOME=${HOME:-/home/ada}
# A home of its own, always: this proof writes the config and installs spark-shell over it, and CI gives it
# a user of its own. A home that already holds a config is someone's, and the proof stops rather than take it.
[ ! -e "$HOME/.config/spark-shell/config" ] || { echo "refusing: $HOME holds a spark-shell config; this proof needs a home of its own"; exit 2; }
export XDG_RUNTIME_DIR=/tmp/proof-runtime SPARK_SHELL_ROOT=$HOME/root SPARK_SHELL_DIALOG_URL=none SPARK_SHELL_FONT_URL=none LANG=C.UTF-8
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK
R=$SPARK_SHELL_ROOT
mkdir -p "$XDG_RUNTIME_DIR" "$R/etc" "$R/var/service" "$R/etc/sv/seatd" "$HOME/.config/spark-shell" "$HOME/.config/spark" "$HOME/bin"
chmod 700 "$XDG_RUNTIME_DIR"
cp /etc/os-release "$R/etc/os-release"
cp /etc/group "$R/etc/group"
cp /etc/passwd "$R/etc/passwd"
me=$(id -un)
cat > "$HOME/bin/usermod" <<EOF
#!/bin/sh
# proof: usermod -aG GROUP USER edits the throwaway root's group file
echo "usermod \$*" >> "$HOME/root-tools.log"
[ "\$1" = -aG ] || exit 0
awk -F: -v g="\$2" -v u="\$3" 'BEGIN { OFS = ":" } \$1 == g { \$4 = (\$4 == "" ? u : \$4 "," u) } { print }' "$R/etc/group" > "$R/etc/group.new" && mv "$R/etc/group.new" "$R/etc/group"
EOF
printf '#!/bin/sh\necho "gpasswd $*" >> "%s/root-tools.log"\n' "$HOME" > "$HOME/bin/gpasswd"
chmod 755 "$HOME/bin/usermod" "$HOME/bin/gpasswd"
export PATH=$HOME/bin:${SWAY_NOCAP:+$SWAY_NOCAP:}$PATH   # SWAY_NOCAP: a folder with a copy of sway that carries no file capability (see ci.yml)
printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=skyline\nDISPLAY_IDLE=0\nDISPLAY_LOCK=0\n' > "$HOME/.config/spark-shell/config"
cd "$HOME"
distro=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"')

echo "== spark-shell on --yes -v ($distro, as $me)"
sh "$REPO/spark-shell" on --yes -v 2>&1 | tee "$HOME/on.out"
grep -q '^ok     packages     installed$' "$HOME/on.out" || { echo "FAIL: the packages row is not ok"; exit 1; }
grep -q '^render wallpaper    skyline drawn in nord ' "$HOME/on.out" || { echo "FAIL: skyline was not drawn in nord (rsvg-convert)"; exit 1; }
for f in .config/sway/config .config/foot/foot.ini .config/foot/dialog.ini .config/mako/config .tmux.conf .config/spark-shell/sgr.sh; do
    [ -f "$HOME/$f" ] || { echo "FAIL: $f was not rendered"; exit 1; }
done
png=$HOME/.local/state/spark-shell/wallpapers/skyline-nord.png
[ -s "$png" ] || { echo "FAIL: no $png"; exit 1; }
echo "ok: the renders are in place; skyline drawn in nord, $(wc -c < "$png" | tr -d ' ') bytes"
[ ! -s "$HOME/root-tools.log" ] || { echo "-- the root steps a plain user cannot take, through the shims:"; cat "$HOME/root-tools.log"; }

echo "== spark-shell check"
sh "$REPO/spark-shell" check 2>&1 | tee "$HOME/check.out" || true
grep -Eq '^(ok|warn) +desktop +' "$HOME/check.out" || { echo "FAIL: check's desktop row is not ok or warn"; exit 1; }
grep -q '^ok     look ' "$HOME/check.out" || { echo "FAIL: check's look row is not ok"; exit 1; }
grep -q '^ok     tools ' "$HOME/check.out" || { echo "FAIL: check's tools row is not ok"; exit 1; }

echo "== sway -C: the rendered config reads"
if sway -C -c "$HOME/.config/sway/config" > "$HOME/sway-C.out" 2>&1; then echo "ok: sway -C accepts the config"; else cat "$HOME/sway-C.out"; echo "FAIL: sway -C refused the config"; exit 1; fi
cat "$HOME/sway-C.out"

echo "== a session bus, then a headless sway on it, then a foot window in it"
# a container has no logind, as Void has none: the bus is the desktop's own (layout_start runs sway
# inside dbus-run-session); here one bus for sway and for this script's notify-send and makoctl
command -v dbus-daemon >/dev/null 2>&1 || { echo "FAIL: no dbus-daemon for a session bus"; exit 1; }
dbus-daemon --session --fork --print-address=1 --print-pid=1 > "$HOME/bus.out" || { echo "FAIL: dbus-daemon gave no session bus"; exit 1; }
DBUS_SESSION_BUS_ADDRESS=$(sed -n 1p "$HOME/bus.out"); buspid=$(sed -n 2p "$HOME/bus.out"); export DBUS_SESSION_BUS_ADDRESS
echo "ok: a session bus at $DBUS_SESSION_BUS_ADDRESS"
sway -c "$HOME/.config/sway/config" > "$HOME/sway.log" 2>&1 &
swaypid=$!
trap 'kill "$swaypid" "$buspid" 2>/dev/null || :' EXIT   # a step that fails leaves no sway and no bus behind
sock=''
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1)
    [ -z "$sock" ] || break
    kill -0 "$swaypid" 2>/dev/null || { echo "FAIL: sway ended before its socket came up"; cat "$HOME/sway.log"; exit 1; }
    sleep 1
done
[ -n "$sock" ] || { echo "FAIL: no sway socket after 15 s"; cat "$HOME/sway.log"; exit 1; }
export SWAYSOCK=$sock
sleep 2
WAYLAND_DISPLAY=''   # grim speaks Wayland to the same sway: its socket in the runtime dir, never the .lock beside it
for w in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do [ -S "$w" ] && { WAYLAND_DISPLAY=${w##*/}; break; }; done
export WAYLAND_DISPLAY
swaymsg -t get_version | jq -r '"sway " + .human_readable'
swaymsg -t get_outputs | jq -r '.[] | "output " + .name + " " + (.current_mode.width|tostring) + "x" + (.current_mode.height|tostring)'
swaymsg exec 'foot --app-id proof-window' >/dev/null   # by its app id: the rc's prompt hook retitles a foot window to terminal at once
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == "proof-window")' >/dev/null 2>&1 && break
    sleep 1
done
swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == "proof-window")' >/dev/null || { echo "FAIL: no foot window in sway's tree"; tail -40 "$HOME/sway.log"; exit 1; }
echo "ok: a foot window is open in the headless sway ($(swaymsg -t get_tree | jq -r '[.. | objects | select(.app_id? != null) | .app_id] | unique | join(", ")'))"
for b in $(swaymsg -t get_bar_config | jq -r '.[]'); do swaymsg -t get_bar_config "$b" | jq -r '"bar " + .id + ": mode " + .mode + ", at the " + .position'; done

echo "== a terminal the keys place: its frame on every side, none of the ground inside it, the same window at each press (v0.148.1)"
# foot cuts a floating window to whole cells from 1.17 on unless foot.ini says not to. The window then differed with each
# press: Super+Ctrl+Up shrank it to the terminal's size, and Up again put it back at its place with the ground
# showing in what the terminal left, or its frame covered. An older foot has no such line to take.
fv=$(foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9]*\)\.\([0-9]*\).*/\1 \2/p'); set -- ${fv:-0 0}
if [ "$1" -gt 1 ] || [ "$2" -ge 17 ]; then
    frame=$(sed -n 's/^client\.focused  *#[0-9a-f]* #[0-9a-f]* #[0-9a-f]* #[0-9a-f]* #\([0-9a-f]\{6\}\)$/\1/p' "$HOME/.config/sway/config")
    oh=$(swaymsg -t get_outputs | jq -r '.[0].rect.height')
    was=$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
    swaymsg 'workspace 9' >/dev/null   # a workspace of its own for the new terminal
    swaymsg 'output * bg #00ff00 solid_color' >/dev/null
    plain=''
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        [ "$(grim -t ppm -g "0,$((oh - 1)) 1x1" - 2>/dev/null | tail -c 3 | od -An -tx1 | tr -d ' \n')" != 00ff00 ] || { plain=1; break; }
        sleep 1
    done
    [ -n "$plain" ] || { echo "FAIL: the plain ground this check reads did not come up"; exit 1; }
    swaymsg exec 'foot --app-id proof-new' >/dev/null
    bleed=''
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == "proof-new")' >/dev/null 2>&1 && break; sleep 1; done
    sizes=''
    for place in up up left left; do
        sh "$REPO/spark-shell" desktop window "$place" > "$HOME/window.out" 2>&1 || { cat "$HOME/window.out"; echo "FAIL: desktop window $place"; exit 1; }
        box=''
        for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
            sleep 1
            now=$(swaymsg -t get_tree | jq -r '.. | objects | select(.app_id? == "proof-new") | "\(.rect.x),\(.rect.y - .deco_rect.height) \(.rect.width)x\(.rect.height + .deco_rect.height) \(.deco_rect.height) \(.type)"')
            case $now in *' floating_con') [ "$now" != "$box" ] || break ;; esac
            box=$now
        done
        case $box in *' floating_con') box=${box% *} ;; *) echo "FAIL: after $place the new terminal is not a placed window: $box"; exit 1 ;; esac
        grim -t ppm -g "${box% *}" "$HOME/window.ppm" || { echo "FAIL: grim took no picture of the window"; exit 1; }
        python3 -I -c '
import sys
data, band, frame, place = open(sys.argv[1], "rb").read(), int(sys.argv[2]), bytes.fromhex(sys.argv[3]), sys.argv[4]
_, size, _, px = data.split(b"\n", 3)
w, h = (int(n) for n in size.split())
at = lambda x, y: px[(y * w + x) * 3:(y * w + x) * 3 + 3]
sides = {"left": [at(0, y) for y in range(band, h)], "right": [at(w - 1, y) for y in range(band, h)], "bottom": [at(x, h - 1) for x in range(w)]}
bare = sorted(name for name, line in sides.items() if any(p != frame for p in line))
ground = sum(1 for y in range(band, h - 1) for x in range(1, w - 1) if at(x, y) == b"\x00\xff\x00")
print("%s: the window %dx%d, the frame whole on %s, %d pixels of the ground inside it" % (place, w, h, "every side" if not bare else "every side but the " + ", ".join(bare), ground))
sys.exit(1 if bare or ground else 0)' "$HOME/window.ppm" "${box##* }" "$frame" "$place" || bleed=1
        sizes="$sizes ${box#* }"
    done
    [ -z "$bleed" ] || { echo "FAIL: the terminal does not fill its window, or covers its frame"; exit 1; }
    # shellcheck disable=SC2086   # four sizes and their bands, split on purpose
    set -- $sizes
    [ "$1" = "$3" ] && [ "$5" = "$7" ] || { echo "FAIL: a key pressed again gives another window:$sizes"; exit 1; }
    echo "ok: Up and Up again give one window ($1), Left and Left again one ($5); the terminal fills it and its frame shows on every side"
    swaymsg "[app_id=\"proof-new\"] kill" >/dev/null; swaymsg "workspace $was" >/dev/null
else
    echo "note: foot ${fv:-of no version} has no line in foot.ini for this: not checked here"
fi

echo "== the notifications: mako started by the sway config, three drawn, in two palettes, then do not disturb (#71)"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do makoctl mode >/dev/null 2>&1 && break; sleep 1; done
makoctl mode >/dev/null 2>&1 || { echo "FAIL: mako does not answer on the session bus"; tail -20 "$HOME/sway.log"; exit 1; }
proof=$HOME/proof; mkdir -p "$proof"
corner=$(swaymsg -t get_outputs | jq -r '.[0] | "\(.rect.width - 560),0 560x420"')
shot() {   # shot NAME [LINES]: notifications sent, the screen's top right corner captured into proof/NAME.png, what mako lists said
    notify-send -a firefox "Download finished" "report.pdf, 2.4 MB, in your downloads"
    notify-send -a spark-shell -c x-spark-shell.reminder "call the vet" "due now"
    notify-send -u critical -a power "Battery at 5%" "Plug the charger in"
    sleep 2
    grim -g "$corner" "$proof/$1.png" || { echo "FAIL: grim took no picture"; exit 1; }
    _n=$(makoctl list | grep -c '^Notification' || :)
    [ "$_n" = 3 ] || [ "$(makoctl list | head -c 1)" = '{' ] || { echo "FAIL: mako lists $_n notifications, not 3"; makoctl list; exit 1; }
    echo "ok: $1, the corner in $proof/$1.png ($(wc -c < "$proof/$1.png" | tr -d ' ') bytes)"
    makoctl dismiss -a >/dev/null 2>&1 || :
}
for pal in tokyonight-night solarized-light; do
    sh "$REPO/spark-shell" theme "$pal" > "$HOME/theme.out" 2>&1 || { cat "$HOME/theme.out"; echo "FAIL: theme $pal"; exit 1; }
    grep -q "^background-color=#" "$HOME/.config/mako/config" || { echo "FAIL: mako's config has no background"; exit 1; }
    sleep 1
    shot "notifications-$pal"
done
echo "== the wallpaper: one process draws it after two themes changed it (v0.149.1)"
# each change draws the new picture under a cover of its own, which goes once sway's own has drawn: a cover that stays
# is one more process on the session at every change
walls() { for _e in /proc/[0-9]*/environ; do _p=${_e#/proc/}; _p=${_p%/environ}; [ "$(cat "/proc/$_p/comm" 2>/dev/null)" = swaybg ] || continue; { tr '\0' '\n' < "$_e" | grep -qx "SWAYSOCK=$SWAYSOCK"; } 2>/dev/null && echo "$_p"; done | wc -l | tr -d ' '; }
for _ in 1 2 3 4 5 6 7 8 9 10; do [ "$(walls)" = 1 ] && break; sleep 0.5; done
[ "$(walls)" = 1 ] || { echo "FAIL: $(walls) wallpaper processes draw on this sway, not 1: a cover stayed"; exit 1; }
echo "ok: one wallpaper process"
sh "$REPO/spark-shell" desktop notifications do-not-disturb on
makoctl mode | grep -qx do-not-disturb || { echo "FAIL: do not disturb is not mako's mode"; exit 1; }
grep -qx 'DO_NOT_DISTURB=yes' "$HOME/.config/spark-shell/config" || { echo "FAIL: do not disturb is not in the config"; exit 1; }
shot "notifications-do-not-disturb"   # a look: only the critical one shows
sh "$REPO/spark-shell" desktop notifications do-not-disturb off
sh "$REPO/spark-shell" panel notifications --list | sed -n '1,4p'
swaymsg exit >/dev/null 2>&1 || true
wait "$swaypid" 2>/dev/null || true
kill "$buspid" 2>/dev/null || true
grep -i 'error' "$HOME/sway.log" | head -5 || true
echo "== done: $distro installs the desktop, renders it, and sway runs it headless"
