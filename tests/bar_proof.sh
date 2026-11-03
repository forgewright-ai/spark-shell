#!/bin/sh
# bar_proof.sh -- the bar's review proven on a headless sway, as a plain
# user, each look captured by grim into $HOME/proof: the bar at the top
# and at the bottom, the notifications that came while nobody looked
# counted beside do not disturb, the bar's text on a 1080-row screen and
# on a 2160-row one (auto), and the tray: off, with two apps asking for
# it, then on. The desktop's packages are installed already (CI's desktop
# job, or apt-get as root); spark-shell on renders the files against a
# throwaway root, as desktop_proof.sh does. REPO is the clone; FONT_ZIP
# (optional) is the Monaspace Neon release zip, so the bar wears its own
# glyphs. Every step prints what it found; the first failure ends it.
set -eu
REPO=${REPO:?the clone path}
export HOME=${HOME:?}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/bar-proof-runtime} SPARK_SHELL_ROOT=$HOME/root SPARK_SHELL_DIALOG_URL=none LANG=C.UTF-8
export SPARK_SHELL_FONT_URL=${FONT_ZIP:+file://$FONT_ZIP}; [ -n "$SPARK_SHELL_FONT_URL" ] || SPARK_SHELL_FONT_URL=none
export WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK
R=$SPARK_SHELL_ROOT
mkdir -p "$XDG_RUNTIME_DIR" "$R/etc" "$HOME/.config/spark-shell" "$HOME/bin"
chmod 700 "$XDG_RUNTIME_DIR"
cp /etc/os-release /etc/group /etc/passwd "$R/etc/"
printf '#!/bin/sh\nexit 0\n' > "$HOME/bin/usermod"; cp "$HOME/bin/usermod" "$HOME/bin/gpasswd"; chmod 755 "$HOME/bin/usermod" "$HOME/bin/gpasswd"
export PATH=$HOME/bin:$PATH
printf 'DESKTOP=sway\nTHEME=nord\nWALLPAPER=skyline\nDISPLAY_IDLE=0\nDISPLAY_LOCK=0\n' > "$HOME/.config/spark-shell/config"
cd "$HOME"
proof=$HOME/proof; mkdir -p "$proof"
S() { sh "$REPO/spark-shell" "$@"; }

echo "== spark-shell on --yes"
S on --yes > "$HOME/on.out" 2>&1 || { tail -30 "$HOME/on.out"; echo "FAIL: on"; exit 1; }
grep -q '^    position top$' "$HOME/.config/sway/config" && grep -q '^    tray_output none$' "$HOME/.config/sway/config" || { echo "FAIL: the bar block"; exit 1; }
echo "ok: rendered; the bar at the top, the tray off"

echo "== a session bus, a headless sway on it"
dbus-daemon --session --fork --print-address=1 --print-pid=1 > "$HOME/bus.out"
DBUS_SESSION_BUS_ADDRESS=$(sed -n 1p "$HOME/bus.out"); buspid=$(sed -n 2p "$HOME/bus.out"); export DBUS_SESSION_BUS_ADDRESS
sway -c "$HOME/.config/sway/config" > "$HOME/sway.log" 2>&1 &
swaypid=$!
sock=''
for _ in $(seq 15); do sock=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock 2>/dev/null | head -1); [ -z "$sock" ] || break; sleep 1; done
[ -n "$sock" ] || { tail -30 "$HOME/sway.log"; echo "FAIL: no sway socket"; exit 1; }
export SWAYSOCK=$sock
for w in "$XDG_RUNTIME_DIR"/wayland-[0-9]*; do [ -S "$w" ] && { WAYLAND_DISPLAY=${w##*/}; break; }; done
export WAYLAND_DISPLAY
out=$(swaymsg -t get_outputs | jq -r '.[0].name')
swaymsg "output $out resolution 1920x1080" >/dev/null
sleep 2
swaymsg exec 'foot --app-id proof-window' >/dev/null
for _ in $(seq 15); do makoctl mode >/dev/null 2>&1 && [ -s "$HOME/.local/state/spark-shell/bar.pid" ] && break; sleep 1; done
makoctl mode >/dev/null 2>&1 || { echo "FAIL: mako does not answer"; exit 1; }
echo "ok: $(swaymsg -t get_version | jq -r '"sway " + .human_readable'), output $out 1920x1080, mako up, the bar's loop running"
redraw() { kill -USR1 "$(cat "$HOME/.local/state/spark-shell/bar.pid")" 2>/dev/null || :; sleep "${1:-2}"; }
bar_h() { swaymsg -t get_tree | jq -r '[.. | objects | select(.type? == "workspace" and .name != "__i3_scratch")][0].rect | .y, .height' | paste -sd' ' -; }
shot() { grim "$proof/$1.png"; echo "ok: $proof/$1.png"; }
strip() {   # strip NAME top|bottom: the bar's right half, as drawn
    _o=$(swaymsg -t get_outputs | jq -r '.[0].rect | "\(.width) \(.height)"'); _w=${_o% *}; _h=${_o#* }
    # shellcheck disable=SC2046   # Y and HEIGHT, split on purpose
    set -- "$1" "$2" $(bar_h)   # NAME PLACE Y HEIGHT: the workspace's area; the bar is the rest
    if [ "$2" = top ]; then _bh=$3; _y=0; else _bh=$((_h - $4)); _y=$4; fi
    grim -g "$((_w / 2)),$_y $((_w / 2))x$_bh" "$proof/$1.png"; echo "ok: $proof/$1.png (the bar $_bh pixels high)"
}

echo "== the bar at the top; three notifications came, none looked at (#71)"
notify-send -a firefox "Download finished" "report.pdf, 2.4 MB, in your downloads"
notify-send -a aerc "New mail from Ada" "the minutes of Tuesday"
notify-send -a chat "Ping" "lunch at one?"
sleep 1; makoctl dismiss -a   # gone unseen, as six seconds would take them
redraw
S bar status --once | jq -e 'any(.[]; .name == "notifications" and (.full_text | test("\u25c6 3")))' >/dev/null || { echo "FAIL: no count of 3"; exit 1; }
shot bar-top; strip bar-top-strip top
notify-send -a firefox "Upload finished" "slides.pdf is shared"; sleep 2
grim -g "1360,0 560x260" "$proof/notification-top-right.png"; echo "ok: $proof/notification-top-right.png"
makoctl dismiss -a

echo "== do not disturb on, the count beside it"
S desktop notifications do-not-disturb on >/dev/null; redraw; strip bar-dnd-count top
S desktop notifications do-not-disturb off >/dev/null

echo "== the bar's block clicked: every one looked at, the count gone"
S bar seen; redraw
S bar status --once | jq -e 'all(.[]; .name != "notifications")' >/dev/null || { echo "FAIL: the count stayed"; exit 1; }
strip bar-seen top

echo "== the bar at the bottom; a notification in the bottom right corner"
S bar bottom >/dev/null; sleep 3
[ "$(swaymsg -t get_bar_config bar-0 | jq -r .position)" = bottom ] || { echo "FAIL: sway's bar is not at the bottom"; exit 1; }
for _ in $(seq 15); do [ -s "$HOME/.local/state/spark-shell/bar.pid" ] && kill -0 "$(cat "$HOME/.local/state/spark-shell/bar.pid")" 2>/dev/null && break; sleep 1; done
notify-send -a calendar "Standup in 5 minutes" "room 2, or the call"; sleep 1; redraw
shot bar-bottom; strip bar-bottom-strip bottom
makoctl dismiss -a
S bar top >/dev/null; sleep 3

echo "== the bar's text, auto: 1080 rows, then 2160"
for _ in $(seq 15); do [ -s "$HOME/.local/state/spark-shell/bar.pid" ] && kill -0 "$(cat "$HOME/.local/state/spark-shell/bar.pid")" 2>/dev/null && break; sleep 1; done
S bar seen; redraw 3
f1=$(swaymsg -t get_bar_config bar-0 | jq -r .font); strip text-auto-1080 top
swaymsg "output $out resolution 3840x2160" >/dev/null; sleep 2; redraw 4
f2=$(swaymsg -t get_bar_config bar-0 | jq -r .font); strip text-auto-2160 top
shot screen-2160
echo "ok: the bar's font $f1 on 1080 rows, $f2 on 2160"
[ "$f1" != "$f2" ] || { echo "FAIL: auto kept one size"; exit 1; }
swaymsg "output $out resolution 1920x1080" >/dev/null; sleep 2; redraw 4

echo "== the tray: two apps ask for it; off, then on"
cat > "$HOME/sni.py" <<'PY'
# sni.py R G B ID -- a stand-in app with a tray icon (a StatusNotifierItem): a 32-pixel disc in its own color
import os, sys, dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
r, g, b, ident = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
bus = dbus.SessionBus()
name = "org.kde.StatusNotifierItem-%d-1" % os.getpid()
keep = dbus.service.BusName(name, bus)
px = bytearray()
for y in range(32):
    for x in range(32):
        d = (x - 15.5) ** 2 + (y - 15.5) ** 2
        a = 255 if d < 196 else 0
        w = d < 36
        px += bytes([a, 255 if w else r, 255 if w else g, 255 if w else b])
props = {"Category": "ApplicationStatus", "Id": ident, "Title": ident, "Status": "Active", "IconName": "",
         "IconPixmap": dbus.Array([dbus.Struct((32, 32, dbus.ByteArray(bytes(px))), signature=None)], signature="(iiay)"),
         "ItemIsMenu": False, "WindowId": dbus.Int32(0)}
class Item(dbus.service.Object):
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return props[prop]
    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return props
item = Item(bus, "/StatusNotifierItem")
def register():
    try:
        bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher").RegisterStatusNotifierItem(name, dbus_interface="org.kde.StatusNotifierWatcher")
    except dbus.DBusException:
        pass
    return True
register(); GLib.timeout_add_seconds(1, register)
GLib.MainLoop().run()
PY
py=''; for p in python3 python3.12 python3.11 python3.13; do command -v "$p" >/dev/null 2>&1 && "$p" -c 'import dbus, gi' 2>/dev/null && { py=$p; break; }; done
[ -n "$py" ] || { echo "FAIL: no python3 with dbus and gi (python3-dbus, python3-gi)"; exit 1; }
"$py" "$HOME/sni.py" 23 98 160 steamish > "$HOME/sni1.log" 2>&1 & sni1=$!
"$py" "$HOME/sni.py" 220 60 160 chatish > "$HOME/sni2.log" 2>&1 & sni2=$!
sleep 3; strip tray-off top
S bar tray on >/dev/null; sleep 6
for _ in $(seq 15); do [ -s "$HOME/.local/state/spark-shell/bar.pid" ] && kill -0 "$(cat "$HOME/.local/state/spark-shell/bar.pid")" 2>/dev/null && break; sleep 1; done
for _ in $(seq 15); do busctl --user --list 2>/dev/null | grep -q StatusNotifierWatcher && break; dbus-send --session --print-reply --dest=org.freedesktop.DBus / org.freedesktop.DBus.ListNames 2>/dev/null | grep -q StatusNotifierWatcher && break; sleep 1; done
sleep 4; strip tray-on top
for l in "$HOME/sni1.log" "$HOME/sni2.log"; do [ ! -s "$l" ] || { cat "$l"; echo "FAIL: a stand-in app ended"; exit 1; }; done
S bar tray off >/dev/null; sleep 3
kill "$sni1" "$sni2" 2>/dev/null || :

S panel bar --list > "$proof/panel-bar.txt"; cat "$proof/panel-bar.txt"
swaymsg exit >/dev/null 2>&1 || :
wait "$swaypid" 2>/dev/null || :
kill "$buspid" 2>/dev/null || :
n=0; for f in "$proof"/*.png; do [ ! -f "$f" ] || n=$((n + 1)); done
echo "== done: $n pictures in $proof"
